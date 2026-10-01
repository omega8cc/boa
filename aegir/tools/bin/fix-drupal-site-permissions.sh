#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file permissions of a Drupal site. You need
to provide the following argument:

  --site-path: Path to the Drupal site's directory.

Usage: (sudo) ${0##*/} --site-path=PATH
Example: (sudo) ${0##*/} --site-path=/var/aegir/platforms/drupal-7.50/sites/example.com
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# The walks below run perl and the tools from this PATH, never the caller's.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# The notes on what a walk left as it was (_links_left_note) go to fd 3, a
# copy of stderr taken here: several legs below discard their own output.
exec 3>&2

# The script is invoked via NOPASSWD sudo by aegir and per-Octopus admin users,
# and the account owns the names under ${site_path}, so any of them can be a
# link. Defence is the same shape used by the sibling fix-drupal-* helpers:
# the resolved path is held to the caller's own tree, every step runs inside
# a directory entered for real (_in_pinned_dir) on ./names there, and every
# mode is set through _FCHMOD_PL, on the name itself or from a find walk, so
# no link is followed, whether it was there before or put there during
# the run.
_validate_path_prefix() {
  # Scope the resolved path to the SUDO caller's OWN home tree (aegir ->
  # /var/aegir, Octopus oN -> /data/disk/oN), not merely "some BOA tree": a
  # tenant must not drive this root-run chmod against another tenant's
  # /data/disk/oM/ files. Validating the realpath (not the raw arg) also defeats
  # a symlink planted inside the caller's own tree that points out to another
  # tenant. A direct root run (no SUDO_USER) is trusted and keeps the historical
  # BOA-tree allowlist.
  local _resolved _caller _home
  _resolved=$(realpath -e -- "$1" 2>/dev/null) || {
    printf "Error: path does not resolve: %s\n" "$1" >&2
    exit 1
  }
  _caller="${SUDO_USER:-}"
  if [ -z "${_caller}" ]; then
    case "${_resolved}/" in
      /var/aegir/*|/data/disk/*|/home/*) return 0 ;;
      *)
        printf "Error: path outside allowed roots (/var/aegir, /data/disk, /home): %s\n" "${_resolved}" >&2
        exit 1
        ;;
    esac
  fi
  _home=$(getent passwd "${_caller}" 2>/dev/null | cut -d: -f6)
  _home="${_home%/}"
  case "${_home}" in
    /var/aegir|/data/disk/*) ;;
    *)
      printf "Error: unexpected sudo caller '%s' (home '%s'); refusing.\n" "${_caller}" "${_home}" >&2
      exit 1
      ;;
  esac
  case "${_resolved}/" in
    "${_home}"/*) ;;
    *)
      printf "Error: path '%s' is outside the caller's own tree (%s).\n" "${_resolved}" "${_home}" >&2
      exit 1
      ;;
  esac
}

_store_dir() {
  # Echo the directory to walk for a per-site files/ or private/ store, or
  # nothing (the caller then skips it). These are LEGITIMATELY symlinks --
  # autosymlink points them at <account>/static/files/<site>/<type>, and
  # static/files may itself be a symlink to a dedicated disk -- so they cannot
  # be refused outright. But the tenant owns ~/static and can own the site dir
  # itself (sites/ is 02771 on tenant codebases), so both the link and its
  # target are plantable, static/files included: its resolved path is never
  # the anchor. Accept a real directory, or a link that resolves strictly
  # below THIS account's own real static/files, or below migratefs' layout
  # for this account on attached storage (/mnt/<mount>/files/<acct>/static/files,
  # where no directory of the mount part is itself named files or static).
  # A dot-name right below either store root is BOA's own (.backups,
  # .backup-exports, .archived), never a site's store, so it is left alone.
  local _p _acct="" _res _own _m _top
  _p="$1"
  [ -d "${_p}" ] || return 1
  if [ ! -L "${_p}" ]; then
    printf '%s' "${_p}"
    return 0
  fi
  case "${site_path}/" in
    /var/aegir/*)
      _own="/var/aegir/static/files/"
      ;;
    /data/disk/*/*)
      _acct="${site_path#/data/disk/}"
      _acct="${_acct%%/*}"
      case "${_acct}" in
        ""|*[!a-z0-9-]*) return 1 ;;
      esac
      _own="/data/disk/${_acct}/static/files/"
      ;;
    *)
      return 1
      ;;
  esac
  _res=$(realpath -e -- "${_p}" 2>/dev/null) || return 1
  case "${_res}" in
    *[!A-Za-z0-9._/-]*) return 1 ;;
    "${_own}"?*)
      _top="${_res#"${_own}"}"
      ;;
    /mnt/?*/files/"${_acct}"/static/files/?*)
      [ -n "${_acct}" ] || return 1
      _m="${_res%%/files/"${_acct}"/static/files/*}"
      case "${_m}" in
        */files/*|*/static/*) return 1 ;;
      esac
      _top="${_res#"${_m}"/files/"${_acct}"/static/files/}"
      ;;
    *) return 1 ;;
  esac
  case "${_top}" in
    .*) return 1 ;;
  esac
  printf '%s' "${_res}"
}

_web_group_state() {
  # The account's own web group, wg-<account>, derived on the box and never
  # taken from argv or a cnf: the group its pools, backend user and shell
  # users share for its web paths once the account is converted to it.
  # Prints "<state> <gid> <group>", "none - -" when there is no such group
  # (the record is root's: run as another user, converted reads as held):
  #   none       no group of that name
  #   foreign    the group exists, but an identity outside the account holds
  #              it too: never joined nor written to; claim passes still leave
  #              its paths alone (taking them would cut the pools off)
  #   held       the group exists and only this account's identities hold it:
  #              claim passes leave its paths alone, new identities join it
  #   converted  and root's record names that gid: writers use the group
  #   phaseb     and the record says the identities have left www-data
  # The record is /root/.<account>.web-group.txt, "wg-<account> gid=<n>
  # phase=<A|B> ...", root's own file outside the account tree, so neither
  # the account nor a copy or restore of its tree can make or move it.
  # $1 = account name, one of its identities (oN.ftp, oN.<sub>, oN.web,
  # oN.NN.web), or a path under /data/disk/<oN>, /home/<oN>.*, the account's
  # gems or npm tree, or its store on attached storage
  # (/mnt/<m>/files/<oN>/static/files).
  local _a="${1}" _e _gid _u _r _rg="" _rgid="" _rph="" IFS=$' \t\n'
  # a path is read as written (an alias the account wrote can carry "..",
  # "." or "//"): normalised by text alone, never through a link, first
  case "${_a}" in
    */*) _a=$(realpath -m -s -- "${_a}" 2> /dev/null) || { echo "none - -"; return 0; } ;;
  esac
  case "${_a}" in
    /data/disk/*) _a="${_a#/data/disk/}"; _a="${_a%%/*}" ;;
    /home/*) _a="${_a#/home/}"; _a="${_a%%/*}" ;;
    /opt/user/gems/*|/opt/user/npm/*) _a="${_a#/opt/user/*/}"; _a="${_a%%/*}" ;;
    /mnt/*/files/*/static/files|/mnt/*/files/*/static/files/*)
      _a="${_a#/mnt/}"; _a="${_a#*/files/}"; _a="${_a%%/*}" ;;
    */*) echo "none - -"; return 0 ;;
  esac
  _a="${_a%%.*}"
  case "${_a}" in
    ""|all|aegir|root|www-data|wg-*|*[!a-z0-9-]*) echo "none - -"; return 0 ;;
  esac
  _e=$(getent group "wg-${_a}" 2> /dev/null) || { echo "none - -"; return 0; }
  _gid=$(printf '%s' "${_e}" | cut -d: -f3)
  case "${_gid}" in
    ""|*[!0-9]*) echo "none - -"; return 0 ;;
  esac
  # every holder of the gid: members of each group entry carrying it (a
  # second entry can share the number) and every user with it as primary
  for _u in $(getent group | awk -F: -v g="${_gid}" '$3 == g { print $4 }' | tr ',' ' ') \
    $(getent passwd | awk -F: -v g="${_gid}" '$4 == g { print $1 }'); do
    [[ "${_u}" =~ ^${_a}(\.[a-z0-9]+(-dev)?|\.[0-9]+\.web)?$ ]] \
      || { echo "foreign ${_gid} wg-${_a}"; return 0; }
  done
  _r="/root/.${_a}.web-group.txt"
  if [ -f "${_r}" ] && [ ! -L "${_r}" ] \
    && [ "$(stat -c %u -- "${_r}" 2> /dev/null)" = "0" ]; then
    read -r _rg _rgid _rph _ < "${_r}" || :
  fi
  if [ "${_rg}" != "wg-${_a}" ] || [ "${_rgid}" != "gid=${_gid}" ]; then
    echo "held ${_gid} wg-${_a}"
  elif [ "${_rph}" = "phase=B" ]; then
    echo "phaseb ${_gid} wg-${_a}"
  elif [ "${_rph}" = "phase=A" ]; then
    echo "converted ${_gid} wg-${_a}"
  else
    echo "held ${_gid} wg-${_a}"
  fi
}

