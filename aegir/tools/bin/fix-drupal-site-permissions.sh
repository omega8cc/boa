#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file permissions of a Drupal site. You need
to provide the following argument:

  --site-path: Path to the Drupal site's directory.

  --backup-read: Change nothing but what a backup needs to read: in the
             site's own files and private stores, each file the account's
             web server wrote without group read gets group read, and each
             such directory group read and search. Owner, group and every
             other bit stay as the web server set them.

Usage: (sudo) ${0##*/} --site-path=PATH [--backup-read]
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
# mode is set through _SAT_CHMOD_OWN_PL, on the name itself or from the
# directory a find walk holds, so no link is followed, whether it was there
# before or put there during the run. Only what root or the site's own users
# own (_site_walk_uids) gets a mode, and nothing below a directory another
# user owns: the account's users can rename into their own tree what
# another account left group-writable, a whole directory with everything in
# it; that keeps its modes, and one Notice counts it (_owners_left_note).
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

_master_web_group() {
  # The master's own web group, wg-aegir, the way _web_group_state reads an
  # account's: "<state> <gid> wg-aegir", "none - -" when there is none. Its
  # holders are aegir and the master pool users wwwNN; anyone else holding
  # it makes it foreign. The record is /root/.aegir.web-group.txt, root's
  # own file, "wg-aegir gid=<n> phase=<A|B> ...".
  local _e _gid _u _r _rg="" _rgid="" _rph="" IFS=$' \t\n'
  _e=$(getent group wg-aegir 2> /dev/null) || { echo "none - -"; return 0; }
  _gid=$(printf '%s' "${_e}" | cut -d: -f3)
  case "${_gid}" in
    ""|*[!0-9]*) echo "none - -"; return 0 ;;
  esac
  for _u in $(getent group | awk -F: -v g="${_gid}" '$3 == g { print $4 }' | tr ',' ' ') \
    $(getent passwd | awk -F: -v g="${_gid}" '$4 == g { print $1 }'); do
    [[ "${_u}" =~ ^(aegir|www[0-9][0-9])$ ]] \
      || { echo "foreign ${_gid} wg-aegir"; return 0; }
  done
  _r="/root/.aegir.web-group.txt"
  if [ -f "${_r}" ] && [ ! -L "${_r}" ] \
    && [ "$(stat -c %u -- "${_r}" 2> /dev/null)" = "0" ]; then
    read -r _rg _rgid _rph _ < "${_r}" || :
  fi
  if [ "${_rg}" != "wg-aegir" ] || [ "${_rgid}" != "gid=${_gid}" ]; then
    echo "held ${_gid} wg-aegir"
  elif [ "${_rph}" = "phase=B" ]; then
    echo "phaseb ${_gid} wg-aegir"
  elif [ "${_rph}" = "phase=A" ]; then
    echo "converted ${_gid} wg-aegir"
  else
    echo "held ${_gid} wg-aegir"
  fi
}
_site_web_group() {
  # The web group a root writer gives the site at $1 (resolved): the
  # account's own, as _web_group derives it, or, for a site of the master
  # (/var/aegir), the master's own web group, wg-aegir, once the master's
  # record says it is converted to it; www-data otherwise, as always.
  case "${1}/" in
    /var/aegir/*)
      case "$(_master_web_group)" in
        converted\ *|phaseb\ *) echo "wg-aegir" ;;
        *) echo "www-data" ;;
      esac
      ;;
    *) _web_group "${1}" ;;
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

# The uids root's walks over the account $1's trees act on, comma-separated:
# root's own (0, what root wrote there for the account) and those of every
# identity of the account as passwd names them: oN and oN.<name>, that is
# its .ftp login, its client sub-accounts oN.<client> and oN.<client>-dev
# and its PHP-FPM users oN.web and oN.<ver>.web. An account name holds no
# dot, so the match is exact: o1 never takes o10's. Status 1, and nothing,
# unless the account itself is in passwd.
_acct_walk_uids() {
  local _a="${1}" _n _p _u _r _x="0" _self=NO
  case "${_a}" in
    ""|*[!a-z0-9-]*) return 1 ;;
  esac
  while IFS=: read -r _n _p _u _r; do
    [[ "${_n}" =~ ^${_a}(\.[a-z0-9]+(-dev)?|\.[0-9]+\.web)?$ ]] || continue
    [[ "${_u}" =~ ^[1-9][0-9]*$ ]] || continue
    _x="${_x},${_u}"
    [ "${_n}" = "${_a}" ] && _self=YES
  done < <(getent passwd 2> /dev/null)
  [ "${_self}" = "YES" ] || return 1
  echo "${_x}"
}
# The uids the walks below act for, comma-separated, from the site path as
# resolved, never from argv: under /data/disk/<account>/ that account's
# (_acct_walk_uids); under /var/aegir/ root's, aegir's and those of the
# master's pool users wwwNN, the holders _master_web_group allows. Status
# 1, and nothing, for any other path, or when the account or aegir is not
# in passwd. A uid no passwd entry names counts as the site's own too
# (_SAT_REOWN_OWN_PL, _SAT_CHMOD_OWN_PL): a login removed before its files
# were handed to its account left those.
_site_walk_uids() {
  local _a _n _p _u _r _x="0" _self=NO
  case "${1}/" in
    /data/disk/*/*)
      _a="${1#/data/disk/}"
      _acct_walk_uids "${_a%%/*}"
      return "$?"
      ;;
    /var/aegir/*)
      while IFS=: read -r _n _p _u _r; do
        [[ "${_n}" =~ ^(aegir|www[0-9][0-9])$ ]] || continue
        [[ "${_u}" =~ ^[1-9][0-9]*$ ]] || continue
        _x="${_x},${_u}"
        [ "${_n}" = "aegir" ] && _self=YES
      done < <(getent passwd 2> /dev/null)
      [ "${_self}" = "YES" ] || return 1
      echo "${_x}"
      return 0
      ;;
  esac
  return 1
}
# The uids the walks act for in _OWN_UIDS (_site_walk_uids); a site path in
# neither an account's tree nor the master's is left as it is, with one
# Notice and nothing changed.
_own_uids_or_leave() {
  _OWN_UIDS=$(_site_walk_uids "${site_path}") || _OWN_UIDS=""
  [[ "${_OWN_UIDS}" =~ ^0(,[1-9][0-9]*)*$ ]] && return 0
  printf "Notice: %s is in neither an account's tree nor the master's; nothing changed.\n" \
    "${site_path}" >&2
  exit 0
}
# One line for what the walks left as another user's, each entry once by
# the dev:ino the walkers print ($1, all they printed), on fd 3 beside the
# other notes.
_owners_left_note() {
  local _n
  _n=$(printf '%s\n' "${1}" | grep -E '^[0-9]+:[0-9]+$' | sort -u | grep -c .)
  [[ "${_n}" =~ ^[1-9][0-9]*$ ]] || return 0
  printf "Notice: %s entries owned by another user left as they were in the site %s and its stores\n" \
    "${_n}" "${site_path}" >&3
  return 0
}

# As _FCHMOD_PL on names in the current directory (f or d, the mode, the
# names), given first the uids it acts for (_site_walk_uids): a name
# another named uid owns keeps its mode and is printed (dev:ino), and
# nothing is changed unless the current directory and every directory
# above it, up to /, are owned by those uids (read through '..' from where
# find stands), so nothing below a directory another named uid owns gets a
# mode. Given . as a name, a directory another uid owns above the place is
# printed when it is refused; status 1 when it is.
_SAT_CHMOD_OWN_PL='use Fcntl;
my ($o, $t, $ms) = (shift @ARGV, shift @ARGV, shift @ARGV);
my %own = map { $_ => 1 } grep { /^[0-9]+$/ } split(/,/, $o);
sub own { my $u = shift; unless (exists $own{$u}) { local $! = 0; $own{$u} = defined(getpwuid($u)) ? 0 : ($! == 0 || $!{ENOENT} || $!{ESRCH} || $!{EBADF} || $!{EPERM}) ? 1 : 0; } return $own{$u}; }
my ($p, $ok, @d, @x) = (".", 0);
for (1 .. 256) {
  @x = stat($p) or last;
  last unless own($x[4]);
  if (@d && $x[0] == $d[0] && $x[1] == $d[1]) { $ok = 1; last; }
  @d = @x;
  $p .= "/..";
}
unless ($ok) {
  print "$x[0]:$x[1]\n" if @x && !own($x[4]) && grep { $_ eq "." } @ARGV;
  exit 1;
}
my ($m, $k) = (oct($ms), length($ms) < 5 ? 06000 : 0);
for my $f (@ARGV) {
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if (@s && !own($s[4])) {
    print "$s[0]:$s[1]\n";
  } elsif (@s && $t eq "f" && -f _ && $s[3] == 1) {
    chmod($m, $h);
  } elsif (@s && $t eq "d" && -d _) {
    chmod($m | ($s[2] & $k), $h);
  }
  close($h);
}
exit 0;'

# The mode $2 on each directory ($1 d) or single-link regular file ($1 f)
# in the current (pinned) directory that matches a pattern after it
# (expanded here, nowhere else; . stays .), set through _SAT_CHMOD_OWN_PL
# with the site's own uids (_OWN_UIDS). A pattern that matches nothing is
# skipped. Prints dev:ino of each entry left for another owner; status 1
# when the directory is below one another user owns.
_chmod_own_here() {
  local _t="${1}" _mode="${2}" _pat _p
  local -a _names=()
  shift 2
  [[ "${_OWN_UIDS}" =~ ^0(,[1-9][0-9]*)*$ ]] || return 1
  for _pat in "$@"; do
    for _p in ${_pat}; do
      [ "${_p}" = "." ] || _p="./${_p#./}"
      _names+=("${_p}")
    done
  done
  [ "${#_names[@]}" -gt 0 ] || return 0
  perl -e "${_SAT_CHMOD_OWN_PL}" -- "${_OWN_UIDS}" "${_t}" "${_mode}" "${_names[@]}"
}
# _chmod_own_here inside the directory $1 (resolved once above), entered for
# real.
_chmod_own_in() {
  local _d="${1}"
  shift
  _in_pinned_dir "${_d}" _chmod_own_here "$@"
}
# Status 0 while the current (pinned) directory and every directory above
# it are root's or the site's own users' (_SAT_CHMOD_OWN_PL given . as a
# file, which sets nothing on a directory); otherwise the directory another
# user owns is printed (dev:ino) and the status is 1. Every leg below
# starts with it: nothing is done in a place below another user's
# directory.
_place_own_here() {
  _chmod_own_here f 0644 .
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
# through _FCHMOD_PL, then _links_left_note on the same selection. The
# platform script walks with it; this one walks with _fwalk_own_here.
_fwalk_here() {
  local _m="${1}" _rc
  shift
  find "$@" -type f -exec perl -e "${_FCHMOD_PL}" f "${_m}" {} +
  _rc=$?
  _links_left_note "$@"
  return "${_rc}"
}
# Mode $2 on every directory ($1 d) or single-link regular file ($1 f) the
# find start points and tests after it select (any tests apply first), set
# from the directory find holds (-execdir) through _SAT_CHMOD_OWN_PL with
# the site's own uids (_OWN_UIDS): what another user owns, and everything
# below a directory another user owns, keeps its mode, its dev:ino
# printed. A file walk ends with _links_left_note on the same selection.
_fwalk_own_here() {
  local _t="${1}" _m="${2}" _rc
  shift 2
  [[ "${_OWN_UIDS}" =~ ^0(,[1-9][0-9]*)*$ ]] || return 1
  find "$@" -type "${_t}" \
    -execdir perl -e "${_SAT_CHMOD_OWN_PL}" -- "${_OWN_UIDS}" "${_t}" "${_m}" {} +
  _rc=$?
  [ "${_t}" != "f" ] || _links_left_note "$@"
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
  _place_own_here || return 0
  _fwalk_own_here d 0755 . -path ./user -prune \
    -o -path ./cache -prune \
    -o -path ./logs -prune \
    -o -path ./tmp -prune \
    -o -path ./backup -prune \
    -o -path ./images -prune \
    -o -path ./assets -prune \
    -o 2> /dev/null
  _fwalk_own_here f 0644 . -path ./user -prune \
    -o -path ./cache -prune \
    -o -path ./logs -prune \
    -o -path ./tmp -prune \
    -o -path ./backup -prune \
    -o -path ./images -prune \
    -o -path ./assets -prune \
    -o 2> /dev/null
  _chmod_own_in "${_here}/bin" d 0755 '*'
  _chmod_own_in "${_here}/bin" f 0755 '*'
  for _wd in user cache logs tmp backup images assets; do
    [ -d "./${_wd}" ] || continue
    _fwalk_own_here d 02775 "./${_wd}" 2> /dev/null
    _fwalk_own_here f 0664 "./${_wd}" 2> /dev/null
  done
  # Secret surfaces AFTER the generic pass, which would re-widen them
  # (same class as the TXP private/ store): accounts hold
  # password hashes and live reset tokens, config holds the session salt and
  # SMTP/API credentials. Group-rw for FPM, owner-rw for the CLI, NO world
  # bits. The root .env (phase 2: DB credentials) keeps FPM's read via group.
  for _sd in accounts config env; do
    [ -d "./user/${_sd}" ] || continue
    _in_pinned_dir "${_here}/user" _fwalk_own_here d 02770 "./${_sd}" 2> /dev/null
    _in_pinned_dir "${_here}/user" _fwalk_own_here f 0660 "./${_sd}" 2> /dev/null
  done
  _chmod_own_here f 0640 .env
  _chmod_own_here f 0440 drushrc.php
}

# The Textpattern model, run inside the real site directory.
_txp_site_perm_here() {
  local _wd _here
  _here="$(pwd -P)"
  _place_own_here || return 0
  _fwalk_own_here d 0755 . -path ./private -prune \
    -o -path ./tmp -prune \
    -o -path ./admin/plugins -prune \
    -o -path ./public/files -prune \
    -o -path ./public/images -prune \
    -o -path ./public/themes -prune \
    -o 2> /dev/null
  _fwalk_own_here f 0644 . -path ./private -prune \
    -o -path ./tmp -prune \
    -o -path ./admin/plugins -prune \
    -o -path ./public/files -prune \
    -o -path ./public/images -prune \
    -o -path ./public/themes -prune \
    -o 2> /dev/null
  for _wd in tmp admin/plugins public/files public/images public/themes; do
    [ -d "./${_wd}" ] || continue
    _in_pinned_dir "${_here}/${_wd}" _fwalk_own_here d 02775 . 2> /dev/null
    _in_pinned_dir "${_here}/${_wd}" _fwalk_own_here f 0664 . 2> /dev/null
  done
  # Credential store: group-traversable (FPM reads config.php through the
  # web group), unreadable to everyone else.
  _chmod_own_here d 0750 private
  _in_pinned_dir "${_here}/private" _fwalk_own_here f 0440 . 2> /dev/null
  # Aegir's own site drushrc sits at the site ROOT (not inside private/) and
  # carries the db credentials, so the generic 0644 pass above widens it to
  # world-readable on every verify. Restore the 0440 the Drushrc writer sets --
  # never fight the writer. (Same class as the private/ prune.)
  _chmod_own_here f 0440 drushrc.php
}

# The site's own PHP files made 0440, the glob expanded inside the real site
# directory, each set through _SAT_CHMOD_OWN_PL.
_site_php_here() {
  _fwalk_own_here f 0440 ./*.php
}

# The site directory's own modes, run inside it (entered for real): its PHP
# files, the panel's drushrc.php, civicrm.settings.php, and modules, themes
# and libraries with everything in them.
_site_dir_perm_here() {
  _place_own_here || return 0
  _site_php_here
  ### The hostmaster site's drushrc.php carries the instance DB user (ALL
  ### PRIVILEGES) and only the backend user, its owner, ever reads it: no
  ### group read at all, box-wide 'users' or the account's own group alike.
  if [[ "${site_path}" =~ /aegir/(distro|host_master)/ ]]; then
    _chmod_own_here f 0400 drushrc.php
  fi
  _chmod_own_here f 0640 civicrm.settings.php
  ### modules,themes,libraries - site level
  _fwalk_own_here d 02775 ./modules ./themes ./libraries
  _fwalk_own_here f 0664 ./modules ./themes ./libraries
}

# The subtrees of a files store nginx never serves (a case-insensitive
# prefix after any files/), as find -iregex patterns relative to the store,
# POSIX extended: every find that reads them sets -regextype posix-extended
# first (GNU find's default syntax reads the parentheses and bars as plain
# characters, and would match nothing).
_SITE_DENIED_RE='\./(civicrm/(configandlog|custom|upload|templates_c)|backup_migrate|config_)[^/]*|.*/files/(civicrm/(configandlog|custom|upload|templates_c)|backup_migrate|config_)[^/]*'

