#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

###-------------SYSTEM-----------------###

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
_check_root

[ -e "/root/.proxy.cnf" ] && exit 0
[ -e "/root/.pause_tasks_maint.cnf" ] && exit 0
[ -e "/run/max_load.pid" ] || [ -e "/run/critical_load.pid" ] && exit 0

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_count_cpu() {
  _CPU_INFO=$(grep -c processor /proc/cpuinfo 2>&1)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc 2>&1)
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt 0 ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt 1 ]; then
    _CPU_NR=1
  fi
}

_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_NR}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

_load_control() {
  # shellcheck disable=SC1091
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  : "${_CPU_TASK_RATIO:=2.1}"
  _CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
  _O_LOAD_MAX=$(echo "${_CPU_TASK_RATIO} * 100" | bc -l)
  _get_load
}

_runner_action() {
  for Runner in $(find /var/xdrago -maxdepth 1 -mindepth 1 -type f \
    | grep run- \
    | uniq \
    | sort); do
    _count_cpu
    _load_control
    if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
      echo "Load is ${_O_LOAD}% (below max load ${_O_LOAD_MAX}%). Running ${Runner}"
      if [ ! -e "/run/boa_wait.pid" ]; then
        echo "Running ${Runner}"
        bash "${Runner}"
        _n=$((RANDOM % 9 + 2))
        echo "Waiting ${_n} sec"
        sleep "${_n}"
      else
        echo "Another BOA task is running, we have to wait..."
      fi
    else
      echo "Load is ${_O_LOAD}% while max load is ${_O_LOAD_MAX}%. Waiting..."
    fi
  done
}

_if_allow_aegir_queue() {
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  _ReTest=$(ls /data/disk/*/static/control/run-aegir-queue.info | wc -l 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.aegir.queue.cnf" ]; then
    if [ "${_ReTest}" -ge 1 ]; then
      _ALLOW_AEGIR_QUEUE=TRUE
    fi
  fi
}

###-------------SYSTEM-----------------###

_SQLBACKUP_RUNNING=NO
if (( $(pgrep -fc mysql_backup.sh) > 0 )); then
  _SQLBACKUP_RUNNING=YES
elif (( $(pgrep -fc mysql_cluster_backup.sh) > 0 )); then
  _SQLBACKUP_RUNNING=YES
elif (( $(pgrep -fc mydumper) > 0 )); then
  _SQLBACKUP_RUNNING=YES
fi

_DAILY_RUNNING=NO
if (( $(pgrep -fc daily.sh) > 0 )); then
  _DAILY_RUNNING=YES
fi

# Get total RAM in MB
_TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')

# Compare with 4096 MB (4 GB)
if [ "${_TOTAL_RAM_MB}" -le 4096 ]; then
  if [ ! -e "/root/.slow.cron.cnf" ]; then
    echo SLOW > /root/.slow.cron.cnf
    chattr +i /root/.slow.cron.cnf
    echo SLOW > /root/.slow.cron.cnf.protected
  fi
fi

if [ "$(pgrep -fc 'n7 bash /var/xdrago/runner.sh')" -gt 8 ] \
  || [ "${_SQLBACKUP_RUNNING}" = "TRUE" ] \
  || [ "${_DAILY_RUNNING}" = "TRUE" ] \
  || [ -e "/run/mysql_restart_running.pid" ]
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/boa_wait.pid" ] \
  || [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_cron_wait.pid" ]; then
  touch /var/log/boa/wait-runner.pid
  echo "Another BOA task is running, we will try again later..."
  exit 0
else
  if [ -e "/root/.look.like.jenkins.cnf" ]; then
    _ALLOW_AEGIR_QUEUE=FALSE
    _if_allow_aegir_queue
    if [ "${_ALLOW_AEGIR_QUEUE}" = "TRUE" ]; then
      touch /run/boa_cron_wait.pid
      _runner_action
      sleep 5
      rm -f /run/boa_cron_wait.pid
    else
      echo "No automatic task queue on CI instance allowed by default"
      exit 0
    fi
  elif [ -e "/root/.slow.cron.cnf" ] && [ ! -e "/root/.force.queue.runner.cnf" ]; then
    touch /run/boa_cron_wait.pid
    sleep 15
    _runner_action
    sleep 15
    rm -f /run/boa_cron_wait.pid
  elif [ -e "/root/.fast.cron.cnf" ] || [ -e "/root/.force.queue.runner.cnf" ]; then
    rm -f /run/boa_cron_wait.pid
    for i in {1..10}; do
      _runner_action
      sleep 5
    done
  else
    _runner_action
  fi
  exit 0
fi

