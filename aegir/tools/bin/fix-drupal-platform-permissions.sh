#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file permissions of a Drupal platform. You need
to provide the following argument:

  --root: Path to the root of your Drupal installation.

Usage: (sudo) ${0##*/} --root=PATH
Example: (sudo) ${0##*/} --root=/var/aegir/platforms/drupal-7.50
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
# and the account owns the names under ${drupal_root}, so any of them can be
# a link. Defence:
#  1. _validate_path_prefix on the caller-supplied root.
#  2. Every mode is set through _SAT_CHMOD_OWN_PL, on the name itself
#     (_chmod_own_here) or from a find walk (_fwalk_own_here): a link is
#     never followed (root-managed legacy symlinks stay untouched, and
#     symlinks put there cannot carry a mode to another file), whether it
#     was there before or put there during the run. find's -type test alone
#     would not stop a later chmod by path.
#  3. Every step runs inside a directory entered for real (_in_pinned_dir),
#     on ./names there, so a name on the way swapped for a link after the
#     root was resolved is never followed.
#  4. The account's users can rename into the platform what another account
#     left group-writable, a whole directory or a single file, so only what
#     root or the platform's own users own gets a mode (_site_walk_uids,
#     from the root as resolved): another user's entry is left as it is
#     with everything below it, and nothing is made, renamed or removed in
#     a place it owns.
_validate_path_prefix() {
  # Scope the resolved path to the SUDO caller's OWN home tree (aegir ->
  # /var/aegir, Octopus oN -> /data/disk/oN), not merely "some BOA tree": a
  # tenant must not drive this root-run chmod against another tenant's
  # /data/disk/oM/ files. Validating the realpath (not the raw arg) also defeats
  # a symlink planted inside the caller's own tree that points out to another
  # tenant. A direct root run (no SUDO_USER) is trusted and keeps the historical
  # BOA-tree allowlist; its vendor legs are held to the tree of the account
  # the root lies in (/var/aegir, /data/disk/<oN> or /home/<user>).
  local _resolved _caller _home
  _resolved=$(realpath -e -- "$1" 2>/dev/null) || {
    printf "Error: path does not resolve: %s\n" "$1" >&2
    exit 1
  }
  _caller="${SUDO_USER:-}"
  if [ -z "${_caller}" ]; then
    case "${_resolved}/" in
      /var/aegir/*) _SCOPE_ROOT="/var/aegir" ;;
      /data/disk/*)
        _SCOPE_ROOT="${_resolved#/data/disk/}"
        _SCOPE_ROOT="/data/disk/${_SCOPE_ROOT%%/*}"
        ;;
      /home/*)
        _SCOPE_ROOT="${_resolved#/home/}"
        _SCOPE_ROOT="/home/${_SCOPE_ROOT%%/*}"
        ;;
      *)
        printf "Error: path outside allowed roots (/var/aegir, /data/disk, /home): %s\n" "${_resolved}" >&2
        exit 1
        ;;
    esac
    return 0
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
  # The scope the vendor legs are held to (_in_scoped_dir).
  _SCOPE_ROOT="${_home}"
}

# The root is resolved once below, but its account owns every name on the
# way (~/static and the platform tree), so any of them can be swapped for a
# link at any time. Every act runs inside a directory entered for real: cd -P,
# then "$@" only while pwd -P there is still the resolved path, so a link put
# on the way since is never followed, and ./name then stays in that
# directory whatever is swapped. $1 = a path resolved once above.
_in_pinned_dir() {
  local _d="${1}"
  shift
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_d}" ] && "$@" )
}

# vendor may be a link to elsewhere in the caller's own tree, and the lock
# and drush legs follow it as they always did, but never out of that tree:
# "$@" runs inside the directory $1 resolves to now, only when that is inside
# the scope _validate_path_prefix set, entered for real (_in_pinned_dir).
_in_scoped_dir() {
  local _r
  _r=$(realpath -e -- "${1}" 2> /dev/null) || return 1
  [ -n "${_SCOPE_ROOT}" ] || return 1
  case "${_r}/" in
    "${_SCOPE_ROOT}"/*) ;;
    *)
      printf "Error: refusing out-of-scope path %s -> %s\n" "${1}" "${_r}" >&2
      return 1
      ;;
  esac
  shift
  _in_pinned_dir "${_r}" "$@"
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
# The uids the walks below act for, comma-separated, from the root as
# resolved, never from argv: under /data/disk/<account>/ that account's
# (_acct_walk_uids); under /var/aegir/ root's, aegir's, those of the
# master's pool users wwwNN and www-data's, the web server's user, which no
# account's login can be and a plain Aegir server's PHP runs as. Status 1,
# and nothing, for any other path, or when the account or aegir is not in
# passwd. A uid no passwd entry names counts as the platform's own too
# (_SAT_CHMOD_OWN_PL): a login removed before its files were handed to its
# account left those.
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
        [[ "${_n}" =~ ^(aegir|www-data|www[0-9][0-9])$ ]] || continue
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
# The uids the walks act for in _OWN_UIDS (_site_walk_uids); a root in
# neither an account's tree nor the master's is left as it is, with one
# Notice and nothing changed.
_root_uids_or_leave() {
  _OWN_UIDS=$(_site_walk_uids "${drupal_root}") || _OWN_UIDS=""
  [[ "${_OWN_UIDS}" =~ ^0(,[1-9][0-9]*)*$ ]] && return 0
  printf "Notice: %s is in neither an account's tree nor the master's; nothing changed.\n" \
    "${drupal_root}" >&2
  exit 0
}
# One line for what the walks left as another user's, each entry once by
# the dev:ino the walkers print ($1, all they printed), on fd 3 beside the
# other notes.
_root_owners_left_note() {
  local _n
  _n=$(printf '%s\n' "${1}" | grep -E '^[0-9]+:[0-9]+$' | sort -u | grep -c .)
  [[ "${_n}" =~ ^[1-9][0-9]*$ ]] || return 0
  printf "Notice: %s entries owned by another user left as they were in the platform %s\n" \
    "${_n}" "${drupal_root}" >&3
  return 0
}
# What "$@" prints kept in _LEFT, for that line: the walkers print the
# dev:ino of each entry they leave.
_left_add() {
  _LEFT="${_LEFT}"$'\n'"$("$@")"
}
# The root's place first, tested by $1: nothing is done in a platform that
# is, or is below, a directory another user owns; the run then ends with
# its Notice and its last line ($2).
_root_place_or_leave() {
  _LEFT=$(_in_pinned_dir "${drupal_root}" "${1}") && return 0
  _root_owners_left_note "${_LEFT}"
  echo "${2}"
  exit 0
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
# with the platform's own uids (_OWN_UIDS). A pattern that matches nothing
# is skipped. Prints dev:ino of each entry left for another owner; status 1
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
# The mode $1 on each directory and each single-link regular file in the
# current (pinned) directory that matches a pattern after it: both kinds,
# as one chmod by name set either.
_chmod_any_own_here() {
  local _mode="${1}"
  shift
  _chmod_own_here d "${_mode}" "$@"
  _chmod_own_here f "${_mode}" "$@"
}
# _chmod_any_own_here inside the directory $1 (resolved once above), entered
# for real.
_chmod_any_own_in() {
  local _d="${1}"
  shift
  _in_pinned_dir "${_d}" _chmod_any_own_here "$@"
}
# Status 0 while the current (pinned) directory and every directory above
# it are root's or the platform's own users' (_SAT_CHMOD_OWN_PL given . as a
# file, which sets nothing on a directory); otherwise the directory another
# user owns is printed (dev:ino) and the status is 1.
_place_own_here() {
  _chmod_own_here f 0644 .
}
# "$@" in the current (pinned) directory only while that place is root's
# or the platform's own users' (_place_own_here): nothing is made, renamed
# or removed in a directory another user owns, or below one.
_in_own_here() {
  _place_own_here > /dev/null || return 0
  "$@"
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
# through _FCHMOD_PL, then _links_left_note on the same selection. Kept as
# the site script's copy; every walk below goes through _fwalk_own_here.
_fwalk_here() {
  local _m="${1}" _rc
  shift
  find "$@" -type f -exec perl -e "${_FCHMOD_PL}" f "${_m}" {} +
  _rc=$?
  _links_left_note "$@"
  return "${_rc}"
}
# find's tests, in _NOT_OWN, for an entry another user owns as the walkers
# read it: its uid is none of _OWN_UIDS and a passwd entry names it
# (-nouser is true for a uid no entry names). A walk hands such an entry to
# its walker whatever state it is in, so it is left and counted as before.
_not_own_tests() {
  local _u
  local -a _ids=()
  _NOT_OWN=()
  IFS=, read -r -a _ids <<< "${_OWN_UIDS}"
  for _u in "${_ids[@]}"; do
    _NOT_OWN+=( ! -uid "${_u}" )
  done
  _NOT_OWN+=( ! -nouser )
}
# Mode $2 on every directory ($1 d) or single-link regular file ($1 f) the
# find start points and tests after it select (any tests apply first), set
# from the directory find holds (-execdir) through _SAT_CHMOD_OWN_PL with
# the platform's own uids (_OWN_UIDS): what another user owns, and
# everything below a directory another user owns, keeps its mode, its
# dev:ino printed. A file walk ends with _links_left_note on the same
# selection. Perl starts only in a directory that holds an entry whose mode
# is not yet the walk's, or another user's entry (_not_own_tests): a tree
# already at its modes costs the walk alone. A directory keeps its set-ID
# bits under a mode of fewer than five digits, so any of them may stand
# beside that mode. A mode that is not three or four octal digits, or five
# with a leading 0, is walked as before: every entry goes to perl.
_fwalk_own_here() {
  local _t="${1}" _m="${2}" _rc _v _s _p
  local -a _need=()
  shift 2
  [[ "${_OWN_UIDS}" =~ ^0(,[1-9][0-9]*)*$ ]] || return 1
  if [[ "${_t}" =~ ^[df]$ && "${_m}" =~ ^0?[0-7]{3,4}$ ]]; then
    _v=$(( 8#${_m} ))
    if [[ "${_t}" == "d" && "${#_m}" -lt 5 ]]; then
      for _s in 0 02000 04000 06000; do
        (( (_v & 06000 & ~_s) == 0 )) || continue
        printf -v _p '%04o' "$(( (_v & 01777) | _s ))"
        _need+=( ! -perm "${_p}" )
      done
    else
      printf -v _p '%04o' "${_v}"
      _need=( ! -perm "${_p}" )
    fi
    _not_own_tests
    _need=( \( "${_need[@]}" -o "${_NOT_OWN[@]}" \) )
  fi
  find "$@" -type "${_t}" "${_need[@]}" \
    -execdir perl -e "${_SAT_CHMOD_OWN_PL}" -- "${_OWN_UIDS}" "${_t}" "${_m}" {} +
  _rc=$?
  [ "${_t}" != "f" ] || _links_left_note "$@"
  return "${_rc}"
}
# Mode $2 on every entry of type $1 (d or f) below the start points after
# them, walked from the current (pinned) directory by _fwalk_own_here. Only
# start points that are real directories here are walked: a Drupal 7 root
# has no core/, a Drupal 8+ root no includes/ or misc/, and find printed an
# error into the task log for each one missing. A link was never walked.
_walk_here() {
  local _t="${1}" _m="${2}" _d
  local -a _s=()
  shift 2
  for _d in "$@"; do
    [ -d "${_d}" ] && [ ! -L "${_d}" ] && _s+=("${_d}")
  done
  [ "${#_s[@]}" -gt 0 ] || return 0
  _fwalk_own_here "${_t}" "${_m}" "${_s[@]}"
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

# The day marker in the current (pinned) sites/all/libraries: every earlier
# one removed, today's put as _mark_here puts it.
_perm_marker_here() {
  rm -f -- ./permissions-fixed*.pid
  _mark_here "permissions-fixed-${_TODAY}.pid"
}

# ./drush in the current (pinned) directory set aside as ./.off-drush: -T
# never moves it into a directory or through a link found at the new name.
_off_drush_here() {
  [ -e ./drush ] || return 0
  mv -f -T -- ./drush ./.off-drush
}

# Each Grav capsule in the current (pinned) sites/, entered for real.
# Nothing is done in a capsule that is, or is below, a directory another
# user owns.
_grav_capsules_perm_here() {
  local _c _here
  _here="$(pwd -P)"
  for _c in ./*/; do
    _c="${_c#./}"
    _in_pinned_dir "${_here}/${_c%/}" _grav_capsule_perm_here
  done
}
_grav_capsule_perm_here() {
  local _wd _sd _here
  [ -f ./system/defines.php ] || return 0
  _here="$(pwd -P)"
  _place_own_here || return 0
  # The capsule's own bin/ must stay executable (the enforced-PHP wrapper
  # and the upgrade engine exec bin/grav and bin/gpm).
  _chmod_any_own_in "${_here}/bin" 0755 '*'
  for _wd in user cache logs tmp backup images assets; do
    [ -d "./${_wd}" ] || continue
    _fwalk_own_here d 02775 "./${_wd}" 2> /dev/null
    _fwalk_own_here f 0664 "./${_wd}" 2> /dev/null
  done
  # Secret surfaces AFTER the generic pass, which would re-widen them
  # otherwise: group-rw for FPM, owner-rw for the CLI, NO world
  # bits; the root .env keeps FPM's read via group.
  for _sd in accounts config env; do
    [ -d "./user/${_sd}" ] || continue
    _in_pinned_dir "${_here}/user" _fwalk_own_here d 02770 "./${_sd}" 2> /dev/null
    _in_pinned_dir "${_here}/user" _fwalk_own_here f 0660 "./${_sd}" 2> /dev/null
  done
  _chmod_any_own_here 0640 .env
  _chmod_any_own_here 0440 drushrc.php
}

_SCOPE_ROOT=""
drupal_root=${1%/}

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root=*)
        drupal_root="${1#*=}"
        ;;
    --help) print_help;;
    *)
      printf "Error: Invalid argument, run --help for valid arguments.\n"
      exit 1
  esac
  shift