# The files store, run inside it (entered for real): the day marker, then the
# whole store; nothing is done in a store below another user's directory.
_files_perm_here() {
  _place_own_here || return 0
  ### ctrl pid
  rm -f -- ./permissions-fixed*.pid
  _mark_here "permissions-fixed-${_TODAY}.pid"
  ### files - site level; a Drupal 7 files/private is private data like the
  ### private store and takes its modes once they drop the world bits, and
  ### so do the subtrees nginx denies (_SITE_DENIED_RE): a store walk must
  ### never open them again
  if [ "${_priv_d}" = "02775" ]; then
    _fwalk_own_here d 02775 .
    _fwalk_own_here f 0664 .
  else
    _fwalk_own_here d 02775 . -regextype posix-extended \
      \( -path ./private -o -iregex "${_SITE_DENIED_RE}" \) -prune -o
    _fwalk_own_here f 0664 . -regextype posix-extended \
      \( -path ./private -o -iregex "${_SITE_DENIED_RE}" \) -prune -o
    if [ -d ./private ] && [ ! -L ./private ]; then
      _fwalk_own_here d "${_priv_d}" ./private
      _fwalk_own_here f "${_priv_f}" ./private
    fi
    _fwalk_own_here d "${_priv_d}" . -regextype posix-extended -path ./private -prune -o \
      -iregex "(${_SITE_DENIED_RE})(/.*)?"
    _fwalk_own_here f "${_priv_f}" . -regextype posix-extended -path ./private -prune -o \
      -iregex "(${_SITE_DENIED_RE})(/.*)?"
  fi
  _chmod_own_here d 02775 .
}

