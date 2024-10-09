#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

###-------------SYSTEM-----------------###

_check_root() {
  if [ "$(whoami)" = "root" ]; then
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
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
_check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/root/.pause_tasks_maint.cnf" ]; then
  exit 0
fi

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
    && [ "${_CPU_INFO}" -gt "0" ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt "1" ]; then
    _CPU_NR=1
  fi
}

_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_NR}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

_load_control() {
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

###-------------SYSTEM-----------------###

if [ -e "/run/boa_wait.pid" ] \
  || [ -e "/run/boa_cron_wait.pid" ]; then
  if [ ! -e "/root/.force.queue.runner.cnf" ]; then
    touch /var/xdrago/log/wait-runner.pid
    echo "Another BOA task is running, we will try again later..."
    exit 0
  fi
elif [ "$(ps aux | grep -v "grep" \
  | grep --count "n7 bash.*runner")" -gt "8" ]; then
  if [ ! -e "/root/.force.queue.runner.cnf" ]; then
    touch /var/xdrago/log/wait-runner.pid
    echo "Too many Aegir tasks running now, we will try again later..."
    exit 0
  fi
else
  if [ -e "/root/.slow.cron.cnf" ] && [ ! -e "/root/.force.queue.runner.cnf" ]; then
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
###EOF2024###
