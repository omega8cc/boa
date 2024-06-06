#
# Fix for SA-CORE-2014-005
fix_core_dgd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_core_dgd"
  fi
  # https://www.drupal.org/SA-CORE-2014-005
  # sed -i "s/^_PERMISSIONS_FIX=.*/_PERMISSIONS_FIX=YES/g" /root/.barracuda.cnf
  if [ -e "/var/xdrago" ] \
    && [ -e "/var/aegir/drush" ] \
    && [ ! -e "${saPatch}" ]; then
    mkdir -p /var/xdrago/conf
    cp -a ${bldPth}/aegir/patches/7-core/${saCoreS}.patch -o ${saPatch}
  fi
  if [ -e "/var/xdrago" ] \
    && [ -e "/var/aegir/drush" ] \
    && [ -e "${saPatch}" ] \
    && [ ! -e "${pthLog}/${saCoreN}-fixed-d7.log" ]; then
    if [ -d "/data/all/000/core" ]; then
      for Core in `find /data/all/000/core/drupal-7* \
        -maxdepth 0 -mindepth 0 | sort`; do
        cd ${Core}
        patch -p1 < ${saPatch} &> /dev/null
      done
    elif [ -d "/data/disk/all/000/core" ]; then
      for Core in `find /data/disk/all/000/core/drupal-7* \
        -maxdepth 0 -mindepth 0 | sort`; do
        cd ${Core}
        patch -p1 < ${saPatch} &> /dev/null
      done
    fi
    touch ${pthLog}/${saCoreN}-fixed-d7.log
    cd
  fi
  # https://www.drupal.org/SA-CORE-2014-005 for ancient platforms
  if [ -e "/var/xdrago" ] \
    && [ -e "/var/aegir/drush" ] \
    && [ -e "${saPatch}" ]; then
    if [ -d "/data/all" ] \
      && [ ! -e "${pthLog}/legacy-${saCoreN}-fixed-d7.log" ]; then
      for File in `find /data/all/*/*/${saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        Core=$(echo $File \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${Core}" ] && [ ! -e "${Core}/core" ]; then
          cd ${Core}
          patch -p1 < ${saPatch} &> /dev/null
        fi
      done
      touch ${pthLog}/legacy-${saCoreN}-fixed-d7.log
    elif [ -d "/data/disk/all" ] \
      && [ ! -e "${pthLog}/legacy-${saCoreN}-fixed-d7eee.log" ]; then
      for File in `find /data/disk/all/*/*/${saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        Core=$(echo $File \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${Core}" ] && [ ! -e "${Core}/core" ]; then
          cd ${Core}
          patch -p1 < ${saPatch} &> /dev/null
        fi
      done
      touch ${pthLog}/legacy-${saCoreN}-fixed-d7eee.log
    fi
    cd
  fi
  # https://www.drupal.org/SA-CORE-2014-005 for custom platforms
  if [ -e "/var/xdrago" ] \
    && [ -e "/var/aegir/drush" ] \
    && [ -e "${saPatch}" ]; then
    if [ -d "/data/disk" ] \
      && [ ! -e "${pthLog}/batch-custom-${saCoreN}-fixed-d7.log" ]; then
      for File in `find /data/disk/*/static/*/${saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        Core=$(echo $File \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${Core}" ] \
          && [ ! -e "${Core}/core" ] \
          && [ ! -e "${Core}/profiles/${saCoreS}-fix.info" ]; then
          cd ${Core}
          patch -p1 < ${saPatch} &> /dev/null
          echo fixed > ${Core}/profiles/${saCoreS}-fix.info
        fi
      done
      for File in `find /data/disk/*/static/*/*/${saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        Core=$(echo $File \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${Core}" ] \
          && [ ! -e "${Core}/core" ] \
          && [ ! -e "${Core}/profiles/${saCoreS}-fix.info" ]; then
          cd ${Core}
          patch -p1 < ${saPatch} &> /dev/null
          echo fixed > ${Core}/profiles/${saCoreS}-fix.info
        fi
      done
      for File in `find /data/disk/*/static/*/*/*/${saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        Core=$(echo $File \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${Core}" ] \
          && [ ! -e "${Core}/core" ] \
          && [ ! -e "${Core}/profiles/${saCoreS}-fix.info" ]; then
          cd ${Core}
          patch -p1 < ${saPatch} &> /dev/null
          echo fixed > ${Core}/profiles/${saCoreS}-fix.info
        fi
      done
      for File in `find /data/disk/*/static/*/*/*/*/${saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        Core=$(echo $File \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${Core}" ] \
          && [ ! -e "${Core}/core" ] \
          && [ ! -e "${Core}/profiles/${saCoreS}-fix.info" ]; then
          cd ${Core}
          patch -p1 < ${saPatch} &> /dev/null
          echo fixed > ${Core}/profiles/${saCoreS}-fix.info
        fi
      done
      for File in `find /data/disk/*/static/*/*/*/*/*/${saIncDb} \
        -maxdepth 0 -mindepth 0 | sort`; do
        Core=$(echo $File \
          | sed 's/\/includes.*//g' \
          | awk '{print $1}' 2> /dev/null)
        if [ -d "${Core}" ] \
          && [ ! -e "${Core}/core" ] \
          && [ ! -e "${Core}/profiles/${saCoreS}-fix.info" ]; then
          cd ${Core}
          patch -p1 < ${saPatch} &> /dev/null
          echo fixed > ${Core}/profiles/${saCoreS}-fix.info
        fi
      done
    fi
    cd
    touch ${pthLog}/batch-custom-${saCoreN}-fixed-d7.log
  fi
}
# Fix for Postfix configuration.
fix_cnf_postfix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_cnf_postfix"
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