# The private store, run inside it (entered for real), the same way.
_priv_perm_here() {
  _place_own_here || return 0
  _fwalk_own_here d "${_priv_d}" .
  _fwalk_own_here f "${_priv_f}" .
}

# Group read for an entry the account's web server wrote closed, set through
# the open handle: each ./name -execdir hands over is opened without
# following a link or blocking on a FIFO, and changed only while its group
# is the gid $1 and its owner one of the uids in $2 (a comma list). A file
# gets group read, a directory group read and search, and every other bit
# stays; a regular file with more than one link is left alone, as the walks
# above leave it. Prints how many it changed.
_GREAD_PL='use Fcntl;
my $g = shift @ARGV;
my %u = map { $_ => 1 } grep { /^[1-9][0-9]*$/ } split(/,/, shift @ARGV);
$g =~ /^[0-9]+$/ or exit 1;
my $n = 0;
for my $f (@ARGV) {
  next unless $f =~ m{^\./[^/]+$};
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if (@s && $u{$s[4]} && $s[5] == $g) {
    my $m = $s[2] & 07777;
    if (-d _) {
      $n++ if ($m & 0050) != 0050 && chmod($m | 0050, $h);
    }
    elsif (-f _ && $s[3] == 1) {
      $n++ if !($m & 0040) && chmod($m | 0040, $h);
    }
  }
  close($h);
}
print "$n\n";
exit 0;'

