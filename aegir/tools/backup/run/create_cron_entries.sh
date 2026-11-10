#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Configurable in /root/.barracuda.cnf interval in minutes between backup cycles
_BACKUP_INTERVAL=360
_WRAPPER_DIR="/root/.remote_backups/run"
_WRAPPER_SCRIPT="${_WRAPPER_DIR}/sequential_backups.sh"
_SCHEDULE_DIR="/root/.remote_backups/schedule"
_SCHEDULE_FILE="${_SCHEDULE_DIR}/backup_schedule.txt"
_CRON_FILE="/etc/cron.d/duplicity_backup"
_LOGFILE="/var/log/backup_runtime.log"

# Function to verify root access
_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 0 -p $$
    chmod a+w /dev/null
    [ -e "/root/.gnupg" ] && chmod 700 /root/.gnupg
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST="$(LC_ALL=C command df -P -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="Use%" || $i=="Capacity") u=i }
    NR==2 && u { gsub(/%/,"",$u); print $u }')"
  [[ "${_DF_TEST}" =~ ^[0-9]+$ ]] || _DF_TEST=""
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
  _DI_TEST="$(LC_ALL=C command df -P -i -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="IUse%") u=i }
    NR==2 && u { gsub(/%/,"",$u); print $u }')"
  [[ "${_DI_TEST}" =~ ^[0-9]+$ ]] || _DI_TEST=""
  if [ ! -z "${_DI_TEST}" ] && [ "${_DI_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk is almost out of inodes !!! ${_DI_TEST}/100"
    echo "ERROR: We can not proceed until inode use is below 90/100"
    echo "ERROR: Every file takes an inode, free space alone is not enough: df -i /"
    exit 1
  fi
}
_check_root