_web_group() {
  # The group a root writer gives an account's web paths (files/, private/,
  # settings.php and the like): wg-<account> once the account is converted,
  # www-data otherwise, as always. Until the record says converted every
  # identity of the account still holds www-data (a conversion grants the web
  # group first and a revert gives www-data back before it moves any path),
  # so www-data is the old state, never an outage. Callers write
  # "${_owner}${_wg:+:${_wg}}": a missing helper, an empty answer, changes no
  # group and never hands a path to a login group. Run as any user but root,
  # which cannot read root's record, a held group answers empty: the group
  # each path has is kept. $1 as _web_group_state.
  local _s
  _s=$(_web_group_state "${1}")
  case "${_s%% *}" in
    converted|phaseb) echo "${_s##* }" ;;
    held) [ "$(id -u)" = "0" ] && echo "www-data" || echo "" ;;
    *) echo "www-data" ;;
  esac
}

# The site path and each store are resolved once below, but the account owns
# every name on the way (the platform tree, sites/, static/files), so any of
# them can be swapped for a link at any time. Every act runs inside a
# directory entered for real: cd -P, then "$@" only while pwd -P there is
# still the resolved path, so a link put on the way since is never followed,
# and ./name then stays in that directory whatever is swapped. $1 = a path
# resolved once above.
_in_pinned_dir() {
  local _d="${1}"
  shift
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_d}" ] && "$@" )
}