# The store in the current (pinned) directory: every entry below it that
# one of the account's web users ($2, uids as a comma list) owns in the web
# group ($1, a gid) without group read (and search, for a directory), handed
# to _GREAD_PL from -execdir, which never follows a link. Prints the count.
_backup_read_here() {
  local _u _c _tot=0
  local -a _ids=() _who=()
  IFS=, read -r -a _ids <<< "${2}"
  for _u in "${_ids[@]}"; do
    [[ "${_u}" =~ ^[1-9][0-9]*$ ]] || continue
    [ "${#_who[@]}" -gt 0 ] && _who+=( -o )
    _who+=( -uid "${_u}" )
  done
  if [ "${#_who[@]}" -eq 0 ]; then
    echo 0
    return 0
  fi
  while read -r _c; do
    [[ "${_c}" =~ ^[0-9]+$ ]] && _tot=$(( _tot + _c ))
  done < <(find . -mindepth 1 -gid "${1}" \( "${_who[@]}" \) \
    \( \( -type d ! -perm -g+rx \) -o \( -type f ! -perm -g+r \) \) \
    -execdir perl -e "${_GREAD_PL}" "${1}" "${2}" {} + 2> /dev/null)
  echo "${_tot}"
}

# --backup-read: what a backup of the site needs to read, in its own files
# and private stores (_store_dir), and nothing else. The web group and the
# web users are the account's own, derived on the box, never taken from argv.
_backup_read() {
  local _acct _wg _gid _uids _d _what _c _tot=0
  case "${site_path}/" in
    /data/disk/*/*)
      _acct="${site_path#/data/disk/}"
      _acct="${_acct%%/*}"
      ;;
    *)
      printf "Nothing to open: %s is not an Octopus account's site.\n" "${site_path}"
      return 0
      ;;
  esac
  case "${_acct}" in
    ""|*[!a-z0-9-]*)
      printf "Error: unexpected account in %s; refusing.\n" "${site_path}" >&2
      return 1
      ;;
  esac
  _wg=$(_site_web_group "${site_path}")
  _gid=$(getent group "${_wg}" 2> /dev/null | cut -d: -f3)
  if [[ ! "${_gid}" =~ ^[0-9]+$ ]]; then
    printf "Error: no web group for %s; refusing.\n" "${site_path}" >&2
    return 1
  fi
  # The account's web users as BOA names its pools' users: <account>.web
  # and <account>.<version>.web.
  _uids=$(getent passwd | awk -F: -v a="${_acct}" \
    '$1 == a ".web" || $1 ~ ("^" a "\\.[0-9]+\\.web$") { if ($3 ~ /^[1-9][0-9]*$/) { printf "%s%s", s, $3; s = "," } }')
  if [ -z "${_uids}" ]; then
    printf "Nothing to open: %s has no web users.\n" "${_acct}"
    return 0
  fi
  for _what in files private; do
    _d=$(_store_dir "${site_path}/${_what}") || continue
    _c=$(_in_pinned_dir "${_d}" _backup_read_here "${_gid}" "${_uids}") || continue
    [[ "${_c}" =~ ^[0-9]+$ ]] && _tot=$(( _tot + _c ))
  done
  printf "Group read given to %s entries the web server wrote closed in %s.\n" "${_tot}" "${site_path}"
  return 0
}

site_path=${1%/}
_mode_backup_read="NO"

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --site-path=*)
        site_path="${1#*=}"
        ;;
    --backup-read)
        _mode_backup_read="YES"
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

# A backup's read: nothing of the modes below, and only for a Drupal site.
if [ "${_mode_backup_read}" = "YES" ]; then
  if [ -z "${site_path}" ] || [ ! -f "${site_path}/settings.php" ]; then
    printf "Error: Please provide a valid Drupal site directory.\n"
    exit 1
  fi
  _validate_path_prefix "${site_path}"
  _backup_read
  exit $?
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
  _own_uids_or_leave
  # Capsule permission model (spike-proven): code 0755/0644; the writable
  # set 02775 dirs + g+rw files (FPM writes via GROUP; setgid keeps the
  # group on web-created entries); the capsule's own bin/ stays executable
  # (the enforced-PHP wrapper and the upgrade engine exec bin/grav, bin/gpm).
  # Runs inside the real site directory (_in_pinned_dir, _grav_site_perm_here).
  printf "Setting Grav permissions of %s\n" "${site_path}"
  _owners_left_note "$(_in_pinned_dir "${site_path}" _grav_site_perm_here)"
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
  _own_uids_or_leave
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
  _owners_left_note "$(_in_pinned_dir "${site_path}" _txp_site_perm_here)"
  echo "Done setting proper permissions of files and directories (Textpattern site)."
  exit 0
fi

if [ -z "${site_path}" ] || [ ! -f "${site_path}/settings.php" ]; then
  printf "Error: Please provide a valid Drupal site directory.\n"
  exit 1
fi

_validate_path_prefix "${site_path}"
_own_uids_or_leave

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

### Private files keep no world bits once the account (for a site of the
### master, the master) has its own web group: its pools, backend user and
### shell users reach them through that group, and nginx never serves them
### directly. Until then, as always.
_priv_d=02775
_priv_f=0664
case "$(_site_web_group "${site_path}")" in
  wg-*) _priv_d=02770; _priv_f=0660 ;;
esac

### modules, themes and libraries are names the tenant can plant: it can create
### the site dir itself under the group-writable sites/ (02771), and the
### site-level code dirs are 02775 and group-writable. The rm below and the find start
### points walk THROUGH them, while _chmod_own_here protects only the final
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
### Every find walk below sets modes through _SAT_CHMOD_OWN_PL: a name
### swapped for a link during the walk is refused, not followed. What the
### walks leave as another user's, by dev:ino, for one Notice.
_LEFT=$(_in_pinned_dir "${site_path}" _site_dir_perm_here 2> /dev/null)

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
  _LEFT="${_LEFT}"$'\n'"$(_in_pinned_dir "${_files_dir}" _files_perm_here 2> /dev/null)"
  ### private - site level
  if [ -n "${_priv_dir}" ]; then
    _LEFT="${_LEFT}"$'\n'"$(_in_pinned_dir "${_priv_dir}" _priv_perm_here 2> /dev/null)"
  fi
  ### known exceptions
  _LEFT="${_LEFT}"$'\n'"$(_chmod_own_in "${_files_dir}" f 0644 .htaccess)"
fi
_owners_left_note "${_LEFT}"

echo "Done setting proper permissions on site files and directories."
