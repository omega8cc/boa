
#
# Disable Redis.
_disable_redis() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _disable_redis"
  fi
  _mrun "service redis-server stop"
  killall -9 redis-server &> /dev/null
  _mrun "update-rc.d -f redis-server remove"
  mv -f /etc/init.d/redis-server /etc/init.d/redis-server-off &> /dev/null
  killall -9 redis-server &> /dev/null
  rm -f /run/redis/redis.pid
  rm -rf /var/lib/redis
  _msg "INFO: Redis server has been disabled"
}
#
# Forced Valkey password update.
_forced_valkey_password_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _forced_valkey_password_update"
  fi
  if [ "${_VALKEY_LISTEN_MODE}" = "SOCKET" ] \
    || [ "${_VALKEY_LISTEN_MODE}" = "PORT" ] \
    || [ "${_VALKEY_LISTEN_MODE}" = "127.0.0.1" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Generating random password for local Valkey server"
    fi
    _ESC_RPASS=""
    _LEN_RPASS=0
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
      if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt 128 ]; then
        _PWD_CHARS=128
      fi
    fi
    if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt 32 ]; then
      _RANDPASS_TEST=$(randpass -V 2>&1)
      if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
        _ESC_RPASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
      else
        _ESC_RPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_RPASS=$(echo -n "${_ESC_RPASS}" | tr -d "\n" 2>&1)
        _ESC_RPASS=$(_sanitize_string "${_ESC_RPASS}" 2>&1)
      fi
      _ESC_RPASS=$(echo -n "${_ESC_RPASS}" | tr -d "\n" 2>&1)
      _LEN_RPASS=$(echo ${#_ESC_RPASS} 2>&1)
    fi
    if [ -z "${_ESC_RPASS}" ] || [ "${_LEN_RPASS}" -lt 9 ]; then
      _ESC_RPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
      _ESC_RPASS=$(echo -n "${_ESC_RPASS}" | tr -d "\n" 2>&1)
      _ESC_RPASS=$(_sanitize_string "${_ESC_RPASS}" 2>&1)
    fi
  else
    _msg "INFO: Managing password for remote Valkey server"
    if [ -e "/root/.valkey.pass.txt" ] \
      && [ -e "${_pthLog}/remote-valkey-passwd.log" ]; then
      _ESC_RPASS=$(cat /root/.valkey.pass.txt 2>/dev/null | tr -d '\n')
      _ESC_RPASS=$(_sanitize_string "${_ESC_RPASS}" 2>&1)
    else
      _ESC_RPASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      touch ${_pthLog}/remote-valkey-passwd.log
    fi
  fi
  echo "${_ESC_RPASS}" > /root/.valkey.pass.txt
  chmod 0600 /root/.valkey.pass.txt &> /dev/null
  touch ${_pthLog}/sec-valkey-pass-${_xSrl}-${_X_VERSION}-${_NOW}.log
  if [ -e "/etc/valkey/valkey.conf" ]; then
    _FORCE_VALKEY_RESTART=YES
    sed -i "s/^requirepass /# requirepass /g" \
      /etc/valkey/valkey.conf &> /dev/null
    wait
    sed -i "s/^user default on.*/user default on >${_ESC_RPASS} allcommands allkeys/g" \
      /etc/valkey/valkey.conf &> /dev/null
    wait
    chown valkey:valkey /etc/valkey/valkey.conf
    chmod 0600 /etc/valkey/valkey.conf
  fi
  if [ "${_FORCE_VALKEY_RESTART}" = "YES" ]; then
    _mrun "service valkey-server restart"
    wait
  fi
}
#
# Fix Valkey mode.
_fix_valkey_mode() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_valkey_mode"
  fi
  mkdir -p /run/valkey
  chown valkey:valkey /run/valkey
  if [ "${_CUSTOM_CONFIG_VALKEY}" = "NO" ] || [ -z "${_CUSTOM_CONFIG_VALKEY}" ]; then
    _VALKEY_LISTEN_MODE=SOCKET
    if [ "${_VALKEY_LISTEN_MODE}" = "SOCKET" ]; then
      if [ -e "/data/conf/global/global-redis.inc" ]; then
        sed -i "s/redis_client_host/redis_client_socket/g" /data/conf/global/global-redis.inc &> /dev/null
        wait
        sed -i "s/'host'/'socket'/g" /data/conf/global/global-redis.inc &> /dev/null
        wait
        sed -i "s/  = '127.0.0.1';/= '\/var\/run\/valkey\/valkey.sock';/g" /data/conf/global/global-redis.inc &> /dev/null
        wait
      fi
      if [ -e "/data/conf/global.inc" ]; then
        sed -i "s/redis_client_host/redis_client_socket/g" /data/conf/global.inc &> /dev/null
        wait
        sed -i "s/'host'/'socket'/g" /data/conf/global.inc &> /dev/null
        wait
        sed -i "s/  = '127.0.0.1';/= '\/var\/run\/valkey\/valkey.sock';/g" /data/conf/global.inc &> /dev/null
        wait
      fi
      sed -i "s/^port 0/port 6379/g" /etc/valkey/valkey.conf &> /dev/null
      wait
      sed -i "s/^# bind 127.0.0.1/bind 127.0.0.1/g" /etc/valkey/valkey.conf &> /dev/null
      wait
      sed -i "s/^# unixsocket/unixsocket/g" /etc/valkey/valkey.conf &> /dev/null
      wait
    elif [ "${_VALKEY_LISTEN_MODE}" = "PORT" ] \
      || [ "${_VALKEY_LISTEN_MODE}" = "127.0.0.1" ]; then
      _DO_NOTHING=YES
    else
      _VALKEY_LISTEN_MODE=${_VALKEY_LISTEN_MODE//[^0-9.]/}
      if [ ! -z "${_VALKEY_LISTEN_MODE}" ]; then
        _find_correct_ip
        _LOCAL_VALKEY_PORT_TEST="${_LOC_IP}"
        if [ "${_LOCAL_VALKEY_PORT_TEST}" = "${_VALKEY_LISTEN_MODE}" ]; then
          _VALKEY_HOST=LOCAL
        else
          _VALKEY_HOST=REMOTE
        fi
        if [[ "${_VALKEY_LISTEN_MODE}" =~ (^)"10." ]] \
          || [[ "${_VALKEY_LISTEN_MODE}" =~ (^)"192.168." ]] \
          || [[ "${_VALKEY_LISTEN_MODE}" =~ (^)"172.16." ]] \
          || [[ "${_VALKEY_LISTEN_MODE}" =~ (^)"127.0." ]]; then
          if [ "${_VALKEY_HOST}" = "LOCAL" ]; then
            sed -i "s/^bind 127.0.0.1/bind ${_VALKEY_LISTEN_MODE}/g" /etc/valkey/valkey.conf &> /dev/null
            wait
            if [ -e "/data/conf/global/global-redis.inc" ]; then
              sed -i "s/'127.0.0.1'/'${_VALKEY_LISTEN_MODE}'/g" /data/conf/global/global-redis.inc &> /dev/null
              wait
            fi
            if [ -e "/data/conf/global.inc" ]; then
              sed -i "s/'127.0.0.1'/'${_VALKEY_LISTEN_MODE}'/g" /data/conf/global.inc &> /dev/null
              wait
            fi
          else
            if [ -e "/data/conf/global/global-redis.inc" ]; then
              sed -i "s/'127.0.0.1'/'${_VALKEY_LISTEN_MODE}'/g" /data/conf/global/global-redis.inc &> /dev/null
              wait
            fi
            if [ -e "/data/conf/global.inc" ]; then
              sed -i "s/'127.0.0.1'/'${_VALKEY_LISTEN_MODE}'/g" /data/conf/global.inc &> /dev/null
              wait
            fi
            _mrun "service valkey-server stop"
            killall -9 valkey-server &> /dev/null
            rm -rf /var/lib/valkey
            _mrun "update-rc.d -f valkey-server remove"
            mv -f /etc/init.d/valkey-server /etc/init.d/valkey-server-off &> /dev/null
            killall -9 valkey-server &> /dev/null
            rm -f /run/valkey/valkey.pid
            _msg "INFO: Remote Valkey IP set to ${_VALKEY_LISTEN_MODE}"
            _msg "INFO: Local Valkey instance has been disabled"
          fi
        else
          if [ -e "/data/conf/global/global-redis.inc" ]; then
            sed -i "s/'127.0.0.1'/'${_VALKEY_LISTEN_MODE}'/g" /data/conf/global/global-redis.inc &> /dev/null
            wait
          fi
          if [ -e "/data/conf/global.inc" ]; then
            sed -i "s/'127.0.0.1'/'${_VALKEY_LISTEN_MODE}'/g" /data/conf/global.inc &> /dev/null
            wait
          fi
          _mrun "service valkey-server stop"
          killall -9 valkey-server &> /dev/null
          rm -rf /var/lib/valkey
          _mrun "update-rc.d -f valkey-server remove"
          mv -f /etc/init.d/valkey-server /etc/init.d/valkey-server-off &> /dev/null
          killall -9 valkey-server &> /dev/null
          rm -f /run/valkey/valkey.pid
          _msg "INFO: Remote Valkey IP set to ${_VALKEY_LISTEN_MODE}"
          _msg "INFO: Local Valkey instance has been disabled"
        fi
      fi
    fi
  fi
}
#
# Set or update Valkey password.
_valkey_password_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _valkey_password_update"
  fi
  if [ -e "/etc/valkey/valkey.conf" ]; then
    _VALKEY_TEST=$(grep "user default on" /etc/valkey/valkey.conf 2>&1)
    if [ -z "${_VALKEY_TEST}" ] \
      || [ ! -e "${_pthLog}/sec-valkey-pass-${_xSrl}-${_X_VERSION}-${_NOW}.log" ]; then
      if [ ! -e "/root/.valkey.no.new.password.cnf" ] \
        || [ ! -e "/root/.valkey.pass.txt" ]; then
         _forced_valkey_password_update
      fi
    fi
  fi
  if [ -e "/root/.valkey.pass.txt" ] && [ -e "/etc/valkey/valkey.conf" ]; then
    if [ -z "${_ESC_RPASS}" ]; then
      _RPASS=$(cat /root/.valkey.pass.txt 2>/dev/null | tr -d '\n')
    else
      _RPASS="${_ESC_RPASS}"
    fi
    if [ -e "/data/conf/global/global-if-redis.inc" ]; then
      _VALKEY_PWD_TEST=$(grep "'${_RPASS}'" /data/conf/global/global-if-redis.inc 2>&1)
      if [[ "${_VALKEY_PWD_TEST}" =~ "'${_RPASS}'" ]]; then
        _DO_NOTHING=YES
      else
        if [ ! -z "${_RPASS}" ]; then
          mkdir -p /data/conf
          cp -af ${_locCnf}/global/global-if-redis.inc /data/conf/global/global-if-redis.inc
          sed -i "s/isfoobared/${_RPASS}/g" /data/conf/global/global-if-redis.inc &> /dev/null
          wait
        fi
      fi
    fi
    if [ -e "/data/conf/global/global-redis.inc" ]; then
      _VALKEY_PWD_TEST=$(grep "'${_RPASS}'" /data/conf/global/global-redis.inc 2>&1)
      if [[ "${_VALKEY_PWD_TEST}" =~ "'${_RPASS}'" ]]; then
        _DO_NOTHING=YES
      else
        if [ ! -z "${_RPASS}" ]; then
          mkdir -p /data/conf
          cp -af ${_locCnf}/global/global-redis.inc /data/conf/global/global-redis.inc
          sed -i "s/isfoobared/${_RPASS}/g" /data/conf/global/global-redis.inc &> /dev/null
          wait
        fi
      fi
    fi
    if [ -e "/data/conf/global.inc" ]; then
      _VALKEY_PWD_TEST=$(grep "'${_RPASS}'" /data/conf/global.inc 2>&1)
      if [[ "${_VALKEY_PWD_TEST}" =~ "'${_RPASS}'" ]]; then
        _DO_NOTHING=YES
      else
        if [ ! -z "${_RPASS}" ]; then
          mkdir -p /data/conf
          cp -af ${_locCnf}/global/global.inc /data/conf/global.inc
          sed -i "s/isfoobared/${_RPASS}/g" /data/conf/global.inc &> /dev/null
          wait
        fi
      fi
    fi
    if [ -e "${_mtrInc}" ] \
      && [ ! -L "${_mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sfn /data/conf/global.inc ${_mtrInc}/global.inc
    fi
    _fix_valkey_mode
  fi
}
#
# Install Valkey from sources.
_install_valkey_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_valkey_src"
  fi
  _msg "INFO: Installing Valkey ${_VALKEY_VRN}..."
  if [ ! -e "/var/lib/valkey" ]; then
    _mrun "adduser --system --group valkey --home /home/valkey"
  fi
  cd /var/opt
  rm -rf valkey*
  _get_dev_src "valkey-${_VALKEY_VRN}.tar.gz"
  rm -f /usr/local/bin/valkey*
  rm -f /usr/bin/valkey*
  cd valkey-${_VALKEY_VRN}
  _mrun "make -j $(nproc) --quiet"
  _mrun "make --quiet PREFIX=/usr install"
  cp -af ${_locCnf}/valkey/valkey-server /etc/init.d/valkey-server
  chmod 755 /etc/init.d/valkey-server &> /dev/null
  _mrun "update-rc.d valkey-server defaults"
  mkdir -p /run/valkey
  chown -R valkey:valkey /run/valkey
  mkdir -p /var/log/valkey
  chown -R valkey:valkey /var/log/valkey
  mkdir -p /var/lib/valkey
  chown -R valkey:valkey /var/lib/valkey
  rm -f /var/lib/valkey/*
  mkdir -p /etc/valkey
  if [ -e "/etc/valkey/valkey.conf" ] && [ "${_STATUS}" = "UPGRADE" ]; then
    _if_hosted_sys
    if [ "${_CUSTOM_CONFIG_VALKEY}" = "NO" ] \
      || [ -z "${_CUSTOM_CONFIG_VALKEY}" ] \
      || [ "${_hostedSys}" = "YES" ]; then
      if [ "${_CUSTOM_CONFIG_VALKEY}" = "YES" ]; then
        _DO_NOTHING=YES
      else
        if [ "${_VALKEY_INSTALL_MISMATCH}" = "YES" ] \
          || [ ! -e "${_pthLog}/valkey-${_VALKEY_VRN}-${_xSrl}-${_X_VERSION}.log" ]; then
          cp -af ${_locCnf}/valkey/${_valkeyCnfTpl} /etc/valkey/valkey.conf
        fi
      fi
    fi
  else
    if [ ! -e "/etc/valkey/valkey.conf" ] \
      || [ "${_VALKEY_INSTALL_MISMATCH}" = "YES" ] \
      || [ ! -e "${_pthLog}/valkey-${_VALKEY_VRN}-${_xSrl}-${_X_VERSION}.log" ]; then
      cp -af ${_locCnf}/valkey/${_valkeyCnfTpl} /etc/valkey/valkey.conf
    fi
  fi
  _valkey_password_update
  touch ${_pthLog}/valkey-${_VALKEY_VRN}-${_xSrl}-${_X_VERSION}.log
  _disable_redis
  _mrun "service valkey-server restart"
  wait
}

_valkey_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _valkey_install_upgrade"
  fi
  if [ "${_VALKEY_MAJOR_RELEASE}" = "7" ]; then
    _VALKEY_VRN=${_VALKEY_SEVEN_VRN}
    _valkeyCnfTpl="valkey7.conf"
  elif [ "${_VALKEY_MAJOR_RELEASE}" = "8" ]; then
    _VALKEY_VRN=${_VALKEY_EIGHT_VRN}
    _valkeyCnfTpl="valkey8.conf"
  fi
  if [ ! -e "/var/lib/valkey" ]; then
    _mrun "adduser --system --group valkey --home /home/valkey"
  fi
  mkdir -p /run/valkey
  chown -R valkey:valkey /run/valkey
  mkdir -p /var/log/valkey
  chown -R valkey:valkey /var/log/valkey
  mkdir -p /var/lib/valkey
  chown -R valkey:valkey /var/lib/valkey
  if [ "${_STATUS}" = "UPGRADE" ]; then
    _VALKEY_V_ITD=$(valkey-server -v 2>&1 \
      | tr -d "\n" \
      | tr -d "v=" \
      | cut -d" " -f2 \
      | awk '{ print $1}' 2>&1)
    if [ "${_VALKEY_V_ITD}" = "serer" ]; then
      _VALKEY_V_ITD=$(valkey-server -v 2>&1 \
        | tr -d "\n" \
        | tr -d "v=" \
        | cut -d" " -f3 \
        | awk '{ print $1}' 2>&1)
    fi
    if [ "${_VALKEY_V_ITD}" = "${_VALKEY_VRN}" ]; then
      _VALKEY_INSTALL_MISMATCH=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Valkey version ${_VALKEY_V_ITD}, OK"
      fi
    else
      _VALKEY_INSTALL_MISMATCH=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Valkey version ${_VALKEY_V_ITD}, upgrade required"
      fi
    fi
  else
    if [ -x "/usr/bin/valkey-server" ]; then
      _VALKEY_V_ITD=$(valkey-server -v 2>&1 \
        | tr -d "\n" \
        | tr -d "v=" \
        | cut -d" " -f2 \
        | awk '{ print $1}' 2>&1)
      if [ "${_VALKEY_V_ITD}" = "serer" ]; then
        _VALKEY_V_ITD=$(valkey-server -v 2>&1 \
          | tr -d "\n" \
          | tr -d "v=" \
          | cut -d" " -f3 \
          | awk '{ print $1}' 2>&1)
      fi
      if [ "${_VALKEY_V_ITD}" = "${_VALKEY_VRN}" ]; then
        _VALKEY_INSTALL_MISMATCH=NO
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Valkey version ${_VALKEY_V_ITD}, OK"
        fi
      else
        _VALKEY_INSTALL_MISMATCH=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Valkey version ${_VALKEY_V_ITD}, rebuild required"
        fi
      fi
    fi
  fi
  _VALKEY_TEST=$(grep "user default on" /etc/valkey/valkey.conf 2>&1)
  if [ "${_VALKEY_INSTALL_MISMATCH}" = "YES" ] \
    || [ -z "${_VALKEY_TEST}" ] \
    || [ ! -d "/run/valkey" ] \
    || [ ! -x "/usr/bin/valkey-server" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    if [ "${_VALKEY_HOST}" = "LOCAL" ] || [ -z "${_VALKEY_HOST}" ]; then
      _install_valkey_src
    fi
  fi
}