# shellcheck disable=SC1091
[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
export _BACKUP_INTERVAL=${_BACKUP_INTERVAL//[^0-9]/}
: "${_BACKUP_INTERVAL:=360}"

# Ensure global run directory exists and is owned by root
mkdir -p "${_WRAPPER_DIR}"
chown root:root "${_WRAPPER_DIR}"
chmod 700 "${_WRAPPER_DIR}"

# Ensure global schedule directory exists and is owned by root
mkdir -p "${_SCHEDULE_DIR}"
chown root:root "${_SCHEDULE_DIR}"
chmod 700 "${_SCHEDULE_DIR}"

# Function to generate the wrapper script. Written to a temp file and
# swapped in with an atomic same-directory mv: truncating the live file
# in place corrupts any wrapper instance still executing it (bash reads
# scripts lazily), and this generator runs nightly while a monthly full
# can hold an instance for many hours.
_generate_wrapper_script() {
  cat << 'EOF' > "${_WRAPPER_SCRIPT}.fresh"
#!/bin/bash

# Enable strict error handling for debugging only
# set -euo pipefail

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# File paths
_SCHEDULE_FILE="/root/.remote_backups/schedule/backup_schedule.txt"
_PID_DIR="/run"
_LOGFILE="/var/log/backup_runtime.log"

# Liveness for a recorded lock owner: the pid must exist AND still look
# like this tooling. A pid recycled by an unrelated long-lived process
# must not hold a backup lock forever, while a live run (a monthly full
# can span many 6-hour cycles) must never lose its lock. /proc is used
# instead of kill -0 because kill -0 reports EPERM for a live pid owned
# by another user. An unreadable or empty cmdline means the process
# exited (or is a zombie) between the checks: dead.
_pid_is_live() {
  local _pid=$1 _cmd
  [[ "${_pid}" =~ ^[0-9]+$ ]] || return 1
  [ -d "/proc/${_pid}" ] || return 1
  _cmd=$(tr '\0' ' ' 2>/dev/null < "/proc/${_pid}/cmdline")
  [ -n "${_cmd}" ] || return 1
  case "${_cmd}" in
    *duplicity*|*multiback*|*mybackup*|*backboa*|*sequential_backups*) return 0 ;;
    *) return 1 ;;
  esac
}

# Function to acquire the per-service PID lock; heals stale leftovers
# (dead owner, recycled pid, empty file), never removes a live owner's
# lock. Returns 1 on a live holder so the caller can skip just that
# service: an exit here used to starve every later schedule entry for
# as long as one slow service kept running. Claim discipline against
# concurrent starters: the create is an atomic noclobber write that
# never overwrites; a stale file is removed only while it still holds
# the same dead pid, so a lock re-created in the gap is never swept up;
# and every successful claim is read back, so a starter whose fresh
# claim was swept by a slower healer detects the loss and re-enters
# instead of running unlocked.
_acquire_pid_file() {
  local _pidfile=$1 _old_pid _now_pid _try=0
  while [ "${_try}" -lt 3 ]; do
    _try=$((_try + 1))
    if ( set -o noclobber; echo $$ > "${_pidfile}" ) 2>/dev/null; then
      _now_pid=$(tr -dc '0-9' 2>/dev/null < "${_pidfile}")
      if [ "${_now_pid}" = "$$" ]; then
        return 0
      fi
      continue
    fi
    _old_pid=$(tr -dc '0-9' 2>/dev/null < "${_pidfile}")
    if _pid_is_live "${_old_pid}"; then
      echo "Process already running with PID ${_old_pid} holding ${_pidfile}"
      return 1
    fi
    _now_pid=$(tr -dc '0-9' 2>/dev/null < "${_pidfile}")
    if [ "${_now_pid}" = "${_old_pid}" ]; then
      echo "Removing stale PID file ${_pidfile} (pid ${_old_pid:-empty} not running)"
      rm -f "${_pidfile}"
    fi
  done
  echo "Process already running with PID file ${_pidfile}"
  return 1
}

# Function to count live backup streams across ALL wrapper instances --
# the live (non-sequential) multiback locks. One instance dispatches
# entries strictly one at a time, but each 6-hour cron tick can add an
# instance while a monthly full still runs (18-hour fulls are real), and
# unbounded skip-and-continue would pile concurrent fulls onto the same
# day. At the cap, the remaining entries wait for a later cycle.
_live_backup_streams() {
  local _n=0 _f _p
  for _f in /run/duplicity_*.pid; do
    [ -e "${_f}" ] || continue
    case "${_f}" in *_sequential.pid) continue ;; esac
    _p=$(tr -dc '0-9' 2>/dev/null < "${_f}")
    _pid_is_live "${_p}" && _n=$((_n + 1))
  done
  echo "${_n}"
}

# Function to remove PID file
_remove_pid_file() {
  local _pidfile=$1
  if [ -f "${_pidfile}" ]; then
    rm -f "${_pidfile}" || {
      echo "Warning: Failed to remove PID file: ${_pidfile}"
    }
  fi
}

# Function to release the currently held per-service lock; clearing the
# tracker keeps the wrapper-level trap from ever removing a lock this
# run no longer owns
_release_current_pid_file() {
  _remove_pid_file "${_CURRENT_PIDFILE}"
  _CURRENT_PIDFILE=""
}

# Function to remove stale multiback PID file; multiback heals its own
# stale locks too, this covers boxes where the fetched tool lags a
# regenerated wrapper. The removal is guarded by a content re-read: a
# concurrently starting manual multiback can heal and re-acquire this
# very file between the liveness check and the rm, and its fresh live
# lock must never be swept up.
_remove_stale_multiback_pid() {
  _multiback_pidfile="/run/duplicity_${_service}_${_user}.pid"
  if [ -f "${_multiback_pidfile}" ]; then
    _old_pid=$(tr -dc '0-9' 2>/dev/null < "${_multiback_pidfile}")
    if ! _pid_is_live "${_old_pid}"; then
      _now_pid=$(tr -dc '0-9' 2>/dev/null < "${_multiback_pidfile}")
      if [ "${_now_pid}" = "${_old_pid}" ]; then
        echo "Stale multiback PID file detected: ${_multiback_pidfile}. Removing it."
        rm -f "${_multiback_pidfile}"
      fi
    fi
  fi
}

