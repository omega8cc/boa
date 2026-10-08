#!/bin/bash

###
### 10-account.sh -- the per-Octopus-account maintenance worker. The whole
### per-account sequence (_account_process): drush prep, octopus.cnf email sync,
### the hostmaster vSet block, the per-site loop (_daily_process), platform GC,
### hostmaster LE, goaccess, and the final chattr relock. Run once per account by
### the owl.sh orchestrator as `10-account.sh <account-path>` (the unit of
### per-account parallelism); also sourceable for testing (defines functions only).
###
### Reads the per-run context from the run-freeze (/run/night/run.env via
### night_load_run_env): _NOW (keystone), _DOW, _O_CONTRIB*, _MODULES_*, _hostedSys,
### _APT_UPDATE and the cnf flags. Re-derives _hName and the per-account/per-site
### state from the <account> arg. Depends on night.inc.sh (drush8 wrappers, chattr,
### load, run-freeze, _apt_clean_update, _if_gen_goaccess) and 20-sites.sh
### (_daily_process + the per-site family), both sourced below.
###
# Default only: every worker sources /root/.barracuda.cnf after this
# file (night_load_run_env), so the cnf value wins; the literal keeps
# the read well-defined and fail-closed if a worker is ever driven
# outside that chain.
_GOACCESS_ALL=NO

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=dev
export _xSrl=588866devT01
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/20-sites.sh" ] && . /var/xdrago/night/20-sites.sh
# Fail closed: the two libraries are delivered by independent fNN fetches, so
# this worker can land ahead of a night.inc.sh that has no in-flight gate --
# and an undefined function returns 127, which the reap's "! _night_boa_pass_active"
# would read as "no pass running". Defined only if the real one is absent
command -v _night_boa_pass_active > /dev/null 2>&1 \
  || _night_boa_pass_active() { return 0; }
# Same reason, and the same direction as the reap gate: every
# "_provision_running && bail" is fail-OPEN when the function is missing, so the
# cleanup would run through a live Provision task. Deliberately the BROAD
# substring form rather than a copy of the anchored library body: it runs only
# while the library is briefly behind, and over-matching there just skips a
# cleanup. A stub claiming a task is always active would instead spin the drain
# loop below for its full 60s and defer every relocation, every night.
command -v _provision_running > /dev/null 2>&1 \
  || _provision_running() { pgrep -f provision > /dev/null 2>&1; }
# Same skew reason: night.inc.sh carries the real _acct_group, but this worker
# is fetched on its own serial and can land ahead of it -- an undefined
# function returns 127 with empty output, which would make the account chowns
# below emit a bare "user:" and reset the group instead of leaving it alone.
if ! declare -F _acct_group > /dev/null 2>&1; then
_acct_group() {
  # Group that owns an account's tree. Derived, never a literal: an account
  # converted to a private primary group named after itself gets that group,
  # everything else (an unconverted box, root, www-data, an adopted odd
  # group) falls back to 'users' -- so a tool landing on an unconverted or
  # half-converted box leaves it exactly as it is today. Box-wide paths
  # (/data/conf, /data/u, the shared cores) keep 'users' and never use this.
  # $1 = account name (oN, oN.ftp, oN.<sub>) or a path under /data/disk/<oN>
  # or /var/aegir (the master keeps 'users' in this phase).
  local _a="${1}" _g
  case "${_a}" in
    /var/aegir|/var/aegir/*|aegir|root|www-data) echo "users"; return 0 ;;
    /data/disk/*) _a="${_a#/data/disk/}"; _a="${_a%%/*}" ;;
    */*) echo "users"; return 0 ;;
  esac
  _a="${_a%%.*}"
  [ -n "${_a}" ] || { echo "users"; return 0; }
  _g=$(id -gn "${_a}" 2> /dev/null)
  [ "${_g}" = "${_a}" ] || _g="users"
  echo "${_g}"
}
fi
# The web-group helpers, for the same skew: a night.inc.sh older than them
# leaves them undefined, and the drift probe below reads the account's web
# group through them.
if ! declare -F _web_group_state > /dev/null 2>&1; then
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
fi

### oN owns its /data/disk/oN (log/, .drush/, config/, tools/, .tmp/, clients/,
### backups/, distro/, undo/), the main login owns /home/<oN>.ftp, and
### static/ is group-writable: any name there can be a link or a FIFO, and
### any directory on the way can be swapped for a link. Root reads, writes,
### moves and removes those names only through the helpers below. The first
### ones are the night.inc.sh and 20-sites.sh bodies, carried here for the
### same fNN skew as above, and defined only when the libraries lack them.
if ! declare -F _acct_in_real_dir > /dev/null 2>&1; then
  _acct_in_real_dir() {
    local _d="${1}" _a="" _want
    shift
    case "${_d}" in
      /home/?*) _a=/home ;;
      /data/disk/?*) _a=/data/disk ;;
    esac
    if [ -n "${_a}" ]; then
      _want="$(cd -P -- "${_a}" 2> /dev/null && pwd -P)${_d#"${_a}"}"
    else
      _want="$(cd -P -- "${_d%/*}" 2> /dev/null && pwd -P)/${_d##*/}"
    fi
    ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_want}" ] && "$@" )
  }
fi
if ! declare -F _acct_read_here > /dev/null 2>&1; then
  _acct_read_here() {
    timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
      bs=1048576 count=1 status=none 2> /dev/null
  }
fi
if ! declare -F _acct_read_in > /dev/null 2>&1; then
  _acct_read_in() {
    _acct_in_real_dir "${1}" _acct_read_here "${2}"
  }