# A mode set on paths below the current directory, never through a link:
# each directory on a path is opened without following a link and entered
# through that handle, and the last name is opened the same way without
# blocking on a FIFO, checked to be the expected type and changed through
# the open handle, so a name swapped for a link at any moment is refused,
# not followed. A regular file with more than one link is left alone: a hard
# link planted in a tree the account can write would carry the mode to the
# file it shares. Run it on ./names inside a pinned directory, or from
# find -exec ... {} + there, which hands one perl the paths of the whole
# walk (find's -type test alone does not stop a later chmod by path from
# following a link). As chmod does, a directory keeps its setuid and setgid
# bits unless the mode has five digits. Args: f|d|a (regular file,
# directory, either), the mode (octal), the paths.
_FCHMOD_PL='use Fcntl;
my ($t, $m) = (shift @ARGV, shift @ARGV);
$m =~ /^[0-7]{3,5}$/ or exit 1;
my ($v, $k) = (oct($m), length($m) < 5 ? 06000 : 0);
sysopen(my $top, ".", O_RDONLY | O_DIRECTORY) or exit 1;
my @at;
for my $p (@ARGV) {
  my @n = grep { $_ ne "" && $_ ne "." } split(m{/}, $p);
  next if $p =~ m{^/} || grep { $_ eq ".." } @n;
  my $f = @n ? pop(@n) : ".";
  my $i = 0;
  $i++ while $i < @at && $i < @n && $at[$i] eq $n[$i];
  if ($i < @at) {
    chdir($top) or exit 1;
    $i = 0;
    @at = ();
  }
  for my $c (@n[$i .. $#n]) {
    my $d;
    sysopen($d, $c, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
      && chdir($d) or last;
    push(@at, $c);
  }
  next if @at < @n;
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if (-d _ && $t ne "f") {
    chmod($v | ($s[2] & $k), $h);
  }
  elsif (-f _ && $s[3] == 1 && $t ne "d") {
    chmod($v, $h);
  }
  close($h);
}'

# The mode $1 on each regular file or directory in the current (pinned)
# directory that matches a pattern after it (expanded here, nowhere else),
# set through _FCHMOD_PL. A pattern that matches nothing is skipped.
_chmod_here() {
  local _mode="${1}" _pat _p
  local -a _n=()
  shift
  for _pat in "$@"; do
    for _p in ${_pat}; do
      _n+=("./${_p#./}")
    done
  done
  [ "${#_n[@]}" -gt 0 ] || return 0
  perl -e "${_FCHMOD_PL}" a "${_mode}" "${_n[@]}"
}
# _chmod_here inside the directory $1 (resolved once above), entered for real.
_chmod_in() {
  local _d="${1}"
  shift
  _in_pinned_dir "${_d}" _chmod_here "$@"
}
# A walk leaves a regular file with more than one link as it was (a hard
# link planted in a tree the account can write would carry the change to the
# file it shares), so that file keeps its old owner and mode. Say so once
# per walk: how many the walk's selection holds and the first, found by the
# same start points and tests ("$@", run from the directory the walk ran
# in). Printed on fd 3, which the legs that discard their output leave open;
# no count is taken when the whole run's output goes to /dev/null (the
# nightly's foreign-CMS leg), which would only add a traversal nobody reads.
_links_left_note() {
  local _f _n=0 _first="" _here
  [ /dev/fd/3 -ef /dev/null ] && return 0
  while IFS= read -r -d '' _f; do
    [ -n "${_first}" ] || _first="${_f}"
    _n=$(( _n + 1 ))
  done < <(find "$@" -type f -links +1 -print0 2> /dev/null)
  [ "${_n}" -gt 0 ] || return 0
  _here="$(pwd -P)"
  _first="${_here}/${_first#./}"
  printf "Notice: %s file(s) with more than one link left unchanged under %s, first: %s\n" \
    "${_n}" "${_here}" "${_first//[[:cntrl:]]/?}" >&3
  return 0
}
# Mode $1 on every regular file the find start points and tests after it
# select (any tests apply first), walked from the current (pinned) directory
# through _FCHMOD_PL, then _links_left_note on the same selection.
_fwalk_here() {
  local _m="${1}" _rc
  shift
  find "$@" -type f -exec perl -e "${_FCHMOD_PL}" f "${_m}" {} +
  _rc=$?
  _links_left_note "$@"
  return "${_rc}"
}

# ./$1 in the current (pinned) directory as a fresh empty file, created
# exclusively and renamed over the name (root's, as touch made it): a link or
# a FIFO put at the name is replaced, never followed or opened.
_mark_here() {
  local _t="./.${1}.mark.$$.${RANDOM}"
  rm -f -- "${_t}"
  dd if=/dev/null of="${_t}" conv=excl status=none 2> /dev/null \
    && mv -f -T -- "${_t}" "./${1}" && return 0
  rm -f -- "${_t}"
  return 1
}

# The Grav capsule model, run inside the real site directory.
_grav_site_perm_here() {
  local _wd _sd _here
  _here="$(pwd -P)"
  find . -path ./user -prune \
    -o -path ./cache -prune \
    -o -path ./logs -prune \
    -o -path ./tmp -prune \
    -o -path ./backup -prune \
    -o -path ./images -prune \
    -o -path ./assets -prune \
    -o -type d -exec perl -e "${_FCHMOD_PL}" d 0755 {} + 2> /dev/null
  _fwalk_here 0644 . -path ./user -prune \
    -o -path ./cache -prune \
    -o -path ./logs -prune \
    -o -path ./tmp -prune \
    -o -path ./backup -prune \
    -o -path ./images -prune \
    -o -path ./assets -prune \
    -o 2> /dev/null
  _chmod_in "${_here}/bin" 0755 '*'
  for _wd in user cache logs tmp backup images assets; do
    [ -d "./${_wd}" ] || continue
    find "./${_wd}" -type d \
      -exec perl -e "${_FCHMOD_PL}" d 02775 {} + 2> /dev/null
    _fwalk_here 0664 "./${_wd}" 2> /dev/null
  done
  # Secret surfaces AFTER the generic pass, which would re-widen them
  # (same class as the TXP private/ store): accounts hold
  # password hashes and live reset tokens, config holds the session salt and
  # SMTP/API credentials. Group-rw for FPM, owner-rw for the CLI, NO world
  # bits. The root .env (phase 2: DB credentials) keeps FPM's read via group.
  for _sd in accounts config env; do
    [ -d "./user/${_sd}" ] || continue
    _in_pinned_dir "${_here}/user" find "./${_sd}" -type d \
      -exec perl -e "${_FCHMOD_PL}" d 02770 {} + 2> /dev/null
    _in_pinned_dir "${_here}/user" _fwalk_here 0660 "./${_sd}" 2> /dev/null
  done
  _chmod_here 0640 .env
  _chmod_here 0440 drushrc.php
}

# The Textpattern model, run inside the real site directory.
_txp_site_perm_here() {
  local _wd _here
  _here="$(pwd -P)"
  find . -path ./private -prune \
    -o -path ./tmp -prune \
    -o -path ./admin/plugins -prune \
    -o -path ./public/files -prune \
    -o -path ./public/images -prune \
    -o -path ./public/themes -prune \
    -o -type d -exec perl -e "${_FCHMOD_PL}" d 0755 {} + 2> /dev/null
  _fwalk_here 0644 . -path ./private -prune \
    -o -path ./tmp -prune \
    -o -path ./admin/plugins -prune \
    -o -path ./public/files -prune \
    -o -path ./public/images -prune \
    -o -path ./public/themes -prune \
    -o 2> /dev/null
  for _wd in tmp admin/plugins public/files public/images public/themes; do
    [ -d "./${_wd}" ] || continue
    _in_pinned_dir "${_here}/${_wd}" find . -type d \
      -exec perl -e "${_FCHMOD_PL}" d 02775 {} + 2> /dev/null
    _in_pinned_dir "${_here}/${_wd}" _fwalk_here 0664 . 2> /dev/null
  done
  # Credential store: group-traversable (FPM reads config.php through the
  # web group), unreadable to everyone else.
  _chmod_here 0750 private
  _in_pinned_dir "${_here}/private" _fwalk_here 0440 . 2> /dev/null
  # Aegir's own site drushrc sits at the site ROOT (not inside private/) and
  # carries the db credentials, so the generic 0644 pass above widens it to
  # world-readable on every verify. Restore the 0440 the Drushrc writer sets --
  # never fight the writer. (Same class as the private/ prune.)
  _chmod_here 0440 drushrc.php
}

# The site's own PHP files made 0440, the glob expanded inside the real site
# directory, each set through _FCHMOD_PL.
_site_php_here() {
  _fwalk_here 0440 ./*.php
}

# The files store, run inside it (entered for real): the day marker, then the
# whole store.
_files_perm_here() {
  ### ctrl pid
  rm -f -- ./permissions-fixed*.pid
  _mark_here "permissions-fixed-${_TODAY}.pid"
  ### files - site level; a Drupal 7 files/private is private data like the
  ### private store and takes its modes once they drop the world bits
  if [ "${_priv_d}" = "02775" ]; then
    find . -type d -exec perl -e "${_FCHMOD_PL}" d 02775 {} +
    _fwalk_here 0664 .
  else
    find . -path ./private -prune -o -type d \
      -exec perl -e "${_FCHMOD_PL}" d 02775 {} +
    _fwalk_here 0664 . -path ./private -prune -o
    if [ -d ./private ] && [ ! -L ./private ]; then
      find ./private -type d -exec perl -e "${_FCHMOD_PL}" d "${_priv_d}" {} +
      _fwalk_here "${_priv_f}" ./private
    fi
  fi
  chmod 02775 .
}

site_path=${1%/}

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --site-path=*)
        site_path="${1#*=}"
        ;;
    --help) print_help;;
    *)
      printf "Error: Invalid argument, run --help for valid arguments.\n"
      exit 1
  esac
  shift
done

### Resolve the caller-supplied path ONCE, before any check or operation reads
### it: every branch below re-walks the raw argument, and sites/ is 02771 on
### tenant codebases, so the tenant owns the name it was handed and could
### re-point it between _validate_path_prefix and the chmods.
if [ -n "${site_path}" ] && [ -e "${site_path}" ]; then
  site_path=$(realpath -e -- "${site_path}" 2>/dev/null) || site_path=""
fi

# --- Grav 2 site capsule -----------------------------------------------------
# A capsule is a full Grav install at sites/<uri>/ with no settings.php;
# detect it positively and run the capsule permission model instead of
# refusing (union seam: further foreign-CMS branches join here the same way).
if [ -n "${site_path}" ] \
  && [ -f "${site_path}/bin/grav" ] \
  && [ -f "${site_path}/system/defines.php" ] \
  && [ ! -f "${site_path}/settings.php" ]; then
  _validate_path_prefix "${site_path}"
  # Capsule permission model (spike-proven): code 0755/0644; the writable
  # set 02775 dirs + g+rw files (FPM writes via GROUP; setgid keeps the
  # group on web-created entries); the capsule's own bin/ stays executable
  # (the enforced-PHP wrapper and the upgrade engine exec bin/grav, bin/gpm).
  # Runs inside the real site directory (_in_pinned_dir, _grav_site_perm_here).
  printf "Setting Grav permissions of %s\n" "${site_path}"
  _in_pinned_dir "${site_path}" _grav_site_perm_here
  echo "Done setting proper permissions of files and directories (Grav site)."
  exit 0
fi

# --- Textpattern multisite site -----------------------------------------------
# A TXP site is sites/<uri>/{admin,private,public} with no settings.php; detect
# it positively and run the TXP permission model instead of refusing (union seam
# shared with the Grav branch above).
if [ -n "${site_path}" ] \
  && [ -f "${site_path}/public/index.php" ] \
  && [ -f "${site_path}/public/css.php" ] \
  && [ -d "${site_path}/admin" ] \
  && [ ! -f "${site_path}/settings.php" ]; then
  _validate_path_prefix "${site_path}"
  # Code 0755/0644; the writable set 02775 dirs + g+rw files (FPM writes via
  # GROUP; setgid keeps the group on web-created entries).
  #
  # private/ is PRUNED from the generic pass on purpose: it is the credential
  # store, and the generic 0644 file pass would widen private/config.php from
  # 0440 to world-readable. It is set explicitly below instead.
  #
  # find is never given -L, so the four admin symlinks are type l, are not
  # matched by -type d/f and are not descended into -- the shared core tree is
  # never touched from here. Runs inside the real site directory
  # (_in_pinned_dir, _txp_site_perm_here).
  printf "Setting Textpattern permissions of %s\n" "${site_path}"
  _in_pinned_dir "${site_path}" _txp_site_perm_here
  echo "Done setting proper permissions of files and directories (Textpattern site)."
  exit 0
fi

if [ -z "${site_path}" ] || [ ! -f "${site_path}/settings.php" ]; then
  printf "Error: Please provide a valid Drupal site directory.\n"
  exit 1
fi

_validate_path_prefix "${site_path}"

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

### Private files keep no world bits once the account has its own web group:
### its pools, backend user and shell users reach them through that group,
### and nginx never serves them directly. Until then, as always.
_priv_d=02775
_priv_f=0664
case "$(_web_group "${site_path}")" in
  wg-*) _priv_d=02770; _priv_f=0660 ;;
esac

### modules, themes and libraries are names the tenant can plant: it can create
### the site dir itself under the group-writable sites/ (02771), and the
### site-level code dirs are 02775 and group-writable. The rm below and the find start
### points walk THROUGH them, while _chmod_here protects only the final
### component. None is ever legitimately a symlink at site level.
for _d in modules themes libraries; do
  if [ -L "${site_path}/${_d}" ]; then
    printf "Error: %s is a symlink in %s; refusing.\n" "${_d}" "${site_path}" >&2
    exit 1
  fi
done

### Every act below runs inside a directory entered for real
### (_in_pinned_dir) and names only ./entries there; refuse now when the
### site directory itself cannot be entered as resolved.
if ! _in_pinned_dir "${site_path}" true; then
  printf "Error: %s is not a real directory; refusing.\n" "${site_path}" >&2
  exit 1
fi

if [ -e "${site_path}/libraries/permissions-fixed.pid" ]; then
  _in_pinned_dir "${site_path}/libraries" rm -f -- ./permissions-fixed.pid
fi
printf 'Setting correct permissions on key files and directories inside %s...\n' "${site_path}"
### directory and settings files - site level
if [ -e "${site_path}/aegir.services.yml" ]; then
  _in_pinned_dir "${site_path}" rm -f -- ./aegir.services.yml
fi
### Every find walk below sets modes through _FCHMOD_PL: a name swapped for
### a link during the walk is refused, not followed.
_in_pinned_dir "${site_path}" _site_php_here &> /dev/null
### The hostmaster site's drushrc.php carries the instance DB user (ALL
### PRIVILEGES) and only the backend user, its owner, ever reads it: no group
### read at all, box-wide 'users' or the account's own group alike.
if [[ "${site_path}" =~ /aegir/(distro|host_master)/ ]]; then
  _chmod_in "${site_path}" 0400 drushrc.php
fi
_chmod_in "${site_path}" 0640 civicrm.settings.php
### modules,themes,libraries - site level
_in_pinned_dir "${site_path}" find ./modules ./themes ./libraries -type d \
  -exec perl -e "${_FCHMOD_PL}" d 02775 {} + &> /dev/null
_in_pinned_dir "${site_path}" _fwalk_here 0664 ./modules ./themes ./libraries \
  &> /dev/null

### files/ and private/ are legitimately symlinks into the per-account static
### store, and a walk through such a link goes wherever it points. Each store
### is resolved once, accepted only inside this account's own store root, and
### walked from inside the resolved directory, entered for real.
_files_dir=$(_store_dir "${site_path}/files") || _files_dir=""
_priv_dir=$(_store_dir "${site_path}/private") || _priv_dir=""
if [ -z "${_files_dir}" ] && [ -e "${site_path}/files" ]; then
  printf "Notice: %s is not this account's own files store; skipping.\n" \
    "${site_path}/files" >&2
fi

if [ -n "${_files_dir}" ] \
  && [ ! -e "${_files_dir}/permissions-fixed-${_TODAY}.pid" ]; then
  _in_pinned_dir "${_files_dir}" _files_perm_here &> /dev/null
  ### private - site level
  if [ -n "${_priv_dir}" ]; then
    _in_pinned_dir "${_priv_dir}" find . -type d \
      -exec perl -e "${_FCHMOD_PL}" d "${_priv_d}" {} + &> /dev/null
    _in_pinned_dir "${_priv_dir}" _fwalk_here "${_priv_f}" . &> /dev/null
  fi
  ### known exceptions
  _chmod_in "${_files_dir}" 0644 .htaccess
fi

echo "Done setting proper permissions on site files and directories."