# Read backup services and users from the configuration file
if [ ! -f "${_SCHEDULE_FILE}" ]; then
  echo "Error: Backup schedule file ${_SCHEDULE_FILE} not found."
  exit 1
fi

# Function to print env for debugging
_print_env() {
  if [ "$(id -u)" -eq 0 ] && [ -e "/root/.dev.server.cnf" ]; then
    # secret values and URL userinfo stay out of the dump
    _ENV=$(env 2>&1 | sed -E \
      -e 's/^(PASSPHRASE|[A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD|CONNECTION_STRING|ACCOUNT_ID)[A-Z0-9_]*)=.*/\1=[redacted]/' \
      -e 's|://[^@[:space:]]*@|://|g')
    echo
    echo "_ENV in $1 start"
    echo "${_ENV}"
    echo "_ENV in $1 end"
    echo
    _ENV=
  fi
}

# One trap set covers whichever per-service lock this run holds right
# now; single quotes defer expansion to fire time. The old in-loop trap
# expanded an undefined variable at set time, so it removed nothing and
# an interrupted run left its pid file behind, blocking every later
# cycle. A signal death re-enters the EXIT trap for the cleanup.
_CURRENT_PIDFILE=""
trap '[ -n "${_CURRENT_PIDFILE}" ] && rm -f "${_CURRENT_PIDFILE}"' EXIT
trap 'exit 1' INT TERM HUP