done

### Resolve the caller-supplied root ONCE, before any check or operation reads
### it: every branch below re-walks the raw argument, and ~/static is 02775 on
### tenant codebases, so the tenant owns the name it was handed and could
### re-point it between _validate_path_prefix and the chmod legs. An
### empty result falls through to the "valid Drupal root" refusal below.
if [ -n "${drupal_root}" ] && [ -e "${drupal_root}" ]; then
  drupal_root=$(realpath -e -- "${drupal_root}" 2>/dev/null) || drupal_root=""
fi

# --- Grav 2 platform (site capsules) -----------------------------------------
# A Grav root carries no Drupal system.module; detect it positively and run
# the capsule model instead of refusing (union seam: further foreign-CMS
# branches join here the same way).
if [ -n "${drupal_root}" ] \
  && [ -f "${drupal_root}/bin/grav" ] \
  && [ -f "${drupal_root}/system/defines.php" ] \
  && [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
  && [ ! -f "${drupal_root}/modules/system/system.module" ]; then
  _validate_path_prefix "${drupal_root}"
  _root_uids_or_leave
  # Capsule permission model (spike-proven): code 0755/0644; the writable
  # set 02775 dirs + g+rw files (FPM writes via GROUP; setgid keeps the
  # group on web-created entries).
  # Each pass runs inside the real root or capsule (_in_pinned_dir). A
  # capsule is a site: what another user owns in it, or a capsule another
  # user owns, is left whole.
  printf "Setting Grav permissions of %s\n" "${drupal_root}"
  _root_place_or_leave _place_own_here \
    "Done setting proper permissions of files and directories (Grav)."
  _left_add _in_pinned_dir "${drupal_root}" _fwalk_own_here d 0755 . \
    -path "./sites/*/user" -prune \
    -o -path "./sites/*/cache" -prune \
    -o -path "./sites/*/logs" -prune \
    -o -path "./sites/*/tmp" -prune \
    -o -path "./sites/*/backup" -prune \
    -o -path "./sites/*/images" -prune \
    -o -path "./sites/*/assets" -prune \
    -o 2> /dev/null
  _left_add _in_pinned_dir "${drupal_root}" _fwalk_own_here f 0644 . \
    -path "./sites/*/user" -prune \
    -o -path "./sites/*/cache" -prune \
    -o -path "./sites/*/logs" -prune \
    -o -path "./sites/*/tmp" -prune \
    -o -path "./sites/*/backup" -prune \
    -o -path "./sites/*/images" -prune \
    -o -path "./sites/*/assets" -prune \
    -o 2> /dev/null
  _left_add _in_pinned_dir "${drupal_root}/sites" _grav_capsules_perm_here
  _left_add _chmod_any_own_in "${drupal_root}/bin" 0755 '*'
  _root_owners_left_note "${_LEFT}"
  echo "Done setting proper permissions of files and directories (Grav)."
  exit 0
fi

# --- Textpattern platform (shared core) --------------------------------------
# A TXP root carries no Drupal system.module; detect it positively (the same
# probe as codebasecheck: textpattern/lib/constants.php + css.php + no core/)
# and run the shared-core model instead of refusing.
if [ -n "${drupal_root}" ] \
  && [ -f "${drupal_root}/textpattern/lib/constants.php" ] \
  && [ -f "${drupal_root}/css.php" ] \
  && [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
  && [ ! -f "${drupal_root}/modules/system/system.module" ]; then
  _validate_path_prefix "${drupal_root}"
  _root_uids_or_leave
  # Shared-core permission model: pristine core 0755/0644. Everything under
  # sites/* is the SITE scripts' territory -- those trees carry 0440 secrets
  # (config.php, drushrc.php) and 02775 setgid writable dirs; a platform-wide
  # chmod would widen the secrets and strip the setgid bits (the drushrc
  # lesson: never fight the writer), so sites/* is pruned outright.
  printf "Setting Textpattern permissions of %s\n" "${drupal_root}"
  _root_place_or_leave _place_own_here \
    "Done setting proper permissions of files and directories (Textpattern platform)."
  _left_add _in_pinned_dir "${drupal_root}" _fwalk_own_here d 0755 . \
    -path "./sites/*" -prune -o 2> /dev/null
  _left_add _in_pinned_dir "${drupal_root}" _fwalk_own_here f 0644 . \
    -path "./sites/*" -prune -o 2> /dev/null
  _root_owners_left_note "${_LEFT}"
  echo "Done setting proper permissions of files and directories (Textpattern platform)."
  exit 0
fi

# Every generation has sites/ and one of the two system.module paths; the
# ungrouped form let a Drupal 7 tree without sites/ through (see the
# ownership twin).
if [ -z "${drupal_root}" ] \
  || [ ! -d "${drupal_root}/sites" ] \
  || { [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
    && [ ! -f "${drupal_root}/modules/system/system.module" ]; }; then
    printf "Error: Please provide a valid Drupal root directory.\n"
    exit 1
fi

_validate_path_prefix "${drupal_root}"
_root_uids_or_leave

### sites and sites/all are names a tenant can plant as symlinks (the docroot
### is group-writable) and the find/chmod passes below walk THROUGH them;
### _chmod_own_here protects only the final component. A symlinked skeleton
### is never legitimate.
if [ -L "${drupal_root}/sites" ] || [ -L "${drupal_root}/sites/all" ]; then
  printf "Error: sites or sites/all is a symlink in %s; refusing.\n" "${drupal_root}" >&2
  exit 1
fi
### The four names under sites/all are plantable the same way, and the day
### marker's rm glob and touch, the mkdir and the tcpdf leg below resolve
### through them; _chmod_own_here protects only the final component. Never
### legitimately symlinks (the o_contrib* links live under the platform
### root's own modules/, never under sites/all): refuse, as the site-level
### helper does; the nightly withholds the same legs instead. Inside a
### skeleton that passed, a symlinked entry is skipped per entry rather
### than refused (the sites/<uri> sweep below). tcpdf and its cache child
### are prechecked at their own leg below.
for _d in modules themes libraries drush; do
  if [ -L "${drupal_root}/sites/all/${_d}" ]; then
    printf "Error: sites/all/%s is a symlink in %s; refusing.\n" "${_d}" "${drupal_root}" >&2
    exit 1
  fi
done

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

### Group write is the shell pair's free-ride territory under ~/static only.
### A hostmaster tree (aegir/distro on an Octopus account, /var/aegir/distro on
### the master) serves nothing an lshell user may touch: no group write at all.
### A built-in platform (~/distro and every other root) keeps its documented
### tenant-writable sites/all/{modules,themes,libraries}, while core, profiles,
### includes, vendor and the platform root itself take no group write: the
### backend user owns them and the web user only reads.
if [[ "${drupal_root}" =~ /aegir/distro/ ]]; then
  _MODE_DIR=0755
  _MODE_FILE=0644
  _SA_DIR=0755
  _SA_FILE=0644
elif [[ "${drupal_root}" =~ /static/ ]]; then
  _MODE_DIR=02775
  _MODE_FILE=0664
  _SA_DIR=02775
  _SA_FILE=0664
else
  _MODE_DIR=0755
  _MODE_FILE=0644
  _SA_DIR=02775
  _SA_FILE=0664
fi

### Fix permissions only once daily, unless it's Drupal 8 or newer
if [ -e "${drupal_root}/sites/all/libraries/permissions-fixed-${_TODAY}.pid" ]; then
  if [ -e "${drupal_root}/core/themes/olivero" ] \
    || [ ! -e "${drupal_root}/core/themes/classy" ]; then
    _drupal_eight_nine_ten=TRUE
  else
    exit 0
  fi
fi

### Every act below runs inside a directory entered for real
### (_in_pinned_dir) and names only ./entries there; refuse now when the
### root itself cannot be entered as resolved.
if ! _in_pinned_dir "${drupal_root}" true; then
  printf "Error: %s is not a real directory; refusing.\n" "${drupal_root}" >&2
  exit 1
fi

printf 'Setting main permissions inside %s...\n' "${drupal_root}"
_root_place_or_leave _place_own_here \
  "Done setting proper permissions on platform files and directories."
### Nothing is made in a directory another user owns (_in_own_here), here
### and below; what the walks leave as another user's is kept in _LEFT for
### the one Notice.
_in_pinned_dir "${drupal_root}/sites" _in_own_here mkdir -p ./all
_in_pinned_dir "${drupal_root}/sites/all" \
  _in_own_here mkdir -p ./modules ./themes ./libraries ./drush

### Create ctrl pid
_in_pinned_dir "${drupal_root}/sites/all/libraries" \
  _in_own_here _perm_marker_here

printf 'Setting permissions of all codebase directories inside %s...\n' "${drupal_root}"
_left_add _in_pinned_dir "${drupal_root}" _walk_here d "${_MODE_DIR}" \
  ./modules ./themes ./libraries ./includes ./misc ./profiles ./core

printf 'Setting permissions of all codebase files inside %s...\n' "${drupal_root}"
_left_add _in_pinned_dir "${drupal_root}" _walk_here f "${_MODE_FILE}" \
  ./modules ./themes ./libraries ./includes ./misc ./profiles ./core

if [ -e "${drupal_root}/vendor" ]; then
  printf 'Setting permissions of all codebase directories inside %s...\n' "${drupal_root}/vendor"
  _left_add _in_pinned_dir "${drupal_root}" \
    _fwalk_own_here d "${_MODE_DIR}" ./vendor
  printf 'Setting permissions of all codebase files inside %s...\n' "${drupal_root}/vendor"
  _left_add _in_pinned_dir "${drupal_root}" \
    _fwalk_own_here f "${_MODE_FILE}" ./vendor
elif [ -e "${drupal_root}/../vendor" ]; then
  printf 'Setting permissions of all codebase directories inside %s...\n' "${drupal_root}/../vendor"
  _left_add _in_pinned_dir "${drupal_root%/*}" \
    _fwalk_own_here d "${_MODE_DIR}" ./vendor
  printf 'Setting permissions of all codebase files inside %s...\n' "${drupal_root}/../vendor"
  _left_add _in_pinned_dir "${drupal_root%/*}" \
    _fwalk_own_here f "${_MODE_FILE}" ./vendor
fi

### vendor is never symlink-prechecked (a link to elsewhere in the caller's
### own tree is followed, as before), so the drush and lock legs act only
### inside the directory it resolves to, held to the caller's tree
### (_in_scoped_dir).
if [ -e "${drupal_root}/vendor/bin/drush" ]; then
  _in_scoped_dir "${drupal_root}/vendor/bin" _in_own_here _off_drush_here
elif [ -e "${drupal_root}/../vendor/bin/drush" ]; then
  _in_scoped_dir "${drupal_root%/*}/vendor/bin" _in_own_here _off_drush_here
fi

if [ -e "${drupal_root}/vendor/drush/drush/drush" ]; then
  _in_scoped_dir "${drupal_root}/vendor/drush/drush" \
    _in_own_here _off_drush_here
elif [ -e "${drupal_root}/../vendor/drush/drush/drush" ]; then
  _in_scoped_dir "${drupal_root%/*}/vendor/drush/drush" \
    _in_own_here _off_drush_here
fi

if [ -e "${drupal_root}/vendor/drush/drush/drush.php" ]; then
  _left_add _in_scoped_dir "${drupal_root}/vendor/drush/drush" \
    _chmod_any_own_here 0775 drush.php
elif [ -e "${drupal_root}/../vendor/drush/drush/drush.php" ]; then
  _left_add _in_scoped_dir "${drupal_root%/*}/vendor/drush/drush" \
    _chmod_any_own_here 0775 drush.php
fi

_left_add _chmod_own_in "${drupal_root}" d "${_MODE_DIR}" .

if [ -d "${drupal_root}/web" ]; then
  _left_add _chmod_any_own_in "${drupal_root}" "${_MODE_DIR}" web
elif [ -d "${drupal_root}/docroot" ]; then
  _left_add _chmod_any_own_in "${drupal_root}" "${_MODE_DIR}" docroot
elif [ -d "${drupal_root}/html" ]; then
  _left_add _chmod_any_own_in "${drupal_root}" "${_MODE_DIR}" html
fi

printf 'Setting permissions of all codebase directories inside %s...\n' "${drupal_root}/sites/all"
_left_add _in_pinned_dir "${drupal_root}/sites/all" \
  _fwalk_own_here d "${_SA_DIR}" ./modules ./themes ./libraries

printf 'Setting permissions of all codebase files inside %s...\n' "${drupal_root}/sites/all"
_left_add _in_pinned_dir "${drupal_root}/sites/all" \
  _fwalk_own_here f "${_SA_FILE}" ./modules ./themes ./libraries

_left_add _chmod_any_own_in "${drupal_root}" 0644 '*.php'
_left_add _chmod_any_own_in "${drupal_root}" "${_MODE_FILE}" autoload.php
_left_add _chmod_any_own_in "${drupal_root}" 0751 sites
_left_add _chmod_any_own_in "${drupal_root}/sites" 0755 '*'
_left_add _chmod_any_own_in "${drupal_root}/sites" 0644 '*.php'
_left_add _chmod_any_own_in "${drupal_root}/sites" 0644 '*.txt'
_left_add _chmod_any_own_in "${drupal_root}/sites" 0644 '*.yml'
_left_add _chmod_any_own_in "${drupal_root}/sites/all" 0755 drush

### Tenant composer codebases (~/static, D8+): core's composer scaffold, run
### by the oN.ftp shell user (a group member, never the owner), rewrites its
### files under sites/ whenever one is missing or changed and insists on a
### writable parent first, so its two parents take group write here. Owner
### and the x-only bit for others stay as they are; BOA-built platforms keep
### the tight skeleton (omega8cc/boa#1936). Mirrored in night/20-sites.sh
### and provision's verify exit hook.
if [[ "${drupal_root}" =~ "/static/" ]] \
  && [ -e "${drupal_root}/core/lib/Drupal.php" ]; then
  _left_add _chmod_any_own_in "${drupal_root}" 02771 sites
  _left_add _chmod_any_own_in "${drupal_root}/sites" 02775 default
fi

### Lock Local Drush and Symfony Console Input/Style
if [ -e "${drupal_root}/core" ]; then
  if [ -e "${drupal_root}/vendor" ]; then
    printf 'Locking Drush and Symfony Console Input in %s...\n' "${drupal_root}/vendor"
    _left_add _in_scoped_dir "${drupal_root}/vendor" \
      _chmod_any_own_here 0400 drush
    _left_add _in_scoped_dir "${drupal_root}/vendor/symfony/console" \
      _chmod_any_own_here 0400 Input Style
  elif [ -e "${drupal_root}/../vendor" ]; then
    printf 'Locking Drush and Symfony Console Input in %s...\n' "${drupal_root}/../vendor"
    _left_add _in_scoped_dir "${drupal_root%/*}/vendor" \
      _chmod_any_own_here 0400 drush
    _left_add _in_scoped_dir "${drupal_root%/*}/vendor/symfony/console" \
      _chmod_any_own_here 0400 Input Style
  fi
fi

### Known exceptions
### tcpdf and its cache child are both names the tenant can plant under the
### 02775 libraries/. Precheck both, as the nightly does, and walk cache from
### inside it, entered for real, setting 775 on every file and directory
### there as chmod -R did, through _SAT_CHMOD_OWN_PL from find (chmod -R
### before coreutils 9.5 follows an entry swapped for a link during its
### walk); a real directory is treated exactly as before.
if [ ! -L "${drupal_root}/sites/all/libraries/tcpdf" ] \
  && [ ! -L "${drupal_root}/sites/all/libraries/tcpdf/cache" ]; then
  _left_add _in_pinned_dir "${drupal_root}/sites/all/libraries/tcpdf/cache" \
    _fwalk_own_here d 775 . 2> /dev/null
  _left_add _in_pinned_dir "${drupal_root}/sites/all/libraries/tcpdf/cache" \
    _fwalk_own_here f 775 . 2> /dev/null
fi
_left_add _chmod_any_own_in "${drupal_root}" 0644 .htaccess
_root_owners_left_note "${_LEFT}"

echo "Done setting proper permissions on platform files and directories."