fi
if ! declare -F _acct_read_plain_here > /dev/null 2>&1; then
  _acct_read_plain_here() {
    [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
    _acct_read_here "${1}"
  }
fi
if ! declare -F _acct_put_here > /dev/null 2>&1; then
  _acct_put_here() {
    local _t="./.${1}.put.$$.${RANDOM}"
    rm -f -- "${_t}"
    ( umask 022
      printf '%s\n' "${2}" | dd of="${_t}" conv=excl status=none 2> /dev/null ) \
      && mv -f -T -- "${_t}" "./${1}" && return 0
    rm -f -- "${_t}"
    return 1
  }
fi
if ! declare -F _acct_mark_here > /dev/null 2>&1; then
  _acct_mark_here() {
    local _t="./.${1}.mark.$$.${RANDOM}"
    rm -f -- "${_t}"
    dd if=/dev/null of="${_t}" conv=excl status=none 2> /dev/null \
      && mv -f -T -- "${_t}" "./${1}" && return 0
    rm -f -- "${_t}"
    return 1
  }
fi
if ! declare -F _log_ctrl_mark > /dev/null 2>&1; then
  _log_ctrl_mark() {
    _acct_in_real_dir "${_usEr}/log" mkdir -p ./ctrl 2> /dev/null
    _acct_in_real_dir "${_usEr}/log/ctrl" _acct_mark_here "${1}"
  }
fi
if ! declare -F _acct_undo_here > /dev/null 2>&1; then
  _acct_undo_here() {
    local _u
    _u="$(cd -P /data/disk 2> /dev/null && pwd -P)${_usEr#/data/disk}/undo"
    _acct_in_real_dir "${_usEr}" mkdir -p ./undo 2> /dev/null
    exec 9< "${_u}/." || return 1
    [ "$(readlink /proc/self/fd/9)" = "${_u}" ] || return 1
    mv -f -T -- "./${1}" "/proc/self/fd/9/${2:-${1}}"
  }
fi
: "${_GH_REFUSED:=the move into undo/ was refused (a link or a path outside this account on the way, or the rename failed)}"
### A tree handed over through each entry's own handle, never by name, and
### entries locked or unlocked the same way (the 20-sites.sh and night.inc.sh
### bodies, for the same skew).
if ! declare -F _reown_tree_here > /dev/null 2>&1; then
  _ACCT_REOWN_PL='use Fcntl; my ($u, $g, @f) = @ARGV; for my $f (@f) { sysopen(my $h, $f, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or next; my @s = stat($h); chown($u, $g, $h) if @s && (-d _ || (-f _ && $s[3] == 1)); close($h); } exit 0'
  _night_ids() {
    local _u _g=-1
    _u=$(id -u -- "${1%%:*}" 2> /dev/null)
    [[ "${_u}" =~ ^[0-9]+$ ]] || return 1
    if [[ "${1}" == *:* ]]; then
      _g=$(getent group "${1#*:}" 2> /dev/null | cut -d: -f3)
      [[ "${_g}" =~ ^[0-9]+$ ]] || return 1
    fi
    printf '%s %s\n' "${_u}" "${_g}"
  }
  _reown_tree_here() {
    local _ids _u _g
    _ids=$(_night_ids "${1}") || return 0
    read -r _u _g <<< "${_ids}"
    shift
    [ "$#" -gt 0 ] || return 0
    env PATH=/usr/local/bin:/usr/bin:/bin find "$@" \( -type d -o -type f \) \
      -execdir perl -e "${_ACCT_REOWN_PL}" "${_u}" "${_g}" {} + &> /dev/null
    return 0
  }
fi
if ! declare -F _night_chattr_entries_here > /dev/null 2>&1; then
  _ACCT_CHATTR_PL='use Fcntl; my ($op, @f) = @ARGV; my $rc = 0; for my $f (@f) { sysopen(my $h, $f, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or do { $rc = 1; next }; my @s = stat($h); if (@s && (-d _ || (-f _ && $s[3] == 1))) { my $b = pack("L", 0); if (ioctl($h, 0x80086601, $b)) { my $fl = unpack("L", $b); $fl = $op eq "+" ? ($fl | 0x10) : ($fl & ~0x10); ioctl($h, 0x40086602, pack("L", $fl)) or $rc = 1; } else { $rc = 1 } } else { $rc = 1 } close($h); } exit $rc'
  _night_chattr_sub_here() {
    local _h
    _h="$(pwd -P)"
    ( cd -P -- "./${2}" 2> /dev/null && [ "$(pwd -P)" = "${_h}/${2}" ] \
      && chattr "${1}i" . ) &> /dev/null
    return 0
  }
  _night_chattr_entries_here() {
    local _e _chf=()
    for _e in ./*; do
      if [ -d "${_e}" ] && [ ! -L "${_e}" ]; then
        _night_chattr_sub_here "${1}" "${_e#./}"
      elif [ -f "${_e}" ] && [ ! -L "${_e}" ]; then
        _chf+=( "${_e}" )
      fi
    done
    [ "${#_chf[@]}" -eq 0 ] \
      || perl -e "${_ACCT_CHATTR_PL}" "${1}" "${_chf[@]}" &> /dev/null
    return 0
  }
fi

### Run "$@" inside the directory $1, a path resolved just before, entered
### with cd -P and checked there, so ./name stays in it whatever is swapped.
_night_in_pinned() {
  local _d="${1}"
  shift
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_d}" ] && "$@" )
}
### Run "$@" inside ./$1 of the current (pinned) directory, entered for real.
_night_sub() {
  local _h _s="${1}"
  shift
  _h="$(pwd -P)"
  ( cd -P -- "./${_s}" 2> /dev/null && [ "$(pwd -P)" = "${_h}/${_s}" ] && "$@" )
}
### The account's files store as it resolves now, printed: its own
### static/files, or migratefs' layout on attached storage
### (/mnt/.../files/<oN>/static/files). static/ is group-writable, so
### static/files can be any link: anything else is not the store (status 1),
### nor is a directory of that name made inside another store or account
### tree on the mount. Reads _usEr.
_night_acct_store() {
  local _a _r _m
  _a=$(realpath -e -- "${_usEr}" 2> /dev/null) || return 1
  _r=$(realpath -e -- "${_usEr}/static/files" 2> /dev/null) || return 1
  case "${_r}" in
    *[!A-Za-z0-9._/-]*) return 1 ;;
    "${_a}/static/files") ;;
    /mnt/?*/files/"${_usEr##*/}"/static/files)
      _m="${_r%/files/"${_usEr##*/}"/static/files}"
      case "${_m}" in
        */files/*|*/static/*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
  [ -d "${_r}" ] || return 1
  printf '%s\n' "${_r}"
}
### migratefs relocating this account's files store holds it:
### /run/migratefs-account-<oN>.pid names a live root process that runs
### migratefs, matched as executed, never as a word anywhere on a command
### line (a pid reused after a kill -9, by another user's process or another
### command, never holds). Root is read as the real uid in
### /proc/<pid>/status: /proc/<pid> itself shows root as the owner of any
### process that is not dumpable. Reads _HM_U.
_night_mfs_held() {
  local _p
  _p=$( { tr -dc '0-9' < "/run/migratefs-account-${_HM_U}.pid"; } 2> /dev/null )
  [ -n "${_p}" ] && kill -0 "${_p}" 2> /dev/null \
    && [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_p}/status" 2> /dev/null)" = "0" ] \
    && { tr '\0' ' ' < "/proc/${_p}/cmdline"; } 2> /dev/null \
    | grep -qE '^([^ ]*/)?bash (-[^ ]+ )*([^ ]*/)?migratefs( |$)'
}
### Run "$@" inside ${_usEr}/$1 (backups, backup-exports): the real directory,
### or, once the backups mover made it a link, the directory that link
### resolves to, only while that lies inside the account's store; any other
### link is refused.
_night_in_bak_dir() {
  local _n="${1}" _s _r
  shift
  if [ ! -L "${_usEr}/${_n}" ]; then
    _acct_in_real_dir "${_usEr}/${_n}" "$@"
    return
  fi
  _s=$(_night_acct_store) || return 1
  _r=$(realpath -e -- "${_usEr}/${_n}" 2> /dev/null) || return 1
  case "${_r}" in
    "${_s}"/?*) ;;
    *) return 1 ;;
  esac
  _night_in_pinned "${_r}" "$@"
}
### One line when ${_usEr}/$1 is a link _night_in_bak_dir refused: nothing
### below it is purged until it leads into the account's store again.
_night_bak_unpurged() {
  [ -L "${_usEr}/${1}" ] || return 0
  echo "backups-on-static: ${_usEr}/${1} is a link that does not lead into the account's store; not purged"
}
### The uids root's walks over the account $1's trees act on, comma-separated:
### root's own (0, what root wrote there for the account) and those of every
### identity of the account as passwd names them: oN and oN.<name>, that is
### its .ftp login, its client sub-accounts oN.<client> and oN.<client>-dev
### and its PHP-FPM users oN.web and oN.<ver>.web. An account name holds no
### dot, so the match is exact: o1 never takes o10's. Status 1, and nothing,
### unless the account itself is in passwd. The walks also take a uid no
### passwd entry names as the account's own: a login removed before the
### limited-shell worker handed its files to the account at removal left
### those. Nothing records which account a freed number served, so such an
### entry is taken wherever it came from. A lookup that fails, rather than
### finding no such user, leaves the entry another user's.
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
### Root's removals in an account's trees, run inside the directory they act
### in: only what the uids given second own (_acct_walk_uids), or a uid no
### passwd entry names (sub own), is removed or unlocked, and nothing below a
### directory another named uid owns. The account's identities can rename into
### their own trees what another account left group-writable, a whole
### directory with everything nested in it, so such a directory stays whole.
### Nothing is done unless the current directory and every directory above it,
### up to /, are owned by those uids or by one no passwd entry names, read
### through '..' from where the walk stands. A directory is entered through a
### handle opened without following a link, only as the directory lstat saw,
### and its entries are acted on by name from inside it. The first argument is
### the act, on the names after the third:
###   r  each removed, a directory depth first, then itself once empty
###   u  each unlocked (+i cleared through a handle), a directory with
###      everything below it the walk reaches
###   h  each removed unless it is a directory (find's hits)
### or, the third argument a number of days, on the current directory:
###   d  every entry below it older than that (find -mtime +N) removed as r
###      removes it, younger directories searched alike, top-level dot
###      names kept
###   a  as d, the top-level dot names included
###   f  as d, regular files only, every directory searched
### Prints dev:ino of each entry left because another uid owns it, and of
### the directory another uid owns above the place when the walk refuses
### it; status 3 when one was, 1 when a removal failed.
_ACCT_RM_OWN_PL='use Fcntl;
my ($op, $ul, $days, @f) = @ARGV;
my %own = map { $_ => 1 } grep { /^[0-9]+$/ } split(/,/, defined($ul) ? $ul : "");
sub own { my $u = shift; unless (exists $own{$u}) { local $! = 0; $own{$u} = defined(getpwuid($u)) ? 0 : ($! == 0 || $!{ENOENT} || $!{ESRCH} || $!{EBADF} || $!{EPERM}) ? 1 : 0; } return $own{$u}; }
my ($left, $bad, $now) = (0, 0, time);
sub left { my ($l) = @_; print "$l->[0]:$l->[1]\n"; $left++; }
sub done { exit($bad ? 1 : $left ? 3 : 0); }
my ($p, $ok, @d, @x) = (".", 0);
for (1 .. 256) {
  @x = stat($p) or last;
  last unless own($x[4]);
  if (@d && $x[0] == $d[0] && $x[1] == $d[1]) { $ok = 1; last; }
  @d = @x;
  $p .= "/..";
}
unless ($ok) { left(\@x) if @x && !own($x[4]); $left = 1; done(); }
sub kids {
  opendir(my $h, ".") or do { $bad = 1; return (); };
  my @n = grep { $_ ne "." && $_ ne ".." } readdir($h);
  closedir($h);
  return @n;
}
sub into {
  my ($n, $l, $cb) = @_;
  sysopen(my $up, ".", O_RDONLY | O_DIRECTORY) or do { $bad = 1; return 0; };
  sysopen(my $dn, $n, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
    or do { $bad = 1; return 0; };
  my @s = stat($dn);
  unless (@s && $s[0] == $l->[0] && $s[1] == $l->[1] && chdir($dn)) {
    $bad = 1;
    return 0;
  }
  close($dn);
  $cb->();
  chdir($up) or die "no way back\n";
  return 1;
}
sub rmown {
  my ($n) = @_;
  my @l = lstat($n) or return;
  unless (own($l[4])) { left(\@l); return; }
  if (-d _) {
    into($n, \@l, sub { rmown($_) for kids(); }) or return;
    rmdir($n) or $!{ENOTEMPTY} or $!{EEXIST} or $bad = 1;
  } else {
    unlink($n) or $bad = 1;
  }
}
sub noimm {
  my ($n, $l) = @_;
  sysopen(my $h, $n, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or return;
  my @s = stat($h);
  if (@s && $s[0] == $l->[0] && $s[1] == $l->[1] && own($s[4])) {
    my $b = pack("L", 0);
    if (ioctl($h, 0x80086601, $b)) {
      my $fl = unpack("L", $b);
      ioctl($h, 0x40086602, pack("L", $fl & ~0x10)) if $fl & 0x10;
    }
  }
  close($h);
}
sub unown {
  my ($n) = @_;
  my @l = lstat($n) or return;
  return unless own($l[4]);
  if (-d _) {
    noimm($n, \@l);
    into($n, \@l, sub { unown($_) for kids(); });
  } elsif (-f _ && $l[3] == 1) {
    noimm($n, \@l);
  }
}
sub aged { return int(($now - $_[0]->[9]) / 86400) > $days; }
sub sel {
  my ($n, $top) = @_;
  return if $top && $op ne "a" && substr($n, 0, 1) eq ".";
  my @l = lstat($n) or return;
  unless (own($l[4])) { left(\@l); return; }
  if ($op eq "f") {
    if (-d _) {
      into($n, \@l, sub { sel($_, 0) for kids(); });
    } elsif (-f _ && aged(\@l)) {
      unlink($n) or $bad = 1;
    }
  } elsif (aged(\@l)) {
    rmown($n);
  } elsif (-d _) {
    into($n, \@l, sub { sel($_, 0) for kids(); });
  }
}
if ($op eq "r") {
  rmown($_) for @f;
} elsif ($op eq "u") {
  unown($_) for @f;
} elsif ($op eq "h") {
  for my $n (@f) {
    my @l = lstat($n) or next;
    next if -d _;
    if (own($l[4])) { unlink($n) or $bad = 1; } else { left(\@l); }
  }
} elsif ($op =~ /^[adf]$/ && defined($days) && $days =~ /^[0-9]+$/) {
  sel($_, 1) for kids();
} else {
  exit 2;
}
done();'
### What the nightly purge leaves in place because another user owns it, as
### dev:ino lines (_ACCT_RM_OWN_PL) gathered across its legs (each runs in a
### subshell, and two legs can meet the same entry) in a file of root's, and
### said once per account, each entry counted once (_purge_left_note).
_purge_left_open() {
  _PURGE_LEFT_F="/run/night-purge-left-${_usEr##*/}"
  : > "${_PURGE_LEFT_F}" 2> /dev/null || _PURGE_LEFT_F=""
}
_purge_left_add() {
  [ -n "${_PURGE_LEFT_F:-}" ] && [ -n "${1}" ] || return 0
  printf '%s\n' "${1}" >> "${_PURGE_LEFT_F}" 2> /dev/null
  return 0
}
_purge_left_note() {
  local _n
  [ -n "${_PURGE_LEFT_F:-}" ] || return 0
  _n=$(grep -E '^[0-9]+:[0-9]+$' "${_PURGE_LEFT_F}" 2> /dev/null | sort -u | grep -c .)
  rm -f -- "${_PURGE_LEFT_F}"
  _PURGE_LEFT_F=""
  [[ "${_n}" =~ ^[1-9][0-9]*$ ]] || return 0
  echo "NOTE: ${_usEr##*/}: the nightly purge left ${_n} entries owned by another user in place below ${_usEr} and /home/${_usEr##*/}.ftp"
}
### Every entry below the current (pinned) directory older than $1 days
### removed, the top-level dot names kept as the X/* globs this replaces kept
### them ($2: all = none kept; files = regular files only), through
### _ACCT_RM_OWN_PL: only what root or the account's own identities own,
### never through a link, and nothing below a directory another user owns.
_night_purge_here() {
  local _o _n _m=d
  _o=$(_acct_walk_uids "${_usEr##*/}") || return 0
  case "${2}" in
    files) _m=f ;;
    all) _m=a ;;
  esac
  _n=$(perl -e "${_ACCT_RM_OWN_PL}" -- "${_m}" "${_o}" "${1}" 2> /dev/null)
  _purge_left_add "${_n}"
  return 0
}
### ./$1 in the current (pinned) directory removed as rm -rf removed it,
### through _ACCT_RM_OWN_PL: only what root or the account's identities own.
_night_rm_own_here() {
  local _o _n
  [ -e "./${1}" ] || [ -L "./${1}" ] || return 0
  _o=$(_acct_walk_uids "${_usEr##*/}") || return 0
  _n=$(perl -e "${_ACCT_RM_OWN_PL}" -- r "${_o}" - "./${1}" 2> /dev/null)
  _purge_left_add "${_n}"
  return 0
}
### The regular files of the current (pinned) log/ctrl matching the globs
### after $1 (never a dot name) removed when older than $1 days.
_night_ctrl_purge_here() {
  local _d="${1}" _g
  shift
  for _g in "$@"; do
    find . -mindepth 1 -maxdepth 1 ! -name '.*' -name "${_g}" -type f \
      -mtime "+${_d}" -delete 2> /dev/null
  done
  return 0
}
### In the current (pinned) clients/: each real client directory's backups
### removed ($1 = rm), or its entries older than $2 days (purge), only what
### root or the account's own identities own (_ACCT_RM_OWN_PL).
_night_clients_bak_here() {
  local _c
  for _c in ./*; do
    [ -d "${_c}" ] && [ ! -L "${_c}" ] || continue
    if [ "${1}" = "rm" ]; then
      _night_sub "${_c#./}" _night_rm_own_here backups
    else
      _night_sub "${_c#./}" _night_sub backups _night_purge_here "${2}"
    fi
  done
  return 0
}
### Every dangling link below the current (pinned) directory removed, as
### symlinks -dr removed them; find walks without following a link.
_night_dangling_rm_here() {
  find . -xdev -mindepth 1 -xtype l -delete 2> /dev/null
  return 0
}
### $1 as its words joined by single spaces, without expanding a glob; text
### over 4 KiB gives nothing.
_night_words() (
  [ "${#1}" -le 4096 ] || exit 0
  set -f
  # shellcheck disable=SC2086
  set -- ${1}
  printf '%s' "$*"
)
### The addresses in $1 (words, as log/email.txt holds them) that have an
### e-mail address's form, joined by single spaces; text over 4 KiB gives
### nothing. They are written into root's octopus.cnf, which root sources,
### and reach s-nail as its recipients. The form the octopus pass and
### usage.sh take: a local part of letters, digits and . _ % + = ' - (a
### letter, a digit or _ first), '@' and a host name.
_night_mail_list() (
  local _w _o="" _re _q="'"
  _re="^[A-Za-z0-9_][A-Za-z0-9._%+=${_q}-]*@[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$"
  [ "${#1}" -le 4096 ] || exit 0
  set -f
  # shellcheck disable=SC2086
  for _w in ${1//\\\@/\@}; do
    [[ "${_w}" =~ ${_re} ]] || continue
    _o="${_o}${_o:+ }${_w}"
  done
  printf '%s' "${_o}"
)
### Client mail on a test box. While /data/conf/client_mail_hold.txt exists,
### mail BOA would send an account's client goes to the one address it holds
### instead, its subject noting who would have been mailed; a file that anyone
### but root can write, or that does not hold exactly one plain address, stops
### that mail (fail closed) with one line saying why. Read through one handle
### opened without following a link or blocking on a FIFO, and only while it
### is a regular file of root's, not writable by group or others, with a
### single link, 1 KiB at most (_MAIL_HOLD_PL: status 2 gone, 3 not root's or
### writable by others, 4 any other shape, 5 not one plain address). $1 = the
### client recipients (words). Sets _MAIL_HOLD_RCPT, the recipients to use, and
### _MAIL_HOLD_SFX, the note for the subject; status 1: send none. Without the
### file they are $1 and empty. One copy in each tool that mails a client.
# shellcheck disable=SC2016
_MAIL_HOLD_PL='use Fcntl; sysopen(my $h, $ARGV[0], O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or exit($!{ENOENT} ? 2 : 4); my @s = stat($h); exit 4 unless @s; exit 3 unless $s[4] == 0 && !($s[2] & 022); exit 4 unless -f _ && $s[3] == 1 && $s[7] <= 1024; my ($d, $r) = (""); while ($r = sysread($h, my $c, 1025)) { $d .= $c; exit 4 if length($d) > 1024; } exit 4 unless defined $r; $d =~ /\A\s*([A-Za-z0-9_][A-Za-z0-9._%+=\x27-]*\@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)\s*\z/ or exit 5; print $1; exit 0'
_client_mail_hold() {
  local _f="/data/conf/client_mail_hold.txt" _a _rc _to _q="'"
  _MAIL_HOLD_RCPT="${1}"
  _MAIL_HOLD_SFX=""
  [ -e "${_f}" ] || [ -L "${_f}" ] || return 0
  [ -n "${1//[[:space:]]/}" ] || return 0
  _to="$(printf '%s' "${1//\\\@/@}" | tr -s '[:space:]' ' ' \
    | LC_ALL=C tr -cd "A-Za-z0-9._%+=@${_q} -" | cut -c1-200)"
  _to="${_to# }"
  _to="${_to% }"
  _to="${_to:-?}"
  _a="$(perl -e "${_MAIL_HOLD_PL}" "${_f}" 2> /dev/null)"
  _rc=$?
  case "${_rc}" in
    0)
      _MAIL_HOLD_RCPT="${_a}"
      _MAIL_HOLD_SFX=" [held for ${_to}]"
      return 0
      ;;
    2)
      return 0
      ;;
    3)
      echo "ALRT: ${_f} is not root's, or group or others can write it, and cannot be trusted: client mail for ${_to} not sent"
      ;;
    5)
      echo "ALRT: ${_f} does not hold exactly one plain address: client mail for ${_to} not sent"
      ;;
    *)
      echo "ALRT: ${_f} is not a regular file of one link, 1 KiB at most, that this run can read: client mail for ${_to} not sent"
      ;;
  esac
  _MAIL_HOLD_RCPT=""
  return 1
}
### True when $1 is a host name: letters, digits, dots and hyphens, starting
### and ending with a letter or a digit. It names root's /etc/ssl/private
### files and log/ctrl markers.
_night_host_ok() {
  [[ "${1}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]
}
### True when $1 names none of the box's own certificates in
### /etc/ssl/private (a name without a dot, such as nginx-wild-ssl or
### ssl-cert-snakeoil; every account front is a full domain name), not the
### master's front and not the front (_DOMAIN) of another account on this
### box: the account's front names root's /etc/ssl/private/<front>.crt and
### .key.
_night_front_free() {
  local _c _u _d
  case "${1}" in
    *.*) ;;
    *) return 1 ;;
  esac
  _d=$(sed -n 's/^_MY_FRONT=//p' /root/.barracuda.cnf 2> /dev/null \
    | tail -n 1 | tr -d "\"' ")
  [ "${_d}" = "${1}" ] && return 1
  _d=$(grep -E "^[[:space:]]*'uri'[[:space:]]*=>" \
    /var/aegir/.drush/hostmaster.alias.drushrc.php 2> /dev/null \
    | head -n 1 | cut -d"'" -f4)
  [ "${_d}" = "${1}" ] && return 1
  for _c in /root/.*.octopus.cnf; do
    [ -f "${_c}" ] || continue
    _u="${_c#/root/.}"
    _u="${_u%.octopus.cnf}"
    [ "${_u}" = "${_HM_U}" ] && continue
    [ -d "/data/disk/${_u}" ] || continue
    _d=$(sed -n 's/^_DOMAIN=//p' "${_c}" 2> /dev/null \
      | tail -n 1 | tr -d "\"' ")
    [ "${_d}" = "${1}" ] && return 1
  done
  return 0
}
### True when every word of $1 is a host name.
_night_hosts_ok() (
  local _w
  set -f
  # shellcheck disable=SC2086
  set -- ${1}
  [ "$#" -gt 0 ] || exit 1
  for _w in "$@"; do
    _night_host_ok "${_w}" || exit 1
  done
)
### The mtime of ./$1 in the current (pinned) directory, only while it is a
### regular file.
_night_mtime_here() {
  local _t
  [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
  _t=$(stat -c %Y -- "./${1}" 2> /dev/null)
  [[ "${_t}" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "${_t}"
}
### ./$2 in the current (pinned) directory made a link to $1 where no name
### there resolves.
_night_link_new_here() {
  [ -e "./${2}" ] || ln -sfn -- "${1}" "./${2}"
}

_relocate_one_backup_dir() {
  # Relocate one per-account backup directory ($1: backups or backup-exports)
  # onto the account's store ($2, resolved) as .$1 and replace it with the
  # link $3, so large (dereferenced) backups never fill the root partition.
  # Data-safe and never destructive: the real dir is copied whole, and only
  # then emptied; on a failure it is left in place with its owner and mode,
  # and no link is created. Idempotent.
  #
  # The account owns its root, the directory and everything below it, and
  # the store: while the copy runs the directory and .$1 in the store are
  # root's and closed (0700), so no name below either changes; the copy
  # starts inside the real directory and writes into .$1 held open
  # (/proc/self/fd), the directory is emptied from inside itself by find,
  # and the rmdir and the link act on names inside the real account root.
  #
  # The owner and mode are recorded in root's /var/backups before anything
  # is closed, and a TERM, INT or HUP to this pass opens both again. A pass
  # killed outright (KILL, a reboot, OOM) leaves them closed, and Aegir's
  # backup tasks fail there once the queue runs again; the next pass reads
  # the record (or, without one, gives the account's own owner and 750, as
  # the octopus pass does), finishes the relocation and hands both back.
  local _n="$1" _st="$2" _lnk="$3" _src="${_usEr}/$1" _ug _md _dm _rec
  _rec="$(_night_bak_rec "${_n}")"

  # Already a link to the intended target -> just make sure the store has it
  # and that it is the account's, not root's.
  if [ -L "${_src}" ]; then
    if [ "$(readlink -- "${_src}" 2>/dev/null)" = "${_lnk}" ]; then
      read -r _ug _md <<< "$(_night_bak_recorded "${_n}")"
      _night_in_pinned "${_st}" _night_bak_store_here ".${_n}" \
        "${_ug}" "${_md}"
      rm -f -- "${_rec}"
    else
      echo "backups-on-static: ${_src} is a symlink to an unexpected target; leaving for review"
    fi
    return 0
  fi

  # Only relocate an EXISTING real directory (so its exact ownership is preserved);
  # if the path does not exist yet, do nothing (Ægir creates it on first use and a
  # later run relocates it).
  [ -d "${_src}" ] || return 0

  _ug=$(_acct_in_real_dir "${_src}" stat -c '%U:%G' . 2>/dev/null)
  _md=$(_acct_in_real_dir "${_src}" stat -c '%a' . 2>/dev/null)
  [ -n "${_ug}" ] && [[ "${_md}" =~ ^[0-7]+$ ]] || return 0
  # Root's: closed by a pass that was killed during the copy.
  if [ "${_ug}" = "root:root" ]; then
    read -r _ug _md <<< "$(_night_bak_recorded "${_n}")"
  fi
  if ! ( umask 077; printf '%s %s\n' "${_ug}" "${_md}" > "${_rec}" ) 2>/dev/null; then
    echo "backups-on-static: could not record the owner of ${_src} in ${_rec}; left as real dir"
    return 0
  fi
  _dm="${_st}/.${_n}"
  trap '_night_bak_open "${_src}" "${_dm}" "${_ug}" "${_md}"; rm -f -- "${_rec}"; exit 143' TERM INT HUP
  _night_bak_move
  trap - TERM INT HUP
  rm -f -- "${_rec}"
  return 0
}
# The relocation proper, for _relocate_one_backup_dir: reads its _n, _st,
# _lnk, _src, _dm, _ug and _md. Every return leaves both directories open
# with that owner and mode, or never closed them.
_night_bak_move() {
  if ! _night_in_pinned "${_st}" _night_bak_dst_here ".${_n}"; then
    _night_bak_open "" "${_dm}" "${_ug}" "${_md}"
    echo "backups-on-static: ${_st}/.${_n} is not a real directory; left ${_src} as real dir"
    return 0
  fi

  if [ -n "$(_acct_in_real_dir "${_src}" ls -A . 2>/dev/null)" ]; then
    # Re-check the task interlock right before the move: skip (leave the
    # real dir untouched) if a provision task started since the entry check, so a
    # backup being written is never moved mid-write.
    if _provision_running; then
      _night_bak_open "${_src}" "${_dm}" "${_ug}" "${_md}"
      echo "backups-on-static: provision task active -- left ${_src} as real dir"
      return 0
    fi
    # One-time migration de-links any pre-existing backups<->backup-exports hardlink
    # pairs (the two dirs are copied in separate rsync runs, no -H), so old tarballs
    # briefly cost double space -- on the static FS (the target), not the tight root,
    # and it ages out via the -mtime purge. New backups after relocation hardlink
    # fine (both dirs are then co-located on the static FS).
    if ! _acct_in_real_dir "${_src}" _night_close_here \
      || ! _acct_in_real_dir "${_src}" _night_bak_copy_here "${_dm}"; then
      _night_bak_open "${_src}" "${_dm}" "${_ug}" "${_md}"
      echo "backups-on-static: move failed ${_src} -> ${_st}/.${_n}; left as real dir"
      return 0
    fi
    # A device, FIFO or socket is never copied: a dir holding one stays.
    if [ -n "$(_acct_in_real_dir "${_src}" find -P . \( -type b -o -type c \
      -o -type p -o -type s \) -print -quit 2>/dev/null)" ]; then
      _night_bak_open "${_src}" "${_dm}" "${_ug}" "${_md}"
      echo "backups-on-static: ${_src} not empty after move; left as real dir for review"
      return 0
    fi
    _acct_in_real_dir "${_src}" find -P . -mindepth 1 -depth -delete 2>/dev/null
  fi

  # Refuse to replace the dir with a symlink unless it emptied cleanly.
  if [ -n "$(_acct_in_real_dir "${_src}" ls -A . 2>/dev/null)" ]; then
    _night_bak_open "${_src}" "${_dm}" "${_ug}" "${_md}"
    echo "backups-on-static: ${_src} not empty after move; left as real dir for review"
    return 0
  fi

  _night_bak_open "" "${_dm}" "${_ug}" "${_md}"
  if ! _acct_in_real_dir "${_usEr}" rmdir -- "./${_n}" 2>/dev/null; then
    _night_bak_open "${_src}" "" "${_ug}" "${_md}"
    return 0
  fi
  # A name put there meanwhile makes this fail, never takes the link inside
  # it, and the link is never handed over by its name (_night_bak_link_here).
  _acct_in_real_dir "${_usEr}" _night_bak_link_here "${_lnk}" "${_n}" "${_ug}" \
    || { echo "backups-on-static: could not symlink ${_src}; data is safe in ${_st}/.${_n}, relink manually"; return 0; }
  echo "backups-on-static: relocated ${_src} -> ${_st}/.${_n} (static filesystem)"
}
# In the real account root (the current directory): ./$2 made a link to $1
# owned by $3 (owner:group), only while no name is there, as ln -s -T made
# it. oN writes this directory, so a hard link it renamed over a new link
# would be handed over by a chown -h on the name: the link is made by its
# owner under a fresh name and renamed onto ./$2 without replacing anything
# found there. A link root makes, when that owner cannot make one here,
# stays root's: nothing checks the owner of a link.
_night_bak_link_here() {
  local _t="./.${2}.lnk.$$.${RANDOM}" _u _g
  _u=$(id -u -- "${3%%:*}" 2> /dev/null)
  _g=$(getent group "${3#*:}" 2> /dev/null | cut -d: -f3)
  rm -f -- "${_t}"
  if [[ "${_u}" =~ ^[0-9]+$ && "${_g}" =~ ^[0-9]+$ ]] && [ "${_u}" != 0 ]; then
    setpriv --reuid="${_u}" --regid="${_g}" --clear-groups \
      ln -s -- "${1}" "${_t}" 2> /dev/null
  fi
  if [ ! -L "${_t}" ]; then
    rm -f -- "${_t}"
    ln -s -- "${1}" "${_t}" 2> /dev/null || return 1
  fi
  mv -n -T -- "${_t}" "./${2}" 2> /dev/null
  rm -f -- "${_t}"
  [ -L "./${2}" ] && [ "$(readlink -- "./${2}")" = "${1}" ]
}
# Root's record of the owner and mode ${_usEr}/$1 had before a relocation
# closed it.
_night_bak_rec() {
  printf '/var/backups/.backups-on-static.%s.%s\n' "${_usEr##*/}" "${1}"
}
# The owner and mode recorded for ${_usEr}/$1 (_night_bak_rec), printed as
# "owner:group mode"; without a record, the account's own and 750, what the
# octopus pass gives backups.
_night_bak_recorded() {
  local _r _re='^[A-Za-z0-9._-]+:[A-Za-z0-9._-]+ [0-7]{1,4}$'
  _r=$(head -c 256 -- "$(_night_bak_rec "${1}")" 2> /dev/null)
  if [[ "${_r}" =~ ${_re} ]] && [ "${_r%% *}" != "root:root" ]; then
    printf '%s\n' "${_r}"
  else
    printf '%s:%s 750\n' "${_usEr##*/}" "$(_acct_group "${_usEr##*/}")"
  fi
}
# In the store (the current, pinned directory): ./$1 made a real directory
# where missing, and handed to the owner $2 with the mode $3 while it is
# root's (made here, or left closed by a pass that was killed).
_night_bak_store_here() {
  [ -L "./${1}" ] && return 1
  if [ ! -e "./${1}" ]; then
    mkdir -m 0700 -- "./${1}" 2>/dev/null || return 1
  elif [ "$(_night_sub "${1}" stat -c '%U' . 2>/dev/null)" != "root" ]; then
    return 0
  fi
  _night_sub "${1}" chown -h "${2}" . 2>/dev/null
  _night_sub "${1}" chmod "${3}" . 2>/dev/null
}
# In the store (the current, pinned directory): ./$1 a real directory, made
# when missing, and closed for the copy (root's, 0700).
_night_bak_dst_here() {
  [ -L "./${1}" ] && return 1
  [ -e "./${1}" ] || mkdir -m 0700 -- "./${1}" 2>/dev/null
  _night_sub "${1}" _night_close_here
}
# The current (pinned) directory root's and 0700: nobody else can enter it
# or change a name in it.
_night_close_here() {
  chown root:root . 2>/dev/null && chmod 0700 . 2>/dev/null
}
# From inside the real, closed directory being relocated: its whole content
# copied into the store directory $1, which is opened once and held
# (/proc/self/fd/9), so no name on its path is looked up again.
_night_bak_copy_here() {
  exec 9< "${1}/." || return 1
  [ "$(readlink /proc/self/fd/9)" = "${1}" ] || return 1
  rsync -a --no-devices --no-specials ./ /proc/self/fd/9/ 2>/dev/null
}
# The directory $1 and the store directory $2 (either may be empty) handed
# back with the owner $3 and the mode $4, each inside its real directory.
_night_bak_open() {
  if [ -n "${1}" ]; then
    _acct_in_real_dir "${1}" chown -h "${3}" . 2>/dev/null
    _acct_in_real_dir "${1}" chmod "${4}" . 2>/dev/null
  fi
  if [ -n "${2}" ]; then
    _night_in_pinned "${2}" chown -h "${3}" . 2>/dev/null
    _night_in_pinned "${2}" chmod "${4}" . 2>/dev/null
  fi
  return 0
}

_relocate_backups_to_static_fs() {
  # Move this account's backups + backup-exports onto the static/files filesystem
  # (static/files/.backups + static/files/.backup-exports) via symlinks, so large
  # dereferenced backups cannot fill the root partition, while keeping BOTH on ONE
  # filesystem so the Ægir backup-download hardlinks keep working (hardlinks can
  # not cross filesystems). The leading-dot names are skipped by the site/orphan
  # scan (like static/files/.archived). Gated on static/files being a SEPARATE
  # filesystem (no benefit otherwise), kill-switchable, idempotent, non-fatal.
  local _acct="${_usEr}"
  local _static="${_acct}/static/files"

  # Kill-switch: box-wide or per-account.
  [ -f "/data/conf/disable_backups_on_static_fs.cnf" ] && return 0
  [ -f "${_acct}/static/control/no_backups_on_static_fs.info" ] && return 0

  # static/files must exist and resolve to a DIFFERENT device than the account root
  # (else the relocation gives no protection). static/files is a separate disk only
  # for large accounts moved to attached storage -- which is exactly the case this
  # protects; on a default single-filesystem box this is a deliberate no-op.
  [ -e "${_static}" ] || return 0
  # ${_acct}/static is 02775 and group-writable by the account's shell
  # identities, so static/files can be any link, and root does the mkdir,
  # the chown and the copy at the far end: only the account's own store
  # counts (_night_acct_store), resolved once here and used by that path.
  local _st _acctR _statR
  _acctR=$(realpath -e -- "${_acct}" 2>/dev/null) || return 0
  if ! _st=$(_night_acct_store); then
    _statR=$(realpath -e -- "${_static}" 2>/dev/null) || return 0
    case "${_statR}/" in
      "${_acctR}"/*) ;;
      *) echo "backups-on-static: ${_static} is not the account's store (static/files or /mnt/.../files/${_acct##*/}/static/files); skipping" ;;
    esac
    return 0
  fi
  local _acctDev _statDev
  _acctDev=$(stat -c '%d' "${_acctR}" 2>/dev/null)
  _statDev=$(stat -c '%d' "${_st}" 2>/dev/null)
  [ -n "${_acctDev}" ] && [ -n "${_statDev}" ] || return 0
  [ "${_acctDev}" != "${_statDev}" ] || return 0

  # Fast idempotent path: if neither dir is a real dir pending a one-time migration
  # (already a symlink, or absent), just normalise the symlink targets and return --
  # no queue pause needed for a no-op (the common case after the first relocation).
  local _need=NO
  { [ -d "${_acct}/backups" ]        && [ ! -L "${_acct}/backups" ]; }        && _need=YES
  { [ -d "${_acct}/backup-exports" ] && [ ! -L "${_acct}/backup-exports" ]; } && _need=YES
  if [ "${_need}" = "NO" ]; then
    _relocate_one_backup_dir backups        "${_st}" "${_static}/.backups"
    _relocate_one_backup_dir backup-exports "${_st}" "${_static}/.backup-exports"
    return 0
  fi

  # A real one-time migration is pending. Serialise the parallel per-account fan-out
  # with a real flock (the kernel releases it if this process dies -- no stale-lock
  # guessing), then PAUSE the Ægir task queue with the dedicated, self-healing stop
  # file so no NEW task starts mid-move. runner.sh honours /run/boa_queue_stop.pid
  # (parent exit + per-child skip); it holds for as long as this pass lives,
  # however long the copy takes: clear.sh purges one whose pid is gone and /run
  # clears on reboot, so it can never freeze the queue. The _provision_running
  # interlock still drains any already-running task first.
  local _lockfd
  exec {_lockfd}>/run/.boa_backups_relocate.flock 2>/dev/null || return 0
  if ! flock -n "${_lockfd}"; then
    exec {_lockfd}>&-
    return 0
  fi

  # The pause is taken only as its owner: a pause another live operation
  # holds ends when that operation is done, and the queue would then
  # dispatch tasks mid-move. Deferred instead; the move is idempotent and
  # the next night takes it. The flock above keeps the parallel account
  # passes from competing for it.
  local _stop="/run/boa_queue_stop.pid" _madeStop=NO _qsPid
  if [ -e "${_stop}" ]; then
    _qsPid=$( { tr -dc '0-9' < "${_stop}"; } 2> /dev/null )
    if [ -n "${_qsPid}" ] && kill -0 "${_qsPid}" 2> /dev/null \
      && [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_qsPid}/status" 2> /dev/null)" = "0" ]; then
      echo "backups-on-static: queue pause held by pid ${_qsPid}; relocation for ${_acct} deferred to the next night"
      flock -u "${_lockfd}"
      exec {_lockfd}>&-
      return 0
    fi
    # Only root writes the pause, so one whose pid is gone, or is now
    # another user's process, holds nothing (clear.sh purges it too).
    # Removed only while it still names that pid: a pause another operation
    # created meanwhile is never taken from it.
    if [ "$( { tr -dc '0-9' < "${_stop}"; } 2> /dev/null )" = "${_qsPid}" ]; then
      rm -f "${_stop}"
    fi
  fi
  if ( set -C; echo "$$" > "${_stop}" ) 2> /dev/null; then
    _madeStop=YES
  else
    echo "backups-on-static: queue pause taken meanwhile; relocation for ${_acct} deferred to the next night"
    flock -u "${_lockfd}"
    exec {_lockfd}>&-
    return 0
  fi

  # Drain any in-flight task (bounded ~60s); with the queue paused none starts anew.
  local _t=0
  while _provision_running && [ "${_t}" -lt 30 ]; do sleep 2; _t=$((_t + 1)); done

  if _provision_running; then
    echo "backups-on-static: provision task still active after wait -- deferring relocation for ${_acct}"
  else
    _relocate_one_backup_dir backups        "${_st}" "${_static}/.backups"
    _relocate_one_backup_dir backup-exports "${_st}" "${_static}/.backup-exports"
  fi

  # Release the queue (only if WE set it and still own it -- verify the recorded PID
  # so we never delete another op's pause) and the flock.
  [ "${_madeStop}" = "YES" ] && [ "$(cat "${_stop}" 2>/dev/null)" = "$$" ] && rm -f "${_stop}"
  flock -u "${_lockfd}"
  exec {_lockfd}>&-
}

