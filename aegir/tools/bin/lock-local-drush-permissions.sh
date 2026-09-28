#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to lock permissions on local Drush. You need
to provide the following argument:

  --root: Path to the root of your Drupal installation.
  --mode: Action mode lock/unlock (defaults to 'lock')

Usage: (sudo) ${0##*/} --root=PATH --mode=MODE
Example: (sudo) ${0##*/} --root=/var/aegir/platforms/drupal-10.1
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# Same defence pattern as the fix-drupal-* helpers: the account owns the
# names under ${drupal_root}/vendor, so any of them can be a link, and the
# modes set here through the NOPASSWD sudo entry point land only inside the
# caller's own tree, never through a link.
_validate_path_prefix() {
  # Scope the resolved path to the SUDO caller's OWN home tree (aegir ->
  # /var/aegir, Octopus oN -> /data/disk/oN), not merely "some BOA tree": a
  # tenant must not drive this root-run chmod against another tenant's
  # /data/disk/oM/ files. Validating the realpath (not the raw arg) also defeats
  # a symlink planted inside the caller's own tree that points out to another
  # tenant. A direct root run (no SUDO_USER) is trusted and keeps the historical
  # BOA-tree allowlist; its targets are held to the tree of the account the
  # root lies in (/var/aegir, /data/disk/<oN> or /home/<user>).
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
    _ROOT_RESOLVED="${_resolved}"
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
  # Publish what was validated so every later op is pinned to it.
  _ROOT_RESOLVED="${_resolved}"
  _SCOPE_ROOT="${_home}"
}

# Run "$@" inside the directory $1, a path resolved just before: entered with
# cd -P and checked there with pwd -P, so a name on the way the account
# swapped for a link since is never followed, and ./name then stays in that
# directory whatever is swapped.
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

# ./$2 in the current (pinned) directory given the mode $1 through
# _FCHMOD_PL: a regular file or a directory, never through a link.
_chmod_nolink_here() {
  perl -e "${_FCHMOD_PL}" a "${1}" "./${2}"
}

_chmod_safe() {
  local _mode=$1
  shift
  local _p _r
  for _p in "$@"; do
    [ -L "${_p}" ] && continue
    [ -e "${_p}" ] || continue
    # -L guards the FINAL component only: a tenant-planted INTERMEDIATE (vendor,
    # vendor/symfony) still points this root chmod out of the validated tree, so
    # re-check the resolved target against the scope _validate_path_prefix set.
    [ -n "${_SCOPE_ROOT}" ] || continue
    _r=$(realpath -e -- "${_p}" 2>/dev/null) || continue
    case "${_r}/" in
      "${_SCOPE_ROOT}"/*) ;;
      *)
        printf "Error: refusing out-of-scope path %s -> %s\n" "${_p}" "${_r}" >&2
        continue
        ;;
    esac
    # The checked target, never the path walked again: a directory takes the
    # mode on '.' once entered for real, anything else on its own name inside
    # its directory entered for real, so a name swapped for a link after the
    # check above is never followed.
    if [ -d "${_r}" ]; then
      _in_pinned_dir "${_r}" chmod "${_mode}" .
    else
      _in_pinned_dir "${_r%/*}" _chmod_nolink_here "${_mode}" "${_r##*/}"
    fi
  done
}

# Positional invocation is rejected by the parser below; both values come from
# the named flags, and 'lock' is the documented default.
drupal_root=""
mode="lock"

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root=*)
        drupal_root="${1#*=}"
        ;;
    --mode=*)
        mode="${1#*=}"
        ;;
    --help) print_help;;
    *)
      printf "Error: Invalid argument, run --help for valid arguments.\n"
      exit 1
  esac
  shift
done

# Grouped on purpose: && and || bind equally left-to-right, so without the
# braces the whole verdict hangs on the D7 marker alone.
if [ -z "${drupal_root}" ] \
  || [ ! -d "${drupal_root}/sites" ] \
  || { [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
    && [ ! -f "${drupal_root}/modules/system/system.module" ]; }; then
    printf "Error: Please provide a valid Drupal root directory.\n"
    exit 1
fi

# Set by _validate_path_prefix; empty means "not validated" and _chmod_safe
# refuses rather than falling open.
_ROOT_RESOLVED=""
_SCOPE_ROOT=""
_validate_path_prefix "${drupal_root}"
# Operate on the path that was actually validated: a relative --root would be
# re-resolved against the NEW cwd after the cd below, and a --root swapped for a
# symlink after the realpath check would be followed by every raw-path op.
drupal_root="${_ROOT_RESOLVED}"

cd "${drupal_root}" || exit 1

if [ -e "${drupal_root}/core" ]; then
  if [ -e "${drupal_root}/vendor" ]; then
    if [ "$mode" = "unlock" ]; then
      printf "Unlocking Drush and Symfony Console Input in "${drupal_root}/vendor"...\n"
      _chmod_safe 0775 "${drupal_root}/vendor/drush"
      _chmod_safe 0775 "${drupal_root}/vendor/symfony/console/Input"
      _chmod_safe 0775 "${drupal_root}/vendor/symfony/console/Style"
    else
      printf "Locking Drush and Symfony Console Input in %s...\n" "${drupal_root}/vendor"
      _chmod_safe 0400 "${drupal_root}/vendor/drush"
      _chmod_safe 0400 "${drupal_root}/vendor/symfony/console/Input"
      _chmod_safe 0400 "${drupal_root}/vendor/symfony/console/Style"
    fi
  elif [ -e "${drupal_root}/../vendor" ]; then
    if [ "$mode" = "unlock" ]; then
      printf "Unlocking Drush and Symfony Console Input in "${drupal_root}/../vendor"...\n"
      _chmod_safe 0775 "${drupal_root}/../vendor/drush"
      _chmod_safe 0775 "${drupal_root}/../vendor/symfony/console/Input"
      _chmod_safe 0775 "${drupal_root}/../vendor/symfony/console/Style"
    else
      printf "Locking Drush and Symfony Console Input in "${drupal_root}/../vendor"...\n"
      _chmod_safe 0400 "${drupal_root}/../vendor/drush"
      _chmod_safe 0400 "${drupal_root}/../vendor/symfony/console/Input"
      _chmod_safe 0400 "${drupal_root}/../vendor/symfony/console/Style"
    fi
  fi
  if [ "$mode" = "unlock" ]; then
    echo "Done Unlocking Drush and Symfony Console Input."
  else
    echo "Done Locking Drush and Symfony Console Input."
  fi
fi


