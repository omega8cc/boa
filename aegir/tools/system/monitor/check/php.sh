#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/php.incident.log"

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

# Run only on fully installed system
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# Sanitize to allow only digits and minus sign
export _B_NICE=${_B_NICE//[^0-9-]/}

# Validate and set default if necessary
if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then
  _B_NICE=0
fi

# Clamp the value within -20 to 19
if (( _B_NICE < -20 )); then
  _B_NICE=-20
elif (( _B_NICE > 19 )); then
  _B_NICE=19
fi

renice ${_B_NICE} -p $$ &> /dev/null

: "${_FPM_COOLDOWN_SECS:=30}"

_NOW=$(date +%y%m%d-%H%M%S)
_NOW=${_NOW//[^0-9-]/}

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
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
  ###
  ### Map legacy + validate
  ###
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

_incident_email_report() {
  if ! _check_uptime_grace_period >/dev/null; then return 1; fi
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "ALL" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < <(tail -n 200 "${_pthOml}")
  fi
}

_fpm_reload() {
  : > /run/fmp_wait.pid
  : > /run/restarting_fmp_wait.pid
  sleep 3
  renice ${_B_NICE} -p $$ &> /dev/null
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service "php${e}-fpm" reload
    fi
  done
  echo "$(date) $1 incident PHP-FPM reloaded" >> ${_pthOml}
  sleep 1
  rm -f /run/fmp_wait.pid /run/restarting_fmp_wait.pid
}

_fpm_duplicate_instances_detection() {
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    # Count masters for this exact conf path
    _pat="php-fpm: master process.*/opt/php${e}/etc/php${e}-fpm.conf"
    _cnt=$(pgrep -fc "${_pat}")
    if (( _cnt > 1 )); then
      _thisErrLog="$(date) Duplicate master for php${e}-fpm (count=${_cnt})"
      echo ${_thisErrLog} >> ${_pthOml}
      [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
      mv -f /var/log/php/php${e}-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
      service "php${e}-fpm" restart
      wait
    fi
  done
}

_fpm_giant_log_detection() {
  _PHPLOG_SIZE_TEST=$(du -s -h /var/log/php 2>/dev/null)
  if echo "${_PHPLOG_SIZE_TEST}" | grep -q "G"; then
    _thisErrLog="$(date) Too big PHP error logs detected: ${_PHPLOG_SIZE_TEST}"
    echo ${_thisErrLog} >> ${_pthOml}
    # No restart here; health checks will react if needed.
  fi
}

_fpm_listen_conflict_detection() {
  if [ -e "/var/log/php" ]; then
    _hit=$(tail --lines=500 /var/log/php/php*-fpm-error.log 2>/dev/null | grep -c "already listen on")
    if [ "${_hit}" -gt 0 ]; then
      sleep 2
      _hit2=$(tail --lines=500 /var/log/php/php*-fpm-error.log 2>/dev/null | grep -c "already listen on")
      if [ "${_hit2}" -gt 0 ]; then
        [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
        mv -f /var/log/php/php*-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
        _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
        for e in ${_PHP_V}; do
          if [ ! -S "/run/www${e}.fpm.socket" ]; then
            _thisErrLog="$(date) FPM listen conflict for php${e}, restarting"
            echo ${_thisErrLog} >> ${_pthOml}
            service "php${e}-fpm" restart
            wait
          fi
        done
      fi
    fi
  fi
}

_fpm_proc_max_detection() {
  # Per-pool saturation is what FPM actually logs when a pool cannot spawn a
  # worker:
  #   WARNING: [pool NAME] server reached max_children setting (N), consider raising it
  # The GLOBAL "process.max" ceiling BOA sets to 0 (disabled) is never logged,
  # so the old grep for it never matched. Match the per-pool string instead.
  #
  # Because that warning line persists in the log until rotation, a flat
  # "tail | grep -c" would re-emit the NOTE on every run (this script runs each
  # minute) for as long as the line stays in the tail window. Track a per-file
  # byte offset so only NEW hits since the last run are reported — same approach
  # scan_nginx.sh uses for its Tier-B FPM-saturation trigger.
  local _posfile="/var/log/boa/fpm_maxchildren.pos"
  local _tmp _f _sz _off _new _hits _hitf
  declare -A _POS
  if [ -f "${_posfile}" ]; then
    while IFS='|' read -r _f _off; do
      [ -n "${_f}" ] && [[ "${_off}" =~ ^[0-9]+$ ]] && _POS["${_f}"]="${_off}"
    done < "${_posfile}"
  fi
  _tmp="${_posfile}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  _hits=0
  _hitf=""
  for _f in /var/log/php/php*-fpm-error.log; do
    [ -f "${_f}" ] || continue
    _sz=$(stat -c %s "${_f}" 2>/dev/null)
    [[ "${_sz}" =~ ^[0-9]+$ ]] || _sz=0
    _off="${_POS["${_f}"]:-0}"
    # Log rotated/truncated since last run: re-baseline from the start.
    (( _sz < _off )) && _off=0
    if (( _sz > _off )); then
      _new=$(tail -c +"$(( _off + 1 ))" "${_f}" 2>/dev/null \
        | grep -c -- "reached max_children setting")
      [[ "${_new}" =~ ^[0-9]+$ ]] || _new=0
      if (( _new > 0 )); then
        _hits=$(( _hits + _new ))
        _hitf="${_hitf} ${_f##*/}(${_new})"
      fi
    fi
    printf '%s|%s\n' "${_f}" "${_sz}" >> "${_tmp}"
  done
  mv -f "${_tmp}" "${_posfile}" 2>/dev/null
  if (( _hits > 0 )); then
    _thisErrLog="$(date) NOTE: PHP-FPM reached max_children setting (${_hits} new hit(s) in${_hitf}). Consider raising pm.max_children for the affected pool(s)"
    echo "${_thisErrLog}" >> "${_pthOml}"
    # No restart; capacity signal only.
  fi
}

_fpm_sockets_healing() {
  _hit=$(tail --lines=500 /var/log/php/php*-fpm-error.log 2>/dev/null | grep -c "Address already in use")
  if [ "${_hit}" -gt 0 ]; then
    sleep 2
    _hit2=$(tail --lines=500 /var/log/php/php*-fpm-error.log 2>/dev/null | grep -c "Address already in use")
    if [ "${_hit2}" -gt 0 ]; then
      [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
      mv -f /var/log/php/php*-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
      _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ ! -S "/run/www${e}.fpm.socket" ]; then
          _thisErrLog="$(date) FPM socket conflict sustained for php${e}; restarting"
          echo ${_thisErrLog} >> ${_pthOml}
          service "php${e}-fpm" restart
          wait
        fi
      done
    fi
  fi
}

_fpm_fastcgi_temp() {
  _FASTCGI_SIZE_TEST=$(du -s -h /usr/fastcgi_temp/*/*/* 2>/dev/null | grep G)
  if [ -n "${_FASTCGI_SIZE_TEST}" ]; then
    rm -f /usr/fastcgi_temp/*/*/* 2>/dev/null
    _thisErrLog="$(date) PHP fastcgi_temp too big, cleaned"
    echo ${_thisErrLog} >> ${_pthOml}
    echo "$(date) ${_FASTCGI_SIZE_TEST}" >> ${_pthOml}
    _incident_email_report "PHP fastcgi_temp too big, cleaned"
    echo >> ${_pthOml}
  fi
}

_fpm_health_check_fix() {
  _thisErrLog=
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -x "/opt/php${e}/bin/php" ]; then
      _pat="php-fpm: master process.*/opt/php${e}/etc/php${e}-fpm.conf"

      _ok_master=false
      _ok_socket=false
      _ok_pid=false

      # First pass
      pgrep -f "${_pat}" >/dev/null 2>&1 && _ok_master=true
      [ -S "/run/www${e}.fpm.socket" ] && _ok_socket=true
      [ -s "/run/php${e}-fpm.pid" ] && _ok_pid=true

      # Second pass (grace for reloads)
      if ! ${_ok_master} || ! ${_ok_socket} || ! ${_ok_pid}; then
        sleep 2
        _ok_master=false; _ok_socket=false; _ok_pid=false
        pgrep -f "${_pat}" >/dev/null 2>&1 && _ok_master=true
        [ -S "/run/www${e}.fpm.socket" ] && _ok_socket=true
        [ -s "/run/php${e}-fpm.pid" ] && _ok_pid=true
      fi

      if ! ${_ok_master} || ! ${_ok_socket} || ! ${_ok_pid}; then
        # Per-version cooldown: /run/php<ver>-fpm.cooldown (15 seconds default)
        _cd="/run/php${e}-fpm.cooldown"
        _now=$(date +%s)
        if [ -s "${_cd}" ]; then
          _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
          if [ -n "${_ts}" ]; then
            _delta=$(( _now - _ts ))
            if [ "${_delta}" -lt "${_FPM_COOLDOWN_SECS}" ]; then
              echo "$(date) INFO: php${e}-fpm unhealthy but in cooldown (${_delta}s < ${_FPM_COOLDOWN_SECS}s); skipping restart" >> ${_pthOml}
              continue
            fi
          fi
        fi

        : > /run/fmp_wait.pid
        : > /run/restarting_fmp_wait.pid

        echo "$(date) php${e}-fpm health failed (master=${_ok_master} socket=${_ok_socket} pid=${_ok_pid}) — restart" >> ${_pthOml}
        [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
        mv -f /var/log/php/php${e}-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
        service "php${e}-fpm" restart
        wait
        sleep 1

        # Re-check after restart
        _ok_master=false; _ok_socket=false; _ok_pid=false
        pgrep -f "${_pat}" >/dev/null 2>&1 && _ok_master=true
        [ -S "/run/www${e}.fpm.socket" ] && _ok_socket=true
        [ -s "/run/php${e}-fpm.pid" ] && _ok_pid=true

        if ${_ok_master} && ${_ok_socket} && ${_ok_pid}; then
          _thisErrLog="$(date) PHP-FPM ${e} was down, restarted"
          echo ${_thisErrLog} >> ${_pthOml}
          date +%s > "${_cd}"
        else
          # As last resort: stop/start for only this version
          echo "$(date) php${e}-fpm still unhealthy after restart; stop/start" >> ${_pthOml}
          service "php${e}-fpm" stop
          sleep 1
          [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
          mv -f /var/log/php/php${e}-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
          service "php${e}-fpm" start
          date +%s > "${_cd}"
        fi

        rm -f /run/fmp_wait.pid /run/restarting_fmp_wait.pid
      fi
    fi
  done
  if [ -n "${_thisErrLog}" ]; then
    _incident_email_report "PHP-FPM was down, restarted"
    echo >> ${_pthOml}
  fi
}

# Fire-and-forget launcher, cron-safe and interactive-safe
_spawn_detached() {
  _cmd="$1"
  if command -v nohup >/dev/null 2>&1; then
    nohup bash -c "${_cmd}" >/dev/null 2>&1 &
  elif command -v setsid >/dev/null 2>&1; then
    setsid bash -c "${_cmd}" >/dev/null 2>&1 &
  else
    ( bash -c "${_cmd}" >/dev/null 2>&1 ) &
  fi
  # If interactive shell, drop it from the job table to mimic cron behavior
  if [[ "$-" == *i* ]]; then disown; fi
}

_fpm_logs_empty() {
  _LOG_NR=$(ls /var/log/php | wc -l)
  if [ -n "${_LOG_NR}" ] && [ "${_LOG_NR}" -ge 3 ]; then
    _LOGS=OK
  else
    _fpm_reload "NOLOGS"
  fi
}

_fpm_apcu_reload_sentinel() {
  # Allows site owners on qualifying plans to request a graceful PHP-FPM
  # reload (which clears APCu) by creating an empty sentinel file:
  #
  #   touch ~/static/control/run-php-fpm-reload.pid
  #
  # The system detects the file within seconds, performs a graceful reload
  # of all PHP-FPM versions, and removes the file automatically.
  #
  # Plan gate: mirrors _if_valkey_restart in valkey.sh — only available on
  # POWER, PHANTOM, CLUSTER, ULTRA, MONSTER plans or when the explicit allow
  # file /etc/boa/.allow.php.fpm.reload.cnf is present.
  #
  # Why this is needed:
  #   APCu caches field definitions, plugin registries, and other Drupal
  #   internals at the PHP-FPM worker process level. Unlike Valkey, APCu
  #   cannot be flushed remotely — it lives inside the FPM worker processes.
  #   After a config change, platform update, or Solr core rename, stale APCu
  #   entries can cause FieldException and PluginNotFoundException errors in
  #   Drupal logs. A graceful FPM reload recycles all workers and clears APCu
  #   without dropping active connections.
  #
  # Cooldown: respects _FPM_COOLDOWN_SECS (default 30s) to prevent reload
  # storms if the sentinel is created repeatedly.

  # Plan-level gate — same logic as _if_valkey_restart in valkey.sh
  local _PrTestPower _PrTestPhantom _PrTestCluster _PrTestUltra _PrTestMonster
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>/dev/null)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>/dev/null)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>/dev/null)
  _PrTestUltra=$(grep "ULTRA" /root/.*.octopus.cnf 2>/dev/null)
  _PrTestMonster=$(grep "MONSTER" /root/.*.octopus.cnf 2>/dev/null)

  if [[ "${_PrTestPower}"   =~ "POWER"   ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [[ "${_PrTestUltra}"   =~ "ULTRA"   ]] \
    || [[ "${_PrTestMonster}" =~ "MONSTER" ]] \
    || [ -e "/etc/boa/.allow.php.fpm.reload.cnf" ]; then
    : # plan allows self-service FPM reload — proceed
  else
    return 0  # plan does not allow self-service FPM reload
  fi

  local _FpmTest
  _FpmTest=$(ls /data/disk/*/static/control/run-php-fpm-reload.pid 2>/dev/null | wc -l)
  [ "${_FpmTest}" -lt 1 ] && return 0

  # Cooldown check — reuse php84-fpm cooldown as shared gate since a reload
  # affects all FPM versions simultaneously
  local _cd="/run/php84-fpm.cooldown"
  local _now
  _now=$(date +%s)
  if [ -s "${_cd}" ]; then
    local _ts _delta
    _ts=$(tr -d '\n' < "${_cd}" 2>/dev/null)
    if [ -n "${_ts}" ]; then
      _delta=$(( _now - _ts ))
      if [ "${_delta}" -lt "${_FPM_COOLDOWN_SECS}" ]; then
        echo "$(date) INFO: run-php-fpm-reload.pid found but in cooldown (${_delta}s < ${_FPM_COOLDOWN_SECS}s); skipping" >> ${_pthOml}
        rm -f /data/disk/*/static/control/run-php-fpm-reload.pid
        return 0
      fi
    fi
  fi

  echo "$(date) PHP-FPM reload requested via sentinel — reloading to clear APCu" >> ${_pthOml}
  rm -f /data/disk/*/static/control/run-php-fpm-reload.pid
  _fpm_reload "SENTINEL"

  # Update cooldown timestamp for all FPM versions
  local _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    [ -e "/etc/init.d/php${e}-fpm" ] && date +%s > "/run/php${e}-fpm.cooldown"
  done
  echo "$(date) PHP-FPM reload complete (APCu cleared)" >> ${_pthOml}
}


if [ ! -e "/var/tmp/fpm" ]; then
  mkdir -p /var/tmp/fpm
  # 1777 (sticky) instead of 777: every PHP-FPM pool (each a per-tenant uid)
  # still creates its own opcache.lockfile, but cross-tenant deletion of those
  # lockfiles is prevented. Mirrors /tmp's standard scratch-dir model.
  chmod 1777 /var/tmp/fpm
fi

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ]; then
  _fpm_apcu_reload_sentinel
  _fpm_logs_empty
  _fpm_duplicate_instances_detection
  _fpm_listen_conflict_detection
  _fpm_proc_max_detection
  _fpm_sockets_healing
  _fpm_fastcgi_temp
  _fpm_giant_log_detection
  _fpm_health_check_fix
  if [ ! -e "/root/.high_traffic.cnf" ] \
    && [ ! -e "/root/.giant_traffic.cnf" ]; then
    _spawn_detached 'perl /var/xdrago/monitor/check/segfault_alert.pl'
  fi
fi

echo DONE!
exit 0