_account_process() {
  _HM_U=$(echo ${_usEr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
  # .drush/, log/ and .tmp/ are oN's: the alias is read bounded inside the
  # real .drush, never through a link or blocked on a FIFO, and log/ctrl is
  # made and .tmp/cache removed only inside the real directory.
  _THIS_HM_SITE=$(_acct_read_in "${_usEr}/.drush" hostmaster.alias.drushrc.php \
    | grep "site_path'" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1)
  _acct_in_real_dir "${_usEr}/log" mkdir -p ./ctrl 2> /dev/null
  su -s /bin/bash ${_HM_U} -c "drush8 cc drush" &> /dev/null
  wait
  _acct_in_real_dir "${_usEr}/.tmp" rm -rf -- ./cache
  chage -M 99999 ${_HM_U}.ftp &> /dev/null
  su -s /bin/bash - ${_HM_U}.ftp -c "drush8 cc drush" &> /dev/null
  wait
  chage -M 90 ${_HM_U}.ftp &> /dev/null
  # .tmp sits in the tenant's own, never-immutable home: cache is removed
  # only inside the real .tmp.
  _acct_in_real_dir "/home/${_HM_U}.ftp/.tmp" rm -rf -- ./cache
  _SQL_CONVERT=NO
  _DEL_OLD_EMPTY_PLATFORMS="0"
  # The account's front as root's octopus.cnf gives it, or none.
  _DOMAIN=
  if [ -e "/root/.${_HM_U}.octopus.cnf" ]; then
    # The account's Drush 9+ yml alias store is the ltd worker's to rebuild:
    # dropping its record of the last finished rebuild makes its next pass
    # regenerate the store the safe way (converted aside, so a failed
    # conversion keeps the last store); an in-place rebuild here emptied the
    # store whenever the conversion failed.
    if [ -x "/usr/bin/drush10" ]; then
      rm -f "/var/backups/ltd/.stores/${_HM_U}.md5"
    fi

    _MY_OCTO_EMAIL=
    _CLIENT_EMAIL=
    _MY_EMAIL=

    # shellcheck disable=SC1091
    [ -e "/root/.${_HM_U}.octopus.cnf" ] && source /root/.${_HM_U}.octopus.cnf

    [ -n "${_MY_OCTO_EMAIL}" ] && _MY_OCTO_EMAIL=${_MY_OCTO_EMAIL//\\\@/\@}
    [ -n "${_CLIENT_EMAIL}" ] && _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
    [ -n "${_MY_EMAIL}" ] && _MY_EMAIL=${_MY_EMAIL//\\\@/\@}

    _MY_OCTO_EMAIL_TEST=$(grep "^_MY_OCTO_EMAIL=" /root/.${_HM_U}.octopus.cnf 2>&1)
    _MY_EMAIL_TEST=$(grep "^_MY_EMAIL=" /root/.${_HM_U}.octopus.cnf 2>&1)

    if [[ ! "${_MY_OCTO_EMAIL_TEST}" =~ "_MY_OCTO_EMAIL" ]] \
      && [[ "${_MY_EMAIL_TEST}" =~ "_MY_EMAIL" ]] \
      && [ -n "${_MY_EMAIL}" ]; then
      _MY_OCTO_EMAIL="${_MY_EMAIL}"
      sed -i "s/^_MY_EMAIL=.*/_MY_OCTO_EMAIL=\"${_MY_EMAIL}\"/g" /root/.${_HM_U}.octopus.cnf
      _MY_EMAIL=
    fi

    if [ ! -z "${_CLIENT_EMAIL}" ] \
      && [[ ! "${_CLIENT_EMAIL}" =~ "${_MY_OCTO_EMAIL}" ]]; then
      _ALRT_EMAIL="${_CLIENT_EMAIL}"
    else
      _ALRT_EMAIL="${_MY_OCTO_EMAIL}"
    fi

    if [ "${_hostedSys}" = "YES" ]; then
      _BCC_EMAIL="inbox@boa.io"
    else
      _BCC_EMAIL="${_MY_OCTO_EMAIL}"
    fi

    _DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS//[^0-9]/}

    # log/email.txt is oN's and the cnf is sourced by root: the file is
    # read bounded inside the real log/, never through a link or blocked on
    # a FIFO, and only its words in an e-mail address's form reach the cnf
    # (_night_mail_list). That form holds no double quote, $, backquote,
    # backslash, '/', '&' or newline, so it is literal both inside the
    # double quotes root sources and in the sed replacement. Nothing in that
    # form leaves the cnf as it is.
    _F_CLIENT_EMAIL=
    if [ -e "${_usEr}/log/email.txt" ]; then
      _F_CLIENT_EMAIL=$(_night_mail_list "$(_acct_read_in "${_usEr}/log" email.txt)")
    fi

    if [ ! -z "${_F_CLIENT_EMAIL}" ]; then
      if grep -qxF -- "_CLIENT_EMAIL=\"${_F_CLIENT_EMAIL}\"" /root/.${_HM_U}.octopus.cnf 2>/dev/null; then
        _DO_NOTHING=YES
      elif grep -q "^_CLIENT_EMAIL=" /root/.${_HM_U}.octopus.cnf 2>/dev/null; then
        sed -i "s/^_CLIENT_EMAIL=.*/_CLIENT_EMAIL=\"${_F_CLIENT_EMAIL}\"/g" /root/.${_HM_U}.octopus.cnf
        wait
        _CLIENT_EMAIL=${_F_CLIENT_EMAIL}
      else
        printf '_CLIENT_EMAIL="%s"\n' "${_F_CLIENT_EMAIL}" >> /root/.${_HM_U}.octopus.cnf
        _CLIENT_EMAIL=${_F_CLIENT_EMAIL}
      fi
    fi

    # The email healer above kept the cnf honest against log/email.txt, but
    # its plan-identity siblings could disagree with their log/ stamps
    # forever (a migrated cnf is exactly that state). Same discipline for
    # the plan trio: the log/ stamp is the witness, replace-if-present,
    # append-if-absent.
    # Each stamp is read as email.txt is; text over 256 bytes is no plan
    # value and is skipped before the filter below.
    for _idPair in "_CLIENT_OPTION:option" "_CLIENT_SUBSCR:subscr" "_CLIENT_CORES:cores"; do
      _idVar="${_idPair%%:*}"
      _idFile="${_usEr}/log/${_idPair##*:}.txt"
      [ -s "${_idFile}" ] || continue
      _idVal=$(_acct_read_in "${_usEr}/log" "${_idPair##*:}.txt" | tr -d "\n")
      [ "${#_idVal}" -le 256 ] || continue
      _idVal=${_idVal//[^a-zA-Z0-9]/}
      [ -z "${_idVal}" ] && continue
      if grep -q "^${_idVar}=\"${_idVal}\"" /root/.${_HM_U}.octopus.cnf 2>/dev/null; then
        _DO_NOTHING=YES
      elif grep -q "^${_idVar}=" /root/.${_HM_U}.octopus.cnf 2>/dev/null; then
        sed -i "s/^${_idVar}=.*/${_idVar}=\"${_idVal}\"/g" /root/.${_HM_U}.octopus.cnf
        wait
      else
        echo "${_idVar}=\"${_idVal}\"" >> /root/.${_HM_U}.octopus.cnf
      fi
    done
  fi
  # The ltd worker rebuilds ~/.drush inside its own unlock/relock span every
  # three minutes; the relock below landing on such a rebuild leaves it half
  # done (EPERM on every write). Hold this account FIRST -- with the marker
  # in place the worker will not enter it (its per-account guard) -- so the
  # wait only has to cover a worker already inside this account's own span.
  # The marker carries this pid: a killed pass must not hold the account.
  echo $$ > /run/night-account-${_HM_U}.pid
  # migratefs relocating this account's files store holds it: the store legs
  # below would act on a store mid-copy or set aside and closed. Checked with
  # the marker above in place, the order migratefs takes with its hold, so one
  # of the two always sees the other. Skipped, not waited for: a relocation
  # can outlast the night, and the next night takes the account as usual.
  if _night_mfs_held; then
    echo "${_HM_U}: migratefs is relocating this account's files store; skipped tonight"
    rm -f "/run/night-account-${_HM_U}.pid"
    return 0
  fi
  # A web-group conversion run holds the account the same way (it waits for
  # this marker, so of the two one always sees the other): skipped tonight.
  # The hold names a root run; a pid that is gone, or that another user's
  # process now has, is a killed run's leftover (clear.sh reaps it).
  local _wgHold
  _wgHold=$( { tr -dc '0-9' < "/run/instgrp-web-${_HM_U}.pid"; } 2> /dev/null )
  if [ -n "${_wgHold}" ] && kill -0 "${_wgHold}" 2> /dev/null \
    && [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_wgHold}/status" 2> /dev/null)" = "0" ]; then
    echo "${_HM_U}: a web-group conversion run holds this account; skipped tonight"
    rm -f "/run/night-account-${_HM_U}.pid"
    return 0
  fi
  # The worker's pid file names its pid: a worker killed mid-pass leaves the
  # file behind until clear.sh sweeps it, and the nightly must not stall on a
  # dead one. Bounded on purpose; proceeding after the bound is the old race
  # narrowed to "worker still inside this account", so it leaves a witness.
  _nightWait=0
  while [ -e "/run/manage_ltd_users.pid" ] \
    && kill -0 "$(cat /run/manage_ltd_users.pid 2>/dev/null)" 2>/dev/null \
    && [ ${_nightWait} -lt 180 ]; do
    sleep 5
    _nightWait=$((_nightWait + 5))
  done
  [ ${_nightWait} -ge 180 ] \
    && echo "${_HM_U}: the ltd worker is still running after ${_nightWait} s; unlocking anyway"
  _disable_chattr ${_HM_U}.ftp
  rm -rf /home/${_HM_U}.ftp/drush-backups
  if [ -e "${_THIS_HM_SITE}" ]; then
    cd -- "${_THIS_HM_SITE}"
    su -s /bin/bash ${_HM_U} -c "drush8 cc drush" &> /dev/null
    wait
    _acct_in_real_dir "${_usEr}/.tmp" rm -rf -- ./cache
    _run_drush8_hmr_cmd "${_vSet} hosting_cron_default_interval 3600"
    _run_drush8_hmr_cmd "${_vSet} hosting_queue_cron_frequency 1"
    _run_drush8_hmr_cmd "${_vSet} hosting_civicrm_cron_queue_frequency 60"
    _run_drush8_hmr_cmd "${_vSet} hosting_queue_task_gc_frequency 300"
    if [ -e "${_usEr}/log/hosting_cron_use_backend.txt" ]; then
      _run_drush8_hmr_cmd "${_vSet} hosting_cron_use_backend 1"
    else
      _run_drush8_hmr_cmd "${_vSet} hosting_cron_use_backend 0"
    fi
    _run_drush8_hmr_cmd "${_vSet} hosting_ignore_default_profiles 0"
    _run_drush8_hmr_cmd "${_vSet} hosting_queue_tasks_frequency 1"
    _run_drush8_hmr_cmd "${_vSet} hosting_queue_tasks_items 1"
    _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
    _relocate_backups_to_static_fs
    _run_drush8_hmr_cmd "${_vSet} aegir_backup_export_path ${_usEr}/backup-exports"
    _run_drush8_hmr_cmd "fr hosting_custom_settings -y"
    _run_drush8_hmr_cmd "cache-clear all"
    _run_drush8_hmr_cmd "cache-clear all"
  fi
  _night_web_hit
  _daily_process
  _night_web_d9
  _run_drush8_hmr_cmd "sqlq \"DELETE FROM hosting_task \
    WHERE task_type='delete' AND task_status='-1'\""
  _run_drush8_hmr_cmd "sqlq \"DELETE FROM hosting_task \
    WHERE task_type='delete' AND task_status='0' AND executed='0'\""
  _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
  _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
    SET status=1 WHERE publish_path LIKE '%/aegir/distro/%'\""
  _check_old_empty_platforms
  _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
  _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
    SET status=-2 WHERE publish_path LIKE '%/aegir/distro/%'\""
  # The platform root goes into the SQL text: a path only.
  _THIS_HM_PLR=$(_acct_read_in "${_usEr}/.drush" hostmaster.alias.drushrc.php \
    | grep "root'" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1)
  if [[ "${_THIS_HM_PLR}" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
    _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
      SET status=1 WHERE publish_path LIKE '${_THIS_HM_PLR}'\""
  fi
  # the purge's legs remove only what root or the account's identities own,
  # and what they leave because another user owns it is said once, below
  _purge_left_open
  _purge_cruft_machine
  # clients/ and every client dir in it are oN's, and the main login owns its
  # home: each removal runs inside the real directory, and a dangling link is
  # removed by find, which walks without following a link.
  if [ "${_hostedSys}" = "YES" ]; then
    _acct_in_real_dir "${_usEr}/clients" \
      rm -rf -- ./admin ./omega8ccgmailcom ./nocomega8cc &> /dev/null
  fi
  _acct_in_real_dir "${_usEr}/clients" _night_clients_bak_here rm
  _purge_left_note
  _acct_in_real_dir "${_usEr}/clients" _night_dangling_rm_here
  if [ -d "/home/${_HM_U}.ftp" ]; then
    _acct_in_real_dir "/home/${_HM_U}.ftp" _night_dangling_rm_here
    rm -f /home/${_HM_U}.ftp/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
  _le_hm_ssl_check_update ${_HM_U}
  if [ "${_ENABLE_GOACCESS}" = "YES" ] \
    && { [ "${_GOACCESS_ALL}" = "YES" ] \
      || [ -e "/etc/boa/.goaccess.all.cnf" ]; }; then
    _if_gen_goaccess "ALL"
  fi
  echo "Done for ${_usEr}"
  _le_account_report
  _ghost_account_report
  _enable_chattr ${_HM_U}.ftp
  rm -f /run/night-account-${_HM_U}.pid
}

### Per-account helpers relocated from owl.sh (hostmaster LE cert +
### empty-platform GC + cruft purge). Called by _account_process above.

_if_le_hm_ssl_old() {
  # Get the current time in seconds since epoch
  _current_time=$(date +%s)

  # Path to the file you want to check
  _filePath="$1"

  # Define the thresholds
  _recent_threshold_days=60  # 60 days to consider for new updates
  _update_check_days=30      # Don't update NEW if it was already set within the last 30 days

  # certs/<domain> is oN's: the file's modification time is taken inside the
  # real directory (through a link, as the client links each name), and the
  # stamp beside it is read bounded, as digits only, and put as a fresh
  # file, never through a link or a FIFO at its name.
  _file_mod_time=$(_acct_in_real_dir "${_filePath%/*}" \
    stat -L -c %Y -- "./${_filePath##*/}" 2> /dev/null)
  [[ "${_file_mod_time}" =~ ^[0-9]{1,12}$ ]] || _file_mod_time=0

  # Calculate the time difference in minutes
  _time_diff_minutes=$(( (_current_time - 10#${_file_mod_time}) / 60 ))

  # Calculate the time difference in days
  _time_diff_days=$(( _time_diff_minutes / 1440 ))

  # Calculate the last update check time (from some state file, if exists)
  _last_update_time=$(_acct_in_real_dir "${_filePath%/*}" \
    _acct_read_plain_here "${_filePath##*/}.lastupdate" | head -c 32)
  _last_update_time="${_last_update_time//[[:space:]]/}"
  [[ "${_last_update_time}" =~ ^[0-9]{1,12}$ ]] || _last_update_time=0

  _last_update_diff_days=$(( (_current_time - 10#${_last_update_time}) / 86400 ))  # 86400 seconds in a day

  # Check if the file was modified within the last 30 minutes
  if [ "${_time_diff_minutes}" -lt 30 ]; then
    _crtLastMod=NEW
  # Check if the file was modified within the last 60 days and not marked NEW in the last 30 days
  elif [ "${_time_diff_days}" -le "${_recent_threshold_days}" ] && [ "${_last_update_diff_days}" -ge "${_update_check_days}" ]; then
    _crtLastMod=NEW
    _acct_in_real_dir "${_filePath%/*}" \
      _acct_put_here "${_filePath##*/}.lastupdate" "${_current_time}"
  else
    _crtLastMod=OLD
  fi
}

# ./$1 in the current (pinned) certs/<domain>/, or the file beside it its
# link names, read as _acct_read_here reads; nothing for a link that leads
# anywhere else.
_night_le_file_here() {
  local _f="${1}" _t
  if [ -L "./${_f}" ]; then
    _t="$(readlink -- "./${_f}")"
    case "${_t}" in
      ""|.|..|*/*) return 1 ;;
    esac
    _f="${_t}"
  fi
  _acct_read_here "${_f}"
}
# The file $1 of the account's certs/<domain>/ (_leCrtPath), read as
# _night_le_file_here reads it, put at root's own $2 (0600) as a fresh file
# renamed over the name; $2 stays as it is when nothing is read.
_night_le_copy() {
  local _c _t="${2}.put.$$.${RANDOM}"
  _c="$(_acct_in_real_dir "${_leCrtPath}" _night_le_file_here "${1}")"
  [ -n "${_c}" ] || return 1
  rm -f -- "${_t}"
  ( umask 077
    printf '%s\n' "${_c}" | dd of="${_t}" conv=excl status=none 2> /dev/null ) \
    && mv -f -T -- "${_t}" "${2}" && return 0
  rm -f -- "${_t}"
  return 1
}

_if_le_hm_ssl_crt_key_copy() {
  _crtPath=
  if [ -e "${_leCrtPath}/fullchain.pem" ]; then
    _crtPath="${_leCrtPath}/fullchain.pem"
  elif [ -e "${_leCrtPath}/cert.pem" ]; then
    _crtPath="${_leCrtPath}/cert.pem"
  fi
  # tools/le is oN's: the certificate and the key are read bounded inside the
  # real certs/<domain>/, through a link only to a file beside it (as the
  # client links each name to a versioned file), and written as root's own
  # 0600 files.
  if [ -n "${_crtPath}" ]; then
    _night_le_copy "${_crtPath##*/}" "/etc/ssl/private/${_hmFront}.crt"
  fi
  _keyPath="${_leCrtPath}/privkey.pem"
  if [ -e "${_keyPath}" ]; then
    _night_le_copy privkey.pem "/etc/ssl/private/${_hmFront}.key"
  fi
}

_le_hm_ssl_check_update() {
  _leCrtPath=
  _hmFront=
  _hmFrontExtra=
  _exeLe="${_usEr}/tools/le/dehydrated"
  # log/ and .drush/ are oN's: each name is read bounded inside the real
  # directory, never through a link or blocked on a FIFO. The front-end
  # name names root's /etc/ssl/private files and a log/ctrl marker: it is
  # used only in a host name's form, only when it is the account's own
  # front (_DOMAIN in root's octopus.cnf) and only when that front names
  # nothing the box or another account uses there (_night_front_free).
  if [ -e "${_usEr}/log/domain.txt" ]; then
    _hmFront=$(_night_words "$(_acct_read_in "${_usEr}/log" domain.txt)")
  fi
  if [ -e "${_usEr}/log/extra_domain.txt" ]; then
    _hmFrontExtra=$(_night_words "$(_acct_read_in "${_usEr}/log" extra_domain.txt)")
  fi
  if [ -z "${_hmFront}" ]; then
    if [ -e "${_usEr}/.drush/hostmaster.alias.drushrc.php" ]; then
      _hmFront=$(_acct_read_in "${_usEr}/.drush" hostmaster.alias.drushrc.php \
        | grep -E "^[[:space:]]*'uri'[[:space:]]*=>" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
    fi
  fi
  if [ -n "${_hmFront}" ] && ! _night_host_ok "${_hmFront}"; then
    echo "LE: the hostmaster name for ${_HM_U} is not a host name; skipped"
    _hmFront=
  fi
  if [ -n "${_hmFront}" ] && [ "${_hmFront}" != "${_DOMAIN}" ]; then
    echo "LE: the hostmaster name ${_hmFront} for ${_HM_U} is not the _DOMAIN in /root/.${_HM_U}.octopus.cnf; skipped"
    _hmFront=
  fi
  if [ -n "${_hmFront}" ] && ! _night_front_free "${_hmFront}"; then
    echo "LE: the hostmaster name ${_hmFront} for ${_HM_U} is one the box or another account uses; skipped"
    _hmFront=
  fi
  if [ -n "${_hmFrontExtra}" ] && ! _night_hosts_ok "${_hmFrontExtra}"; then
    echo "LE: ${_usEr}/log/extra_domain.txt holds no host names; ignored"
    _hmFrontExtra=
  fi
  if [ ! -z "${_hmFront}" ]; then
    _leCrtPath="${_usEr}/tools/le/certs/${_hmFront}"
  fi
  if [ ! -z "${_hmFront}" ] \
    && [ -e "${_usEr}/tools/le/.ctrl/dont-overwrite-${_hmFront}.pid" ]; then
    ### Same immutable-marker contract as the per-site nightly leg. Only the
    ### dehydrated run is gated; the copy to /etc/ssl/private below still
    ### happens, so a manually replaced hostmaster cert propagates.
    echo "LE renewal skipped for hostmaster ${_hmFront} -- immutable dont-overwrite marker present"
  elif [ -x "${_exeLe}" ] \
    && [ ! -z "${_hmFront}" ] \
    && [ -e "${_leCrtPath}/fullchain.pem" ]; then
    _DOM=$(date +%e)
    _DOM=${_DOM//[^0-9]/}
    _RDM=$((RANDOM%25+6))
    if [ "${_DOM}" = "${_RDM}" ] || [ -e "${_usEr}/static/control/force-ssl-certs-rebuild.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/site.${_hmFront}.cert-x1-rebuilt.info" ]; then
        _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
        _log_ctrl_mark "site.${_hmFront}.cert-x1-rebuilt.info"
      else
        _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
      fi
    else
      _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
    fi
    if [ ! -z "${_hmFrontExtra}" ]; then
      echo "Running LE cert check directly for hostmaster ${_HM_U} with ${_hmFrontExtra}"
      su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${_leParams} --domain ${_hmFront} --domain ${_hmFrontExtra}"
      wait
    else
      echo "Running LE cert check directly for hostmaster ${_HM_U}"
      su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${_leParams} --domain ${_hmFront}"
      wait
    fi
  fi
  _crtLastMod=OLD
  if [ -n "${_leCrtPath}" ]; then
    _if_le_hm_ssl_old "${_leCrtPath}/fullchain.pem"
  fi
  if [ "${_crtLastMod}" = "NEW" ]; then
    echo "Copying NEW LE cert for hostmaster ${_hmFront} to /etc/ssl/private/"
    _if_le_hm_ssl_crt_key_copy
  else
    echo "No new LE cert for hostmaster ${_hmFront} to copy"
  fi
}

# Client LE notices are ON unless explicitly disabled. The per-account override
# in /root/.<user>.octopus.cnf (already sourced into scope by _account_process)
# wins over the global default frozen from /root/.barracuda.cnf; only the
# literal NO disables. tr is used instead of ${x^^} so it stays portable.
_le_client_notify_on() {
  local _v
  _v=$(echo "${_LE_CLIENT_NOTIFY}" | tr -d "\"' " | tr '[:lower:]' '[:upper:]')
  [ "${_v}" = "NO" ] && return 1
  return 0
}

# Build and send the Let's Encrypt renewal incident report for THIS account
# from its own night log. The operator (server admin _ADMIN_EMAIL, the
# _MY_EMAIL from /root/.barracuda.cnf) gets the full per-account detail every
# night; the affected client (_CLIENT_EMAIL from this account's .octopus.cnf,
# kept in sync with log/email.txt) gets an actionable notice, throttled to once
# per 7 days per failing site so a dead clone does not mail them nightly.
# Reading ONLY this account's log and using ONLY this account's own resolved
# _CLIENT_EMAIL is what guarantees the client notice can never reach the wrong
# account. Operator mail also carries any non-LE backend incident lines so the
# move to per-account logs does not lose the old _thisLog catch-all.
_le_account_report() {
  local _acctLog _fails _nonle _throttle _now _markerDir _marker _fresh _mTime
  local _site _cdom _calt _ctype _cdetail _reason _opBody _clBody _clList _reply
  _acctLog="$(_acct_night_log "${_usEr}")"
  [ -r "${_acctLog}" ] || return 0
  _fails="$(_le_extract_failures "${_acctLog}")"
  ###
  ### Operator catch-all for non-validation backend + account/order-level ACME
  ### errors. The rich _le_extract_failures path covers per-domain validation
  ### failures; this restores the old _thisLog _incident_detection coverage of
  ### the ACME urn:* tokens (badNonce/serverInternal/rateLimited surfacing
  ### outside a per-domain detail block) now that per-account output left
  ### _thisLog. The `grep -v '^\["'` drops the per-domain jsonsh dump lines so a
  ### normal validation failure is not also echoed here (already in the report).
  ###
  _nonle="$(grep -E -a \
    'Remote PerformValidation RPC failed|ModuleNotFoundError|Traceback|Drush command terminated abnormally|ArgumentCountError|THIS SITE IS BROKEN|urn:ietf:params:acme:error:|urn:acme:error:serverInternal' \
    "${_acctLog}" 2>/dev/null | grep -v -E '^\["' | sort -u | head -n 40)"
  [ -z "${_fails}" ] && [ -z "${_nonle}" ] && return 0
  _throttle=7
  _now=$(date +%s)
  # log/ctrl is oN's: each notify marker is read and put only inside the
  # real directory (_night_mtime_here, _log_ctrl_mark), never through a link
  # or a FIFO at its name.
  _markerDir="${_usEr}/log/ctrl"
  _acct_in_real_dir "${_usEr}/log" mkdir -p ./ctrl 2> /dev/null

  ###
  ### Operator report -- full per-account detail, every night, unless incident
  ### reporting is silenced (_INCIDENT_REPORT OFF/NO, matching the old gate).
  ###
  if [ -n "${_ADMIN_EMAIL}" ] \
    && [ "${_INCIDENT_REPORT}" != "OFF" ] \
    && [ "${_INCIDENT_REPORT}" != "NO" ]; then
    _opBody="LE (HTTPS certificate) renewal report for account ${_HM_U} on ${_hName}"$'\n'
    if [ -n "${_fails}" ]; then
      _opBody="${_opBody}"$'\n'"Sites failing Let's Encrypt renewal:"$'\n'
      while IFS=$'\x1f' read -r _site _cdom _calt _ctype _cdetail; do
        [ -z "${_cdom}" ] && continue
        _reason="$(_le_reason "${_ctype}" "${_cdetail}")"
        _opBody="${_opBody}"$'\n'"  Site: ${_site}"$'\n'"    Certificate names: ${_calt:-${_cdom}}"$'\n'"    Cause: ${_reason}"$'\n'"    LE detail [${_ctype}]: ${_cdetail}"$'\n'
      done <<EOF
${_fails}
EOF
    fi
    if [ -n "${_nonle}" ]; then
      _opBody="${_opBody}"$'\n'"Other backend incidents detected in this account's run:"$'\n'"${_nonle}"$'\n'
    fi
    _opBody="${_opBody}"$'\n'"Full account log: ${_acctLog}"$'\n'
    echo "Sending LE/incident operator report for ${_HM_U} to ${_ADMIN_EMAIL} on $(date)"
    echo "${_opBody}" \
      | s-nail -s "LE renewal/incident report: ${_HM_U} on ${_hName}" "${_ADMIN_EMAIL}"
  fi

  ###
  ### Client report -- only on LE failures, opt-out aware, throttled per site.
  ### Skip entirely when disabled or when there is no real external client
  ### address (empty or the local "root" alias used on operator master accounts).
  ###
  [ -z "${_fails}" ] && return 0
  _le_client_notify_on || return 0
  if [ -z "${_CLIENT_EMAIL}" ] || [ "${_CLIENT_EMAIL}" = "root" ]; then
    return 0
  fi
  # before any site is marked notified: a notice the hold stops goes out later
  _client_mail_hold "${_CLIENT_EMAIL}" || return 0
  _clList=""
  while IFS=$'\x1f' read -r _site _cdom _calt _ctype _cdetail; do
    [ -z "${_cdom}" ] && continue
    _marker="le-notify.$(printf '%s' "${_cdom}" | tr -c 'a-zA-Z0-9._-' '_').info"
    _fresh=YES
    _mTime=$(_acct_in_real_dir "${_markerDir}" _night_mtime_here "${_marker}")
    if [ -n "${_mTime}" ]; then
      if [ "$(( (_now - _mTime) / 86400 ))" -lt "${_throttle}" ]; then
        _fresh=NO
      fi
    fi
    [ "${_fresh}" = "NO" ] && continue
    _reason="$(_le_reason "${_ctype}" "${_cdetail}")"
    _clList="${_clList}"$'\n'"  - ${_cdom} -- ${_reason}"$'\n'"      Details: ${_cdetail}"$'\n'
    _log_ctrl_mark "${_marker}"
  done <<EOF
${_fails}
EOF
  [ -z "${_clList}" ] && return 0
  _clBody="Hello,"$'\n'
  _clBody="${_clBody}"$'\n'"Automatic HTTPS (Let's Encrypt SSL) certificate renewal failed for the"$'\n'"following site(s) in your hosting account on ${_hName}:"$'\n'"${_clList}"
  _clBody="${_clBody}"$'\n'"While a certificate cannot be renewed, this check runs and fails again every"$'\n'"night, so please take one of these actions:"$'\n'
  _clBody="${_clBody}"$'\n'"  - If the site is still in use: point its domain's DNS A record at this"$'\n'"    server and remove any AAAA record (the server answers on IPv4 only),"$'\n'"    and the certificate will renew automatically."$'\n'
  _clBody="${_clBody}"$'\n'"  - If the site or alias is no longer used: please disable Encryption (SSL)"$'\n'"    for it, or remove the obsolete domain alias, to stop these daily"$'\n'"    failures and notices."$'\n'
  _clBody="${_clBody}"$'\n'"This is an automated message from your hosting platform."$'\n'
  # Reply-To the account owner (else the server admin) so a client's reply
  # reaches a human, not the undeliverable root@<host> envelope sender. Only set
  # when it resolves to a real address (non-empty, not "root", has an @).
  _reply="${_MY_OCTO_EMAIL}"
  if [ -z "${_reply}" ] || [ "${_reply}" = "root" ] \
    || [[ "${_reply}" =~ ^root@ ]]; then
    # root and the derived root@<fqdn> self-hosted admin identity are both
    # local-only mailboxes -- as undeliverable for a client reply as bare root.
    _reply="${_ADMIN_EMAIL}"
  fi
  echo "Sending LE client notice for ${_HM_U} to ${_MAIL_HOLD_RCPT}${_MAIL_HOLD_SFX} on $(date)"
  if [ -n "${_reply}" ] && [ "${_reply}" != "root" ] \
    && ! [[ "${_reply}" =~ ^root@ ]] && [[ "${_reply}" =~ @ ]]; then
    echo "${_clBody}" \
      | s-nail -S replyto="${_reply}" -s "Action needed: HTTPS certificate renewal failed for one or more of your sites${_MAIL_HOLD_SFX}" "${_MAIL_HOLD_RCPT}"
  else
    echo "${_clBody}" \
      | s-nail -s "Action needed: HTTPS certificate renewal failed for one or more of your sites${_MAIL_HOLD_SFX}" "${_MAIL_HOLD_RCPT}"
  fi
}

# Ghost-site client notices follow the LE gate model: ON unless the literal NO,
# per-account octopus.cnf override wins over the barracuda.cnf default.
_ghost_client_notify_on() {
  local _v
  _v=$(echo "${_GHOST_CLIENT_NOTIFY}" | tr -d "\"' " | tr '[:lower:]' '[:upper:]')
  [ "${_v}" = "NO" ] && return 1
  return 0
}

# Build and send the ghost-site notice for THIS account from its own night log.
# A ghost site is a registration (Drush alias + nginx vhost) whose site
# directory no longer exists -- typically an install or clone that failed or
# was rolled back. The nightly _cleanup_ghost_drushrc sweep already logs each
# one (and moves the backend leftovers aside when _GHOST_SITES_CLEANUP=YES),
# but a record still present in the account's own Aegir front-end can only be
# removed there, and any task run on it re-creates the backend leftovers -- so
# the account owner gets an actionable notice, throttled per site. Only the
# post-grace "GHOST drushrc" lines are matched, which the sweep emits ONLY
# after confirming the front-end record still exists (_hmr_context_exists):
# a ghost whose node the customer already deleted is logged as a backend
# leftover instead and cleaned without any mail, since there is nothing they
# could see or act on. Never matched either: the single-night grace line, the
# SKIPPED classifications, the vhost/platform/.restore variants. Same source
# discipline as _le_account_report: only THIS account's log and THIS
# account's _CLIENT_EMAIL, so a notice can never reach the wrong account.
_ghost_account_report() {
  local _acctLog _ghosts _throttle _now _markerDir _marker _fresh _mTime
  local _site _ghList _clBody _reply
  _acctLog="$(_acct_night_log "${_usEr}")"
  [ -r "${_acctLog}" ] || return 0
  _ghosts="$(awk '
    /^GHOST drushrc for [^ ]+ detected and moved to / { print $4; next }
    /^GHOST drushrc for [^ ]+ detected \(dry-run/ { print $4 }
  ' "${_acctLog}" 2>/dev/null | sort -u)"
  [ -z "${_ghosts}" ] && return 0
  _ghost_client_notify_on || return 0
  if [ -z "${_CLIENT_EMAIL}" ] || [ "${_CLIENT_EMAIL}" = "root" ]; then
    return 0
  fi
  # before any site is marked notified: a notice the hold stops goes out later
  _client_mail_hold "${_CLIENT_EMAIL}" || return 0
  # Ghosts are not urgent (the dead record is the only thing left), so the
  # throttle is much longer than the 7-day LE one to keep mail volume low.
  _throttle=30
  _now=$(date +%s)
  # log/ctrl is oN's: each notify marker is read and put only inside the
  # real directory (_night_mtime_here, _log_ctrl_mark), never through a link
  # or a FIFO at its name.
  _markerDir="${_usEr}/log/ctrl"
  _acct_in_real_dir "${_usEr}/log" mkdir -p ./ctrl 2> /dev/null
  _ghList=""
  # One record per line, read literally: ${_ghosts} comes from the night log
  # and an unquoted expansion here would word-split it and glob it against the
  # cwd (_account_process cd'd into the hostmaster site dir), putting local
  # filenames into a customer-facing notice.
  while IFS= read -r _site; do
    [ -n "${_site}" ] || continue
    _marker="ghost-notify.$(printf '%s' "${_site}" | tr -c 'a-zA-Z0-9._-' '_').info"
    _fresh=YES
    _mTime=$(_acct_in_real_dir "${_markerDir}" _night_mtime_here "${_marker}")
    if [ -n "${_mTime}" ]; then
      if [ "$(( (_now - _mTime) / 86400 ))" -lt "${_throttle}" ]; then
        _fresh=NO
      fi
    fi
    [ "${_fresh}" = "NO" ] && continue
    _ghList="${_ghList}"$'\n'"  - ${_site}"
    _log_ctrl_mark "${_marker}"
  done <<EOF
${_ghosts}
EOF
  [ -z "${_ghList}" ] && return 0
  _clBody="Hello,"$'\n'
  _clBody="${_clBody}"$'\n'"The nightly maintenance on ${_hName} found broken leftover site"$'\n'"registration(s) in your hosting account:"$'\n'"${_ghList}"$'\n'
  _clBody="${_clBody}"$'\n'"Each of these is a record of a site that has no directory on the server"$'\n'"any more -- typically an install or clone that failed or was rolled back,"$'\n'"so only its registration was left behind. The record still shows up in"$'\n'"your Aegir control panel and keeps being re-detected until it is removed"$'\n'"there; the server cannot remove it for you, because the control panel"$'\n'"re-creates the backend records on the next task run."$'\n'
  _clBody="${_clBody}"$'\n'"How to remove it in your Aegir control panel (takes a minute):"$'\n'
  _clBody="${_clBody}"$'\n'"  - If you do not need the site: open the site's page in the control"$'\n'"    panel, run Disable first if the site still shows as enabled (the"$'\n'"    Delete button appears only on a disabled site), then run Delete."$'\n'"    If Delete fails or never finishes, note the number at the end of"$'\n'"    the site page's address (it looks like /node/12345), then open"$'\n'"    /node/12345/delete in your browser and confirm -- this removes the"$'\n'"    stuck record directly."$'\n'
  _clBody="${_clBody}"$'\n'"  - If you still need the site: open the site's page and re-run the"$'\n'"    failed task (Install or Clone), or delete the broken record and"$'\n'"    create the site afresh."$'\n'
  _clBody="${_clBody}"$'\n'"These records point at no site data on the server, so removing them"$'\n'"does not touch any of your working sites, and nothing is deleted on the"$'\n'"server side by this process."$'\n'
  _clBody="${_clBody}"$'\n'"This is an automated message from your hosting platform."$'\n'
  _reply="${_MY_OCTO_EMAIL}"
  if [ -z "${_reply}" ] || [ "${_reply}" = "root" ] \
    || [[ "${_reply}" =~ ^root@ ]]; then
    # root and the derived root@<fqdn> self-hosted admin identity are both
    # local-only mailboxes -- as undeliverable for a client reply as bare root.
    _reply="${_ADMIN_EMAIL}"
  fi
  echo "Sending ghost-site client notice for ${_HM_U} to ${_MAIL_HOLD_RCPT}${_MAIL_HOLD_SFX} on $(date)"
  if [ -n "${_reply}" ] && [ "${_reply}" != "root" ] \
    && ! [[ "${_reply}" =~ ^root@ ]] && [[ "${_reply}" =~ @ ]]; then
    echo "${_clBody}" \
      | s-nail -S replyto="${_reply}" -s "Action suggested: broken leftover site record(s) in your control panel${_MAIL_HOLD_SFX}" "${_MAIL_HOLD_RCPT}"
  else
    echo "${_clBody}" \
      | s-nail -s "Action suggested: broken leftover site record(s) in your control panel${_MAIL_HOLD_SFX}" "${_MAIL_HOLD_RCPT}"
  fi
}

_delete_this_platform() {
  _run_drush8_hmr_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

# In the current (pinned) .drush: the site_path lines of every
# *.drushrc.php, each read as _acct_read_plain_here reads it and prefixed
# with its path as grep prints a file's matches.
_night_site_path_lines_here() {
  local _f
  for _f in ./*.drushrc.php; do
    _acct_read_plain_here "${_f#./}" \
      | grep -H --label="${_usEr}/.drush/${_f#./}" "site_path"
  done
  return 0
}

_check_old_empty_platforms() {
  local _drD="${_usEr}/.drush" _pf _siteLines
  _provision_running && { echo "INFO: provision task active -- skipping empty-platform cleanup"; return; }
  if [ "${_hostedSys}" = "YES" ]; then
    if [[ "${_hName}" =~ "demo.aegir.cc" ]] \
      || [ -e "${_usEr}/static/control/platforms.info" ]; then
      _DO_NOTHING=YES
    else
      if [ -n "${_DEL_OLD_EMPTY_PLATFORMS}" ] \
        && [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
        _DO_NOTHING=YES
      else
        _DEL_OLD_EMPTY_PLATFORMS="60"
      fi
    fi
  fi
  if [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
    if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to \
        ${_DEL_OLD_EMPTY_PLATFORMS} days on ${_HM_U} instance"
      # .drush is oN's: the aliases are listed, read and moved only inside
      # the real directory, each read bounded and never through a link or a
      # FIFO; the site_path lines are read once for the whole loop. The
      # list comes on fd 3: the drush calls below read stdin.
      _siteLines=$(_acct_in_real_dir "${_drD}" _night_site_path_lines_here)
      while IFS= read -r _pf <&3; do
        _pf="${_pf#./}"
        _T_PFM_NAME="${_pf#platform_}"
        _T_PFM_NAME="${_T_PFM_NAME%.alias.drushrc.php}"
        # the name reaches a drush command line
        [[ "${_T_PFM_NAME}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        _T_PFM_ROOT=$(_acct_read_in "${_drD}" "${_pf}" \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        # The alias keeps the path the platform was registered with, which for
        # a Composer build can be its app root; site_path and sites/all live
        # under the docroot Provision serves, so both tests below read that.
        _T_PFM_DOC=$(_detect_real_docroot "${_T_PFM_ROOT}")
        _T_PFM_SITE=$(grep -F -e "${_T_PFM_ROOT}/sites/" \
          -e "${_T_PFM_DOC:-${_T_PFM_ROOT}}/sites/" \
          <<< "${_siteLines}" 2>&1)
        if [ -z "${_T_PFM_DOC}" ]; then
          # Version-agnostic emptiness: no index.php at the alias root nor
          # under web/docroot/html. Do NOT key on sites/all (D8+ dropped it).
          if _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_PLATFORMS_CLEANUP \
            || _cnf_flag_yes /root/.barracuda.cnf _GHOST_PLATFORMS_CLEANUP; then
            if _acct_in_real_dir "${_drD}" \
              _acct_undo_here "platform_${_T_PFM_NAME}.alias.drushrc.php" &> /dev/null; then
              echo "GHOST platform ${_T_PFM_ROOT} detected and moved to ${_usEr}/undo/"
            else
              echo "GHOST platform ${_T_PFM_ROOT} detected and not moved: ${_GH_REFUSED}"
            fi
          else
            echo "GHOST platform ${_T_PFM_ROOT} detected (dry-run; set _GHOST_PLATFORMS_CLEANUP=YES in /root/.${_HM_U}.octopus.cnf or /root/.barracuda.cnf to move)"
          fi
        fi
        if [[ "${_T_PFM_SITE}" =~ ".restore" ]]; then
          echo "WARNING: ghost site leftover found: ${_T_PFM_SITE}"
        fi
        if [ -z "${_T_PFM_SITE}" ] \
          && [ -e "${_T_PFM_DOC:-${_T_PFM_ROOT}}/sites/all" ]; then
          _delete_this_platform
        fi
      done 3< <(_acct_in_real_dir "${_drD}" find . -mindepth 1 -maxdepth 1 \
        -name 'platform_*' -mtime "+${_DEL_OLD_EMPTY_PLATFORMS}" -type f \
        2> /dev/null | sort)
    fi
  fi
}

_purge_hits_under_account() {
  # Re-anchor each hit fed in on stdin before deleting it. The static/* globs
  # in _purge_cruft_machine are expanded by the shell, which resolves symlinks
  # in every component, and ${_usEr}/static is 02775 and group-writable by the
  # account's shell identities -- so a tenant-planted link points the pattern
  # at another account's tree. Gate on
  # the RESOLVED path rather than refusing symlinks, because the site files/
  # and private/ links into this account's own store are legitimate. The store
  # may sit on attached storage under /mnt; nothing else is a supported
  # placement. Reads _usEr.
  local _f _r _acct _store _o _n
  _acct=$(realpath -e -- "${_usEr}" 2>/dev/null) || return 0
  _o=$(_acct_walk_uids "${_usEr##*/}") || return 0
  # static/ is group-writable, so static/files itself can be a planted link:
  # only the account's own directory, or its store in migratefs' layout on
  # attached storage (/mnt/<mount>/files/<oN>/static/files), counts as the
  # store, the rule every nightly store leg uses.
  _store=$(_night_acct_store) || _store=
  # the hit is removed from inside its resolved directory, entered for real,
  # so no name on the way is resolved a second time, and only when root or
  # one of the account's own identities owns it and that directory and every
  # one above it (_ACCT_RM_OWN_PL): the account's identities can rename what
  # another account left group-writable into these trees, a whole directory
  # with files nested in it included
  while IFS= read -r -d '' _f; do
    _r=$(realpath -e -- "${_f}" 2>/dev/null) || continue
    case "${_r}/" in
      "${_acct}"/*) ;;
      *)
        [ -n "${_store}" ] || continue
        case "${_r}/" in
          "${_store}"/*) ;;
          *) continue ;;
        esac
        ;;
    esac
    _n=$( ( cd -P -- "${_r%/*}" 2>/dev/null && [ "$(pwd -P)" = "${_r%/*}" ] \
      && perl -e "${_ACCT_RM_OWN_PL}" -- h "${_o}" - "./${_r##*/}" ) 2> /dev/null )
    _purge_left_add "${_n}"
  done
}

### The account's own web group, before the site loop: its drift witnesses
### (instgrp webdrift; an alarm goes to the nightly's incident log and, once
### a day, to the operator's address, never to the account's own), and a
### reclaim when the account carries a web-group record and www-data is back
### in its settings files or store tops (instgrp reclaim runs the web leg
### first). An instgrp without the web group does nothing here.
_night_web_hit() {
  local _l _alarm="" _res=NO _deep=( --deep )
  [ -e "/opt/local/bin/instgrp" ] || return 0
  grep -q "^_wg_drift() {" /opt/local/bin/instgrp 2> /dev/null || return 0
  grep -q "^_WG_DEEP=" /opt/local/bin/instgrp 2> /dev/null || _deep=()
  # --own night: this pass holds the account itself (its night marker), which
  # the witnesses must not read as a conversion run holding it; --deep: the
  # residue rule in full, the private set read in depth
  while IFS= read -r _l; do
    case "${_l}" in
      "ALRT "*) _alarm="${_alarm:+${_alarm}; }${_l#ALRT }" ;;
      "NOTE "*) echo "${_HM_U}: web group: ${_l#NOTE }" ;;
      RESIDUE) _res=YES ;;
    esac
  done < <(bash /opt/local/bin/instgrp webdrift "${_HM_U}" --report --own night "${_deep[@]}" 2> /dev/null)
  if [ -n "${_alarm}" ]; then
    echo "ALRT: ${_HM_U}: web group drift: ${_alarm}"
    if declare -F _night_notice > /dev/null 2>&1; then
      # the operator's address as this run froze it (_ADMIN_EMAIL, the box's
      # _MY_EMAIL), root when there is none: this pass has replaced
      # _MY_EMAIL and _MY_OCTO_EMAIL with what the account's cnf carries
      ( _MY_OCTO_EMAIL=""
        _MY_EMAIL="${_ADMIN_EMAIL:-}"
        _night_notice "wg-drift-${_HM_U}" \
          "BOA nightly on $(hostname -f): web group drift on ${_HM_U}" "${_alarm}" )
    fi
  fi
  if [ "${_res}" = "YES" ]; then
    echo "DRIFT: ${_HM_U}: www-data in the web group's settings files, store tops or private set; running instgrp reclaim"
    bash /opt/local/bin/instgrp reclaim "${_HM_U}"
  fi
  return 0
}

### The limited-shell worker's walk of the public files (D9) that ran out of
### time three passes in a row, after the site loop (whose permissions pass
### gives each site's files store its public modes too), so it never delays
### site maintenance: instgrp reclaim walks the public set whole, with no time
### bound, and moves the worker's stamp to the walk's start (the rebase,
### marked .rebase when it moved). A store whose walk alone outgrows the
### worker's bound times out again at once: while the worker has finished
### no pass since the last rebase (its stamp no newer than the mark), the
### next one waits a week from it.
_night_web_d9() {
  local _st="/var/log/boa/manage-ltd-d9.${_HM_U}.txt" _slow
  [ -e "/opt/local/bin/instgrp" ] || return 0
  grep -q "^_wg_drift() {" /opt/local/bin/instgrp 2> /dev/null || return 0
  _slow=$(head -c 8 "${_st}.slow" 2> /dev/null | tr -cd '0-9')
  [ -n "${_slow}" ] && [ "${_slow}" -ge 3 ] || return 0
  if [ -f "${_st}.rebase" ] && [ ! "${_st}" -nt "${_st}.rebase" ] \
    && [ -z "$(find "${_st}.rebase" -maxdepth 0 -mtime +6 2> /dev/null)" ]; then
    echo "${_HM_U}: the public files walk still runs out of time since the last rebase; the next one waits a week from it"
    return 0
  fi
  echo "${_HM_U}: the public files walk ran out of time ${_slow} passes in a row; running instgrp reclaim to walk it whole"
  bash /opt/local/bin/instgrp reclaim "${_HM_U}"
  # the reclaim moved the stamp when the run of timeouts it ends is gone
  [ -e "${_st}.slow" ] || touch "${_st}.rebase" 2> /dev/null
  return 0
}

_purge_cruft_machine() {

  if [ ! -z "${_DEL_OLD_TMP}" ] && [ "${_DEL_OLD_TMP}" -gt 0 ]; then
    _PURGE_TMP="${_DEL_OLD_TMP}"
  else
    _PURGE_TMP="0"
  fi

  if [ ! -z "${_DEL_OLD_BACKUPS}" ] && [ "${_DEL_OLD_BACKUPS}" -gt 0 ]; then
    _PURGE_BACKUPS="${_DEL_OLD_BACKUPS}"
  else
    _PURGE_BACKUPS="14"
    if [ "${_hostedSys}" = "YES" ]; then
      _PURGE_BACKUPS="7"
    fi
  fi

  _LOW_NR="2"
  _PURGE_CTRL="14"

  # log/ctrl, backups, backup-exports and clients/ are oN's: each is
  # purged from inside the real directory (backups and backup-exports also
  # where the backups mover linked them into the account's store), and every
  # hit is removed from inside the directory the walk entered; the backups,
  # backup-exports and clients legs remove only what root or the account's
  # identities own (_night_purge_here).
  _acct_in_real_dir "${_usEr}/log/ctrl" _night_ctrl_purge_here \
    "${_PURGE_CTRL}" '*cert-x1-rebuilt.info' 'le-notify.*.info'
  _acct_in_real_dir "${_usEr}/log/ctrl" _night_ctrl_purge_here \
    "${_PURGE_TMP}" 'plr*' '*rom-fix.info'

  _night_in_bak_dir backups _night_purge_here "${_PURGE_BACKUPS}" \
    || _night_bak_unpurged backups
  _acct_in_real_dir "${_usEr}/clients" _night_clients_bak_here \
    purge "${_PURGE_BACKUPS}"
  _night_in_bak_dir backup-exports _night_purge_here "${_PURGE_TMP}" files \
    || _night_bak_unpurged backup-exports

  # sites/<uri>/files and private/ are group-writable by the web and shell
  # identities: every hit below, distro/ and static/ alike, is re-anchored
  # before it is removed (see _purge_hits_under_account)
  find ${_usEr}/distro/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/distro/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account

  # These globs are expanded by the SHELL, which resolves symlinks in every
  # component, and ${_usEr}/static is 02775 and group-writable by the account's
  # shell identities -- so a link planted at
  # any level aims the same pattern at another account's tree and root does the
  # deleting. find -P is not the fix: the site files/ and private/ components
  # are legitimately symlinks into this account's own store, and refusing them
  # would stop the purge working at all. Re-anchor every hit instead.
  find ${_usEr}/static/*/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account

  find ${_usEr}/static/*/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account

  find ${_usEr}/distro/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/distro/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -print0 2>/dev/null | _purge_hits_under_account

  # /home/<user>.ftp is the tenant's own (chrooted) home and, unlike a backend
  # account root, is never immutable, so .tmp and tmp can be swapped for
  # symlinks at any moment, as can oN's own .tmp and tmp. Each is purged from
  # inside the real directory only (_night_purge_here), so neither the start
  # nor any name below it leads elsewhere. The top-level dot names are kept,
  # as the /* glob kept them, so the .ctrl.<tree>.<serial>.pid marker that
  # manage_ltd_users.sh keeps in .tmp is left alone; aged entries below a
  # recently touched directory are still reaped.
  for _tmpDir in "/home/${_HM_U}.ftp/.tmp" "/home/${_HM_U}.ftp/tmp" \
    "${_usEr}/.tmp" "${_usEr}/tmp"; do
    _acct_in_real_dir "${_tmpDir}" _night_purge_here "${_PURGE_TMP}"
  done

  # Both writes below land inside this account's own tree, so the group is
  # derived from the account rather than hardcoded; 'users' on an unconverted box.
  local _acctGrp _igHit _igPend _igBak _igId _igUid _igOwn _igSel _igWg _igX=()
  _acctGrp=$(_acct_group "${_HM_U}")
  # A revert (or the rollback of a convert) the limited-shell worker is still
  # finishing leaves the account's own identity on the account's group, which
  # _acct_group reads as converted: write with the box-wide group, as the
  # worker does meanwhile, and leave the drift probe to a later night (a
  # reclaim now would re-group the tree onto the group being reverted).
  _igPend=NO
  if [ -s "/var/log/boa/instgrp.revert-pending.${_HM_U}" ]; then
    _acctGrp=users
    _igPend=YES
  fi
  # Drift probe: the credential-bearing paths (~/.drush aliases, backups,
  # config, tools, the hostmaster sites, every drushrc.php under static) are
  # re-grouped by the octopus arm only, so a stale writer or a hand chown
  # between releases would sit unseen for a release cycle. One early-quit
  # find; instgrp reclaim is the file half alone (no identities, no lock),
  # idempotent, so the nightly may run it. An UNCONVERTED account is probed
  # too: a copy or a root-run restore can land its tree in another
  # account's named group there, and reclaim hands it back to the box-wide
  # group -- the same exposure class, which the converted-only gate missed.
  if [ "${_igPend}" = "NO" ] && [ -x "/opt/local/bin/instgrp" ]; then
    # backups may be a link into the static store (relocated backups): probe
    # where the files are, only while that is the account's own
    # (_night_in_bak_dir). The static leg is bounded to the depth where a
    # site's drushrc.php lives (<platform>[/web]/sites/<uri>/drushrc.php),
    # so the clean case does not traverse every files/ tree.
    # Only what the reclaim walk changes is a hit: a directory, a single-link
    # regular file, or a regular file or FIFO owned by the account or its
    # .ftp identity (members of the target group, so handing them the group
    # gives nothing away). A symlink, a foreign hard-linked file or FIFO, a
    # socket or a device outside the group would otherwise trigger a reclaim
    # that changes nothing, every night. The uids are numeric and an identity
    # that does not resolve is left out, so find never aborts on a bad name.
    _igOwn=()
    for _igId in "${_HM_U}" "${_HM_U}.ftp"; do
      _igUid=$(id -u -- "${_igId}" 2>/dev/null)
      [[ "${_igUid}" =~ ^[0-9]+$ ]] || continue
      [[ "${#_igOwn[@]}" -gt 0 ]] && _igOwn+=(-o)
      _igOwn+=(-uid "${_igUid}")
    done
    _igSel=(\( -type d -o -type f -links 1)
    if [[ "${#_igOwn[@]}" -gt 0 ]]; then
      _igSel+=(-o \( -type f -o -type p \) \( "${_igOwn[@]}" \))
    fi
    _igSel+=(\))
    _igBak=$(_night_in_bak_dir backups pwd -P 2>/dev/null)
    # The account's own web group (the hostmaster site's files/, private/
    # and settings.php once converted) is no drift: its gid is exempt from
    # the moment the group exists, since a conversion moves those paths
    # before it writes its record. Numeric, and only when it resolves: find
    # refuses an unknown group name, and the probe would then read clean.
    _igWg=$(_web_group_state "${_HM_U}")
    if [ "${_igWg%% *}" = "foreign" ]; then
      echo "NOTE: ${_HM_U}: ${_igWg##* } is held by an identity outside the account [$(getent group "${_igWg##* }" | cut -d: -f4)]; its paths are kept, nothing joins it"
    fi
    _igWg=$(cut -d' ' -f2 <<< "${_igWg}")
    case "${_igWg}" in
      ""|*[!0-9]*) ;;
      *) _igX=( ! -gid "${_igWg}" ) ;;
    esac
    _igHit=$(find -P ${_usEr}/.drush ${_igBak:+"${_igBak}"} ${_usEr}/config ${_usEr}/tools \
      ${_usEr}/aegir/distro/*/sites -xdev "${_igSel[@]}" \
      ! -group "${_acctGrp}" ! -group www-data ! -group root "${_igX[@]}" \
      -print -quit 2>/dev/null)
    if [ -z "${_igHit}" ]; then
      _igHit=$(find -P ${_usEr}/static -xdev -maxdepth 5 -name drushrc.php "${_igSel[@]}" \
        ! -group "${_acctGrp}" ! -group www-data ! -group root "${_igX[@]}" \
        -print -quit 2>/dev/null)
    fi
    if [ -n "${_igHit}" ] && [ "${#_igX[@]}" -gt 0 ] \
      && ! grep -qE '^[[:space:]]*_web_group_state\(\) \{' \
        /opt/local/bin/instgrp 2> /dev/null; then
      # an instgrp older than the web group would re-group its paths to the
      # account group, which the account's pools are never in
      echo "DRIFT: ${_HM_U}: paths outside group ${_acctGrp} (first: ${_igHit}); reclaim withheld: instgrp predates the web group"
    elif [ -n "${_igHit}" ]; then
      echo "DRIFT: ${_HM_U}: paths outside group ${_acctGrp} (first: ${_igHit}); running instgrp reclaim"
      bash /opt/local/bin/instgrp reclaim ${_HM_U}
    fi
  fi
  # tools/ is oN's: tools/le is handed to the account from inside the real
  # directory, the walk follows no link below it, and each entry is changed
  # through its own handle, never a hard-linked file (_reown_tree_here): oN
  # can put a hard link under any name there, a stamp root put included.
  _acct_in_real_dir "${_usEr}/tools/le" _reown_tree_here "${_HM_U}:${_acctGrp}" .
  # static/ is tenant-writable (02775, no sticky) and trash/ is handed to the
  # tenant, so the tenant can swap the directory for a symlink at any moment:
  # a link put at trash is dropped, and trash is made, handed over and
  # purged only inside the real static/ and the real trash/.
  _acct_in_real_dir "${_usEr}/static" _night_trash_here \
    "${_HM_U}.ftp:${_acctGrp}" "${_PURGE_TMP}"

  # platforms/ is in the main login's own home and mutable for the whole run
  # (_account_process cleared its immutable bit), and distro/ and every name
  # in both are the account's: each is acted on inside its real directory
  # only, an entry is moved by its own name there, and a link is never
  # followed; the immutable flag is cleared on each entry from inside it or
  # through its handle, never on a hard-linked file
  # (_night_chattr_entries_here).
  _acct_in_real_dir "/home/${_HM_U}.ftp/platforms" _night_pl_ghosts_here
  _acct_in_real_dir "${_usEr}/distro" _night_distro_ghosts_here
  _acct_in_real_dir "${_usEr}/distro" _night_distro_links_here
}

# In the real static/: a link put at trash dropped, trash made when missing,
# and, inside the real trash/ entered once, the directory handed to $1 and
# its entries older than $2 days removed. The owner is set on the directory
# entered, never on the name: static/ is group-writable, so a hard link or
# another of its directories can be renamed onto trash at any moment. A
# directory of root's that holds anything is not one this pass made (the
# files store or the usage reports renamed onto trash), and is left alone,
# as is one another user owns (_acct_walk_uids).
_night_trash_here() {
  [ -L ./trash ] && rm -f -- ./trash
  [ -e ./trash ] || mkdir ./trash 2> /dev/null
  _night_sub trash _night_trash_in_here "${1}" "${2}"
}
_night_trash_in_here() {
  local _o _u
  _u=$(stat -c '%u' . 2> /dev/null)
  if [ "${_u}" = "0" ] && [ -n "$(ls -A . 2> /dev/null)" ]; then
    return 0
  fi
  _o=$(_acct_walk_uids "${_usEr##*/}") || return 0
  case ",${_o}," in
    *",${_u},"*) ;;
    *)
      _purge_left_add "$(stat -c '%d:%i' . 2> /dev/null)"
      return 0
      ;;
  esac
  chown -h "${1}" . 2> /dev/null
  _night_purge_here "${2}" all
}

# In the real platforms/ of the main login: an entry holding fewer than
# _LOW_NR names is moved to /var/backups/ghost by its own name (a link is
# moved as the link).
_night_pl_ghosts_here() {
  local _p _n _g
  for _p in ./*; do
    [ -e "${_p}" ] || continue
    _n=$(ls -- "${_p}" 2> /dev/null | wc -l | tr -d "\n")
    [ -n "${_n}" ] && [ "${_n}" -lt "${_LOW_NR}" ] || continue
    chattr -i . &> /dev/null
    _night_chattr_entries_here -
    _g="/var/backups/ghost/${_HM_U}/$(date +%y%m%d-%H%M%S)"
    [ -d "${_g}" ] || mkdir -p "${_g}"
    echo "Moving /home/${_HM_U}.ftp/platforms/${_p#./} to ${_g}"
    mv -f -- "${_p}" "${_g}/"
  done
  return 0
}

# In the real distro/: each real revision directory gets its keys/ where
# missing, and one holding fewer than two names and untouched for an hour
# is moved to undo/dist/<stamp>.
_night_distro_ghosts_here() {
  local i _n _s
  for i in ./*; do
    [ -d "${i}" ] && [ ! -L "${i}" ] || continue
    # The account owns distro/ and its entries: never through a link at
    # that name (a revision or keys itself), and root's own directory stays
    # root's (the owner and mode it has always had).
    if [ ! -L "${i}" ] && [ ! -e "${i}/keys" ] && [ ! -L "${i}/keys" ]; then
      _acct_in_real_dir "${i}" mkdir -m 0755 ./keys &> /dev/null
    fi
    _n=$(ls -- "${i}" 2> /dev/null | wc -l | tr -d "\n")
    # An installer creates the new distro/NNN empty and fills it over the
    # following minutes, and the keys/ mkdir above scores it 1 by itself,
    # so an under-populated revision is NOT evidence of a ghost on its own:
    # this used to reap the revision a running install was still building
    # into, leaving the installer cd-ing into a path that no longer existed
    # and extracting whole platform trees into the account's home instead.
    # Two independent brakes, because neither alone is sufficient: the mtime
    # test (a live revision is touched continuously; a real ghost is stale
    # for hours, and the keys/ mkdir defers its first sighting by one night)
    # and the in-flight test (owl.sh gates once at entry, while the octopus
    # pass drops boa_run.pid per account -- so it must be re-checked HERE)
    if [ -n "${_n}" ] && [ "${_n}" -lt 2 ] \
      && [ -z "$(find "${i}" -maxdepth 0 -mmin -60 2> /dev/null)" ] \
      && ! _night_boa_pass_active; then
      echo "_RevisionTest is ${_n}"
      _s="$(date +%y%m%d-%H%M%S)"
      if _night_undo_dist_here "${i#./}" "${_s}"; then
        echo "GHOST revision ${_usEr}/distro/${i#./} detected and moved to ${_usEr}/undo/dist/${_s}/"
      else
        echo "GHOST revision ${_usEr}/distro/${i#./} detected and not moved: ${_GH_REFUSED}"
      fi
    fi
  done
  return 0
}
# In the real distro/: ./$1 moved into the account's real undo/dist/$2 (made
# first where missing, root's), opened and checked to be that real directory
# and renamed into it through the open directory (/proc/self/fd), so no name
# on either path can send the move elsewhere.
_night_undo_dist_here() {
  local _u
  _u="$(cd -P /data/disk 2> /dev/null && pwd -P)${_usEr#/data/disk}/undo/dist/${2}"
  _acct_in_real_dir "${_usEr}" mkdir -p ./undo 2> /dev/null
  _acct_in_real_dir "${_usEr}/undo" mkdir -p ./dist 2> /dev/null
  _acct_in_real_dir "${_usEr}/undo/dist" mkdir -p -- "./${2}" 2> /dev/null
  ( exec 9< "${_u}/." || exit 1
    [ "$(readlink /proc/self/fd/9)" = "${_u}" ] || exit 1
    mv -f -T -- "./${1}" "/proc/self/fd/9/${1}" ) 2> /dev/null
}

# In the real distro/: for each real revision directory, the main login's
# platforms/<revision> (platforms/ made where missing, a link put at either
# name never followed) made where missing, and in it the link to the
# revision's keys/ when that is a real directory and one link per platform
# to that platform's sites/, each made inside the real directory.
_night_distro_links_here() {
  local i _n _p _c _pl="/home/${_HM_U}.ftp/platforms"
  for i in ./*; do
    [ -d "${i}" ] && [ ! -L "${i}" ] || continue
    _n="${i#./}"
    [ -L "${_pl}" ] && continue
    [ -e "${_pl}" ] \
      || _acct_in_real_dir "/home/${_HM_U}.ftp" mkdir -p ./platforms 2> /dev/null
    _acct_in_real_dir "${_pl}" _night_pl_rev_here "${_n}" || continue
    if [ -d "${i}/keys" ] && [ ! -L "${i}/keys" ]; then
      _acct_in_real_dir "${_pl}/${_n}" _night_link_new_here \
        "${_usEr}/distro/${_n}/keys" keys
    fi
    _acct_in_real_dir "${_pl}" _night_pl_data_here
    for _p in "${i}"/*; do
      [ -d "${_p}" ] && [ ! -L "${_p}" ] || continue
      [ "${_p##*/}" = "keys" ] && continue
      _c=$(_detect_real_docroot "${_usEr}/distro/${_n}/${_p##*/}")
      [ -n "${_c}" ] && [ -d "${_c}/sites" ] || continue
      _acct_in_real_dir "${_pl}/${_n}" \
        ln -sfn -- "${_c}/sites" "./${_p##*/}" 2> /dev/null
      echo "Fixed ${_p##*/} in ${_n} symlink to ${_c}/sites for ${_HM_U}.ftp"
    done
  done
  return 0
}
# In the real platforms/: +i cleared on it and its entries, a link put at
# ./$1 removed, and ./$1 made where missing.
_night_pl_rev_here() {
  chattr -i . &> /dev/null
  _night_chattr_entries_here -
  [ -L "./${1}" ] && rm -f -- "./${1}"
  [ -e "./${1}" ] || mkdir -- "./${1}" 2> /dev/null
  return 0
}
# ./data in the current (pinned) platforms/ moved to /var/backups/ghost.
_night_pl_data_here() {
  local _g
  [ -e ./data ] || return 0
  _g="/var/backups/ghost/${_HM_U}/$(date +%y%m%d-%H%M%S)"
  [ -d "${_g}" ] || mkdir -p "${_g}"
  mv -f -- ./data "${_g}/platforms_data"
}

###--------------------###
### When executed directly (not sourced), process exactly one account. The
### orchestrator (owl.sh) already applied the load gate and the
### vhost.d/proxied/CANCELLED eligibility checks before invoking us.
if [ "${0##*/}" = "10-account.sh" ]; then
  if ! command -v _run_drush8_hmr_cmd > /dev/null 2>&1 \
    || ! command -v _daily_process > /dev/null 2>&1; then
    echo "FATAL ERROR: night libraries (night.inc.sh/20-sites.sh) not loaded; aborting"
    exit 1
  fi
  night_load_run_env
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  _usEr="$1"
  if [ -z "${_usEr}" ] || [ ! -d "${_usEr}" ]; then
    echo "FATAL ERROR: 10-account.sh requires a valid account path argument"
    exit 1
  fi
  _account_process
fi
