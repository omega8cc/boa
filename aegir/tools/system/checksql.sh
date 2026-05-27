#!/bin/bash

###
### checksql.sh — MySQL health-check, auto-repair, and notification script
### Invoked automatically by sqlcheck.sh only if needed
###

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_FIX_FILE="/var/xdrago/acrashsql.sh"
_LOG_FILE="/var/log/boa/mysqlcheck.log"
_TOUCH_FILE="/var/log/boa/last-run-acrashsql"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

[ -f "/root/.proxy.cnf" ] && exit 0

export _B_NICE=${_B_NICE//[^0-9-]/}
if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then
  _B_NICE=0
fi
if (( _B_NICE < -20 )); then
  _B_NICE=-20
elif (( _B_NICE > 19 )); then
  _B_NICE=19
fi
renice ${_B_NICE} -p $$ &> /dev/null

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    _single_instance_lock
  else
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

###
### Load + normalize _INCIDENT_REPORT
###
### Legacy values:
###   NO  becomes OFF (see below)
###   YES becomes MINI (see below)
###
### Current values:
###   OFF  == Total silence, no email alerts
###   ALL  == Very noisy, good for debugging
###   MINI == Only the most important alerts (default)
###   CRIT == Only critical if _lvl=ALERT
###
_normalize_incident_report() {
  : "${_INCIDENT_REPORT:=MINI}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

_STATUS="CLEAN"
_TIMEDATE=$(date +%y%m%d-%H%M)

rm -f "${_FIX_FILE}"
sleep 90

/usr/bin/mysqlcheck -u root -Aa > "${_LOG_FILE}"

###############################################################################
_repair_this_action() {
  local _FIXDB="${1}"
  local _FIXTBL="${2}"
  local _COUNTER="${3}"

  printf '%s.%s [%s] recorded...\n' "${_FIXDB}" "${_FIXTBL}" "${_COUNTER}"

  # Append repair commands to the fix script.
  # Order: repair → optimise → analyse, each scoped to the specific table.
  # A whole-database repair is prepended as a first-pass safety net because
  # InnoDB crash recovery sometimes leaves the frm/ibd pair inconsistent in
  # ways that only a full-db pass can detect.
  {
    printf '#-- BELOW --# %s.%s [%s] recorded...\n' "${_FIXDB}" "${_FIXTBL}" "${_COUNTER}"
    printf '/usr/bin/mysqlcheck -u root -r %s\n'    "${_FIXDB}"
    printf '/usr/bin/mysqlcheck -u root -r %s.%s\n' "${_FIXDB}" "${_FIXTBL}"
    printf '/usr/bin/mysqlcheck -u root -o %s.%s\n' "${_FIXDB}" "${_FIXTBL}"
    printf '/usr/bin/mysqlcheck -u root -a %s.%s\n' "${_FIXDB}" "${_FIXTBL}"
    printf '\n'
  } >> "${_FIX_FILE}"
}

###############################################################################
_make_actions() {
  # Write a fresh fix-script header
  printf '#!/bin/bash\n\n' > "${_FIX_FILE}"

  # Associative array: key = "database\tTable" → error count
  declare -A _ERR_COUNT

  # mysqlcheck error lines of interest look like:
  #   error    : Table './database/tablename' doesn't exist
  #   status   : Table './database/#sql-xxx' crashed
  # The pattern Table './' identifies them reliably.
  local _DB_TABLE_RE="Table[[:space:]]'\.\/([^/]+)\/([^']+)'"

  while IFS= read -r _line; do
    if [[ "${_line}" =~ ${_DB_TABLE_RE} ]]; then
      _STATUS="ERROR"
      local _db="${BASH_REMATCH[1]//[^a-z0-9_]/}"
      local _tbl="${BASH_REMATCH[2]//[^a-z0-9_]/}"
      if [[ "${_db}" =~ ^[a-z0-9] && -n "${_db}" && -n "${_tbl}" ]]; then
        local _key="${_db}	${_tbl}"
        _ERR_COUNT["${_key}"]=$(( ${_ERR_COUNT["${_key}"]-0} + 1 ))
      fi
    fi
  done < "${_LOG_FILE}"

  local _sumar=0

  # Sort keys for deterministic output; iterate over every affected pair
  local _key
  while IFS= read -r _key; do
    local _count="${_ERR_COUNT[${_key}]}"
    _sumar=$(( _sumar + _count ))
    # Split the tab-separated key back into db and table
    local _db="${_key%%	*}"
    local _tbl="${_key##*	}"
    _repair_this_action "${_db}" "${_tbl}" "${_count}"
  done < <(printf '%s\n' "${!_ERR_COUNT[@]}" | sort)

  printf '\n===[ %s ]\tGLOBAL===\n\n' "${_sumar}"
  unset _ERR_COUNT
}

###############################################################################

_make_actions

touch "${_TOUCH_FILE}"

_hName="$(hostname -f 2>/dev/null)"

if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" != "OFF" ]; then
  if [ "${_STATUS}" != "CLEAN" ]; then
    s-nail -s "SQL check ERROR [${_hName}] ${_TIMEDATE}" \
      "${_MY_EMAIL}" < "${_LOG_FILE}"
    if [ -f "${_FIX_FILE}" ]; then
      bash "${_FIX_FILE}" \
        | s-nail -s "SQL REPAIR done [${_hName}] ${_TIMEDATE}" "${_MY_EMAIL}"
    fi
  fi
  if [ "${_STATUS}" != "ERROR" ] && [ "${_INCIDENT_REPORT}" = "ALL" ]; then
    s-nail -s "SQL check CLEAN [${_hName}] ${_TIMEDATE}" \
      "${_MY_EMAIL}" < "${_LOG_FILE}"
  fi
fi

rm -f "${_LOG_FILE}"
exit 0