# Process each line in the backup configuration file
while IFS= read -r _line || [ -n "${_line}" ]; do
  # Skip empty lines and comments
  if [[ "${_line}" =~ ^\s*# ]] || [[ -z "${_line}" ]]; then
    continue
  fi

  # Parse the service and user
  _service=$(echo "${_line}" | cut -d' ' -f1)
  _user=$(echo "${_line}" | cut -d' ' -f2)

  # Ensure both service and user are defined
  if [ -z "${_service}" ] || [ -z "${_user}" ]; then
    echo "Error: Invalid line in configuration file: ${_line}"
    continue
  fi

  echo "Starting backup for ${_service} (${_user})..."
  export _service="${_service}"
  export _user="${_user}"

  # Defer the rest of the schedule when two backup streams already run
  # box-wide; skipping past every held lock must not stack a third
  if [ "$(_live_backup_streams)" -ge 2 ]; then
    echo "Two backup streams already running; deferring ${_service} (${_user}) and the rest of the schedule to a later cycle."
    break
  fi

  # Define the PID file path
  _SEQ_PIDFILE="${_PID_DIR}/duplicity_${_service}_${_user}_sequential.pid"

  # Acquire the per-service lock; a service still running from an
  # earlier cycle skips only itself, the rest of the schedule proceeds
  if ! _acquire_pid_file "${_SEQ_PIDFILE}"; then
    echo "Skipping backup for ${_service} (${_user}): a previous run still holds its lock."
    continue
  fi
  _CURRENT_PIDFILE="${_SEQ_PIDFILE}"

  # Remove stale multiback PID file if necessary
  _remove_stale_multiback_pid

  # Determine the paths configuration file
  if [ "${_user}" = "global" ] || [ "${_user}" = "data" ] || [ "${_user}" = "custom" ]; then
    _paths_file="/root/.remote_backups/paths/${_user}_paths.txt"
    _credentials_file="/root/.remote_backups/credentials/${_service}.txt"
    _secret_file="/root/.remote_backups/.secret.txt"

    if [ ! -f "${_secret_file}" ]; then
      echo "Secret file ${_secret_file} not found."
      _release_current_pid_file
      continue
    fi

    # Check if _paths_file exists
    if [ ! -f "${_paths_file}" ]; then
      echo "Error: Paths configuration file ${_paths_file} not found."
      _release_current_pid_file
      continue
    fi

    # Check if credentials file exists
    if [ ! -f "${_credentials_file}" ]; then
      echo "Error: Credentials file ${_credentials_file} not found."
      _release_current_pid_file
      continue
    fi

    # Change to the directory where _paths_file and credentials are located
    cd /root/.remote_backups
    _print_env "sequential_backups_a"

  elif [ "${_user}" != "arch" ] \
    && [ "${_user}" != "data" ] \
    && [ "${_user}" != "global" ] \
    && [ "${_user}" != "static" ] \
    && [ "${_user}" != "custom" ]; then
    _paths_file="/data/disk/${_user}/remote_backups/paths/paths.txt"
    _credentials_file="/data/disk/${_user}/static/control/remote_backups/credentials/${_service}.txt"
    _secret_file="/data/disk/${_user}/remote_backups/.secret.txt"

    if [ ! -f "${_secret_file}" ]; then
      echo "Secret file ${_secret_file} not found."
      _release_current_pid_file
      continue
    fi

    if [ ! -f "${_paths_file}" ]; then
      echo "Error: Paths configuration file ${_paths_file} not found."
      _release_current_pid_file
      continue
    fi

    if [ ! -f "${_credentials_file}" ]; then
      echo "Error: Credentials file ${_credentials_file} not found."
      _release_current_pid_file
      continue
    fi

    # multiback resolves and reads every account path inside its real
    # directory itself, so root's working directory stays in its own tree,
    # never in one the account can swap
    cd /root/.remote_backups
    _print_env "sequential_backups_b"
  fi

  # Perform the backup
  if multiback backup "${_service}" "${_user}"; then
    echo "Backup for ${_service} (${_user}) completed successfully."
  else
    echo "Backup for ${_service} (${_user}) failed."
  fi

  # Wipe out exported variables to clean up env after running the backup
  export _service=
  export _user=

  # Return to the original directory
  cd -
  _print_env "sequential_backups_d"

  # Remove the PID file
  _release_current_pid_file

done < "${_SCHEDULE_FILE}"
EOF

  chmod +x "${_WRAPPER_SCRIPT}.fresh"
  mv -f "${_WRAPPER_SCRIPT}.fresh" "${_WRAPPER_SCRIPT}"
  echo "Wrapper script created at ${_WRAPPER_SCRIPT}"
}

# Function to create cron entries
_create_cron_entries() {
  echo "# Cron job for sequential backups" > "${_CRON_FILE}"
  # bash + full path, never a bare path: cron must not depend on an executable
  # bit or on PATH. The wrapper is written with chmod +x a few lines above, but
  # a mode can be lost by any later hand copy, and the failure is silent —
  # "Permission denied" into a log nobody reads while the schedule looks live.
  echo "0 */$((_BACKUP_INTERVAL / 60)) * * * root bash ${_WRAPPER_SCRIPT}" >> "${_CRON_FILE}"
  chmod 644 "${_CRON_FILE}"
  echo "Cron entry created at ${_CRON_FILE}"

  # Validate the cron file
  _validate_cron_file
}

# Function to validate the cron file
_validate_cron_file() {
  if ! grep -q -E "^[^#]*${_WRAPPER_SCRIPT}" "${_CRON_FILE}"; then
    echo "Error: Cron file validation failed. Please check the file at ${_CRON_FILE}."
    exit 1
  fi
  echo "Cron file validated successfully."
}

# An account owns static/control through its .ftp login, so any name below
# it can be a link or a FIFO, and a whole directory on the way can be one.
# _acct_in_real_dir and _acct_read_here are copies of the helpers in
# lib/functions/helper.sh.inc.
#
# Run "$@" inside the real directory $1: below /data/disk and /home every name
# on the path must be a real directory; once entered, ./name stays there
# whatever is swapped.
# The uids root's walks over the account $1's trees act on, comma-separated:
# root's own (0) and those of every identity of the account as passwd names
# them: oN and oN.<name> (its .ftp login, its client sub-accounts oN.<client>
# and oN.<client>-dev) and its PHP-FPM users oN.web and oN.<ver>.web. An
# account name holds no dot, so the match is exact: o1 never takes o10's.
# Status 1, and nothing, unless the account itself is in passwd.
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
# The whole of an account's control/, judged once before a run acts on it:
# run inside the account's real static/, it prints OK when control/ and
# everything in it, never followed through a link, and static/ and every
# directory above it up to /, are root's or one of the account's identities'
# (the uids given first, _acct_walk_uids; a uid no passwd entry names counts
# too), ABSENT when there is no control/, and otherwise why not, on one line.
# Every other account's .ftp login is in the box-wide group, which an account
# not yet on its own group still has on static/: such a login could put a
# control/ of its own there, or a file of its own in a group-writable
# directory below it, for root to act on as the account's.
_ACCT_CTRL_OWN_PL='use Fcntl;
my %own = map { $_ => 1 } grep { /^[0-9]+$/ } split(/,/, shift @ARGV // "");
sub own { my $u = shift; unless (exists $own{$u}) { local $! = 0; $own{$u} = defined(getpwuid($u)) ? 0 : ($! == 0 || $!{ENOENT} || $!{ESRCH} || $!{EBADF} || $!{EPERM}) ? 1 : 0; } return $own{$u}; }
sub isd { ($_[0] & 0170000) == 0040000 }
sub nm { (my $v = shift) =~ s/[^\x20-\x7e]/?/g; return substr($v, 0, 200); }
sub refuse { print "$_[0]\n"; exit 0; }
my ($p, $top, @d, @x) = (".", 0);
for (1 .. 256) {
  @x = stat($p) or refuse("static/ cannot be read");
  own($x[4]) or refuse("a directory above control/ is owned by uid $x[4]");
  if (@d && $x[0] == $d[0] && $x[1] == $d[1]) { $top = 1; last; }
  @d = @x;
  $p .= "/..";
}
$top or refuse("static/ is too deep");
my @s = lstat("./control");
unless (@s) { print(($!{ENOENT} ? "ABSENT" : "control/ cannot be read") . "\n"); exit 0; }
isd($s[2]) or refuse("control is not a directory");
my ($n, @q) = (0, ["control", @s]);
while (my $e = shift @q) {
  my ($f, @t) = @$e;
  own($t[4]) or refuse(nm($f) . " is owned by uid $t[4]");
  next unless isd($t[2]);
  opendir(my $h, "./$f") or refuse(nm($f) . " cannot be read");
  for my $b (readdir($h)) {
    next if $b eq "." || $b eq "..";
    ++$n > 100000 and refuse("control/ holds more than 100000 entries");
    my @u = lstat("./$f/$b") or next;
    push @q, ["$f/$b", @u];
  }
  closedir($h);
}
print "OK\n";
exit 0;'
# 0 when the account $1's control/ is its own as _ACCT_CTRL_OWN_PL judges it
# (or it has none); otherwise why not on stdout, status 1. A run that acts
# on what control/ says leaves the account as it is when it is not.
_acct_ctrl_own() {
  local _a="${1}" _o _r _want
  # an account not in passwd (not made yet, or removed) has nothing to
  # judge it by: read as before
  _o=$(_acct_walk_uids "${_a}" 2> /dev/null) || return 0
  [ -e "/data/disk/${_a}/static" ] || [ -L "/data/disk/${_a}/static" ] || return 0
  _want="$(cd -P -- /data/disk 2> /dev/null && /bin/pwd -P)/${_a}/static"
  _r=$(cd -P -- "/data/disk/${_a}/static" 2> /dev/null && [ "$(/bin/pwd -P)" = "${_want}" ] \
    && perl -e "${_ACCT_CTRL_OWN_PL}" -- "${_o}" 2> /dev/null)
  case "${_r}" in
    OK|ABSENT) return 0 ;;
  esac
  echo "${_r:-static/ is not a real directory}"
  return 1
}
_acct_in_real_dir() {
  local _d="${1}" _a="" _want
  shift
  case "${_d}" in
    /home/?*) _a=/home ;;
    /data/disk/?*) _a=/data/disk ;;
  esac
  if [ -n "${_a}" ]; then
    _want="$(cd -P -- "${_a}" 2> /dev/null && /bin/pwd -P)${_d#"${_a}"}"
  else
    _want="$(cd -P -- "${_d%/*}" 2> /dev/null && /bin/pwd -P)/${_d##*/}"
  fi
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(/bin/pwd -P)" = "${_want}" ] && "$@" )
}
# ./$1 in the current (pinned) directory: never through a link, never blocked
# on a FIFO, at most 1 MiB. Empty for anything else.
_acct_read_here() {
  timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
    bs=1048576 count=1 status=none 2> /dev/null
}
# A "<service> $1" line for every service whose credentials file in the
# current (pinned) directory is a regular file with no placeholder left, as
# the grep over each file decided it before.
_acct_ready_services_here() {
  local _service _body
  for _service in aws aws_one_zone aws_standard_ia azure b2 cloudflare do_spaces gcs ibm linode wasabi; do
    [ -f "./${_service}.txt" ] && [ ! -L "./${_service}.txt" ] || continue
    _body="$(_acct_read_here "${_service}.txt" && echo x)" || continue
    [[ "${_body}" == *your_* ]] || echo "${_service} ${1}"
  done
}

