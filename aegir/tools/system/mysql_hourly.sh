#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

tRee=lts
export tRee="${tRee}"

check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
    if [ ! -e "/dev/fd" ]; then
      if [ -e "/proc/self/fd" ]; then
        rm -rf /dev/fd
        ln -s /proc/self/fd /dev/fd
      fi
    fi
  else
    echo "ERROR: This script should be ran as a root user"
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
check_root

[ -e "/root/.pause_tasks_maint.cnf" ] && rm -f /root/.pause_tasks_maint.cnf
[ -e "/root/.restrict_this_vm.cnf" ] && rm -f /root/.restrict_this_vm.cnf

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/root/.pause_heavy_tasks_maint.cnf" ]; then
  exit 0
fi

_SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
_SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)

os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _THIS_RV=$(lsb_release -sc 2>&1)
  _OS_LIST="daedalus chimaera beowulf buster bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_THIS_RV}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}
os_detection_minimal

apt_clean_update() {
  apt-get clean -qq 2> /dev/null
  rm -rf /var/lib/apt/lists/* &> /dev/null
  ${_APT_UPDATE} -qq 2> /dev/null
}

if [ -x "/usr/bin/gpg2" ]; then
  _GPG=gpg2
else
  _GPG=gpg
fi

find_fast_mirror_early() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    apt_clean_update
    apt-get install netcat ${aptYesUnth} &> /dev/null
    wait
  fi
  ffMirr=$(which ffmirror 2>&1)
  if [ -x "${ffMirr}" ]; then
    ffList="/var/backups/boa-mirrors-2024-01.txt"
    mkdir -p /var/backups
    if [ ! -e "${ffList}" ]; then
      echo "de.files.aegir.cc"  > ${ffList}
      echo "ny.files.aegir.cc" >> ${ffList}
      echo "sg.files.aegir.cc" >> ${ffList}
    fi
    if [ -e "${ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
        _USE_MIR="${_CHECK_MIRROR}"
        [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.aegir.cc"
      else
        _USE_MIR="files.aegir.cc"
      fi
    else
      _USE_MIR="files.aegir.cc"
    fi
  else
    _USE_MIR="files.aegir.cc"
  fi
  urlDev="http://${_USE_MIR}/dev"
  urlHmr="http://${_USE_MIR}/versions/${tRee}/boa/aegir"
}
find_fast_mirror_early

truncate_watchdog_tables() {
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^watchdog$ 2>&1)
  for A in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
    sleep 1
  done
}

if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
  _B_NICE=${_B_NICE//[^0-9]/}
fi
if [ -z "${_B_NICE}" ]; then
  _B_NICE=10
fi

_BACKUPDIR=/data/disk/arch/hourly
_CHECK_HOST=$(uname -n 2>&1)
_DATE=$(date +%y%m%d-%H%M%S 2>&1)
_DOW=$(date +%u 2>&1)
_DOW=${_DOW//[^1-7]/}
_DOM=$(date +%e 2>&1)
_DOM=${_DOM//[^0-9]/}
_SAVELOCATION=${_BACKUPDIR}/${_CHECK_HOST}-${_DATE}
_VM_TEST=$(uname -a 2>&1)
_LOGDIR="/var/xdrago/log/hourly"
_THIS_OS=$(lsb_release -si 2>&1)
_OSR=$(lsb_release -sc 2>&1)
if [[ "${_VM_TEST}" =~ "-beng" ]]; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi

if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
  || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
  || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
  || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
  PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  InTest=$(ls /data/disk/*/static/control/cli.info | wc -l 2>&1)
  if [ "${InTest}" -le "5" ]; then
    if [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
      || [[ "${PrTestCluster}" =~ "PHANTOM" ]]; then
      _HOURLY_DB_BACKUPS="YES"
    fi
  fi
fi

if [ -z "${_HOURLY_DB_BACKUPS}" ] \
  || [ "${_HOURLY_DB_BACKUPS}" != "YES" ]; then
  rm -rf /data/disk/arch/hourly/*
  exit 1
fi

if [ ! -e "/usr/bin/innobackupex" ]; then
  touch /usr/bin/innobackupex
fi

percList="/etc/apt/sources.list.d/percona-release.list"

if [ ! -e "${percList}" ] \
  || [ ! -e "/usr/bin/innobackupex" ]; then
  if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
    && [ -e "/etc/apt/apt.conf.d" ]; then
    echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
  fi
  rm -f /etc/apt/sources.list.d/mariadb.*
  rm -f /etc/apt/sources.list.d/percona-.*
  rm -f /etc/apt/sources.list.d/xtrabackup.*
  percList="/etc/apt/sources.list.d/percona-release.list"
  _DB_SRC="repo.percona.com"
  percRepo="${_DB_SRC}/percona/apt"
  _REAL_OSR="${_OSR}"
  _REAL_OS="${_THIS_OS}"
  if [ "${_REAL_OSR}" = "daedalus" ]; then
    _SQL_OSR=bookworm
  elif [ "${_REAL_OSR}" = "chimaera" ]; then
    _SQL_OSR=bullseye
  elif [ "${_REAL_OSR}" = "beowulf" ]; then
    _SQL_OSR=buster
  else
    _SQL_OSR="${_REAL_OSR}"
  fi
  echo "## Percona APT Repository" > ${percList}
  echo "deb http://${percRepo} ${_SQL_OSR} main" >> ${percList}
  echo "deb-src http://${percRepo} ${_SQL_OSR} main" >> ${percList}
  echo -e 'Package: *\nPin: release o=Percona Development Team\nPin-Priority: 1001' > /etc/apt/preferences.d/00percona.pref
  apt_clean_update
  if [ -x "/usr/sbin/csf" ] \
    && [ -e "/etc/csf/csf.deny" ]; then
    service lfd stop &> /dev/null
    wait
    kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
    killall sleep &> /dev/null
    rm -f /etc/csf/csf.error
    csf -x &> /dev/null
    wait
  fi
  _KEYS_SIG="8507EFA5"
  _KEYS_SERVER_TEST=FALSE
  until [[ "${_KEYS_SERVER_TEST}" =~ "Percona" ]]; do
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo "Retrieving ${_KEYS_SIG} key..."
    fi
    cd /var/opt
    _KEYS_FILE_TEST=FALSE
    until [[ "${_KEYS_FILE_TEST}" =~ "GnuPG" ]]; do
      rm -f percona-key.gpg*
      wget -q -U iCab ${urlDev}/percona-key.gpg
      _KEYS_FILE_TEST=$(grep GnuPG percona-key.gpg 2>&1)
      sleep 5
    done
    cat percona-key.gpg | ${_GPG} --import &> /dev/null
    rm -f percona-key.gpg*
    ${_GPG} --keyserver pgpkeys.mit.edu --recv-key ${_KEYS_SIG} &> /dev/null
    ${_GPG} -a --export ${_KEYS_SIG} | apt-key add - &> /dev/null
    _KEYS_SERVER_TEST=$(${_GPG} --list-keys ${_KEYS_SIG} 2>&1)
    sleep 2
    if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "5" ]; then
      kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
      echo "$(date 2>&1) Too many dirmngr processes killed" >> \
        /var/xdrago/log/dirmngr-count.kill.log
    fi
    if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt "5" ]; then
      kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
      echo "$(date 2>&1) Too many gpg-agent processes killed" >> \
        /var/xdrago/log/gpg-agent-count.kill.log
    fi
  done
  apt_clean_update
  if [ -x "/usr/sbin/csf" ] \
    && [ -e "/etc/csf/csf.deny" ]; then
    csf -e &> /dev/null
    wait
    service lfd start &> /dev/null
    wait
    ### Linux kernel TCP SACK CVEs mitigation
    ### CVE-2019-11477 SACK Panic
    ### CVE-2019-11478 SACK Slowness
    ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
    if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
      _SACK_TEST=$(ip6tables --list | grep tcpmss 2>&1)
      if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
        sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
        iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/sull
        ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      fi
    fi
  fi
  apt_clean_update
  apt-get install percona-xtrabackup-24 -y
fi

if [ "${_VMFAMILY}" = "VS" ]; then
  n=$((RANDOM%300+8))
  echo "Waiting $n seconds 1/2 on `date` before running backup..."
  sleep $n
  n=$((RANDOM%180+8))
  echo "Waiting $n seconds 2/2 on `date` before running backup..."
  sleep $n
fi

echo "Starting backup on `date`"
touch /var/run/boa_live_sql_backup.pid

[ ! -a ${_SAVELOCATION} ] && mkdir -p ${_SAVELOCATION};
[ ! -a ${_LOGDIR} ] && mkdir -p ${_LOGDIR};

for _DB in `mysql -e "show databases" -s | uniq | sort`; do
  if [ "${_DB}" != "Database" ] \
    && [ "${_DB}" != "information_schema" ] \
    && [ "${_DB}" != "performance_schema" ]; then
    if [ "${_DB}" != "mysql" ]; then
      if [ -e "/var/lib/mysql/${_DB}/watchdog.ibd" ]; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/watchdog.ibd | grep "G" 2>&1)
        if [[ "${_IS_GB}" =~ "watchdog" ]]; then
          truncate_watchdog_tables &> /dev/null
          echo "Truncated giant watchdog for ${_DB}"
        fi
      fi
    fi
  fi
done

innobackupex --user=root --no-timestamp ${_SAVELOCATION} >${_LOGDIR}/XtraBackupA-${_DATE}.log 2>&1
_BACKUP_RESULT=$(tail --lines=3 ${_LOGDIR}/XtraBackupA-${_DATE}.log | tr -d "\n" 2>&1)
if [[ "${_BACKUP_RESULT}" =~ "completed OK" ]]; then
  echo "XtraBackup 1/2 completed OK on `date`"
else
  echo "XtraBackup 1/2 FAILED on `date`"
fi
sleep 5

innobackupex --apply-log ${_SAVELOCATION} >${_LOGDIR}/XtraBackupB-${_DATE}.log 2>&1
_BACKUP_RESULT=$(tail --lines=3 ${_LOGDIR}/XtraBackupB-${_DATE}.log | tr -d "\n" 2>&1)
if [[ "${_BACKUP_RESULT}" =~ "completed OK" ]]; then
  echo "XtraBackup 2/2 completed OK on `date`"
else
  echo "XtraBackup 2/2 FAILED on `date`"
fi
sleep 5

find ${_BACKUPDIR} -mtime +1 -type d -exec rm -rf {} \;
find ${_BACKUPDIR} -mtime +1 -type f -exec rm -rf {} \;
find ${_LOGDIR} -mtime +1 -type f -exec rm -rf {} \;
echo "Backups older than 2 days deleted"

cd ${_BACKUPDIR}/
tar cvfj ${_CHECK_HOST}-${_DATE}.tar.bz2 ${_CHECK_HOST}-${_DATE} &> /dev/null
_BACKUP_LATEST=$(tar -czf - ${_CHECK_HOST}-${_DATE}.tar.bz2 | wc -c 2>&1)
echo "XtraBackup compressed size: ${_BACKUP_LATEST}"

_BACKUP_ALL=$(du -s -h ${_BACKUPDIR} 2>&1)
echo "XtraBackup total size: ${_BACKUP_ALL}"
du -s -h ${_BACKUPDIR}/*
rm -f ${_BACKUPDIR}/latest
ln -s ${_BACKUPDIR}/${_CHECK_HOST}-${_DATE} ${_BACKUPDIR}/latest
rm -f ${_BACKUPDIR}/latest.tar.bz2
ln -s ${_BACKUPDIR}/${_CHECK_HOST}-${_DATE}.tar.bz2 ${_BACKUPDIR}/latest.tar.bz2

chmod 700 ${_BACKUPDIR}
chmod 700 /data/disk/arch
echo "Permissions fixed"

rm -rf ${_CHECK_HOST}-${_DATE}
rm -f /var/run/boa_live_sql_backup.pid
touch /var/xdrago/log/last-run-live-mysql-backup
echo "ALL TASKS COMPLETED"
exit 0
###EOF2024###
