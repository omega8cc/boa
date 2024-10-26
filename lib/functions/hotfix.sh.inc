#
# Fix for SA-CORE-2014-005
_fix_core_dgd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_core_dgd"
  fi
  # https://www.drupal.org/SA-CORE-2014-005
  # sed -i "s/^_PERMISSIONS_FIX=.*/_PERMISSIONS_FIX=YES/g" /root/.barracuda.cnf
  if [ -e "/var/xdrago" ] \
    && [ -e "/var/aegir/drush" ] \
    && [ ! -e "${_saPatch}" ]; then
    mkdir -p /var/xdrago/conf
    cp -a ${_bldPth}/aegir/patches/7-core/${_saCoreS}.patch -o ${_saPatch}
  fi
  if [ -e "/var/xdrago" ] \
    && [ -e "/var/aegir/drush" ] \
    && [ -e "${_saPatch}" ] \
    && [ ! -e "${_pthLog}/${_saCoreN}-fixed-d7.log" ]; then
    if [ -d "/data/all/000/core" ]; then
      for _Core in `find /data/all/000/core/drupal-7* \
        -maxdepth 0 -mindepth 0 | sort`; do
        cd ${_Core}
        patch -p1 < ${_saPatch} &> /dev/null
      done
    elif [ -d "/data/disk/all/000/core" ]; then
      for _Core in `find /data/disk/all/000/core/drupal-7* \
        -maxdepth 0 -mindepth 0 | sort`; do
        cd ${_Core}
        patch -p1 < ${_saPatch} &> /dev/null
      done
    fi
    touch ${_pthLog}/${_saCoreN}-fixed-d7.log
    cd
  fi
  # https://www.drupal.org/SA-CORE-2014-005 for ancient platforms
  if [ -e "/var/xdrago" ] \
    && [ -e "/var/aegir/drush" ] \
    && [ -e "${_saPatch}" ]; then
    if [ -d "/data/all" ] \
      && [ ! -e "${_pthLog}/legacy-${_saCoreN}-fixed-d7.log" ]; then
      for _File in `find /data/all/*/*/${_saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        _Core=$(echo ${_File} \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${_Core}" ] && [ ! -e "${_Core}/core" ]; then
          cd ${_Core}
          patch -p1 < ${_saPatch} &> /dev/null
        fi
      done
      touch ${_pthLog}/legacy-${_saCoreN}-fixed-d7.log
    elif [ -d "/data/disk/all" ] \
      && [ ! -e "${_pthLog}/legacy-${_saCoreN}-fixed-d7eee.log" ]; then
      for _File in `find /data/disk/all/*/*/${_saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        _Core=$(echo ${_File} \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${_Core}" ] && [ ! -e "${_Core}/core" ]; then
          cd ${_Core}
          patch -p1 < ${_saPatch} &> /dev/null
        fi
      done
      touch ${_pthLog}/legacy-${_saCoreN}-fixed-d7eee.log
    fi
    cd
  fi
  # https://www.drupal.org/SA-CORE-2014-005 for custom platforms
  if [ -e "/var/xdrago" ] \
    && [ -e "/var/aegir/drush" ] \
    && [ -e "${_saPatch}" ]; then
    if [ -d "/data/u" ] \
      && [ ! -e "${_pthLog}/batch-custom-${_saCoreN}-fixed-d7.log" ]; then
      for _File in `find /data/disk/*/static/*/${_saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        _Core=$(echo ${_File} \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${_Core}" ] \
          && [ ! -e "${_Core}/core" ] \
          && [ ! -e "${_Core}/profiles/${_saCoreS}-fix.info" ]; then
          cd ${_Core}
          patch -p1 < ${_saPatch} &> /dev/null
          echo fixed > ${_Core}/profiles/${_saCoreS}-fix.info
        fi
      done
      for _File in `find /data/disk/*/static/*/*/${_saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        _Core=$(echo ${_File} \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${_Core}" ] \
          && [ ! -e "${_Core}/core" ] \
          && [ ! -e "${_Core}/profiles/${_saCoreS}-fix.info" ]; then
          cd ${_Core}
          patch -p1 < ${_saPatch} &> /dev/null
          echo fixed > ${_Core}/profiles/${_saCoreS}-fix.info
        fi
      done
      for _File in `find /data/disk/*/static/*/*/*/${_saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        _Core=$(echo ${_File} \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${_Core}" ] \
          && [ ! -e "${_Core}/core" ] \
          && [ ! -e "${_Core}/profiles/${_saCoreS}-fix.info" ]; then
          cd ${_Core}
          patch -p1 < ${_saPatch} &> /dev/null
          echo fixed > ${_Core}/profiles/${_saCoreS}-fix.info
        fi
      done
      for _File in `find /data/disk/*/static/*/*/*/*/${_saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        _Core=$(echo ${_File} \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${_Core}" ] \
          && [ ! -e "${_Core}/core" ] \
          && [ ! -e "${_Core}/profiles/${_saCoreS}-fix.info" ]; then
          cd ${_Core}
          patch -p1 < ${_saPatch} &> /dev/null
          echo fixed > ${_Core}/profiles/${_saCoreS}-fix.info
        fi
      done
      for _File in `find /data/disk/*/static/*/*/*/*/*/${_saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        _Core=$(echo ${_File} \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${_Core}" ] \
          && [ ! -e "${_Core}/core" ] \
          && [ ! -e "${_Core}/profiles/${_saCoreS}-fix.info" ]; then
          cd ${_Core}
          patch -p1 < ${_saPatch} &> /dev/null
          echo fixed > ${_Core}/profiles/${_saCoreS}-fix.info
        fi
      done
    fi
    cd
    touch ${_pthLog}/batch-custom-${_saCoreN}-fixed-d7.log
  fi
}
# Fix for Postfix configuration.
_fix_cnf_postfix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_cnf_postfix"
  fi
  _RELOAD_POSTFIX=NO
  _INET_TEST=$(grep 'inet_protocols' /etc/postfix/main.cf 2>&1)
  if [[ "${_INET_TEST}" =~ "inet_protocols" ]]; then
    _INET_TEST=$(grep 'inet_protocols = ipv4' /etc/postfix/main.cf 2>&1)
    if [[ "${_INET_TEST}" =~ "ipv4" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/^inet_protocols.*/inet_protocols = ipv4/g" \
        /etc/postfix/main.cf &> /dev/null
      _RELOAD_POSTFIX=YES
    fi
  else
    echo "inet_protocols = ipv4" >> /etc/postfix/main.cf
    _RELOAD_POSTFIX=YES
  fi
  if [ "${_RELOAD_POSTFIX}" = "YES" ]; then
    postfix reload &> /dev/null
  fi
}