# Function to generate the backup schedule
_generate_backup_schedule() {
  echo "# Backup schedule (service user)" > "${_SCHEDULE_FILE}"

  # Add global backups
  _custom_paths_file="/root/.remote_backups/paths/custom_paths.txt"
  _GLOBAL_CRED_DIR="/root/.remote_backups/credentials"
  for _service in aws aws_one_zone aws_standard_ia azure b2 cloudflare do_spaces gcs ibm linode wasabi; do
    if [ -f "${_GLOBAL_CRED_DIR}/${_service}.txt" ] && ! grep -q "your_" "${_GLOBAL_CRED_DIR}/${_service}.txt"; then
      echo "${_service} global" >> "${_SCHEDULE_FILE}"
      echo "${_service} data" >> "${_SCHEDULE_FILE}"
      [ -s "${_custom_paths_file}" ] && echo "${_service} custom" >> "${_SCHEDULE_FILE}"
    fi
  done

  # Add user-specific backups: the credentials hang off static/control,
  # which the account owns, so they are read only inside the real directory
  for _user_dir in /data/disk/*; do
    if [ -d "${_user_dir}" ]; then
      _user=$(basename "${_user_dir}")
      _USER_CRED_DIR="/data/disk/${_user}/static/control/remote_backups/credentials"
      [ -d "${_USER_CRED_DIR}" ] || continue
      # only from the account's own static/control (_acct_ctrl_own); multiback
      # refuses a run on another one as well
      if ! _why=$(_acct_ctrl_own "${_user}"); then
        echo "Skipping ${_user}: static/control is not the account's own (${_why})."
        continue
      fi
      _acct_in_real_dir "${_USER_CRED_DIR}" \
        _acct_ready_services_here "${_user}" >> "${_SCHEDULE_FILE}"
    fi
  done

  echo "Backup schedule created at ${_SCHEDULE_FILE}"
}

# Function to adjust the backup interval dynamically
_adjust_backup_interval() {
  if [ -f "${_LOGFILE}" ]; then
    _TOTAL_RUNTIME=$(tail -n1 "${_LOGFILE}" | awk '{print $NF}')
    _NEW_INTERVAL=$(( (_TOTAL_RUNTIME / 3600 + 1) * 60 ))  # Round up to the next hour
    if [ "${_NEW_INTERVAL}" -gt "${_BACKUP_INTERVAL}" ]; then
      _BACKUP_INTERVAL="${_NEW_INTERVAL}"
      echo "Adjusted backup interval to $((_BACKUP_INTERVAL / 60)) hours."
      _create_cron_entries
    fi
  fi
}

# Main script execution
_generate_wrapper_script
_generate_backup_schedule
_adjust_backup_interval
_create_cron_entries
