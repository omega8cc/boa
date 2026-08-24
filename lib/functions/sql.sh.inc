
# _backup_to_dragon() moved to the shared helper.sh.inc (Octopus sources helper
# but not sql). Callsites below still use it unchanged.

_check_mysql_version() {
  _DB_V=
  if [ -x "/usr/sbin/aa-teardown" ]; then
    aa-teardown &> /dev/null
  fi
  # Prefer the SERVER binary: a partial apt transaction can leave an 8.x
  # client next to a 5.7 server, and every version-keyed my.cnf branch
  # below must follow the binary that will actually parse the file.
  # --no-defaults (must be the first option) keeps the probe from parsing
  # /etc/mysql/my.cnf -- on a half-flipped box the config is exactly what
  # the server rejects, and a probe that dies on it would silently fall
  # back to the untrustworthy client below.
  if [ -x "/usr/sbin/mysqld" ]; then
    _DB_V=$(/usr/sbin/mysqld --no-defaults -V 2>&1 \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -1 \
      | cut -d"." -f1,2)
  fi
  if [ -z "${_DB_V}" ]; then
    _DB_V=$(mysql -V 2>&1 \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -1 \
      | cut -d"." -f1,2)
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "DBST: via _check_mysql_version ${_DB_V}"
  fi
}

#
# True when the SQL-maintenance marker is held by a DIFFERENT live process.
# Our own marker (written with $$ by _install_with_aptitude_sql) and a
# marker whose writer has died must not suppress the recovery start in the
# bounded waits below; an EMPTY fresh marker keeps its historical "held"
# meaning (xoct/xmass/mysql_repair still write it bare), and a stale one
# (>240 min) is ignored the same way the watchdog ignores it.
_sql_maint_foreign() {
  [ -e "/run/boa_sql_maintenance.pid" ] || return 1
  [ ! -z "$(find /run/boa_sql_maintenance.pid -mmin +240 2>/dev/null)" ] && return 1
  local _mPid="$(tr -dc '0-9' < /run/boa_sql_maintenance.pid 2>/dev/null)"
  [ -z "${_mPid}" ] && return 0
  [ "${_mPid}" = "$$" ] && return 1
  kill -0 "${_mPid}" 2>/dev/null || return 1
  return 0
}

_check_sql_running() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_sql_running"
  fi
  # Ensure MySQLD is up before proceeding. It used to be (re)started as a side
  # effect of _sql_conf_update's innodb update; now that directive sync is
  # decoupled from sizing, start it explicitly here when it is down -- e.g.
  # right after the Percona package install on a 5.7->8.0 upgrade, where
  # nothing else brings it back up.
  # Bounded two ways: ~2 min of CONSECUTIVE dead samples catches a mysqld
  # that died on its config or datadir (a live process with no socket yet is
  # normal -- the first 8.x start runs the data-dictionary upgrade, minutes
  # on a big datadir -- and resets the dead counter), while the total-time
  # ceiling catches a flapping mysqld that a per-sample reset alone would
  # wait on forever. ONE start attempt via the blessed move_sql.sh path
  # (a bare `service mysql start` is a no-op on a stale pidfile), skipped
  # while a fresh SQL-maintenance marker is held by another operation. The
  # marker is deliberately NOT removed on abort here: this generic wait
  # cannot know who owns it (xoct/xmass/mysql_repair hold it too) and the
  # watchdog age-reaps a stale one on its own.
  [ -e "/root/.proxy.cnf" ] && return 0
  local _dead=0
  local _tot=0
  local _started=NO
  while : ; do
    _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
    if [ ! -z "${_IS_MYSQLD_RUNNING}" ] && [ -e "/run/mysqld/mysqld.sock" ]; then
      return 0
    fi
    if [ ! -z "${_IS_MYSQLD_RUNNING}" ]; then
      _dead=0
    else
      _dead=$(( _dead + 1 ))
      if [ "${_started}" = "NO" ] && ! _sql_maint_foreign; then
        _started=YES
        _msg "INFO: MySQLD not running -- starting it..."
        if [ -e "/var/xdrago/move_sql.sh" ]; then
          _mrun "bash /var/xdrago/move_sql.sh start"
        else
          _mrun "service mysql start"
        fi
      fi
    fi
    _tot=$(( _tot + 1 ))
    if [ "${_dead}" -gt 24 ] || [ "${_tot}" -gt 720 ]; then
      _msg "FATAL ERROR: MySQLD did not become available (down $(( (_dead - 1) * 5 ))s, total wait $(( (_tot - 1) * 5 ))s)."
      _msg "FATAL ERROR: Check /var/log/mysql/error.log for the reason, and on a"
      _msg "FATAL ERROR: 5.7 box the mysqld lines in /var/log/syslog (or"
      _msg "FATAL ERROR: /var/log/daemon.log) instead -- 5.7 is configured with"
      _msg "FATAL ERROR: log_syslog, 8.x with log_error. Typically a bad my.cnf"
      _msg "FATAL ERROR: directive or a datadir problem. Aborting instead of"
      _msg "FATAL ERROR: waiting forever; fix it and run the upgrade again."
      _clean_pid_exit _check_sql_running_dead
    fi
    _msg "WAIT: Waiting for MySQLD availability..."
    sleep 5
  done
}

_install_local_ordered() {
  cd "${_WORK}"
  _mrun "dpkg -i ./mysql-common_*_amd64.deb"
  _mrun "dpkg -i ./mysql-community-client-plugins_*_amd64.deb"
  _mrun "dpkg -i ./libmysqlclient24_*_amd64.deb"
  _mrun "dpkg -i ./libmysqlclient-dev_*_amd64.deb"
  _mrun "dpkg -i ./mysql-community-client-core_*_amd64.deb"
  _mrun "dpkg -i ./mysql-community-client_*_amd64.deb"
  _mrun "dpkg -i ./mysql-client_*_amd64.deb"
  _mrun "dpkg -i ./mysql-community-server-core_*_amd64.deb"
  _mrun "dpkg -i ./mysql-community-server_*_amd64.deb"
  _mrun "dpkg -i ./mysql-server_*_amd64.deb"
  _mrun "apt-get -f -y install"
}

_download_pkg_by_name() {
  # $1 = package name
  local _name="$1" _file
  _file="$(awk -v P="${_name}" '
    $1=="Package:" && $2==P {f=1}
    f && $1=="Filename:" {print $2; f=0}
  ' Packages | tail -n1)"
  if [ -z "${_file}" ]; then
    _msg "MSQL: Could not locate package '${_name}' in Packages index"
  fi
  local _url="${_BASE_URL}/${_file}"
  local _base="$(basename "${_file}")"
  if [ -s "${_base}" ]; then
    return 0
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "MSQL: Downloading ${_url}"
  fi
  _mrun "wget -q ${_url} -O ${_base}"
}

_fetch_packages_index() {
  mkdir -p "${_WORK}"
  cd "${_WORK}"
  curl -fsS "${_BASE_URL}/dists/${_SUITE}/${_COMP}/binary-${_ARCH}/Packages" -o Packages
}

_download_all_mysql_debs() {
  _fetch_packages_index
  local _p
  for _p in ${_PKGS}; do
    _download_pkg_by_name "${_p}"
  done
}

_ensure_base_runtime_deps() {
  _apt_clean_update
  _mrun "${_INSTAPP} libmecab2 psmisc libnuma1"
}

_dpkg_install_mysql() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _dpkg_install_mysql"
  fi
  _WORK="/var/backups/mysql84-local"
  _BASE_URL="http://repo.mysql.com/apt/debian"
  _SUITE="trixie"
  _COMP="mysql-8.4-lts"
  _ARCH="amd64"
  _PKGS="
mysql-common
mysql-community-client-plugins
libmysqlclient24
libmysqlclient-dev
mysql-community-client-core
mysql-community-client
mysql-client
mysql-community-server-core
mysql-community-server
mysql-server
"
  _ensure_base_runtime_deps
  _download_all_mysql_debs
  _install_local_ordered
}

#
# Update for keyrings/percona.gpg
_if_sql_keyring_apt_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_sql_keyring_apt_update"
  fi

  if [ "${_DB_SERVER}" = "Percona" ]; then
    _SQL_KEYRING_UPDATE=NO
    if [ -e "/etc/apt/trusted.gpg.d/percona.gpg" ] \
      || [ ! -e "/etc/apt/keyrings/percona.gpg" ] \
      || [ -e "/etc/apt/trusted.gpg.d/percona-keyring.gpg~" ]; then
      _SQL_KEYRING_UPDATE=YES
    fi
  fi

  if [ "${_DB_SERVER}" = "Percona" ] && [ "${_SQL_KEYRING_UPDATE}" = "YES" ]; then
    if [ ! -e "/etc/apt/keyrings/percona.gpg" ]; then
      if [ ! -e "/etc/apt/keyrings" ]; then
        mkdir -m 0755 -p /etc/apt/keyrings
      fi
      if [ -e "/etc/apt/trusted.gpg.d/percona.gpg" ] \
        || [ -e "/etc/apt/trusted.gpg.d/percona-keyring.gpg~" ]; then
        rm -f /etc/apt/trusted.gpg.d/percona*
      fi
      _PERCONA_KEYS_SIG="8507EFA5"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Retrieving ${_PERCONA_KEYS_SIG} key..."
      fi
      apt-key del ${_PERCONA_KEYS_SIG} &> /dev/null
      if [ ! -e "/etc/apt/keyrings/percona.gpg" ]; then
        curl -fsSL ${_urlDev}/percona-key.gpg | ${_GPG} --dearmor -o /etc/apt/keyrings/percona.gpg
      fi
      chmod 644 /etc/apt/keyrings/percona.gpg
      _CNT=$(pgrep -fc dirmngr)
      if (( _CNT > 5 )); then
        pkill -9 -f dirmngr
        echo "$(date) Too many dirmngr processes killed (count=${_CNT})" >> \
          /var/log/boa/dirmngr-count.kill.log
      fi
      _CNT=$(pgrep -fc gpg-agent)
      if (( _CNT > 5 )); then
        pkill -9 -f gpg-agent
        echo "$(date) Too many gpg-agent processes killed (count=${_CNT})" >> \
          /var/log/boa/gpg-agent-count.kill.log
      fi
    fi
    _apt_clean_update
  fi

  if [ "${_DB_SERVER}" = "MySQL" ]; then
    _SQL_KEYRING_UPDATE=NO
    if [ -e "/etc/apt/trusted.gpg.d/mysql.gpg" ] \
      || [ ! -e "/etc/apt/keyrings/mysql.gpg" ] \
      || [ -e "/etc/apt/trusted.gpg.d/mysql-keyring.gpg~" ]; then
      _SQL_KEYRING_UPDATE=YES
    fi
  fi

  if [ "${_DB_SERVER}" = "MySQL" ] && [ "${_SQL_KEYRING_UPDATE}" = "YES" ]; then
    if [ ! -e "/etc/apt/keyrings/mysql.gpg" ]; then
      if [ ! -e "/etc/apt/keyrings" ]; then
        mkdir -m 0755 -p /etc/apt/keyrings
      fi
      if [ -e "/etc/apt/trusted.gpg.d/mysql.gpg" ] \
        || [ -e "/etc/apt/trusted.gpg.d/mysql-keyring.gpg~" ]; then
        rm -f /etc/apt/trusted.gpg.d/mysql*
      fi
      _MYSQL_KEYS_SIG="B7B3B788A8D3785C"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Retrieving ${_MYSQL_KEYS_SIG} key..."
      fi
      apt-key del ${_MYSQL_KEYS_SIG} &> /dev/null
      if [ ! -e "/etc/apt/keyrings/mysql.gpg" ]; then
        curl -fsSL ${_urlDev}/mysql-key.gpg | ${_GPG} --dearmor -o /etc/apt/keyrings/mysql.gpg
      fi
      chmod 644 /etc/apt/keyrings/mysql.gpg
      _CNT=$(pgrep -fc dirmngr)
      if (( _CNT > 5 )); then
        pkill -9 -f dirmngr
        echo "$(date) Too many dirmngr processes killed (count=${_CNT})" >> \
          /var/log/boa/dirmngr-count.kill.log
      fi
      _CNT=$(pgrep -fc gpg-agent)
      if (( _CNT > 5 )); then
        pkill -9 -f gpg-agent
        echo "$(date) Too many gpg-agent processes killed (count=${_CNT})" >> \
          /var/log/boa/gpg-agent-count.kill.log
      fi
    fi
    _apt_clean_update
  fi

  [ ! -z "${_SQL_NEW_OS_CODE}" ] && _SQL_OS_CODE=${_SQL_NEW_OS_CODE}

  if [ "${_DB_V}" = "8.4" ] || [ "${_DB_SERIES}" = "8.4" ]; then
    if [ "${_DB_SERVER}" = "Percona" ]; then
      _DB_SRC="repo.percona.com"
      _percNodot="${_DB_SERIES//./}"
      _sqlDebVersion="ps-${_percNodot}-lts"
      _SQL_DEB_SRC_TEST_A=$(grep ${_DB_SRC} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_B=$(grep ${_SQL_OS_CODE} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_C=$(grep ${_sqlDebVersion} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_D=$(grep ps-8x-innovation /etc/apt/sources.list.d/percona-release.list 2>&1)
    elif [ "${_DB_SERVER}" = "MySQL" ]; then
      _DB_SRC="repo.mysql.com"
      _sqlDebVersion="mysql-${_DB_SERIES}-lts"
      _SQL_DEB_SRC_TEST_A=$(grep ${_DB_SRC} /etc/apt/sources.list.d/mysql.list 2>&1)
      _SQL_DEB_SRC_TEST_B=$(grep ${_SQL_OS_CODE} /etc/apt/sources.list.d/mysql.list 2>&1)
      _SQL_DEB_SRC_TEST_C=$(grep ${_sqlDebVersion} /etc/apt/sources.list.d/mysql.list 2>&1)
    fi
    if [[ "${_SQL_DEB_SRC_TEST_A}" =~ "${_DB_SRC}" ]] \
      && [[ "${_SQL_DEB_SRC_TEST_B}" =~ "${_SQL_OS_CODE}" ]] \
      && [[ "${_SQL_DEB_SRC_TEST_C}" =~ "${_sqlDebVersion}" ]]; then
      if [ "${_DB_SERVER}" = "Percona" ]; then
        if [ -e "/etc/apt/keyrings/percona.gpg" ] \
          && [ -e "/etc/apt/preferences.d/00percona.pref" ]; then
          _SQL_DEB_SRC_UPDATE=NO
        fi
      else
        if [ -e "/etc/apt/keyrings/mysql.gpg" ]; then
          _SQL_DEB_SRC_UPDATE=NO
        fi
      fi
    else
      _SQL_DEB_SRC_UPDATE=YES
    fi
    if [[ "${_SQL_DEB_SRC_TEST_D}" =~ "ps-8x-innovation" ]]; then
      _SQL_DEB_SRC_UPDATE=YES
    fi
  elif [ "${_DB_V}" = "8.3" ] || [ "${_DB_SERIES}" = "8.3" ]; then
    if [ "${_DB_SERVER}" = "Percona" ]; then
      _DB_SRC="repo.percona.com"
      _percNodot="${_DB_SERIES//./}"
      _SQL_DEB_SRC_TEST_A=$(grep ${_DB_SRC} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_B=$(grep ${_SQL_OS_CODE} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_C=$(grep ps-${_percNodot} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_D=$(grep ps-8x-innovation /etc/apt/sources.list.d/percona-release.list 2>&1)
    fi
    if [[ "${_SQL_DEB_SRC_TEST_A}" =~ "${_DB_SRC}" ]] \
      && [[ "${_SQL_DEB_SRC_TEST_B}" =~ "${_SQL_OS_CODE}" ]] \
      && [[ "${_SQL_DEB_SRC_TEST_D}" =~ "ps-8x-innovation" ]] \
      && [ -e "/etc/apt/keyrings/percona.gpg" ] \
      && [ -e "/etc/apt/preferences.d/00percona.pref" ]; then
      _SQL_DEB_SRC_UPDATE=NO
    else
      _SQL_DEB_SRC_UPDATE=YES
    fi
    if [[ "${_SQL_DEB_SRC_TEST_C}" =~ "ps-${_percNodot}" ]]; then
      _SQL_DEB_SRC_UPDATE=YES
    fi
  else
    if [ "${_DB_SERVER}" = "Percona" ]; then
      _DB_SRC="repo.percona.com"
      _percNodot="${_DB_SERIES//./}"
      _sqlDebVersion="ps-${_percNodot}"
      _SQL_DEB_SRC_TEST_A=$(grep ${_DB_SRC} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_B=$(grep ${_SQL_OS_CODE} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_C=$(grep ${_sqlDebVersion} /etc/apt/sources.list.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_D=$(grep ps-8x-innovation /etc/apt/sources.list.d/percona-release.list 2>&1)
    elif [ "${_DB_SERVER}" = "MySQL" ]; then
      _DB_SRC="repo.mysql.com"
      _sqlDebVersion="mysql-${_DB_SERIES}-lts"
      _SQL_DEB_SRC_TEST_A=$(grep ${_DB_SRC} /etc/apt/sources.list.d/mysql.list 2>&1)
      _SQL_DEB_SRC_TEST_B=$(grep ${_SQL_OS_CODE} /etc/apt/sources.list.d/mysql.list 2>&1)
      _SQL_DEB_SRC_TEST_C=$(grep ${_sqlDebVersion} /etc/apt/sources.list.d/mysql.list 2>&1)
    fi
    if [[ "${_SQL_DEB_SRC_TEST_A}" =~ "${_DB_SRC}" ]] \
      && [[ "${_SQL_DEB_SRC_TEST_B}" =~ "${_SQL_OS_CODE}" ]] \
      && [[ "${_SQL_DEB_SRC_TEST_C}" =~ "${_sqlDebVersion}" ]]; then
      if [ "${_DB_SERVER}" = "Percona" ]; then
        if [ -e "/etc/apt/keyrings/percona.gpg" ] \
          && [ -e "/etc/apt/preferences.d/00percona.pref" ]; then
          _SQL_DEB_SRC_UPDATE=NO
        fi
      else
        if [ -e "/etc/apt/keyrings/mysql.gpg" ]; then
          _SQL_DEB_SRC_UPDATE=NO
        fi
      fi
    else
      _SQL_DEB_SRC_UPDATE=YES
    fi
    if [[ "${_SQL_DEB_SRC_TEST_D}" =~ "ps-8x-innovation" ]]; then
      _SQL_DEB_SRC_UPDATE=YES
    fi
  fi

  if [ "${_DB_SERVER}" = "Percona" ] && [ "${_SQL_DEB_SRC_UPDATE}" = "YES" ]; then
    rm -f /etc/apt/sources.list.d/mariadb*
    rm -f /etc/apt/sources.list.d/ourdelta*
    rm -f /etc/apt/sources.list.d/percona*
    rm -f /etc/apt/sources.list.d/mysql*
    _percList="/etc/apt/sources.list.d/percona-release.list"
    if [ "${_DB_V}" = "8.4" ] || [ "${_DB_SERIES}" = "8.4" ]; then
      _percRepo="${_DB_SRC}/ps-${_percNodot}-lts/apt"
    elif [ "${_DB_V}" = "8.3" ] || [ "${_DB_SERIES}" = "8.3" ]; then
      _percRepo="${_DB_SRC}/ps-8x-innovation/apt"
    else
      _percRepo="${_DB_SRC}/ps-${_percNodot}/apt"
    fi
    _percTools="${_DB_SRC}/tools/apt"
    _percTelem="${_DB_SRC}/telemetry/apt"
    _percPrelr="${_DB_SRC}/prel/apt"
    echo "## Percona Server APT Repository" > ${_percList}
    if [ -e "/etc/apt/keyrings/percona.gpg" ]; then
      echo "deb [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percRepo} ${_SQL_OS_CODE} main" >> ${_percList}
      echo "deb-src [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percRepo} ${_SQL_OS_CODE} main" >> ${_percList}
    else
      echo "deb http://${_percRepo} ${_SQL_OS_CODE} main" >> ${_percList}
      echo "deb-src http://${_percRepo} ${_SQL_OS_CODE} main" >> ${_percList}
    fi
    if [ "${_DB_V}" = "8.4" ] || [ "${_DB_SERIES}" = "8.4" ]; then
      echo " " >> ${_percList}
      echo "## Percona Telemetry APT Repository" >> ${_percList}
      if [ -e "/etc/apt/keyrings/percona.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percTelem} ${_SQL_OS_CODE} main" >> ${_percList}
        echo "deb-src [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percTelem} ${_SQL_OS_CODE} main" >> ${_percList}
      else
        echo "deb http://${_percTelem} ${_SQL_OS_CODE} main" >> ${_percList}
        echo "deb-src http://${_percTelem} ${_SQL_OS_CODE} main" >> ${_percList}
      fi
    elif [ "${_SQL_DEBUG_MODE}" = "YES" ]; then
      echo " " >> ${_percList}
      echo "## Percona Tools APT Repository" >> ${_percList}
      if [ -e "/etc/apt/keyrings/percona.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percTools} ${_SQL_OS_CODE} main" >> ${_percList}
        echo "deb-src [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percTools} ${_SQL_OS_CODE} main" >> ${_percList}
      else
        echo "deb http://${_percTools} ${_SQL_OS_CODE} main" >> ${_percList}
        echo "deb-src http://${_percTools} ${_SQL_OS_CODE} main" >> ${_percList}
      fi
      echo " " >> ${_percList}
      echo "## Percona Telemetry APT Repository" >> ${_percList}
      if [ -e "/etc/apt/keyrings/percona.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percTelem} ${_SQL_OS_CODE} main" >> ${_percList}
        echo "deb-src [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percTelem} ${_SQL_OS_CODE} main" >> ${_percList}
      else
        echo "deb http://${_percTelem} ${_SQL_OS_CODE} main" >> ${_percList}
        echo "deb-src http://${_percTelem} ${_SQL_OS_CODE} main" >> ${_percList}
      fi
      echo " " >> ${_percList}
      echo "## Percona Release APT Repository" >> ${_percList}
      if [ -e "/etc/apt/keyrings/percona.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percPrelr} ${_SQL_OS_CODE} main" >> ${_percList}
        echo "deb-src [signed-by=/etc/apt/keyrings/percona.gpg] http://${_percPrelr} ${_SQL_OS_CODE} main" >> ${_percList}
      else
        echo "deb http://${_percPrelr} ${_SQL_OS_CODE} main" >> ${_percList}
        echo "deb-src http://${_percPrelr} ${_SQL_OS_CODE} main" >> ${_percList}
      fi
    fi
    chmod 644 ${_percList}
    echo -e 'Package: *\nPin: release o=Percona Development Team\nPin-Priority: 1001' > /etc/apt/preferences.d/00percona.pref
    _apt_clean_update
  fi

  if [ "${_DB_SERVER}" = "MySQL" ] && [ "${_SQL_DEB_SRC_UPDATE}" = "YES" ]; then
    rm -f /etc/apt/sources.list.d/mariadb*
    rm -f /etc/apt/sources.list.d/ourdelta*
    rm -f /etc/apt/sources.list.d/percona*
    rm -f /etc/apt/sources.list.d/mysql*
    _percList="/etc/apt/sources.list.d/mysql-release.list"
    if [ "${_DB_V}" = "8.4" ] || [ "${_DB_SERIES}" = "8.4" ]; then
      _percRepo="repo.mysql.com/apt/debian/"
    fi
    echo "## MySQL Server APT Repository" > ${_percList}
    if [ -e "/etc/apt/keyrings/mysql.gpg" ]; then
      echo "deb [signed-by=/etc/apt/keyrings/mysql.gpg] http://${_percRepo} ${_SQL_OS_CODE} mysql-8.4-lts mysql-tools" >> ${_percList}
      echo "deb-src [signed-by=/etc/apt/keyrings/mysql.gpg] http://${_percRepo} ${_SQL_OS_CODE} mysql-8.4-lts mysql-tools" >> ${_percList}
    else
      echo "deb http://${_percRepo} ${_SQL_OS_CODE} mysql-8.4-lts mysql-tools" >> ${_percList}
      echo "deb-src http://${_percRepo} ${_SQL_OS_CODE} mysql-8.4-lts mysql-tools" >> ${_percList}
    fi
    chmod 644 ${_percList}
    echo -e 'Package: *\nPin: release o=MySQL Development Team\nPin-Priority: 1001' > /etc/apt/preferences.d/00mysql.pref
    ### Temporary cleanup until MySQL updates gpg keys
    mv -f ${_percList} /var/backups/
    mv -f /etc/apt/preferences.d/00mysql.pref /var/backups/
    mv -f /etc/apt/keyrings/mysql.gpg /var/backups/
    _apt_clean_update
  fi
}

#
# Only supported upgrade path allowed.
_sql_strict_upgrade_path() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sql_strict_upgrade_path"
  fi
  _SQL_UPGRADE=NO
  # Server binary first (--no-defaults so a rejected my.cnf directive cannot
  # kill the probe), client only as fallback: the staging and reinstall
  # decisions must follow the binary that owns the datadir, not a client a
  # partial apt transaction may already have advanced.
  _NOW_DB_V=
  if [ -x "/usr/sbin/mysqld" ]; then
    _NOW_DB_V=$(/usr/sbin/mysqld --no-defaults -V 2>&1 \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -1 \
      | cut -d"." -f1,2)
  fi
  _DBS_TEST="$(which mysql)"
  if [ -z "${_NOW_DB_V}" ] && [ ! -z "${_DBS_TEST}" ]; then
    _NOW_DB_V=$(mysql -V 2>&1 \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -1 \
      | cut -d"." -f1,2)
  fi
  if [ ! -z "${_NOW_DB_V}" ]; then
    if [[ ! "${_NOW_DB_V}" =~ (^)"${_DB_SERIES}" ]]; then
      _SQL_FORCE_REINSTALL=YES
    fi
    if [[ "${_NOW_DB_V}" =~ "available" ]]; then
      _SQL_FORCE_REINSTALL=NO
    fi
  else
    _SQL_FORCE_REINSTALL=YES
  fi
  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    _ALL_FORCE_REINSTALL=YES
  else
    _ALL_FORCE_REINSTALL=NO
  fi
  if [[ "${_NOW_DB_V}" =~ (^)"5.7" ]] \
    && [ ! -z "${_DB_SERIES}" ] \
    && [ "${_DB_SERIES}" != "5.7" ] \
    && [ "${_DB_SERIES}" != "8.0" ]; then
    # Stage 5.7 through 8.0 for THIS run only, never persisted: the durable
    # sed here destroyed the operator's 8.4 target on distros with no cnf
    # re-assertion, so an interrupted two-step could never resume its second
    # leg. With run-scoped staging a completed 8.0 leg resumes toward the
    # cnf/marker-asserted target on the next run (the launcher still honours
    # explicit percona-X.Y selectors and /root/.percona.X.Y.cnf markers).
    _DB_SERIES=8.0
    export _DB_SERIES=8.0
    export _SQL_UPGRADE=YES
  fi
  if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
    export _SQL_UPGRADE=YES
    export _myCnfUpdate=YES
  fi
  if [ "${_SQL_UPGRADE}" = "YES" ]; then
    mysql -u root -e "SET GLOBAL innodb_fast_shutdown = 0;" &> /dev/null
  fi
}

#
# Update innodb_log_file_size.
_innodb_log_file_size_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _innodb_log_file_size_update"
  fi
  _check_mysql_version
  _sql_directives_sync
  _check_sql_running
  if [ "${_DB_V}" != "5.7" ]; then
    _msg "INFO: InnoDB redo log capacity will be set to ${_INNODB_REDO_LOG_CAPACITY_MB}..."
  else
    _msg "INFO: InnoDB log file will be set to ${_INNODB_LOG_FILE_SIZE_MB}..."
  fi
  mysql -u root -e "SET GLOBAL innodb_fast_shutdown = 0;" &> /dev/null
  _mrun "bash /var/xdrago/move_sql.sh stop"
  wait
  _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
  if [ -z "${_IS_MYSQLD_RUNNING}" ]; then
    mkdir -p ${_vBs}/old-sql-ib-log-${_NOW}
    sleep 1
    mv -f /var/lib/mysql/ib_logfile0 ${_vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    mv -f /var/lib/mysql/ib_logfile1 ${_vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    if [ "${_DB_V}" = "5.7" ] || [ "${_DB_SERIES}" = "5.7" ]; then
      if [ "${_SQL_UPGRADE}" = "NO" ]; then
        if [ -e "/root/.dev.server.cnf" ]; then
          echo "DEBUG1: _DB_SERIES is ${_DB_SERIES}"
          echo "DEBUG1: _DB_V is ${_DB_V}"
          echo "DEBUG1: _SQL_UPGRADE is ${_SQL_UPGRADE}"
          echo "DEBUG1: _INNODB_LOG_FILE_SIZE_MB is ${_INNODB_LOG_FILE_SIZE_MB}"
          echo "DEBUG1: _INNODB_REDO_LOG_CAPACITY_MB is ${_INNODB_REDO_LOG_CAPACITY_MB}"
        fi
        sed -i \
          -e "s/.*innodb_redo_log_capacity.*/#innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}/g" \
          -e "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" \
          /etc/mysql/my.cnf &> /dev/null
        echo "innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}" > /var/log/boa/.my.innodb_log_file_size.txt
      fi
    fi
    if [ "${_DB_V}" != "5.7" ]; then
      if [ ! -z "${_DB_SERIES}" ] && [ "${_DB_SERIES}" != "5.7" ]; then
        if [ -e "/root/.dev.server.cnf" ]; then
          echo "DEBUG2: _DB_SERIES is ${_DB_SERIES}"
          echo "DEBUG2: _DB_V is ${_DB_V}"
          echo "DEBUG2: _SQL_UPGRADE is ${_SQL_UPGRADE}"
          echo "DEBUG2: _INNODB_LOG_FILE_SIZE_MB is ${_INNODB_LOG_FILE_SIZE_MB}"
          echo "DEBUG2: _INNODB_REDO_LOG_CAPACITY_MB is ${_INNODB_REDO_LOG_CAPACITY_MB}"
        fi
        sed -i \
          -e "s/.*innodb_redo_log_capacity.*/innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}/g" \
          -e "s/.*innodb_log_file_size.*/#innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" \
          /etc/mysql/my.cnf &> /dev/null
        echo "innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}" > /var/log/boa/.my.innodb_redo_log_capacity.txt
      fi
    fi
    _mrun "bash /var/xdrago/move_sql.sh start"
    wait
  else
    _msg "INFO: Waiting 180s for ${_DB_SERVER} clean shutdown..."
    _mrun "bash /var/xdrago/move_sql.sh stop"
    wait
    sleep 180
    _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
    if [ -z "${_IS_MYSQLD_RUNNING}" ]; then
      mkdir -p ${_vBs}/old-sql-ib-log-${_NOW}
      sleep 1
      mv -f /var/lib/mysql/ib_logfile0 ${_vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      mv -f /var/lib/mysql/ib_logfile1 ${_vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      if [ "${_DB_V}" = "5.7" ] || [ "${_DB_SERIES}" = "5.7" ]; then
        if [ "${_SQL_UPGRADE}" = "NO" ]; then
          if [ -e "/root/.dev.server.cnf" ]; then
            echo "DEBUG3: _DB_SERIES is ${_DB_SERIES}"
            echo "DEBUG3: _DB_V is ${_DB_V}"
            echo "DEBUG3: _SQL_UPGRADE is ${_SQL_UPGRADE}"
            echo "DEBUG3: _INNODB_REDO_LOG_CAPACITY_MB is ${_INNODB_REDO_LOG_CAPACITY_MB}"
            echo "DEBUG3: _INNODB_LOG_FILE_SIZE_MB is ${_INNODB_LOG_FILE_SIZE_MB}"
          fi
          sed -i \
            -e "s/.*innodb_redo_log_capacity.*/#innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}/g" \
            -e "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" \
            /etc/mysql/my.cnf &> /dev/null
          echo "innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}" > /var/log/boa/.my.innodb_log_file_size.txt
        fi
      fi
      if [ "${_DB_V}" != "5.7" ]; then
        if [ ! -z "${_DB_SERIES}" ] && [ "${_DB_SERIES}" != "5.7" ]; then
          if [ -e "/root/.dev.server.cnf" ]; then
            echo "DEBUG4: _DB_SERIES is ${_DB_SERIES}"
            echo "DEBUG4: _DB_V is ${_DB_V}"
            echo "DEBUG4: _SQL_UPGRADE is ${_SQL_UPGRADE}"
            echo "DEBUG4: _INNODB_REDO_LOG_CAPACITY_MB is ${_INNODB_REDO_LOG_CAPACITY_MB}"
            echo "DEBUG4: _INNODB_LOG_FILE_SIZE_MB is ${_INNODB_LOG_FILE_SIZE_MB}"
          fi
          sed -i \
            -e "s/.*innodb_redo_log_capacity.*/innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}/g" \
            -e "s/.*innodb_log_file_size.*/#innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" \
            /etc/mysql/my.cnf &> /dev/null
          echo "innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}" > /var/log/boa/.my.innodb_redo_log_capacity.txt
        fi
      fi
      _mrun "bash /var/xdrago/move_sql.sh start"
      wait
    else
      if [ "${_DB_V}" != "5.7" ]; then
        _msg "WARN: ${_DB_SERVER} refused to stop, InnoDB redo log capacity size not updated"
      else
        _msg "WARN: ${_DB_SERVER} refused to stop, InnoDB log file size not updated"
      fi
      sleep 5
    fi
  fi
}

#
# Update SQL Config.
_sql_conf_update() {
  # Mode "directives" (called via _sql_directives_sync) normalizes only the
  # my.cnf version-compatibility directives and skips innodb sizing plus the
  # mysqld restart it triggers. Default (no arg) runs the full config.
  local _CONF_MODE="${1}"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sql_conf_update"
  fi
  sed -i -e "s/.*innodb_force_recovery/#innodb_force_recovery/g" \
    -e "s/.*innodb_corrupt_table_action/#innodb_corrupt_table_action/g" \
    -e "s/^thread_concurrency.*//g" /etc/mysql/my.cnf &> /dev/null
  _if_hosted_sys
  _check_mysql_version
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ] \
    || [ "${_hostedSys}" = "YES" ]; then
    if [ "${_CUSTOM_CONFIG_SQL}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      # ---------------------------------------------------------------------
      # Reset first: comment out EVERY version-specific logging directive so
      # the file never carries directives from the previously installed
      # Percona version. This is what breaks 5.7 -> 8.0: log_syslog stays
      # enabled and 8.x aborts on the unknown variable.
      # Idempotent: a leading '#' is collapsed, never doubled.
      # ---------------------------------------------------------------------
      sed -i -E \
        -e "s/^#?\s*(log_syslog)/#\1/" \
        -e "s/^#?\s*(log_error)/#\1/" \
        -e "s/^#?\s*(syseventlog)/#\1/" \
        -e "s/^#?\s*(mysqlx)/#\1/" \
        /etc/mysql/my.cnf &> /dev/null

      if [ "${_DB_V}" = "5.7" ]; then
        [ "${_DEBUG_MODE}" = "YES" ] && _msg "DBST: Enable Logging for Percona ${_DB_V}"
        sed -i -E \
          -e "s/^#?\s*(log_syslog)/\1/" \
          /etc/mysql/my.cnf &> /dev/null
      elif [ "${_DB_V}" = "8.0" ]; then
        [ "${_DEBUG_MODE}" = "YES" ] && _msg "DBST: Enable Logging for Percona ${_DB_V}"
        sed -i -E \
          -e "s/^#?\s*(log_error\s)/\1/" \
          -e "s/^#?\s*(log_error_verbosity)/\1/" \
          -e "s/^#?\s*(mysqlx)/\1/" \
          /etc/mysql/my.cnf &> /dev/null
      else
        [ "${_DEBUG_MODE}" = "YES" ] && _msg "DBST: Enable Logging for Percona ${_DB_V}"
        sed -i -E \
          -e "s/^#?\s*(log_error)/\1/" \
          -e "s/^#?\s*(syseventlog)/\1/" \
          -e "s/^#?\s*(mysqlx)/\1/" \
          /etc/mysql/my.cnf &> /dev/null
      fi
      if [ "${_DB_V}" = "8.4" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DBST: Enable legacy mysql_native_password for Percona ${_DB_V}"
        fi
        sed -i -E \
          -e "s/^#?\s*mysql_native_password\s*=.*/mysql_native_password=ON/" \
          -e "s/^(\s*)#\s*(mysql_native_password.*=.*)/\1\2/" \
          /etc/mysql/my.cnf &> /dev/null
      fi
      if [ "${_DB_V}" = "5.7" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DBST: Disable performance_schema for Percona ${_DB_V}"
        fi
        sed -i -E \
          -e "s/^#?\s*performance_schema\s*=.*/performance_schema=OFF/" \
          -e "s/^(\s*)performance_schema_.*=.*/\1#&/" \
          /etc/mysql/my.cnf &> /dev/null
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DBST: Enable performance_schema for Percona ${_DB_V}"
        fi
        sed -i -E \
          -e "s/^#?\s*performance_schema\s*=.*/performance_schema=ON/" \
          -e "s/^(\s*)#\s*(performance_schema_.*=.*)/\1\2/" \
          /etc/mysql/my.cnf &> /dev/null
      fi
      # Reconcile the InnoDB sizing directives with the INSTALLED binary:
      # 5.7 aborts on innodb_redo_log_capacity (an 8.0.30+ variable) and
      # 8.4 aborts on the removed innodb_log_file_size. A half-flipped box
      # (my.cnf written for a target series whose package never landed)
      # must self-heal here so mysqld can start and a retry run can reach
      # the package phase at all. Strip-only: both versions start fine on
      # their defaults; the sizing blocks below restore the tuned values.
      if [ "${_DB_V}" = "5.7" ]; then
        sed -i -E \
          -e "s/^\s*(innodb_redo_log_capacity)/#\1/" \
          /etc/mysql/my.cnf &> /dev/null
      elif [ ! -z "${_DB_V}" ] \
        && [ "${_DB_V}" != "8.0" ] && [ "${_DB_V}" != "8.3" ]; then
        # 8.4 removed innodb_log_file_size outright (8.0/8.3 still accept it
        # deprecated) -- strip it for 8.4 and anything newer. Empty _DB_V
        # (no resolvable binary) must not strip anything.
        sed -i -E \
          -e "s/^\s*(innodb_log_file_size)/#\1/" \
          /etc/mysql/my.cnf &> /dev/null
      fi
      _INNODB_LOG_FILE_SIZE=${_INNODB_LOG_FILE_SIZE//[^0-9]/}
      if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ]; then
        if [ "${_INNODB_LOG_FILE_SIZE}" -ge 50 ]; then
          _INNODB_LOG_FILE_SIZE_MB="${_INNODB_LOG_FILE_SIZE}M"
          _INNODB_REDO_LOG_CAPACITY=$(( _INNODB_LOG_FILE_SIZE * 2 ))
          _INNODB_REDO_LOG_CAPACITY_MB="${_INNODB_REDO_LOG_CAPACITY}M"
          _INNODB_LOG_FILE_SIZE_TEST=$(grep "innodb_log_file_size" \
            ${_vBs}/dragon/t/my.cnf-pre-${_xSrl}-${_X_VERSION}-${_NOW} 2>&1)
          _INNODB_REDO_LOG_CAPACITY_TEST=$(grep "innodb_redo_log_capacity" \
            ${_vBs}/dragon/t/my.cnf-pre-${_xSrl}-${_X_VERSION}-${_NOW} 2>&1)
          if [[ "${_INNODB_LOG_FILE_SIZE_TEST}" =~ "= ${_INNODB_LOG_FILE_SIZE_MB}" ]] \
            && [[ "${_INNODB_REDO_LOG_CAPACITY_TEST}" =~ "= ${_INNODB_REDO_LOG_CAPACITY_MB}" ]]; then
            _INNODB_LOG_FILE_SIZE_SAME=YES
          else
            _INNODB_LOG_FILE_SIZE_SAME=NO
          fi
          if [ -e "/root/.dev.server.cnf" ]; then
            echo "DEBUG5: _INNODB_LOG_FILE_SIZE_TEST is ${_INNODB_LOG_FILE_SIZE_TEST}"
            echo "DEBUG5: _INNODB_REDO_LOG_CAPACITY_TEST is ${_INNODB_REDO_LOG_CAPACITY_TEST}"
            echo "DEBUG5: _INNODB_LOG_FILE_SIZE_MB is ${_INNODB_LOG_FILE_SIZE_MB}"
            echo "DEBUG5: _INNODB_REDO_LOG_CAPACITY_MB is ${_INNODB_REDO_LOG_CAPACITY_MB}"
            echo "DEBUG5: _INNODB_LOG_FILE_SIZE_SAME is ${_INNODB_LOG_FILE_SIZE_SAME}"
          fi
        fi
      fi
      sed -i \
        -e "s/.*slow_query_log/#slow_query_log/g" \
        -e "s/.*long_query_time/#long_query_time/g" \
        -e "s/.*slow_query_log_file/#slow_query_log_file/g" \
        /etc/mysql/my.cnf &> /dev/null
      if [ ! -e "/etc/mysql/skip-name-resolve.txt" ]; then
        sed -i "s/.*skip-name-resolve/#skip-name-resolve/g" /etc/mysql/my.cnf &> /dev/null
      fi
    fi
  fi
  mv -f /etc/mysql/my.cnf-pre* ${_vBs}/dragon/t/ &> /dev/null
  sed -i \
    -e "s/.*default-table-type/#default-table-type/g" \
    -e "s/.*language/#language/g" \
    -e "s/.*innodb_lazy_drop_table.*//g" \
    /etc/mysql/my.cnf &> /dev/null
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ]; then
    if [ "${_DB_BINARY_LOG}" = "NO" ]; then
      # Disable binary logging
      sed -i \
        -e "s/^\s*\(log_bin\s*=.*\)/#\1/" \
        -e "s/^\s*#\s*\(skip-log-bin\)/\1/" \
        -e "s/^\s*\(max_binlog_size\s*=.*\)/#\1/" \
        -e "s/^\s*\(binlog_row_image\s*=.*\)/#\1/" \
        -e "s/^\s*\(binlog_format\s*=.*\)/#\1/" \
        /etc/mysql/my.cnf &> /dev/null
    elif [ "${_DB_BINARY_LOG}" = "YES" ]; then
      # Enable binary logging
      sed -i \
        -e "s/^\s*#\s*\(log_bin\s*=.*\)/\1/" \
        -e "s/^\s*\(skip-log-bin\)/#\1/" \
        -e "s/^\s*#\s*\(max_binlog_size\s*=.*\)/\1/" \
        -e "s/^\s*#\s*\(binlog_row_image\s*=.*\)/\1/" \
        -e "s/^\s*#\s*\(binlog_format\s*=.*\)/\1/" \
        /etc/mysql/my.cnf &> /dev/null
    fi
    if [ "${_CONF_MODE}" != "directives" ] \
      && { [ "${_DB_V}" = "5.7" ] || [ "${_DB_SERIES}" = "5.7" ]; }; then
      if [ -e "/root/.dev.server.cnf" ]; then
        echo "DEBUG6: _DB_SERIES is ${_DB_SERIES}"
        echo "DEBUG6: _DB_V is ${_DB_V}"
        echo "DEBUG6: _SQL_UPGRADE is ${_SQL_UPGRADE}"
        echo "DEBUG6: _INNODB_LOG_FILE_SIZE is ${_INNODB_LOG_FILE_SIZE}"
      fi
      if [ "${_SQL_UPGRADE}" = "NO" ]; then
        if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ] && [ "${_INNODB_LOG_FILE_SIZE}" -ge 50 ]; then
          _INNODB_LOG_FILE_SIZE_MB="${_INNODB_LOG_FILE_SIZE}M"
          _INNODB_LOG_FILE_SIZE_TEST=$(grep "innodb_log_file_size" /etc/mysql/my.cnf 2>&1)
          _INNODB_REDO_LOG_CAPACITY=$(( _INNODB_LOG_FILE_SIZE * 2 ))
          _INNODB_REDO_LOG_CAPACITY_MB="${_INNODB_REDO_LOG_CAPACITY}M"
          if [[ ! "${_INNODB_LOG_FILE_SIZE_TEST}" =~ "= ${_INNODB_LOG_FILE_SIZE_MB}" ]]; then
            if [ "${_INNODB_LOG_FILE_SIZE_SAME}" = "YES" ]; then
              sed -i \
                -e "s/.*innodb_redo_log_capacity.*/#innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}/g" \
                -e "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" \
                /etc/mysql/my.cnf &> /dev/null
              echo "innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}" > /var/log/boa/.my.innodb_log_file_size.txt
            else
              _innodb_log_file_size_update
            fi
          fi
        fi
      fi
    fi
    if [ "${_CONF_MODE}" != "directives" ] \
      && [ "${_DB_V}" != "5.7" ]; then
      if [ -e "/root/.dev.server.cnf" ]; then
        echo "DEBUG7: _DB_SERIES is ${_DB_SERIES}"
        echo "DEBUG7: _DB_V is ${_DB_V}"
        echo "DEBUG7: _SQL_UPGRADE is ${_SQL_UPGRADE}"
        echo "DEBUG7: _INNODB_LOG_FILE_SIZE is ${_INNODB_LOG_FILE_SIZE}"
      fi
      if [ ! -z "${_DB_SERIES}" ] && [ "${_DB_SERIES}" != "5.7" ]; then
        if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ] && [ "${_INNODB_LOG_FILE_SIZE}" -ge 50 ]; then
          _INNODB_LOG_FILE_SIZE_MB="${_INNODB_LOG_FILE_SIZE}M"
          _INNODB_REDO_LOG_CAPACITY=$(( _INNODB_LOG_FILE_SIZE * 2 ))
          _INNODB_REDO_LOG_CAPACITY_MB="${_INNODB_REDO_LOG_CAPACITY}M"
          _INNODB_REDO_LOG_CAPACITY_TEST=$(grep "innodb_redo_log_capacity" /etc/mysql/my.cnf 2>&1)
          if [[ ! "${_INNODB_REDO_LOG_CAPACITY_TEST}" =~ "= ${_INNODB_REDO_LOG_CAPACITY_MB}" ]]; then
            if [ "${_INNODB_LOG_FILE_SIZE_SAME}" = "YES" ]; then
              sed -i \
                -e "s/.*innodb_redo_log_capacity.*/innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}/g" \
                -e "s/.*innodb_log_file_size.*/#innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" \
                /etc/mysql/my.cnf &> /dev/null
              echo "innodb_redo_log_capacity    = ${_INNODB_REDO_LOG_CAPACITY_MB}" > /var/log/boa/.my.innodb_redo_log_capacity.txt
            else
              _innodb_log_file_size_update
            fi
          fi
        fi
      fi
    fi
  fi
}

#
# Refresh only the my.cnf version-compatibility directives (logging, binlog,
# performance_schema, removed options) for the selected Percona version,
# without innodb sizing or restarting mysqld. Called before each mysqld
# (re)start in the staged 5.7->8.0->8.x upgrade so the file never carries a
# directive the target version rejects (e.g. log_syslog) -- the failure mode
# the frequent-update band-aid was meant to cover, done deterministically.
#
_sql_directives_sync() {
  _sql_conf_update directives
}

#
#
_check_mysqld_running() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_mysqld_running"
  fi
  if [ -x "/usr/sbin/aa-teardown" ]; then
    aa-teardown &> /dev/null
  fi
  # Mirrors the doubly-bounded wait in _check_sql_running (kept separate by
  # design -- mirror fixes, don't unify): consecutive-dead cap for a mysqld
  # that died on config/datadir, total-time ceiling for a flapping one, ONE
  # start attempt via the blessed move_sql.sh path gated on no fresh foreign
  # SQL-maintenance marker, and no marker removal on abort (unowned here).
  [ -e "/root/.proxy.cnf" ] && return 0
  local _dead=0
  local _tot=0
  local _started=NO
  while : ; do
    _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
    if [ ! -z "${_IS_MYSQLD_RUNNING}" ] && [ -e "/run/mysqld/mysqld.sock" ]; then
      return 0
    fi
    if [ ! -z "${_IS_MYSQLD_RUNNING}" ]; then
      _dead=0
    else
      _dead=$(( _dead + 1 ))
      if [ "${_started}" = "NO" ] && ! _sql_maint_foreign; then
        _started=YES
        _msg "INFO: MySQLD not running -- starting it..."
        if [ -e "/var/xdrago/move_sql.sh" ]; then
          _mrun "bash /var/xdrago/move_sql.sh start"
        else
          _mrun "service mysql start"
        fi
      fi
    fi
    _tot=$(( _tot + 1 ))
    if [ "${_dead}" -gt 24 ] || [ "${_tot}" -gt 720 ]; then
      _msg "FATAL ERROR: MySQLD did not become available before"
      _msg "FATAL ERROR: _tune_sql_memory_limits (down $(( (_dead - 1) * 5 ))s, total wait $(( (_tot - 1) * 5 ))s)."
      _msg "FATAL ERROR: Check /var/log/mysql/error.log, and on a 5.7 box the"
      _msg "FATAL ERROR: mysqld lines in /var/log/syslog (or /var/log/daemon.log)"
      _msg "FATAL ERROR: instead -- 5.7 is configured with log_syslog, 8.x with"
      _msg "FATAL ERROR: log_error. Fix the reported error and run the upgrade again."
      _clean_pid_exit _check_mysqld_running_dead
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Waiting for MySQLD availability before _tune_sql_memory_limits..."
    fi
    sleep 5
  done
}

#
# Tune memory limits for SQL server.
_tune_sql_memory_limits() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _tune_sql_memory_limits"
  fi
  # The pool budget normally arrives from _sql_pin_overrides; when this
  # function is reached on any other path it falls back to the derived
  # value so the pool and the per-session budgets stay in lock-step.
  if [ -z "${_USE_POOL_SQL}" ]; then
    _USE_POOL_SQL="${_USE_SQL}"
  fi
  if [ -e "/root/.run-to-excalibur.cnf" ] \
    || [ -e "/root/.run-to-daedalus.cnf" ] \
    || [ -e "/root/.run-to-chimaera.cnf" ] \
    || [ -e "/root/.run-to-beowulf.cnf" ]; then
    _DO_NOTHING=YES
  else
    _DO_NOTHING=YES
    _check_mysqld_running
  fi
  if [ ! -e "${_vBs}/dragon/t/my.cnf-pre-${_xSrl}-${_X_VERSION}-${_NOW}" ]; then
    mkdir -p ${_vBs}/dragon/t/
    if [ -e "/etc/mysql/my.cnf" ]; then
      cp -af /etc/mysql/my.cnf ${_vBs}/dragon/t/my.cnf-pre-${_xSrl}-${_X_VERSION}-${_NOW}
    fi
    if [ -e "/root/.dev.server.cnf" ]; then
      echo "DEBUGX: ${_vBs}/dragon/t/my.cnf-pre-${_xSrl}-${_X_VERSION}-${_NOW} created"
    fi
  else
    if [ -e "/root/.dev.server.cnf" ]; then
      echo "DEBUGX: ${_vBs}/dragon/t/my.cnf-pre-${_xSrl}-${_X_VERSION}-${_NOW} exists"
    fi
  fi
  if [ "${_CUSTOM_CONFIG_SQL}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    cp -af ${_locCnf}/var/my.cnf.txt /etc/mysql/my.cnf
  fi
  _INNODB_LOG_FILE_SIZE=$(echo "scale=0; ${_USE_SQL}/4/40*40" | bc 2>&1)
  _DB_COUNT=$(ls /var/lib/mysql/ | wc -l 2>&1)
  if [ "${_DB_COUNT}" -gt 3 ]; then
    if [ "${_INNODB_LOG_FILE_SIZE}" -gt 64 ] \
      && [ "${_INNODB_LOG_FILE_SIZE}" -le 256 ]; then
      _INNODB_LOG_FILE_SIZE=256
    elif [ "${_INNODB_LOG_FILE_SIZE}" -gt 256 ] \
      && [ "${_INNODB_LOG_FILE_SIZE}" -le 512 ]; then
      _INNODB_LOG_FILE_SIZE=512
    elif [ "${_INNODB_LOG_FILE_SIZE}" -gt 512 ] \
      && [ "${_INNODB_LOG_FILE_SIZE}" -le 1024 ]; then
      _INNODB_LOG_FILE_SIZE=1024
    elif [ "${_INNODB_LOG_FILE_SIZE}" -gt 1024 ] \
      && [ "${_INNODB_LOG_FILE_SIZE}" -le 2048 ]; then
      _INNODB_LOG_FILE_SIZE=2048
    elif [ "${_INNODB_LOG_FILE_SIZE}" -gt 2048 ]; then
      _INNODB_LOG_FILE_SIZE=2048
    fi
  fi
  if [ "${_INNODB_LOG_FILE_SIZE}" -le 64 ] \
    || [ -z "${_INNODB_LOG_FILE_SIZE}" ]; then
    _INNODB_LOG_FILE_SIZE=64
  fi
  if [ -e "/etc/mysql/my.cnf" ]; then
    sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${_USE_POOL_SQL}M/g"  /etc/mysql/my.cnf &> /dev/null
  fi
  # An explicit log size pin wins over every derivation arm above. It is
  # deliberately the only way a pool pin can move the redo band: the
  # derived size keeps using the unpinned base, so a pool pin alone
  # never triggers _innodb_log_file_size_update and its mysqld restart.
  if [ -n "${_LOG_FILE_SIZE_PIN}" ]; then
    _INNODB_LOG_FILE_SIZE="${_LOG_FILE_SIZE_PIN}"
  fi
}

_prep_for_install_db_sql() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _prep_for_install_db_sql"
  fi
  if [ -x "/usr/sbin/aa-teardown" ]; then
    aa-teardown &> /dev/null
  fi

  # Create the mysql group if it doesn't exist
  if ! getent group mysql > /dev/null; then
    groupadd mysql
  fi

  # Create the mysql user if it doesn't exist
  if ! id -u mysql > /dev/null 2>&1; then
    useradd -r -g mysql -d /var/lib/mysql -s /bin/false mysql
  fi

  # Create the directory if it doesn't exist
  [ ! -e "/var/lib/mysql" ] && mkdir -p /var/lib/mysql

  # Set ownership to mysql:mysql
  [ -e "/var/lib/mysql" ] && chown mysql:mysql /var/lib/mysql

  _SQL_SCR=APT
  if [ "${_OS_CODE}" = "excalibur" ]; then
    _SQL_OS_CODE=trixie
  elif [ "${_OS_CODE}" = "daedalus" ]; then
    _SQL_OS_CODE=bookworm
  elif [ "${_OS_CODE}" = "chimaera" ]; then
    _SQL_OS_CODE=bullseye
  elif [ "${_OS_CODE}" = "beowulf" ]; then
    _SQL_OS_CODE=buster
  else
    _SQL_OS_CODE="${_OS_CODE}"
  fi
  if [ "${_SQL_OS_CODE}" = "trixie" ]; then
    _SQL_SCR=APT
  fi
  # Server binary first (--no-defaults so a rejected my.cnf directive cannot
  # kill the probe), client only as fallback: the staging and reinstall
  # decisions must follow the binary that owns the datadir, not a client a
  # partial apt transaction may already have advanced.
  _NOW_DB_V=
  if [ -x "/usr/sbin/mysqld" ]; then
    _NOW_DB_V=$(/usr/sbin/mysqld --no-defaults -V 2>&1 \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -1 \
      | cut -d"." -f1,2)
  fi
  _DBS_TEST="$(which mysql)"
  if [ -z "${_NOW_DB_V}" ] && [ ! -z "${_DBS_TEST}" ]; then
    _NOW_DB_V=$(mysql -V 2>&1 \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -1 \
      | cut -d"." -f1,2)
  fi
  if [ -e "/usr/bin/php" ]; then
    _PHP_MYSQLND_TEST=$(/usr/bin/php -i | grep "with-mysqli=mysqlnd" 2>&1)
    if [ -z "${_PHP_MYSQLND_TEST}" ]; then
      _SQL_MAJOR_UP_ALLOW=NO
    else
      _SQL_MAJOR_UP_ALLOW=YES
    fi
  else
    _SQL_MAJOR_UP_ALLOW=YES
  fi
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  cd /var/opt

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Installing dirmngr..."
  fi
  for _PKG in dirmngr; do
    if ! _pkg_installed "${_PKG}"; then
      _mrun "${_INSTAPP} ${_PKG}"
    fi
  done

  _msg "INFO: Installing ${_DB_SERVER} ${_DBS_VRN} in ${_OS_DIST}/${_OS_CODE}"

  ### Update keyring and apt if needed
  _if_sql_keyring_apt_update

  ### Only supported upgrade path allowed
  _sql_strict_upgrade_path

  _check_mysql_version

  if [ "${_DB_SERIES}" = "${_DB_V}" ]; then
    if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      sed -i "s/.*innodb_force_recovery.*/innodb_force_recovery = 3/g" /etc/mysql/my.cnf &> /dev/null
    fi
  fi

  if [ "${_DB_SERIES}" = "${_DB_V}" ]; then
    if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
      mkdir -p ${_vBs}/old-sql-ib-log-${_NOW}
      sleep 1
      mv -f /var/lib/mysql/ib_logfile0 ${_vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      mv -f /var/lib/mysql/ib_logfile1 ${_vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      mv -f /var/lib/mysql/aria_log.00000001 ${_vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      mv -f /var/lib/mysql/aria_log_control ${_vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      sed -i "s/.*innodb-defragment.*/innodb_force_recovery = 3/g" /etc/mysql/my.cnf &> /dev/null
      sed -i "s/^thread_concurrency.*//g" /etc/mysql/my.cnf &> /dev/null
    fi
  fi

  if [ "${_DB_SERIES}" = "5.7" ]; then
    _SQLDEB="percona-server-server-${_DB_SERIES}"
  else
    _SQLDEB="percona-server-server"
  fi

  if [ "${_DB_SERVER}" = "MySQL" ]; then
    _SQLDEB="mysql-server"
  fi

  _SQLXTR="libdbi-perl"

  if [ "${_DB_SERIES}" = "5.7" ]; then
    _SQLADD="libperconaserverclient20 libperconaserverclient20-dev"
  elif [ "${_DB_SERIES}" = "8.0" ]; then
    _SQLADD="libperconaserverclient21 libperconaserverclient21-dev"
  else
    _SQLADD="libperconaserverclient24 libperconaserverclient24-dev"
  fi

  if [ "${_OS_CODE}" = "excalibur" ] || [ "${_DB_SERIES}" = "8.4" ]; then
    _SQLADD="${_SQLADD} percona-telemetry-agent"
  fi

  if [ "${_DB_SERVER}" = "MySQL" ]; then
    _SQLADD="libmysqlclient24"
  fi

}

#
# Fetch one archived Percona .deb.gz plus its .sha256 sidecar from the BOA dev
# mirror, verify the checksum of the COMPRESSED file (the sidecar hashes the
# .gz, so the check runs before gunzip), then gunzip in place -- leaving the
# plain .deb in the current dir. Same _crlGet/_urlDev fetch + sha256sum -c
# verify idiom as _install_boa_deb, so no new curl flags reach the shared
# fetch path (the fleet still has curl older than the flags a rewrite would
# add). Returns non-zero on any fetch or integrity failure so the caller never
# installs an unverified package.
_fetch_archived_sql_deb() {
  local _debFile="${1}"
  local _debSum=""
  [[ -z "${_debFile}" ]] && return 1
  rm -f "${_debFile}" "${_debFile}.gz" "${_debFile}.gz.sha256"
  if ! curl ${_crlGet} "${_urlDev}/${_debFile}.gz.sha256" -o "${_debFile}.gz.sha256"; then
    _msg "NOTE: Fetch of archived ${_debFile}.gz.sha256 failed"
    rm -f "${_debFile}.gz.sha256"
    return 1
  fi
  if ! curl ${_crlGet} "${_urlDev}/${_debFile}.gz" -o "${_debFile}.gz"; then
    _msg "NOTE: Fetch of archived ${_debFile}.gz failed"
    rm -f "${_debFile}.gz" "${_debFile}.gz.sha256"
    return 1
  fi
  _debSum=$(awk '{print $1}' "${_debFile}.gz.sha256" 2>/dev/null)
  if [[ -z "${_debSum}" ]] \
    || ! echo "${_debSum}  ${_debFile}.gz" | sha256sum -c - &> /dev/null; then
    _msg "NOTE: Checksum mismatch on archived ${_debFile}.gz"
    rm -f "${_debFile}.gz" "${_debFile}.gz.sha256"
    return 1
  fi
  if ! gunzip -q "${_debFile}.gz"; then
    _msg "NOTE: Decompression of archived ${_debFile}.gz failed"
    rm -f "${_debFile}" "${_debFile}.gz" "${_debFile}.gz.sha256"
    return 1
  fi
  rm -f "${_debFile}.gz.sha256"
  return 0
}

#
# Mirror fallback for the archived Percona 5.7 package set.
#
# Percona 5.7 is EOL upstream. Its apt suite is frozen but still served, and
# the normal fresh-install path takes 5.7 straight from repo.percona.com; this
# function is insurance for the day that stops being true, not a workaround for
# a present outage. It also covers any local reason apt delivers nothing at all
# (network, DNS, keyring), because the symptom is identical either way: the apt
# attempts in _install_with_aptitude_sql return no package, _mrun swallows the
# "no installation candidate" error, and the install would otherwise wedge
# forever in the _check_sql_running WAIT loop. BOA keeps the frozen 5.7 debs on
# its own static /dev/ mirror; fetch, verify and install them from there so a
# fresh 5.7 install survives whatever kept apt from delivering. The distro-lib
# Depends (libaio1, libnuma1, libdbi-perl ...) come from the OS repos via the
# trailing apt-get install -f, so they are unaffected regardless. Idempotent:
# no-ops when the server package is already installed -- which is the normal
# case -- and leaves nothing half-fetched behind on failure so the caller's
# fail-fast fires cleanly.
_db_server_mirror_fallback_57() {
  if [[ "${_DEBUG_MODE}" = "YES" ]]; then
    _msg "PROC: _db_server_mirror_fallback_57"
  fi
  local _dbVrn="5.7.44-48-1"
  local _dbPkg=""
  local _debFile=""
  local _debSet=""
  # Dependency-safe order: common, the two client libs, client, then server.
  # A single dpkg -i of the whole set lets dpkg configure them in Depends
  # order regardless of the order they are listed here.
  local _dbPkgs="percona-server-common-5.7 libperconaserverclient20 libperconaserverclient20-dev percona-server-client-5.7 percona-server-server-5.7"
  if _pkg_installed "percona-server-server-5.7"; then
    return 0
  fi
  _msg "NOTE: Percona 5.7 apt repository did not deliver percona-server-server-5.7"
  _msg "INFO: Installing archived Percona 5.7 packages from the BOA mirror..."
  # The set Pre-Depends on mysql-common and debsums (dpkg -i cannot satisfy a
  # missing Pre-Depends and the whole chain collapses to removal on apt -f),
  # and the -dev lib needs zlib1g-dev. All three are distro packages, still
  # reachable with the Percona repo dead; the rest of the Depends chain is
  # completed by the trailing apt-get install -f. Harness-proven on a bare
  # bookworm base.
  _mrun "apt-get install ${_aptYesUnth} mysql-common debsums zlib1g-dev"
  mkdir -p /var/opt
  cd /var/opt
  for _dbPkg in ${_dbPkgs}; do
    _debFile="${_dbPkg}_${_dbVrn}.${_SQL_OS_CODE}_amd64.deb"
    if ! _fetch_archived_sql_deb "${_debFile}"; then
      _msg "NOTE: Archived Percona 5.7 mirror fetch failed for ${_dbPkg}"
      [[ -n "${_debSet}" ]] && rm -f ${_debSet}
      return 1
    fi
    _debSet="${_debSet} ${_debFile}"
  done
  # dpkg -i the whole set at once (dpkg orders configuration by Depends), then
  # apt-get install -f pulls the distro-lib Depends from the OS repos. The
  # authoritative success signal is the _pkg_installed re-check below, not the
  # dpkg exit code, so a first-pass unmet-Depends dpkg return is expected.
  dpkg -i ${_debSet} &> /dev/null
  _mrun "apt-get install -f ${_aptYesUnth}"
  rm -f ${_debSet}
  ldconfig 2> /dev/null
  if _pkg_installed "percona-server-server-5.7"; then
    _msg "INFO: Archived Percona 5.7 packages installed from the BOA mirror"
    return 0
  fi
  _msg "NOTE: Archived Percona 5.7 install from the BOA mirror did not complete"
  return 1
}

_install_with_aptitude_sql() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_with_aptitude_sql"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Installing ${_DB_SERVER}..."
  fi
  # The Percona package install stops the old mysqld and starts the new one
  # (a 5.7->8.0 major upgrade also runs the data-dictionary upgrade at that
  # start). Throughout this window mysqld is intermittently down. The
  # cron-launched mysql.sh watchdog would see it down and start a COMPETING
  # mysqld -> the two race for the datadir -> "InnoDB: Unable to lock ./ibdata1
  # error: 11", the DD upgrade aborts, and the watchdog then crash-loops
  # restarting it (observed on a fast box). Hold the SQL-maintenance marker so
  # the watchdog stands down ENTIRELY for the whole install/upgrade (not just
  # its restart branch). Cleared at function exit; /run is tmpfs and the
  # watchdog self-ignores a stale marker, so a crash can never wedge it.
  echo "$$" > /run/boa_sql_maintenance.pid
  _prep_for_install_db_sql
  if [ "${_SQL_SCR}" = "APT" ]; then
    _mrun "${_INSTAPP} ${_SQLDEB}"
    _mrun "${_INSTAPP} ${_SQLADD}"
    _mrun "${_INSTAPP} ${_SQLXTR}"
    _mrun "${_INSTAPP} ${_SQLDEB}"
  elif [ "${_SQL_SCR}" = "DPKG" ]; then
    _dpkg_install_mysql
    _mrun "${_INSTAPP} ${_SQLXTR}"
  fi
  # Archived Percona 5.7 mirror fallback + loud fail-fast. Scoped to the fresh
  # 5.7/bookworm Percona apt path only: 8.x, excalibur, MySQL and the DPKG
  # branch are untouched, and an upgrade run with 5.7 already installed skips
  # both the fallback (idempotent) and the abort -- the normal case, since
  # repo.percona.com still serves the frozen 5.7 suite. Should the apt attempts
  # above ever deliver nothing (_mrun hides the "no installation candidate"
  # error), recover from BOA's own archived-deb mirror. If even that fails,
  # abort here -- before any _check_sql_running is reached -- with a clear
  # reason, rather than hang forever in the WAIT-for-MySQLD loop.
  if [[ "${_DB_SERIES}" = "5.7" ]] \
    && [[ "${_SQL_OS_CODE}" = "bookworm" ]] \
    && [[ "${_DB_SERVER}" = "Percona" ]]; then
    if ! _pkg_installed "${_SQLDEB}"; then
      _db_server_mirror_fallback_57
    fi
    if ! _pkg_installed "${_SQLDEB}"; then
      _msg "FATAL ERROR: No ${_DB_SERVER} 5.7 database server package could be installed."
      _msg "FATAL ERROR: Neither the Percona 5.7 apt repository (repo.percona.com) nor the"
      _msg "FATAL ERROR: BOA archived-deb mirror fallback delivered it. Aborting the install"
      _msg "FATAL ERROR: now instead of waiting forever for a MySQLD that can never start."
      _msg "FATAL ERROR: Check network, DNS and apt keyring access to both repo.percona.com"
      _msg "FATAL ERROR: and the BOA mirrors (${_urlDev}), then run the install again."
      rm -f /run/boa_sql_maintenance.pid
      _clean_pid_exit _db_server_install_5_7_unavailable
    fi
  fi
  # Fail-closed for EVERY series on the apt path: after the attempts above
  # the target server package must be fully installed AND at the target
  # series (_SQLDEB is the unversioned percona-server-server for all 8.x, so
  # the name alone would pass an 8.0->8.4 leg that delivered nothing; _mrun
  # swallows the installer's exit code by design). Abort loudly here --
  # before any _check_sql_running or my.cnf tuning -- so a died package
  # phase can never leave a half-flipped box waiting forever for a MySQLD
  # that cannot exist. Live-hit 2026-08-12: an aptfast scratch-file denial
  # killed a 5.7->8.0 leg silently and the run continued into exactly the
  # wedge this guard prevents.
  if [ "${_SQL_SCR}" = "APT" ] && [ "${_DB_SERVER}" = "Percona" ]; then
    local _SQLDEB_VRN=$(dpkg-query -W -f='${Version}' "${_SQLDEB}" 2>/dev/null)
    if ! _pkg_installed "${_SQLDEB}" \
      || [[ ! "${_SQLDEB_VRN}" =~ (^)"${_DB_SERIES}" ]]; then
      _msg "FATAL ERROR: ${_DB_SERVER} server package ${_SQLDEB} is not fully"
      _msg "FATAL ERROR: installed at the ${_DB_SERIES} series after the package"
      _msg "FATAL ERROR: install phase. Observed dpkg state:"
      _msg "FATAL ERROR: $(dpkg-query -W -f='${Package} ${Status} ${Version}\n' 'percona-server-server*' 2>/dev/null | tr '\n' ';')"
      _msg "FATAL ERROR: Aborting now, before any config tuning by this run."
      _msg "FATAL ERROR: Check the apt errors in the log, then run the upgrade again."
      rm -f /run/boa_sql_maintenance.pid
      _clean_pid_exit _db_server_install_pkg_missing
    fi
  fi
  if [ -x "/usr/sbin/aa-teardown" ]; then
    aa-teardown &> /dev/null
  fi
  if [ "${_DB_SERVER}" = "Percona" ] \
    && [ "${_SQL_FORCE_REINSTALL}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Running ${_DB_SERVER} tables fix, check and upgrade..."
    fi
    _check_mysql_version
    _sql_directives_sync
    # mysql_native_password=ON (and other startup-only options) just written
    # for 8.4 take effect only on a mysqld (re)start. Restart unconditionally
    # so the plugin loads before mysqlcheck/mysql_upgrade and the root
    # credentials update connect as root -- a pgrep guard here raced the
    # package's async start and never fired. _check_sql_running first brings up
    # a down 5.7->8.0 server; the restart then re-reads my.cnf on the running
    # 8.4 server. Mirrors the unconditional restart the fresh-install path does
    # after the same sed. (8.4-only: mysql_native_password is removed in 9.0 --
    # a 9.x bump must switch to caching_sha2_password.)
    _check_sql_running
    _mrun "service mysql restart"
    _check_sql_running
    rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
    _mrun "mysqlcheck -u root -A --auto-repair --silent"
    if [ "${_DB_V}" = "5.7" ]; then
      _mrun "mysql_upgrade -u root --force"
      mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN default_role;" &> /dev/null
      mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN is_role;" &> /dev/null
      mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN max_statement_time;" &> /dev/null
      _mrun "mysql_upgrade -u root --force"
    fi
  fi
  usermod -aG users mysql
  # Upgrade window over: the new server is up and DD-upgraded, so re-arm the
  # mysql.sh watchdog.
  rm -f /run/boa_sql_maintenance.pid
}

#
# Forced MySQL root password update.
_forced_mysql_root_password_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _forced_mysql_root_password_update"
  fi
  mkdir -p ${_vBs}/dragon/config/archive &> /dev/null
  mv -f /root/.my.cnf-pre-* ${_vBs}/dragon/config/archive/ &> /dev/null
  mv -f /root/.my.pass.txt-pre-* ${_vBs}/dragon/config/archive/ &> /dev/null
  touch /root/.my.pass.txt
  chmod 0600 /root/.my.pass.txt &> /dev/null
  _ESC_PASS=""
  _LEN_PASS=0
  _ESC="*.*"
  if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
    _PWD_CHARS=64
  elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
    _PWD_CHARS=32
  else
    _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
    if [ ! -z "${_STRONG_PASSWORDS}" ] \
      && [ "${_STRONG_PASSWORDS}" -gt 32 ]; then
      _PWD_CHARS="${_STRONG_PASSWORDS}"
    else
      _PWD_CHARS=32
    fi
    if [ ! -z "${_PWD_CHARS}" ] \
      && [ "${_PWD_CHARS}" -gt 128 ]; then
      _PWD_CHARS=128
    fi
  fi
  if [ "${_STRONG_PASSWORDS}" = "YES" ] \
    || [ "${_PWD_CHARS}" -gt 32 ]; then
    if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
      _ESC_PASS="$(openssl rand -base64 64 | tr -d '\n')"
    else
      _RANDPASS_TEST=$(randpass -V 2>&1)
      if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
        _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
      else
        _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
      fi
    fi
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
  fi
  if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt 9 ]; then
    _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
  fi
  if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
    _ROOT_SQL_PASWD=$(cat /root/.my.cluster_root_pwd.txt 2>&1)
    _ROOT_SQL_PASWD=$(echo -n ${_ROOT_SQL_PASWD} | tr -d "\n" 2>&1)
    _ESC_PASS="${_ROOT_SQL_PASWD}"
  fi
  _check_mysql_version
  _sql_directives_sync
  _check_sql_running
  if [ ! -z "${_DB_V}" ] && [ ! -z "${_ESC_PASS}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "DBEF: ${_DB_SERVER} _ESC_PASS ${_ESC_PASS}"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
      if [ "${_SQL_DEBUG_MODE}" = "YES" ]; then
        mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
        mysql -u root -e "SHOW GRANTS FOR 'root'@'::1';"
        if [ "${_DB_V}" = "5.7" ]; then
          mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
        fi
      fi
    fi
    _backup_to_dragon /root/.my.cnf
    _backup_to_dragon /root/.my.pass.txt
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'localhost';"
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'localhost' WITH GRANT OPTION;"
    if [ "${_DB_V}" = "5.7" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "DBST: WITH mysql_native_password BY for Percona ${_DB_V}"
      fi
      mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "DBST: WITH caching_sha2_password BY for Percona ${_DB_V}"
      fi
      mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${_ESC_PASS}';"
    fi
    ### Only groups with real consumers; separators must be empty lines --
    ### a single-space line breaks the mydumper/myloader defaults-file parser.
    echo "[client]" > /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
    echo "" >> /root/.my.cnf
    echo "[mysql]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
    echo "" >> /root/.my.cnf
    echo "[mysqldump]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
    echo "" >> /root/.my.cnf
    echo "[mydumper]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
    echo "" >> /root/.my.cnf
    echo "[myloader]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
    echo "" >> /root/.my.cnf
    chmod 0600 /root/.my.cnf
    echo "db=mysql" > /root/.mytop
    chmod 0600 /root/.mytop
    echo "${_ESC_PASS}" > /root/.my.pass.txt
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1';"
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'::1';"
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'${_MY_OWNIP}';"
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'::1' WITH GRANT OPTION;"
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'${_MY_OWNIP}' WITH GRANT OPTION;"
    if [ "${_DB_V}" = "5.7" ]; then
      mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
      mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
      mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
    else
      mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH caching_sha2_password BY '${_ESC_PASS}';"
      mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH caching_sha2_password BY '${_ESC_PASS}';"
      mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH caching_sha2_password BY '${_ESC_PASS}';"
    fi
    mysqladmin -u root flush-privileges &> /dev/null
    mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG HOSTS" &> /dev/null
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "DAFT: ${_DB_SERVER} _ESC_PASS ${_ESC_PASS}"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
      if [ "${_SQL_DEBUG_MODE}" = "YES" ]; then
        mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
        mysql -u root -e "SHOW GRANTS FOR 'root'@'::1';"
        if [ "${_DB_V}" = "5.7" ]; then
          mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
        fi
      fi
    fi
    echo " "
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
        _msg "INFO: New secure random password for ${_DB_SERVER} generated"
      else
        _msg "INFO: New random password for ${_DB_SERVER} generated"
      fi
    fi
  else
    _msg "CRIT: _ESC_PASS empty or not generated, ignored, no changes"
  fi
}

_db_server_apt_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _db_server_apt_cleanup"
  fi
  [ -e "/etc/apt/sources.list.d/percona-original-release.list.bak" ] && rm -f /etc/apt/sources.list.d/percona-original-release.list.bak
  [ -e "/etc/apt/sources.list.d/percona-original-release.list" ] && rm -f /etc/apt/sources.list.d/percona-original-release.list
  [ -e "/etc/apt/sources.list.d/percona-prel-release.list.bak" ] && rm -f /etc/apt/sources.list.d/percona-prel-release.list.bak
  [ -e "/etc/apt/sources.list.d/percona-prel-release.list" ] && rm -f /etc/apt/sources.list.d/percona-prel-release.list
  [ -e "/etc/apt/sources.list.d/percona-release.list.bak" ] && rm -f /etc/apt/sources.list.d/percona-release.list.bak
  _apt_clean_update
}

_db_server_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _db_server_install"
  fi
  _db_server_apt_cleanup
  _SQL_SCR=APT
  if [ "${_OS_CODE}" = "excalibur" ]; then
    _SQL_OS_CODE=trixie
  elif [ "${_OS_CODE}" = "daedalus" ]; then
    _SQL_OS_CODE=bookworm
  elif [ "${_OS_CODE}" = "chimaera" ]; then
    _SQL_OS_CODE=bullseye
  elif [ "${_OS_CODE}" = "beowulf" ]; then
    _SQL_OS_CODE=buster
  else
    _SQL_OS_CODE="${_OS_CODE}"
  fi
  if [ "${_SQL_OS_CODE}" = "trixie" ]; then
    _SQL_SCR=APT
  fi
  _THIS_DB_PORT=3306
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _db_server_apt_cleanup
    _install_with_aptitude_sql
    _db_server_apt_cleanup
    [ -e "/etc/mysql/my.cnf" ] && mv -f /etc/mysql/my.cnf /var/backups/package.my.cnf
    cp -af ${_locCnf}/var/my.cnf.txt /etc/mysql/my.cnf
    if [ "${_DB_SERIES}" = "8.4" ]; then
      # Enable legacy mysql_native_password for Percona 8.4
      sed -i -E \
        -e "s/^#?\s*mysql_native_password\s*=.*/mysql_native_password=ON/" \
        -e "s/^(\s*)#\s*(mysql_native_password.*=.*)/\1\2/" \
        /etc/mysql/my.cnf &> /dev/null
    fi
    # ---------------------------------------------------------------------
    # Reset first: comment out EVERY version-specific logging directive so
    # the file never carries directives from the previously installed
    # Percona version. This is what breaks 5.7 -> 8.0: log_syslog stays
    # enabled and 8.x aborts on the unknown variable.
    # Idempotent: a leading '#' is collapsed, never doubled.
    # ---------------------------------------------------------------------
    sed -i -E \
      -e "s/^#?\s*(log_syslog)/#\1/" \
      -e "s/^#?\s*(log_error)/#\1/" \
      -e "s/^#?\s*(syseventlog)/#\1/" \
      -e "s/^#?\s*(mysqlx)/#\1/" \
      /etc/mysql/my.cnf &> /dev/null

    if [ "${_DB_SERIES}" = "5.7" ]; then
      [ "${_DEBUG_MODE}" = "YES" ] && _msg "DBST: Enable Logging for Percona ${_DB_SERIES}"
      sed -i -E \
        -e "s/^#?\s*(log_syslog)/\1/" \
        /etc/mysql/my.cnf &> /dev/null
    elif [ "${_DB_SERIES}" = "8.0" ]; then
      [ "${_DEBUG_MODE}" = "YES" ] && _msg "DBST: Enable Logging for Percona ${_DB_SERIES}"
      sed -i -E \
        -e "s/^#?\s*(log_error\s)/\1/" \
        -e "s/^#?\s*(log_error_verbosity)/\1/" \
        -e "s/^#?\s*(mysqlx)/\1/" \
        /etc/mysql/my.cnf &> /dev/null
    else
      [ "${_DEBUG_MODE}" = "YES" ] && _msg "DBST: Enable Logging for Percona ${_DB_SERIES}"
      sed -i -E \
        -e "s/^#?\s*(log_error)/\1/" \
        -e "s/^#?\s*(syseventlog)/\1/" \
        -e "s/^#?\s*(mysqlx)/\1/" \
        /etc/mysql/my.cnf &> /dev/null
    fi
    cp -af ${_locCnf}/var/mysql /etc/init.d/mysql
    chmod 755 /etc/init.d/mysql
    _mrun "update-rc.d mysql defaults"
    _mrun "service mysql restart"
  else
    ###
    ### Update keyring and apt if needed
    _if_sql_keyring_apt_update
    ###
    ### Only supported upgrade path allowed
    _sql_strict_upgrade_path
    ###
    if [ "${_SQL_UPGRADE}" = "YES" ]; then
      _msg "INFO: Running ${_DB_SERVER} upgrade..."
      _msg "WAIT: This may take a while, please wait..."
      if [ "${_DB_SERIES}" != "5.7" ]; then
        bash -c 'echo -e "#!/bin/bash\ntrue" > /bin/systemctl'
        chmod +x /bin/systemctl
        [ -e "${_locCnf}/var/mysql" ] && cp -af ${_locCnf}/var/mysql /etc/init.d/mysql
        chmod 755 /etc/init.d/mysql
        _mrun "update-rc.d mysql defaults"
      fi
      _sql_conf_update
      if [ ! -e "/root/.proxy.cnf" ]; then
        _check_mysql_version
        if [ "${_DB_V}" = "5.7" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Running ${_DB_SERVER} system tables check..."
          fi
          rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
          if [ -x "/usr/bin/mysql_upgrade" ]; then
            _mrun "mysql_upgrade -u root --force"
          fi
        fi
      fi
      _mrun "apt-get autoclean -y"
      _apt_clean_update
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/.*default-table-type/#default-table-type/g" /etc/mysql/my.cnf &> /dev/null
        sed -i "s/.*language/#language/g" /etc/mysql/my.cnf &> /dev/null
      fi
      rm -f /var/lib/mysql/debian-*.flag &> /dev/null
      rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
      _db_server_apt_cleanup
      _install_with_aptitude_sql
      _db_server_apt_cleanup
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/.*innodb_lazy_drop_table.*//g" /etc/mysql/my.cnf &> /dev/null
      fi
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/.*default-table-type/#default-table-type/g" /etc/mysql/my.cnf &> /dev/null
        sed -i "s/.*language/#language/g" /etc/mysql/my.cnf &> /dev/null
      fi
      _CUSTOM_CONFIG_SQL=NO
      sleep 8
      _check_mysql_version
      _sql_directives_sync
      _check_sql_running
      if [ "${_DB_V}" = "5.7" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Running ${_DB_SERVER} system tables (1) upgrade..."
        fi
        rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
        if [ -x "/usr/bin/mysql_upgrade" ]; then
          _mrun "mysql_upgrade -u root --force"
          _mrun "mysql_upgrade -u root --force"
        fi
      fi
      _tune_memory_limits
      _myCnf="/etc/mysql/my.cnf"
      _preCnf="${_vBs}/dragon/t/my.cnf-pre-${_xSrl}-${_X_VERSION}-${_NOW}"
      if [ -f "${_myCnf}" ]; then
        _myCnfUpdate=NO
        _myTopReinstall=NO
        _myRstrd=NO
        if [ ! -f "${_preCnf}" ]; then
          mkdir -p ${_vBs}/dragon/t/
          cp -af ${_myCnf} ${_preCnf}
        fi
        _diffMyTest=$(diff -w -B \
          -I userstat \
          -I innodb_buffer_pool_size \
          -I innodb_buffer_pool_instances \
          -I innodb_page_cleaners \
          -I tmp_table_size \
          -I max_heap_table_size \
          -I myisam_sort_buffer_size \
          -I key_buffer_size \
          -I max_connect_errors ${_myCnf} ${_preCnf} 2>&1)
        if [ -z "${_diffMyTest}" ]; then
          _myCnfUpdate=NO
          _myTopReinstall=NO
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: ${_DB_SERVER} diff0 empty"
          fi
        else
          _myCnfUpdate=YES
          _myTopReinstall=YES
          # _diffMyTest=$(echo -n ${_diffMyTest} | fmt -su -w 2500)
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: ${_DB_SERVER} diff1 ${_diffMyTest}"
          fi
        fi
        if [[ "${_diffMyTest}" =~ "innodb_buffer_pool_size" ]]; then
          # Suppress only when the surviving diff carries nothing but
          # ignore-listed knob lines; a mixed hunk keeps its restart for
          # the co-riding knob the -I list does not cover.
          _diffMyOther=$(printf '%s\n' "${_diffMyTest}" \
            | grep -E "^[<>] " \
            | grep -vE "userstat|innodb_buffer_pool_size|innodb_buffer_pool_instances|innodb_page_cleaners|tmp_table_size|max_heap_table_size|myisam_sort_buffer_size|key_buffer_size|max_connect_errors" 2>&1)
          if [ -z "${_diffMyOther}" ]; then
            _myCnfUpdate=NO
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              _msg "INFO: ${_DB_SERVER} diff2 ${_diffMyTest}"
            fi
          fi
        fi
        if [[ "${_diffMyTest}" =~ "No such file or directory" ]]; then
          _myCnfUpdate=NO
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: ${_DB_SERVER} diff3 ${_diffMyTest}"
          fi
        fi
      fi
      if [ ! -e "/root/.run-to-excalibur.cnf" ] \
        && [ ! -e "/root/.run-to-daedalus.cnf" ] \
        && [ ! -e "/root/.run-to-chimaera.cnf" ] \
        && [ ! -e "/root/.run-to-beowulf.cnf" ]; then
        if [ "${_myCnfUpdate}" = "NO" ]; then
          _myUptime=$(mysqladmin -u root version | grep -i uptime 2>&1)
          _myUptime=$(echo -n ${_myUptime} | fmt -su -w 2500 2>&1)
          _msg "INFO: ${_DB_SERVER} ${_myUptime}"
        fi
        if [ "${_myCnfUpdate}" = "YES" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Restarting ${_DB_SERVER} server..."
          fi
          _mrun "bash /var/xdrago/move_sql.sh"
          wait
          _msg "INFO: ${_DB_SERVER} server restart completed"
          _myRstrd=YES
        fi
        _check_mysql_version
        _sql_directives_sync
        _check_sql_running
        if [ "${_DB_V}" = "5.7" ] || [ "${_DB_SERIES}" = "5.7" ]; then
          # Replication standby: mysql.* is replicated content, and the heal
          # below is binlogged DDL (CREATE USER / mysqlcheck / ALTER) that
          # would mint errant own-UUID GTIDs on the replica -- the flush-hosts
          # class. Empty probe = heal skipped; the active runs the same heal
          # and replication carries it. The SET GLOBAL tuning below stays.
          if [ -e "/root/.standby.cnf" ]; then
            _CHECK_EXISTS=""
          else
            _CHECK_EXISTS=$(mysql -u root -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'drandom_2test')" | grep "0" 2>&1)
          fi
          if [[ "${_CHECK_EXISTS}" =~ "0" ]]; then
            _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              echo _CHECK_REPAIR 1 ${_CHECK_REPAIR}
            fi
            if [[ "${_CHECK_REPAIR}" =~ "corrupted" ]]; then
              mysqlcheck -u root -A --auto-repair --silent
              mysql_upgrade -u root --force
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN default_role;"
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN is_role;"
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN max_statement_time;"
              mysql_upgrade -u root --force
            fi
            _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              echo _CHECK_REPAIR 2 ${_CHECK_REPAIR}
            fi
          fi
          mysql -u root -e "SET GLOBAL innodb_flush_log_at_trx_commit=2;" &> /dev/null
          mysql -u root -e "SET GLOBAL innodb_flush_log_at_timeout=1;" &> /dev/null
          mysql -u root -e "SET GLOBAL innodb_stats_on_metadata=0;" &> /dev/null
          rm -f /etc/mysql/conf.d/mysqldump.cnf
        fi
      fi
      [ -e "/bin/systemctl" ] && rm /bin/systemctl
      if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
        _mrun "csf -e"
        _mrun "service lfd start"
        ### Linux kernel TCP SACK CVEs mitigation
        ### CVE-2019-11477 SACK Panic
        ### CVE-2019-11478 SACK Slowness
        ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
        if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
          ### Persist the rules via csfpost.sh so csf -r cannot flush them;
          ### the appended lines use POSIX redirects only (csfpost.sh runs
          ### under sh). Gated on -x so the fresh-install csfpost.sh seeding
          ### block in BOA.sh.txt (gated on ! -x) is never preempted.
          if [ -x "/etc/csf/csfpost.sh" ] \
            && ! grep -q "BOA-SACK-MITIGATION" /etc/csf/csfpost.sh; then
            echo "### BOA-SACK-MITIGATION begin (CVE-2019-11477/78/79) do not edit" >> /etc/csf/csfpost.sh
            echo "sysctl net.ipv4.tcp_mtu_probing=0 >/dev/null 2>&1" >> /etc/csf/csfpost.sh
            echo "iptables -C INPUT -p tcp -m tcpmss --mss 1:500 -j DROP >/dev/null 2>&1 || iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP" >> /etc/csf/csfpost.sh
            echo "ip6tables -C INPUT -p tcp -m tcpmss --mss 1:500 -j DROP >/dev/null 2>&1 || ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP" >> /etc/csf/csfpost.sh
            echo "### BOA-SACK-MITIGATION end" >> /etc/csf/csfpost.sh
          fi
          _SACK_TEST=$(ip6tables --list | grep tcpmss)
          if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
            sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
            iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
            ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
            [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
          fi
        fi
      fi
    fi
  fi
}

_init_sql_root_credentials() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _init_sql_root_credentials"
  fi
  if [ ! -e "/root/.my.pass.txt" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Generating random password for ${_DB_SERVER}"
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Using default dummy password for ${_DB_SERVER}"
      fi
    fi
    touch /root/.my.pass.txt
    chmod 0600 /root/.my.pass.txt &> /dev/null
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_PASS=""
      _LEN_PASS=0
      if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
        _PWD_CHARS=64
      elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
        _PWD_CHARS=32
      else
        _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
        if [ ! -z "${_STRONG_PASSWORDS}" ] \
          && [ "${_STRONG_PASSWORDS}" -gt 32 ]; then
          _PWD_CHARS="${_STRONG_PASSWORDS}"
        else
          _PWD_CHARS=32
        fi
        if [ ! -z "${_PWD_CHARS}" ] \
          && [ "${_PWD_CHARS}" -gt 128 ]; then
          _PWD_CHARS=128
        fi
      fi
      if [ "${_STRONG_PASSWORDS}" = "YES" ] \
        || [ "${_PWD_CHARS}" -gt 32 ]; then
        if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
          _ESC_PASS="$(openssl rand -base64 64 | tr -d '\n')"
        else
          _RANDPASS_TEST=$(randpass -V 2>&1)
          if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
            _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
          else
            _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
            _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
            _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
          fi
        fi
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
      fi
      if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt 9 ]; then
        _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
      fi
    else
      _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
    fi
    echo "${_ESC_PASS}" > /root/.my.pass.txt
  fi
  if [ -e "/root/.my.pass.txt" ]; then
    if [ "${_STATUS}" = "INIT" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: New ${_DB_SERVER} root password in /root/.my.pass.txt"
      fi
    fi
  else
    _msg "EXIT on error due to not found file with your ${_DB_SERVER} root password"
    cat <<EOF

    It appears that you don't have required file with your root sql password.
    Create this file first and run this script again:

    echo "your_working_SQL_ROOT_password" > /root/.my.pass.txt
    chmod 0600 /root/.my.pass.txt

EOF
    _msg "EXIT on error due to not found file with your ${_DB_SERVER} root password"
    _clean_pid_exit _init_sql_root_credentials_a
  fi
}

_sql_root_credentials_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sql_root_credentials_update"
  fi
  if [ ! -e "/root/.my.cnf" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: ${_DB_SERVER} final setup"
    fi
    #
    # Let's just do what mysql_secure_installation does,
    # so we can do it non-interactively:
    # - remove anonymous users
    # - remove remote root
    # - remove test database
    # - remove privileges on test database
    # - set auto-generated root password
    # - reload privileges table
    #
    if [ ! -e "/root/.my.pass.txt" ]; then
      _init_sql_root_credentials
    fi
    if [ -e "/root/.my.pass.txt" ]; then
      _check_mysql_version
      _sql_directives_sync
      _check_sql_running
      if [ -z "${_ESC_PASS}" ]; then
        _PXSWD=$(cat /root/.my.pass.txt 2>&1)
      else
        _PXSWD="${_ESC_PASS}"
      fi
      _PASWD=$(echo -n ${_PXSWD} | tr -d "\n" 2>&1)
      _ESC="*.*"
      if [ -z "${_PASWD}" ]; then
        _msg "CRIT: PASWD for ${_DB_SERVER} is empty!"
      elif [ -z "${_DB_V}" ]; then
        _msg "CRIT: _DB_V for ${_DB_SERVER} is empty!"
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DBEF: ${_DB_SERVER} PASWD ${_PASWD}"
          mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
          if [ "${_SQL_DEBUG_MODE}" = "YES" ]; then
            mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
            mysql -u root -e "SHOW GRANTS FOR 'root'@'::1';"
            if [ "${_DB_V}" = "5.7" ]; then
              mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
            fi
          fi
        fi
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'localhost';"
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'localhost' WITH GRANT OPTION;"
        if [ "${_DB_V}" = "5.7" ]; then
          mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${_PASWD}';"
        else
          mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${_PASWD}';"
        fi
        ### Only groups with real consumers; separators must be empty lines --
        ### a single-space line breaks the mydumper/myloader defaults-file parser.
        echo "[client]" > /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${_PASWD}" >> /root/.my.cnf
        echo "" >> /root/.my.cnf
        echo "[mysql]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${_PASWD}" >> /root/.my.cnf
        echo "" >> /root/.my.cnf
        echo "[mysqldump]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${_PASWD}" >> /root/.my.cnf
        echo "" >> /root/.my.cnf
        echo "[mydumper]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${_PASWD}" >> /root/.my.cnf
        echo "" >> /root/.my.cnf
        echo "[myloader]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${_PASWD}" >> /root/.my.cnf
        echo "" >> /root/.my.cnf
        chmod 0600 /root/.my.cnf
        echo "db=mysql" > /root/.mytop
        chmod 0600 /root/.mytop
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1';"
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'::1';"
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'${_MY_OWNIP}';"
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'127.0.0.1' WITH GRANT OPTION;"
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'::1' WITH GRANT OPTION;"
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'${_MY_OWNIP}' WITH GRANT OPTION;"
        if [ "${_DB_V}" = "5.7" ]; then
          mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${_PASWD}';"
          mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH mysql_native_password BY '${_PASWD}';"
          mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH mysql_native_password BY '${_PASWD}';"
        else
          mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH caching_sha2_password BY '${_PASWD}';"
          mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH caching_sha2_password BY '${_PASWD}';"
          mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH caching_sha2_password BY '${_PASWD}';"
        fi
        mysqladmin -u root flush-privileges &> /dev/null
        mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG HOSTS" &> /dev/null
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DAFT: ${_DB_SERVER} PASWD ${_PASWD}"
          mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
          if [ "${_SQL_DEBUG_MODE}" = "YES" ]; then
            mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
            mysql -u root -e "SHOW GRANTS FOR 'root'@'::1';"
            if [ "${_DB_V}" = "5.7" ]; then
              mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
            fi
          fi
        fi
        if [ "${_THIS_DB_HOST}" = "localhost" ] \
          || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
          || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
          echo "skip-name-resolve" > /etc/mysql/skip-name-resolve.txt
        else
          sed -i "s/.*skip-name-resolve/#skip-name-resolve/g" /etc/mysql/my.cnf &> /dev/null
        fi
        mysqladmin -u root flush-privileges &> /dev/null
        mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG HOSTS" &> /dev/null
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Restarting ${_DB_SERVER} server..."
        fi
        _mrun "bash /var/xdrago/move_sql.sh"
        wait
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: ${_DB_SERVER} setup completed"
          _msg "INFO: You can now log in as root by typing just 'mysql'"
        fi
      fi
    fi
  else
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ ! -e "/root/.mysql.no.new.password.cnf" ]; then
        if [ -e "/root/.mysql.yes.new.password.cnf" ] \
          || [ -e "/root/.my.cluster_root_pwd.txt" ]; then
          _forced_mysql_root_password_update
        fi
      fi
    fi
  fi
}
