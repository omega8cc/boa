#
# Update Nginx Config.
_nginx_conf_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_conf_update"
  fi
  if [ ! -e "${_pthLog}/nginx-config-params-fixed-${_xSrl}-${_X_VERSION}.log" ] \
    && [ -d "/var/aegir" ]; then
    if [ -e "${_locCnf}/nginx/nginx.conf" ] \
      && [ -e "/etc/nginx/nginx.conf" ]; then
      mv -f /etc/nginx/nginx.conf-* ${_vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/mime.types-pre-* ${_vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/fastcgi_params-pre-* ${_vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/nginx.conf ${_vBs}/dragon/t/nginx.conf-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
      mv -f /etc/nginx/fastcgi_params ${_vBs}/dragon/t/fastcgi_params-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
      cp -af ${_locCnf}/nginx/nginx.conf /etc/nginx/nginx.conf
      ### The template includes main.d from its main context; the directory
      ### must never lag the line that names it.
      mkdir -p /etc/nginx/main.d
      cp -af ${_locCnf}/nginx/fastcgi_params.txt /etc/nginx/fastcgi_params
      touch ${_pthLog}/nginx-config-params-fixed-${_xSrl}-${_X_VERSION}.log
    fi
  fi
  ### PHP's global.inc believes a remote peer's client address only on
  ### nginx's word (BOA_NGINX_CLIENT). A box whose fastcgi_params predate
  ### that param takes the current file now, not at the next version change.
  if [ -e "${_locCnf}/nginx/fastcgi_params.txt" ] \
    && [ -e "/etc/nginx/fastcgi_params" ] \
    && grep -q BOA_NGINX_CLIENT "${_locCnf}/nginx/fastcgi_params.txt" \
    && ! grep -q BOA_NGINX_CLIENT /etc/nginx/fastcgi_params; then
    mkdir -p ${_vBs}/dragon/t
    cp -af /etc/nginx/fastcgi_params ${_vBs}/dragon/t/fastcgi_params-pre-client-${_NOW}
    cp -af ${_locCnf}/nginx/fastcgi_params.txt /etc/nginx/fastcgi_params
  fi
  if [ -e "${_mtrNgx}/pre.d/nginx_speed_purge.conf" ]; then
    rm -f ${_mtrNgx}/pre.d/nginx_speed_purge.conf
  fi
}

#
# Sub Force advanced Nginx configuration.
_sub_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sub_force_advanced_nginx_config"
  fi
  if [ -e "/opt/php${_PHP_SV}/etc/php${_PHP_SV}-fpm.conf" ]; then
    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${_mtrInc}/nginx_compact_include.conf &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${_mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${_mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${_mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${_mtrInc}/nginx_vhost_common.conf &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${_mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${_mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${_mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${_mtrTpl}/subdir.tpl.php &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${_mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${_mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${_mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${_mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
  fi
}

#
# Force advanced Nginx configuration.
_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _force_advanced_nginx_config"
  fi
  if [ ! -e "/etc/ssl/private/nginx-wild-ssl.dhp" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Generating DH parameters, 2048 bit..."
    fi
    _mrun "openssl dhparam -out /etc/ssl/private/nginx-wild-ssl.dhp 2048"
    wait
  fi
  cp -af ${_locCnf}/nginx/nginx_compact_include.conf ${_mtrInc}/nginx_compact_include.conf
  _validate_local_ip &> /dev/null
  _sub_force_advanced_nginx_config
  sed -i "s/ 90;/ 180;/g" ${_mtrNgx}/pre.d/*.conf &> /dev/null
  wait
  if [ "${_NGINX_SPDY}" = "YES" ]; then
    sed -i "s/:443;/:443 ssl;/g" ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/:443;/:443 ssl;/g" ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
    sed -i "s/:443 ssl spdy;/:443 ssl;/g" ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/:443 ssl spdy;/:443 ssl;/g" ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
    sed -i "s/:443 ssl http2;/:443 ssl;/g" ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/:443 ssl http2;/:443 ssl;/g" ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
  fi
  if [ -e "/root/.install.modern.openssl.cnf" ] \
    && [ -x "/usr/local/ssl3/bin/openssl" ]; then
    _SSL_BINARY=/usr/local/ssl3/bin/openssl
  else
    _SSL_BINARY=/usr/local/ssl/bin/openssl
  fi
  _SSL_ITD=$(${_SSL_BINARY} version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_SSL_ITD}" = "${_OPENSSL_MODERN_VRN}" ] \
    || [ "${_SSL_ITD}" = "${_OPENSSL_EOL_VRN}" ] \
    || [ "${_SSL_ITD}" = "${_OPENSSL_LEGACY_VRN}" ] \
    || [[ "${_SSL_ITD}" =~ "1.1.0" ]] \
    || [[ "${_SSL_ITD}" =~ "1.0.2" ]] \
    || [[ "${_SSL_ITD}" =~ "1.0.1" ]]; then
    _PFS_READY=YES
  else
    _PFS_READY=NO
  fi
  if [ "${_PFS_READY}" = "YES" ] \
    && [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    _ALLOW_NGINX_FORWARD_SECRECY=YES
    _SSL_PROTOCOLS="TLSv1.2 TLSv1.3;"
    _SSL_CIPHERS="TLS_AES_128_GCM_SHA256:  \
      TLS_AES_256_GCM_SHA384:  \
      TLS_CHACHA20_POLY1305_SHA256:  \
      ECDHE-RSA-AES256-GCM-SHA384:  \
      ECDHE-ECDSA-AES256-GCM-SHA384:  \
      ECDHE-RSA-AES256-SHA384:  \
      ECDHE-ECDSA-AES256-SHA384:  \
      AES256-GCM-SHA384:  \
      ECDHE-ECDSA-CHACHA20-POLY1305:  \
      ECDHE-RSA-CHACHA20-POLY1305:  \
      DHE-RSA-AES256-CCM:  \
      DHE-RSA-AES256-CCM8:  \
      DHE-RSA-AES128-CCM:  \
      DHE-RSA-AES128-CCM8:  \
      ECDHE-RSA-AES128-GCM-SHA256:  \
      ECDHE-ECDSA-AES128-GCM-SHA256:  \
      DHE-RSA-AES128-GCM-SHA256:  \
      DHE-DSS-AES128-GCM-SHA256:  \
      kEDH+AESGCM:  \
      ECDHE-RSA-AES128-SHA256:  \
      ECDHE-ECDSA-AES128-SHA256:  \
      ECDHE-RSA-AES128-SHA:  \
      ECDHE-ECDSA-AES128-SHA:  \
      ECDHE-RSA-AES256-SHA:  \
      ECDHE-ECDSA-AES256-SHA:  \
      DHE-RSA-AES128-SHA256:  \
      DHE-RSA-AES128-SHA:  \
      DHE-DSS-AES128-SHA256:  \
      DHE-RSA-AES256-SHA256:  \
      DHE-DSS-AES256-SHA:  \
      DHE-RSA-AES256-SHA:  \
      AES128-GCM-SHA256:  \
      AES128-SHA256:  \
      AES256-SHA256:  \
      AES128-SHA:  \
      AES256-SHA:  \
      AES:  \
      \!aNULL:  \
      \!eNULL:  \
      \!EXPORT:  \
      \!DES:  \
      \!RC4:  \
      \!MD5:  \
      \!PSK:  \
      \!aECDH:  \
      \!EDH-DSS-DES-CBC3-SHA:  \
      \!EDH-RSA-DES-CBC3-SHA:  \
      \!KRB5-DES-CBC3-SHA:  \
      \!ECDHE-ECDSA-AES128-SHA256:  \
      \!ECDHE-ECDSA-AES256-SHA384;"
    _SSL_CIPHERS=$(echo "${_SSL_CIPHERS}" | sed "s/ //g" 2>&1)
  else
    _ALLOW_NGINX_FORWARD_SECRECY=NO
  fi
  if [ "${_ALLOW_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
      ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
      ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
    sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
      ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
      ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
  fi
  if [ -e "${_mtrInc}/nginx_vhost_common.conf" ]; then
    rm -f ${_mtrInc}/nginx_advanced_include.conf
    rm -f ${_mtrInc}/nginx_legacy_include.conf
    rm -f ${_mtrInc}/nginx_modern_include.conf
    rm -f ${_mtrInc}/nginx_octopus_include.conf
    rm -f ${_mtrInc}/nginx_simple_include.conf
  fi
  # -h: global.inc here is a link into /data/conf; the link is handed over,
  # never what it leads to
  chown -h aegir:aegir ${_mtrInc}/*
  chown aegir:aegir /var/aegir/.drush/sys/provision/http/Provision/Config/Nginx/*
  # The switch's one template lives in the tools tree (/var/xdrago/conf on a
  # box), where BOA.sh.txt also puts it back from between upgrades.
  if [ ! -e "/data/conf/nginx_high_load_off.conf" ]; then
    mkdir -p /data/conf
    _acct_in_real_dir /data/conf _nginx_conf_put_here \
      "${_bldPth}/aegir/tools/system/conf/nginx_high_load_off.conf" \
      nginx_high_load_off.conf 644
  fi
}

#
# The file $1 (root's own) put as ./$2 in the current (pinned) directory with
# the owner and group of $1 and the mode $3, as cp -a and a chmod by name put
# it, but through one handle (_ACCT_PUT_PL, helper.sh.inc) and renamed over
# the name: a run of an earlier release handed /data/conf to the account it
# upgraded, so a link put at the name is replaced, never written through,
# and nothing is chmoded by name there.
_nginx_conf_put_here() {
  local _t="./.${2}.put.$$.${RANDOM}" _o
  _o="$(stat -c '%u:%g' -- "${1}" 2> /dev/null)"
  [[ "${_o}" =~ ^[0-9]+:[0-9]+$ ]] || return 1
  rm -f -- "${_t}"
  if perl -e "${_ACCT_PUT_PL}" "${_t}" "${_o%%:*}" "${_o#*:}" "${3}" \
    < "${1}" && mv -f -T -- "${_t}" "./${2}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}

#
# Check for Linux/Cdorked.A malware and delete if discovered.
_detect_cdorked_malware() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _detect_cdorked_malware"
  fi
  if [ -x "/usr/sbin/nginx" ]; then
    _C_DORKED=NO
    _C_FILE=${_bldPth}/aegir/helpers/dump_cdorked_config.c
    if [ -e "${_C_FILE}" ]; then
      ### _msg "INFO: Checking for Linux/Cdorked.A malware..."
      chattr -ai /usr/sbin/nginx
      cd ${_vBs}
      rm -rf /var/opt/foo_bar*
      gcc -o /var/opt/foo_bar ${_bldPth}/aegir/helpers/dump_cdorked_config.c &> /dev/null
      _C_DORKED_TEST=$(/var/opt/foo_bar 2>&1)
      if [[ "${_C_DORKED_TEST}" =~ "No shared memory matching Cdorked signature" ]]; then
        _DO_NOTHING=YES
        ### _msg "INFO: No Linux/Cdorked.A malware traces found - system clean"
      else
        _msg "ALRT! Your system is probably infected by Linux/Cdorked.A malware!"
        _msg "ALRT! Please send the ${_vBs}/httpd_cdorked_config.bin file"
        _msg "ALRT! to leveille@eset.com for investigation"
        rm -f $(which nginx)
        _NGX_FORCE_REINSTALL=YES
        _C_DORKED=YES
      fi
    fi
  fi
}

#
# An account's config/ and .drush/ belong to its users, so any name there can
# be a link or a FIFO, and any directory on the way can itself be a link. Root
# reads, edits and removes those files only through these, inside the real
# directory (_acct_in_real_dir and _acct_read_here, helper.sh.inc).
#
# The real directories /data/disk/<oN>/$1 of every account, one per line. A
# name in $1 holding a glob (server_*) expands only inside the real directory
# above it, and only to real directories with plain names; each directory is
# entered again with _acct_in_real_dir before anything is done there.
_nginx_acct_dirs() {
  local _u
  for _u in /data/disk/*; do
    [[ "${_u##*/}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    [ -d "${_u}" ] && [ ! -L "${_u}" ] || continue
    _nginx_acct_dirs_below "${_u}" "${1}"
  done
}
# The same below the single directory $1, for the relative path $2.
_nginx_acct_dirs_below() {
  local _d="${1}" _n _r="" _m
  if [ -z "${2}" ]; then
    echo "${_d}"
    return 0
  fi
  _n="${2%%/*}"
  [ "${_n}" = "${2}" ] || _r="${2#*/}"
  case "${_n}" in
    *'*'*|*'?'*)
      while IFS= read -r _m; do
        _nginx_acct_dirs_below "${_d}/${_m}" "${_r}"
      done < <(_acct_in_real_dir "${_d}" _nginx_dir_names_here "${_n}")
      ;;
    *) _nginx_acct_dirs_below "${_d}/${_n}" "${_r}" ;;
  esac
}
# Names of the real directories matching the glob $1 in the current (pinned)
# directory, plain names only, one per line.
_nginx_dir_names_here() {
  local _m
  # shellcheck disable=SC2086
  for _m in ./${1}; do
    _m="${_m#./}"
    [[ "${_m}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    [ -d "./${_m}" ] && [ ! -L "./${_m}" ] && echo "${_m}"
  done
}
# ./$1 in the current (pinned) directory edited by sed "${@:2}", as sed -i
# edited it: only a regular file under 1 MiB is read, never through a link or
# into a FIFO; the result is a fresh file with the old file's numeric owner
# and the read/write bits of its mode, created, handed over and moded
# through one handle (_ACCT_PUT_PL, helper.sh.inc), renamed over the name:
# nothing is chowned by name, so a hard link the account renames over the
# temp name is never handed over.
_nginx_sed_here() {
  local _n="${1}" _st _own _m _sz _ft _t
  shift
  _st="$(stat -c '%u:%g %a %s %F' -- "./${_n}" 2> /dev/null)" || return 1
  case "${_st}" in
    *" regular file"|*" regular empty file") ;;
    *) return 1 ;;
  esac
  read -r _own _m _sz _ft <<< "${_st}"
  [ "${_sz}" -lt 1048576 ] || return 1
  [[ "${_own}" =~ ^[0-9]+:[0-9]+$ && "${_m}" =~ ^[0-7]+$ ]] || return 1
  _t="./.${_n}.sed.$$.${RANDOM}"
  rm -f -- "${_t}"
  if ( set -o pipefail
    _acct_read_here "${_n}" | sed "$@" \
      | perl -e "${_ACCT_PUT_PL}" "${_t}" "${_own%%:*}" "${_own#*:}" \
        "${_m}" 2> /dev/null ) \
    && mv -f -T -- "${_t}" "./${_n}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}
# sed "${@:2}" over every regular file matching the glob $1 in the current
# (pinned) directory, each edited as _nginx_sed_here edits it.
_nginx_sed_glob_here() {
  local _p="${1}" _f
  shift
  # shellcheck disable=SC2086
  for _f in ./${_p}; do
    [ -f "${_f}" ] && [ ! -L "${_f}" ] || continue
    _nginx_sed_here "${_f#./}" "$@"
  done
}
# sed -i "${@:3}" over /data/disk/*/$1/$2 of every account ($1 a directory as
# _nginx_acct_dirs takes it, $2 a file glob), each file edited inside its real
# directory as _nginx_sed_here edits it.
_nginx_acct_sed() {
  local _rel="${1}" _pat="${2}" _d
  shift 2
  while IFS= read -r -u 9 _d; do
    _acct_in_real_dir "${_d}" _nginx_sed_glob_here "${_pat}" "$@"
  done 9< <(_nginx_acct_dirs "${_rel}")
}
# NUL-terminated names directly in the current (pinned) directory that the
# glob $1 matches (never a dot-name, which the glob skips) and whose text
# grep "${@:2}" matches. One grep reads only the regular files under 1 MiB
# there, the ones _nginx_sed_here edits, for at most 60 seconds; -D skip
# never blocks on a FIFO or a device put at a name since the listing. When
# the listing or grep cannot tell (an error, a timeout, an option it
# lacks), every name the glob matches is listed. A record starting with /
# carries a status: no name listed here holds one.
_nginx_names_with_here() {
  local _p="${1}" _f _rc=""
  local -a _n=() _m=()
  shift
  while IFS= read -r -d '' _f; do
    case "${_f}" in
      /rc=*) _rc="${_f#/rc=}"; continue ;;
    esac
    _f="${_f#./}"
    case "${_f}" in
      */*|.*) continue ;;
    esac
    # shellcheck disable=SC2254
    case "${_f}" in
      ${_p}) _n+=( "${_f}" ) ;;
    esac
  done < <(find . -mindepth 1 -maxdepth 1 -type f -size -1048576c -print0 2> /dev/null
    printf '/rc=%s\0' "$?")
  if [ "${_rc}" = "0" ]; then
    [ "${#_n[@]}" -gt 0 ] || return 0
    _rc=""
    while IFS= read -r -d '' _f; do
      case "${_f}" in
        /rc=*) _rc="${_f#/rc=}" ;;
        *) _m+=( "${_f}" ) ;;
      esac
    done < <(LC_ALL=C timeout 60 grep -lZ -d skip -D skip "$@" -- "${_n[@]}" 2> /dev/null
      printf '/rc=%s\0' "$?")
    if [ "${_rc}" = "0" ] || [ "${_rc}" = "1" ]; then
      [ "${#_m[@]}" -gt 0 ] && printf '%s\0' "${_m[@]}"
      return 0
    fi
  fi
  # shellcheck disable=SC2086
  for _f in ./${_p}; do
    [ -e "${_f}" ] || [ -L "${_f}" ] || continue
    printf '%s\0' "${_f#./}"
  done
}
# As _nginx_sed_glob_here, but only on the files _nginx_names_with_here
# lists. Args: the glob, the grep arguments, --, the sed arguments.
_nginx_sed_if_here() {
  local _p="${1}" _f
  local -a _g=()
  shift
  while [ "$#" -gt 0 ] && [ "${1}" != "--" ]; do
    _g+=( "${1}" )
    shift
  done
  shift
  while IFS= read -r -d '' _f; do
    _nginx_sed_here "${_f}" "$@"
  done < <(_nginx_names_with_here "${_p}" "${_g[@]}")
}
# As _nginx_acct_sed, but each file is edited only when its text holds a
# line the sed arguments change, as the grep arguments tell. Args: the
# directory, the glob, the grep arguments, --, the sed arguments.
_nginx_acct_sed_if() {
  local _rel="${1}" _d
  shift
  while IFS= read -r -u 9 _d; do
    _acct_in_real_dir "${_d}" _nginx_sed_if_here "$@"
  done 9< <(_nginx_acct_dirs "${_rel}")
}
# Every regular file below the real directory $1 whose text holds $2, removed:
# the tree is listed from inside $1, each file's directory is entered again
# for real, and the file is read as _acct_read_here reads it and removed by
# its name there, so no link on the way is followed and no FIFO blocks.
_nginx_drop_marked() {
  local _top="${1}" _f _sub
  while IFS= read -r -d '' -u 9 _f; do
    _f="${_f#./}"
    _sub=""
    case "${_f}" in
      */*) _sub="/${_f%/*}" ;;
    esac
    _acct_in_real_dir "${_top}${_sub}" _nginx_drop_if_here "${_f##*/}" "${2}"
  done 9< <(_acct_in_real_dir "${_top}" find . -type f -print0 2> /dev/null)
}
_nginx_drop_if_here() {
  _acct_read_here "${1}" | grep -q -- "${2}" && rm -f -- "./${1}"
}
# Every name directly in the current (pinned) directory removed, as rm -f
# dir/* removed them; the glob expands here only.
_nginx_rm_files_here() {
  rm -f -- ./*
}

#
# Purge legacy Nginx config.
_nginx_clean_legacy_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_clean_legacy_config"
  fi
  if [ -e "/var/aegir/config/server_master/nginx/pre.d/nginx_speed_purge.conf" ]; then
    rm -f /var/aegir/config/server_master/nginx/pre.d/nginx_speed_purge.conf
  fi
  _R_TEST=$(grep "upload_progress" /var/aegir/config/nginx.conf 2>&1)
  if [[ "${_R_TEST}" =~ "upload_progress" ]]; then
    sed -i "s/.*upload_progress.*//g" /var/aegir/config/nginx.conf
  fi
  if [ -d "/data/u" ]; then
    _R_TEST=$(_acct_read_all config/includes nginx_vhost_common.conf \
      | grep "upload_progress_json_output" 2>&1)
    if [[ "${_R_TEST}" =~ "upload_progress_json_output" ]]; then
      _nginx_acct_sed config/includes nginx_vhost_common.conf \
        -e "s/.*upload_progress_json_output.*//g" \
        -e "s/.*report_uploads.*//g" \
        -e "s/.*track_uploads.*//g"
      _nginx_acct_sed "config/server_master/nginx/subdir.d/*" "*.conf" \
        -e "s/.*upload_progress_json_output.*//g" \
        -e "s/.*report_uploads.*//g" \
        -e "s/.*track_uploads.*//g"
      sed -i "s/.*upload_progress_json_output.*//g" /var/aegir/config/includes/nginx_vhost_common.conf
      wait
      sed -i "s/.*report_uploads.*//g" /var/aegir/config/includes/nginx_vhost_common.conf
      wait
      sed -i "s/.*track_uploads.*//g" /var/aegir/config/includes/nginx_vhost_common.conf
      wait
    fi
  fi
  _mrun "service nginx reload"
}

#
# Install or upgrade Nginx.
#
# Try the prebuilt boa-nginx .deb for the pinned version; fall back to
# sources on any failure. Published for the default build shape only: any
# box with a non-default module set (extra conf, headers-more, LDAP, NAXSI,
# purge) is refused up front and keeps the source path -- the phase-1
# _PHP_EXTRA_CONF refusal pattern -- because installing a default-shape
# binary over a working custom one and then failing the health check would
# leave a module-less nginx in place mid-run. The deb overlays the binary
# the distro nginx package owns on fresh boxes (Replaces: in the package
# control), while the distro package itself stays installed, pinned and
# held -- it keeps providing the config/init/user structure. nginx links
# its OpenSSL statically, so no loader sync is needed before the probe;
# the expected OpenSSL token is resolved here the same way the source
# build resolves it, so a marker-less box expects the version it would
# have built rather than the one the builder baked.
_install_nginx_deb() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_nginx_deb"
  fi
  _NGINX_DEB_INSTALLED=NO
  if [ -z "${_NGINX_VRN}" ]; then
    return 1
  fi
  if [ ! -z "${_NGINX_EXTRA_CONF}" ] \
    || [ "${_NGINX_HEADERS}" = "YES" ] \
    || [ "${_NGINX_LDAP}" = "YES" ] \
    || [ "${_NGINX_NAXSI}" = "YES" ] \
    || [ "${_PURGE_MODE}" = "ON" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Custom Nginx build shape; skipping prebuilt boa-nginx"
    fi
    return 1
  fi
  # Read-only mirror of the source build's OpenSSL selection; the stretch
  # marker cleanup stays in the source path only.
  if [ "${_OS_CODE}" = "excalibur" ] \
    || [ "${_OS_CODE}" = "daedalus" ] \
    || [ "${_OS_CODE}" = "chimaera" ] \
    || [ "${_OS_CODE}" = "beowulf" ] \
    || [ "${_OS_CODE}" = "bookworm" ] \
    || [ "${_OS_CODE}" = "bullseye" ] \
    || [ "${_OS_CODE}" = "buster" ]; then
    _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
    if [ -e "/root/.install.modern.openssl.cnf" ]; then
      _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
    fi
  elif [ "${_OS_CODE}" = "stretch" ]; then
    _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
  else
    _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
  fi
  # Builders are modern-marker boxes by construction, so every published
  # deb bakes the modern OpenSSL statically. A box that expects any other
  # version could only install the deb, fail the token check and purge --
  # leaving no binary until the source rebuild lands. Refuse up front
  # instead; such boxes keep the source path untouched.
  if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_MODERN_VRN}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Non-modern OpenSSL expected; skipping prebuilt boa-nginx"
    fi
    return 1
  fi
  # Snapshot the working binary: with Replaces: in play the deb takes
  # ownership of /usr/sbin/nginx, so a purge on any failure below removes
  # the file itself -- and the source rebuild that follows can fail
  # silently (_mrun). The snapshot keeps the failure envelope identical
  # to the source path's: a failed attempt leaves the previous working
  # binary in place. The source branch's rm -rf nginx* sweeps any stray
  # snapshot on its next run.
  if [ -x "/usr/sbin/nginx" ]; then
    cp -af /usr/sbin/nginx /var/opt/nginx-pre-deb
  fi
  # An attacker-set immutable flag would make dpkg's unpack fail silently.
  chattr -i /usr/sbin/nginx &> /dev/null
  if ! _install_boa_deb "boa-nginx" "${_NGINX_VRN}"; then
    if [ ! -x "/usr/sbin/nginx" ] && [ -x "/var/opt/nginx-pre-deb" ]; then
      cp -af /var/opt/nginx-pre-deb /usr/sbin/nginx
    fi
    rm -f /var/opt/nginx-pre-deb
    return 1
  fi
  # dpkg unpacks the payload with the builder's hardened 0750 mode but
  # archive ownership root:root, and AegirSetupM's provision probes
  # `nginx -V` as the aegir user for feature detection inside the window
  # before _strict_bin_permissions converts group root to users. An
  # unexecutable binary silently degrades the generated server config to
  # the ancient pre-1.1.8 shape (limit_zone), which the modern binary
  # then refuses to load on the next start. Normalize to the canonical
  # root:users shape immediately, matching the boa-php deb precedent.
  chown root:users /usr/sbin/nginx &> /dev/null
  chmod 750 /usr/sbin/nginx &> /dev/null
  _NGINX_DEB_F_ITD=$(/usr/sbin/nginx -v 2>&1 | tr -d "\n" \
    | cut -d"/" -f2 | awk '{ print $1}' 2>&1)
  _NGINX_DEB_V_ITD=$(/usr/sbin/nginx -V 2>&1)
  _NGINX_DEB_V_ITD="$(printf '%s' "${_NGINX_DEB_V_ITD}" | tr '\n\t' '  ')"
  _NGINX_DEB_OK=YES
  if [ ! -x "/usr/sbin/nginx" ] \
    || [ "${_NGINX_DEB_F_ITD}" != "${_NGINX_VRN}" ]; then
    _NGINX_DEB_OK=NO
  fi
  # The same compiled-in tokens the next run's rebuild decision checks; a
  # payload that would immediately re-trigger a rebuild must not pass.
  if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- 'geoip'; then
    _NGINX_DEB_OK=NO
  fi
  if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- ' --with-http_flv_module'; then
    _NGINX_DEB_OK=NO
  fi
  if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- ' --with-http_mp4_module'; then
    _NGINX_DEB_OK=NO
  fi
  if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- "OpenSSL ${_OPENSSL_NEW_VRN}"; then
    _NGINX_DEB_OK=NO
  fi
  if [ "${_NGINX_SPDY}" = "YES" ]; then
    if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- ' --with-http_v2_module'; then
      _NGINX_DEB_OK=NO
    fi
    if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ]; then
      if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- ' --with-http_v3_module'; then
        _NGINX_DEB_OK=NO
      fi
      if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- 'enable-ktls'; then
        _NGINX_DEB_OK=NO
      fi
    fi
  fi
  if [ "${_NGINX_DEB_OK}" = "YES" ]; then
    rm -f /var/opt/nginx-pre-deb
    _NGINX_DEB_INSTALLED=YES
    _msg "INFO: Nginx ${_NGINX_VRN} installed from prebuilt package"
    return 0
  fi
  # The purge removes the binary boa-nginx now owns; restore the snapshot
  # so the box keeps a working nginx even if the source rebuild that runs
  # next fails silently.
  dpkg --purge "boa-nginx" &> /dev/null
  if [ -x "/var/opt/nginx-pre-deb" ]; then
    cp -af /var/opt/nginx-pre-deb /usr/sbin/nginx
    rm -f /var/opt/nginx-pre-deb
  fi
  _msg "NOTE: Prebuilt boa-nginx failed health check; building from sources"
  return 1
}

_nginx_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_install_upgrade"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Testing Nginx version..."
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    _NGINX_INSTALL_REQUIRED=NO
  fi
  if [ -x "/usr/sbin/nginx" ]; then
    _NGINX_F_ITD=$(/usr/sbin/nginx -v 2>&1 | tr -d "\n" \
      | cut -d"/" -f2 | awk '{ print $1}' 2>&1)
    _NGINX_V_ITD=$(/usr/sbin/nginx -V 2>&1)
    _NGINX_V_ITD="$(printf '%s' "${_NGINX_V_ITD}" | tr '\n\t' '  ')"
    if [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ] \
      && [ "${_STATUS}" = "UPGRADE" ]; then
      _NGINX_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Nginx ${_NGINX_F_ITD}, OK"
      fi
    elif [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ] \
      && [ "${_STATUS}" = "INIT" ]; then
      _NGINX_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Nginx ${_NGINX_F_ITD}, OK"
      fi
    elif [ "${_NGINX_F_ITD}" != "${_NGINX_VRN}" ]; then
      _NGINX_INSTALL_REQUIRED=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Nginx ${_NGINX_F_ITD}, upgrade required"
      fi
    fi
    if [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ]; then
      if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'geoip'; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          _msg "INFO: Nginx forced rebuild to include geoip module"
        fi
      fi
      if printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'nginx-development-kit'; then
        _NGINX_INSTALL_REQUIRED=YES
        _msg "INFO: Nginx rebuild required to avoid apt-get overwrite"
      fi
      if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- ' --with-http_flv_module'; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          _msg "INFO: Nginx forced rebuild to include pseudo-streaming support"
        fi
      fi
      if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- ' --with-http_mp4_module'; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          _msg "INFO: Nginx forced rebuild to include pseudo-streaming support"
        fi
      fi
      if [ "${_OS_CODE}" = "excalibur" ] \
        || [ "${_OS_CODE}" = "daedalus" ] \
        || [ "${_OS_CODE}" = "chimaera" ] \
        || [ "${_OS_CODE}" = "beowulf" ] \
        || [ "${_OS_CODE}" = "bookworm" ] \
        || [ "${_OS_CODE}" = "bullseye" ] \
        || [ "${_OS_CODE}" = "buster" ]; then
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
        fi
      elif [ "${_OS_CODE}" = "stretch" ]; then
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          chattr -i /root/.install.modern.openssl.cnf
          rm -f /root/.install.modern.openssl.cnf
        fi
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
      else
        _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
      fi
      if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- "OpenSSL ${_OPENSSL_NEW_VRN}"; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          _msg "INFO: Nginx forced rebuild to include latest OpenSSL version"
        fi
      fi
      if [ "${_NGINX_HEADERS}" = "YES" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'nginx-headers-more'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include Headers More support"
          fi
        fi
      fi
      if [ "${_NGINX_LDAP}" = "YES" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'nginx-auth-ldap'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include LDAP support"
          fi
        fi
      fi
      if [ "${_PURGE_MODE}" = "ON" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'purge'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include purge module"
          fi
        fi
      fi
      if [ "${_NGINX_NAXSI}" = "YES" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'naxsi'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include NAXSI module"
          fi
        fi
      fi
      if [ "${_NGINX_SPDY}" = "YES" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- ' --with-http_v2_module'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include HTTP/2 support"
          fi
        fi
        if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ]; then
          if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- ' --with-http_v3_module'; then
            _NGINX_INSTALL_REQUIRED=YES
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
              _msg "INFO: Nginx forced rebuild to include HTTP/3 support"
            fi
          fi
          if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'enable-ktls'; then
            _NGINX_INSTALL_REQUIRED=YES
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
              _msg "INFO: Nginx forced rebuild to include kTLS support"
            fi
          fi
        fi
      fi
    fi
  else
    _NGINX_INSTALL_REQUIRED=YES
  fi
  _detect_cdorked_malware
  if [ "${_C_DORKED}" = "YES" ]; then
    _NGINX_INSTALL_REQUIRED=YES
    _msg "INFO: Nginx rebuild required to remove possible Linux/Cdorked.A malware"
  fi
  if [ "${_NGINX_INSTALL_REQUIRED}" = "YES" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_NGX_FORCE_REINSTALL}" = "YES" ]; then
    if [ "${_STATUS}" = "UPGRADE" ]; then
      _msg "INFO: Upgrading Nginx to ${_NGINX_VRN}..."
    else
      _msg "INFO: Installing Nginx ${_NGINX_VRN}..."
    fi
    # Prebuilt package path (_USE_PREBUILT_PKGS): replaces only the source
    # fetch + compile below; the shared tail (ldconfig, legacy-config
    # cleanup, service restart) and the follow-up _nginx_initd_check +
    # _nginx_mime_check_fix service wiring run unchanged for both paths.
    _NGINX_DEB_INSTALLED=NO
    if [ "${_USE_PREBUILT_PKGS}" = "YES" ]; then
      _install_nginx_deb
    fi
    if [ "${_NGINX_DEB_INSTALLED}" != "YES" ]; then
      cd /var/opt; rm -rf nginx*
      _get_dev_src "nginx-${_NGINX_VRN}.tar.gz"
      if [ ! -z "${_NGINX_EXTRA_CONF}" ]; then
        _NGINX_EXTRA="${_NGINX_EXTRA_CONF}"
      else
        _NGINX_EXTRA=""
      fi
      if [ "${_NGINX_HEADERS}" = "YES" ]; then
        cd /var/opt
        rm -rf /var/opt/nginx-headers-more*
        _get_dev_src "nginx-headers-more.tar.gz"
        if [ -e "/var/opt/nginx-headers-more" ]; then
          _NGINX_EXTRA="--add-module=/var/opt/nginx-headers-more/ ${_NGINX_EXTRA}"
        fi
      fi
      if [ "${_NGINX_LDAP}" = "YES" ]; then
        cd /var/opt
        rm -rf /var/opt/nginx-auth-ldap*
        _get_dev_src "nginx-auth-ldap.tar.gz"
        if [ -e "/var/opt/nginx-auth-ldap" ]; then
          _NGINX_EXTRA="--add-module=/var/opt/nginx-auth-ldap/ ${_NGINX_EXTRA}"
        fi
      fi
      if [ "${_NGINX_NAXSI}" = "YES" ]; then
        cd /var/opt
        rm -rf /var/opt/nginx-naxsi*
        _get_dev_src "nginx-naxsi.tar.gz"
        if [ -e "/var/opt/nginx-naxsi" ]; then
          _NGINX_EXTRA="--add-module=/var/opt/nginx-naxsi/naxsi_src/ ${_NGINX_EXTRA}"
        fi
      fi
      if [ "${_NGINX_SPDY}" = "YES" ]; then
        if [ "${_OS_CODE}" = "none" ]; then
          _NGINX_EXTRA="--with-http_spdy_module ${_NGINX_EXTRA}"
        else
          _NGINX_EXTRA="--with-http_v2_module ${_NGINX_EXTRA}"
        fi
      fi
      if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ]; then
        _NGINX_EXTRA="--with-http_v3_module ${_NGINX_EXTRA}"
      fi
      if [ "${_OS_CODE}" = "excalibur" ] \
        || [ "${_OS_CODE}" = "daedalus" ] \
        || [ "${_OS_CODE}" = "chimaera" ] \
        || [ "${_OS_CODE}" = "beowulf" ] \
        || [ "${_OS_CODE}" = "bookworm" ] \
        || [ "${_OS_CODE}" = "bullseye" ] \
        || [ "${_OS_CODE}" = "buster" ]; then
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
        fi
      elif [ "${_OS_CODE}" = "stretch" ]; then
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          chattr -i /root/.install.modern.openssl.cnf
          rm -f /root/.install.modern.openssl.cnf
        fi
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
      else
        _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
      fi
      if [ ! -e "/var/opt/openssl-${_OPENSSL_NEW_VRN}" ]; then
        cd /var/opt
        rm -rf "/var/opt/openssl-${_OPENSSL_NEW_VRN}" "/var/opt/openssl-${_OPENSSL_NEW_VRN}.tar.gz"
        _get_dev_src "openssl-${_OPENSSL_NEW_VRN}.tar.gz"
      fi
      cd /var/opt/nginx-${_NGINX_VRN}
      _mrun "bash ./configure \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --group=www-data \
        --http-client-body-temp-path=/var/lib/nginx/body \
        --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
        --http-log-path=/var/log/nginx/access.log \
        --http-proxy-temp-path=/var/lib/nginx/proxy \
        --http-scgi-temp-path=/var/lib/nginx/scgi \
        --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
        --lock-path=/var/lock/nginx.lock \
        --pid-path=/run/nginx.pid \
        --prefix=/usr \
        --sbin-path=/usr/sbin/nginx \
        --user=www-data \
        --with-compat \
        --with-file-aio \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_geoip_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-threads \
        --without-http_scgi_module \
        --without-http_uwsgi_module \
        --without-mail_imap_module \
        --without-mail_pop3_module \
        --without-mail_smtp_module \
        --with-openssl=/var/opt/openssl-${_OPENSSL_NEW_VRN} \
        --with-openssl-opt='no-tests no-ssl3 enable-ktls zlib-dynamic enable-ec_nistp_64_gcc_128' \
        --with-cc-opt='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
        --with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
        --with-debug ${_NGINX_EXTRA} | tee /var/opt/nginx-configure.out"
      _mrun "make -j $(nproc)"
      _mrun "make install"
      # A configure that aborts before objs/Makefile leaves make with nothing
      # to build and the previous binary in place while the stamp would claim
      # the new version; say so instead of reporting a clean pass. configure
      # prints its abort on stdout, which the tee above keeps for the quote
      # (its stderr still reaches the errors log); ldconfig first so a
      # freshly installed library cannot make the probe misread a good build.
      ldconfig 2> /dev/null
      _NGX_BUILT=$(/usr/sbin/nginx -v 2>&1 | grep -oE "nginx/[0-9.]+")
      if [ ! -x "/var/opt/nginx-${_NGINX_VRN}/objs/nginx" ]; then
        _msg "OOPS: Nginx ${_NGINX_VRN} did not build (no objs/nginx in the build tree); the previous binary stays in place, see ${_LOG_INFO:-the info log}"
        _NGX_CFG_ERR=$(grep -m1 "configure: error" /var/opt/nginx-configure.out 2>/dev/null)
        [ -n "${_NGX_CFG_ERR}" ] && _msg "OOPS: nginx configure said: ${_NGX_CFG_ERR}"
      elif [ "${_NGX_BUILT}" != "nginx/${_NGINX_VRN}" ]; then
        _msg "OOPS: Nginx ${_NGINX_VRN} built but was not installed (nginx -v reports ${_NGX_BUILT:-nothing}); the previous binary stays in place, see ${_LOG_INFO:-the info log}"
      fi
    fi
    ldconfig 2> /dev/null
    _nginx_clean_legacy_config
    _mrun "service nginx restart"
    _NGINX_INSTALL_REQUIRED=NO
  fi
  if [ ! -L "/usr/bin/nginx" ]; then
    ln -sfn /usr/sbin/nginx /usr/bin/nginx
  fi
}

#
# Fix multi-IP cron access.
_master_fix_multi_ip_cron_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _master_fix_multi_ip_cron_access"
  fi
  [ -e "/root/.local.IP.list.allow" ] && rm -f /root/.local.IP.list.allow
  for _IP in `cat /root/.local.IP.list \
    | cut -d '#' -f1 \
    | sort \
    | uniq \
    | tr -d "\s"`;do echo "  allow        ${_IP};" >> \
      /root/.local.IP.list.allow;done
  echo "  allow 127.0.0.1;" >> /root/.local.IP.list.allow
  ###
  ### Only the locations kept for the box itself (FPM status and ping, the
  ### cron entry points) take the box's other addresses: they are the ones
  ### that allow 127.0.0.1. A location that denies everyone (backup_migrate
  ### files, config sync dirs) stays closed to the box as well, or every proxy
  ### that connects from it (the wildcard SSL front, an HTTPS proxy in pre.d)
  ### would serve those files to any visitor. Each pass first drops the lines
  ### it added before, in its own padded format, and any allow line inside
  ### those two locations, so a file expanded by an older pass heals too. The
  ### rendered subdir vhosts were copied from the template, so they get the
  ### same treatment. These dirs belong to the aegir user, so a symlink is
  ### skipped, the new text is staged in a root-only dir, and sed -i writes a
  ### new file and renames it over the path, never through it. mawk has no
  ### {n} repetition and before 1.3.4 no [:class:] sets: both are spelled out.
  ###
  local _f _d _t
  _d=$(mktemp -d /var/backups/.boa-multi-ip.XXXXXX 2>/dev/null) || return 0
  _t="${_d}/stage"
  for _f in ${_mtrTpl}/Inc/vhost_include.tpl.php \
    ${_mtrTpl}/subdir.tpl.php \
    ${_mtrInc}/nginx_vhost_common.conf \
    /var/aegir/config/server_master/nginx/subdir.d/*/*.conf; do
    [ -f "${_f}" ] && [ ! -L "${_f}" ] || continue
    awk -v list="/root/.local.IP.list.allow" '
      BEGIN { while ((getline _l < list) > 0) _ips[++_n] = _l }
      /^[ \t]*location[ \t].*files\/(backup_migrate\/|config_)/ { _closed = 1; _depth = 0 }
      {
        _o = gsub(/\{/, "{"); _c = gsub(/\}/, "}")
        if (_closed) _depth += _o - _c
        _drop = 0
        if ($0 ~ /^[ \t]*allow        [^ ;]+;[ \t\r]*$/) _drop = 1
        else if (_closed && $0 ~ /^[ \t]*allow[ \t]/) _drop = 1
        else if ($0 ~ /^[ \t]*allow 127\.0\.0\.1;[ \t\r]*$/) {
          match($0, /^[ \t]*/); _ind = substr($0, 1, RLENGTH)
          for (_i = 1; _i <= _n; _i++) { _s = _ips[_i]; sub(/^[ \t]*/, _ind, _s); print _s }
          _drop = 1
        }
        if (!_drop) print
        if (_closed && _depth <= 0 && (_o || _c)) _closed = 0
      }' "${_f}" > "${_t}"
    if [ -s "${_t}" ] && [ -s "${_f}" ] && ! cmp -s "${_t}" "${_f}"; then
      sed -i -e "1r ${_t}" -e d "${_f}"
    fi
  done
  rm -rf "${_d}"
}

_nginx_initd_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_initd_check"
  fi
  _X_INIT_TEST=
  if [ -e "/etc/init.d/nginx" ]; then
    _X_INIT_TEST_A=$(cat /etc/init.d/nginx | grep ULIMIT 2>&1)
    _X_INIT_TEST_B=$(cat /etc/init.d/nginx | grep Giedymin 2>&1)
    ### The rotate action is required by the stock logrotate.d/nginx
    ### postrotate (invoke-rc.d nginx rotate); scripts without it made
    ### the daily logrotate cron fail and left nginx writing to the
    ### renamed log files until the next reload.
    _X_INIT_TEST_C=$(cat /etc/init.d/nginx | grep rotate 2>&1)
    ### The passive-standby hold gates start() in this script (the escape
    ### hatch /root/.standby.serve.cnf names it). A deployed copy that
    ### predates the hold passes the three tests above and was never
    ### refreshed, so an upgraded mirror still booted its web tier and
    ### served its own panel until the watchdog caught up. Refresh on the
    ### gate's absence too. The gate now follows the DATABASE, not the
    ### xmass window (every init released the web tier), and a deployed
    ### copy with the older predicate still names standby.serve.cnf -- so
    ### the test names a string only the CURRENT gate carries.
    _X_INIT_TEST_D=$(cat /etc/init.d/nginx | grep standby_promoted 2>&1)
  fi
  if [[ "${_X_INIT_TEST_A}" =~ ULIMIT ]] \
    && [[ "${_X_INIT_TEST_B}" =~ Giedymin ]] \
    && [[ "${_X_INIT_TEST_C}" =~ rotate ]] \
    && [[ "${_X_INIT_TEST_D}" =~ standby_promoted ]]; then
    chmod 755 /etc/init.d/nginx &> /dev/null
    _mrun "update-rc.d nginx defaults"
  else
    mv -f /etc/init.d/nginx \
      ${_vBs}/nginx-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${_locCnf}/nginx/nginx /etc/init.d/nginx
    chmod 755 /etc/init.d/nginx &> /dev/null
    _mrun "update-rc.d nginx defaults"
    _mrun "service nginx start"
  fi
}

_nginx_mime_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_mime_check_fix"
  fi
  if [ -e "${_locCnf}/nginx/mime.types" ]; then
    # Back up and replace only on a change: every pass otherwise left one
    # more identical copy behind, and nginx-default serves its directory.
    if ! cmp -s "${_locCnf}/nginx/mime.types" /etc/nginx/mime.types; then
      mv -f /etc/nginx/mime.types \
        /etc/nginx/mime.types-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
      cp -af ${_locCnf}/nginx/mime.types /etc/nginx/mime.types
    fi
    if [ ! -L "/var/www/nginx-default/index.html" ] \
      && [ ! -L "/var/www/nginx-default/under_construction.jpg" ]; then
      mkdir -p /var/www/nginx-default
      if ! cmp -s "${_locCnf}/tpl/uc.html" /var/www/nginx-default/index.html; then
        mv -f /var/www/nginx-default/index.html \
          /var/www/nginx-default/index.html-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
        cp -af ${_locCnf}/tpl/uc.html /var/www/nginx-default/index.html
      fi
      cp -af ${_locCnf}/tpl/under_construction.jpg \
        /var/www/nginx-default/under_construction.jpg
    fi
    if [ -e "${_locCnf}/tpl/maintenance.html" ]; then
      cp -af ${_locCnf}/tpl/maintenance.html \
        /var/www/nginx-default/maintenance.html
    fi
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/modules-enabled/*
    # Reload on proxies too: the mutations above have already landed on
    # disk, and skipping the reload only leaves the running nginx
    # diverged from its own config until something else reloads it.
    _mrun "service nginx reload"
  fi
}

_nginx_limit_req_zones_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_limit_req_zones_update"
  fi
  local _zones_src="${_locCnf}/nginx/nginx_limit_req_zones.conf"
  local _zones_dst="/etc/nginx/conf.d/limit-req-zones-boa.conf"
  [ -e "${_zones_src}" ] || return 0
  [ -d "/etc/nginx/conf.d" ] || return 0
  if [ -e "${_zones_dst}" ] && cmp -s "${_zones_src}" "${_zones_dst}"; then
    return 0
  fi
  ### Provision vhost includes render their limit_req consumers only when
  ### this file is present with the expected zone, so on-disk presence is
  ### the contract; no reload is needed here — the next configtest-gated
  ### reload activates the zones together with any consumer that needs them.
  local _zones_bak=""
  if [ -e "${_zones_dst}" ]; then
    _zones_bak="${_zones_dst}.pre-${_NOW}"
    cp -af "${_zones_dst}" "${_zones_bak}"
  fi
  cp -af "${_zones_src}" "${_zones_dst}.tmp"
  chmod 644 "${_zones_dst}.tmp"
  chown root:root "${_zones_dst}.tmp"
  mv -f "${_zones_dst}.tmp" "${_zones_dst}"
  ### Fail closed on a box whose nginx rejects the zones: rendered includes
  ### must never be able to trust a file the running nginx cannot load.
  ### Skip the test where nginx is not installed yet (fresh INIT ordering);
  ### the shipped content is static and known-good on every nginx BOA builds.
  if command -v nginx > /dev/null 2>&1; then
    if ! nginx -t > /dev/null 2>&1; then
      if [ -n "${_zones_bak}" ] && [ -e "${_zones_bak}" ]; then
        mv -f "${_zones_bak}" "${_zones_dst}"
      else
        rm -f "${_zones_dst}"
      fi
      _msg "ALERT: nginx -t rejected ${_zones_dst}; previous state restored"
      return 0
    fi
  fi
  if [ -n "${_zones_bak}" ]; then
    rm -f "${_zones_bak}"
  fi
  return 0
}

### The wild-ssl front is a static copy in the master render tree and the
### upgrade path restarts nginx without a configtest, so its crawler-fleet
### guard may only exist while the installed zones file declares the variable
### it reads. The range is anchored on the exact marker lines, so text that
### merely quotes a marker can never widen what is deleted.
_nginx_wild_ssl_fleet_gate() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_wild_ssl_fleet_gate"
  fi
  [[ -e "${_WILD_SSL_VHOST}" ]] || return 0
  if ! grep -qF 'map $boa_fleet_uaid $boa_fleet_block {' /etc/nginx/conf.d/limit-req-zones-boa.conf 2> /dev/null; then
    if ! sed -i '/^  ### BOA-FLEET-GUARD-BEGIN$/,/^  ### BOA-FLEET-GUARD-END$/d' "${_WILD_SSL_VHOST}" &> /dev/null; then
      _msg "ALERT: could not strip the crawler-fleet guard from ${_WILD_SSL_VHOST}"
    fi
  fi
  return 0
}

_nginx_wildcard_ssl_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_wildcard_ssl_install"
  fi
  _WILD_SSL_VHOST="${_mtrNgx}/pre.d/nginx_wild_ssl.conf"
  if [ ! -e "${_WILD_SSL_VHOST}" ]; then
    _msg "INFO: Installing default SSL Wildcard Nginx Proxy..."
    _validate_public_ip &> /dev/null
    _validate_xtras_ip &> /dev/null
    openssl req -x509 -nodes -sha256 -days 7300 \
      -subj "/C=US/ST=New York/O=Aegir/OU=Cloud/L=New York/CN=*.${_THISHOST}" \
      -newkey rsa:2048 \
      -keyout /etc/ssl/private/nginx-wild-ssl.key \
      -out /etc/ssl/private/nginx-wild-ssl.crt -batch 2> /dev/null
    ### The upstream must stay pinned to 127.0.0.1 — `localhost` resolves to
    ### [::1] too on dual-stack /etc/hosts while nginx listens v4-only, adding
    ### a permanently-refusing peer; one backend hiccup then marks 127.0.0.1
    ### down as well and every proxied vhost 502s ("no live upstreams").
    cp -af ${_locCnf}/nginx/nginx_wild_ssl.conf ${_WILD_SSL_VHOST}
    _nginx_wild_ssl_fleet_gate
    sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g" ${_WILD_SSL_VHOST} &> /dev/null
    [ -e "/etc/nginx/no_ktls.conf" ] \
      && sed -i "/ssl_conf_command Options.*KTLS/d" ${_WILD_SSL_VHOST} &> /dev/null
    if [ -e "${_locCnf}/global/global.inc" ]; then
      ### Deploy the full global include set (per-core chain + dispatcher);
      ### the dispatcher alone would be inert without the chain.
      _global_inc_conf_update
    fi
    if [ -e "${_mtrInc}" ] \
      && [ ! -L "${_mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sfn /data/conf/global.inc ${_mtrInc}/global.inc
    fi
    if [ -e "/etc/init.d/valkey-server" ]; then
      _valkey_password_update
    fi
    _mrun "service nginx restart"
  else
    _WILD_SSL_PROXY_UP=NO
    _RSPRT_TEST=$(grep "quic reuseport" ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_RSPRT_TEST}" =~ "quic reuseport" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs quic reuseport update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _HTTP3_TEST=$(grep http3 ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_HTTP3_TEST}" =~ "http3" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs http3 update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _WILDCARD_SSL_TEST=$(grep "127.0.0.1:80" ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_WILDCARD_SSL_TEST}" =~ "127.0.0.1:80" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs port update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _HTTPVER_TEST=$(grep proxy_http_version ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_HTTPVER_TEST}" =~ "proxy_http_version" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs http/1.1 upstream update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _BANGUARD_TEST=$(grep is_banned ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_BANGUARD_TEST}" =~ "is_banned" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs IDS enforcement update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _FRONTACL_TEST=$(grep boa_front_local_deny ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_FRONTACL_TEST}" =~ "boa_front_local_deny" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs per-site access-list update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    if ! grep -qE '^[[:space:]]*send_timeout[[:space:]]+3600s;' ${_WILD_SSL_VHOST} 2> /dev/null; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs media send timeout update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    ### Keep the crawler-fleet guard in step with the zones file both ways:
    ### redeploy to add it once the maps are declared, and redeploy (the gate
    ### then strips it) when they are not.
    local _fleet_zones=NO _fleet_front=NO
    grep -qF 'map $boa_fleet_uaid $boa_fleet_block {' /etc/nginx/conf.d/limit-req-zones-boa.conf 2> /dev/null && _fleet_zones=YES
    grep -qF 'BOA-FLEET-GUARD-BEGIN' "${_WILD_SSL_VHOST}" 2> /dev/null && _fleet_front=YES
    if [[ "${_fleet_zones}" != "${_fleet_front}" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs crawler-fleet guard update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    ### Re-deploy when the deployed KTLS state disagrees with the opt-out
    ### control file, so toggling _NGINX_KTLS self-heals the front either way.
    _KTLS_STATE_TEST=$(grep "Options.*KTLS" ${_WILD_SSL_VHOST} 2>&1)
    if [ -e "/etc/nginx/no_ktls.conf" ]; then
      [[ "${_KTLS_STATE_TEST}" =~ "KTLS" ]] && _WILD_SSL_PROXY_UP=YES
    else
      [[ ! "${_KTLS_STATE_TEST}" =~ "KTLS" ]] && _WILD_SSL_PROXY_UP=YES
    fi
    if [ "${_WILD_SSL_PROXY_UP}" = "YES" ]; then
      _validate_public_ip &> /dev/null
      _validate_xtras_ip &> /dev/null
      cp -af ${_locCnf}/nginx/nginx_wild_ssl.conf ${_WILD_SSL_VHOST}
      _nginx_wild_ssl_fleet_gate
      sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g" ${_WILD_SSL_VHOST}
      [ -e "/etc/nginx/no_ktls.conf" ] \
        && sed -i "/ssl_conf_command Options.*KTLS/d" ${_WILD_SSL_VHOST}
    fi
  fi
}

_nginx_ktls_control_update() {
  ### KTLS opt-out signal. `ssl_conf_command Options KTLS` on OpenSSL 3.2+ can
  ### throw recv() (5: Input/output error) alerts that abort TLS connections
  ### mid-request (kernel kTLS RX returns EIO on a control record - alert,
  ### handshake or TLS 1.3 KeyUpdate - see nginx issue 651). This control file
  ### lets an operator shed KTLS server-wide via _NGINX_KTLS=NO: the provision
  ### render reads it (like basic_nginx.conf) to leave nginx_has_ktls FALSE, and
  ### the static wild-ssl / ssl_proxy fronts strip their KTLS line on deploy.
  ### Default _NGINX_KTLS=YES removes the file, so KTLS stays on unchanged.
  if [ "${_NGINX_KTLS}" = "NO" ]; then
    mkdir -p /etc/nginx
    if [ ! -e "/etc/nginx/no_ktls.conf" ]; then
      echo "# KTLS disabled server-wide via _NGINX_KTLS=NO in barracuda.cnf" \
        > /etc/nginx/no_ktls.conf
    fi
  else
    rm -f /etc/nginx/no_ktls.conf
  fi
}

_nginx_quic_bpf_probe() {
  ### The only test that exercises the eBPF init behind quic_bpf before the
  ### directive is written: nginx -t skips it (no SO_REUSEPORT during a
  ### config test), and on a real start a failed init refuses to start Nginx
  ### at all. So start a throwaway master from a minimal config -- same
  ### binary, same worker count, one QUIC listener with reuseport on a
  ### loopback port -- and see whether it lives. Returns 0 only for a master
  ### that started and logged no complaint. Its life is bounded to a few
  ### seconds, and the Nginx monitor leaves a master of this title alone.
  local _pDir="/run/boa-nginx-quic-bpf-probe"
  local _pCnf="${_pDir}/nginx.conf"
  local _pPid="${_pDir}/nginx.pid"
  local _pLog="${_pDir}/error.log"
  local _pCrt="/etc/ssl/private/nginx-wild-ssl.crt"
  local _pKey="/etc/ssl/private/nginx-wild-ssl.key"
  local _pPort="" _try _wrk _usr _mPid="" _w _rc=1
  [ -x "/usr/sbin/nginx" ] || return 1
  [ -e "${_pCrt}" ] && [ -e "${_pKey}" ] || return 1
  command -v ss > /dev/null 2>&1 || return 1
  ### Below the ephemeral range, and -a so that a connected UDP socket (which
  ### -l would not list) counts as busy too.
  for _try in 28443 28444 28445 28446; do
    if ! ss -Huna 2> /dev/null | grep -q "[:.]${_try} "; then
      _pPort="${_try}"
      break
    fi
  done
  [ -n "${_pPort}" ] || return 1
  _wrk=$(sed -n 's/^worker_processes[[:space:]]\{1,\}\([a-z0-9]\{1,\}\);.*/\1/p' \
    /etc/nginx/nginx.conf 2> /dev/null | head -n 1)
  [ -n "${_wrk}" ] || _wrk="auto"
  _usr=$(sed -n 's/^user[[:space:]]\{1,\}\([a-zA-Z0-9_. -]\{1,\}\);.*/\1/p' \
    /etc/nginx/nginx.conf 2> /dev/null | head -n 1)
  [ -n "${_usr}" ] || _usr="www-data"
  ### A master left by a pass that was killed mid-probe still holds its port
  ### and would outlive the config removed below.
  for _mPid in $(pgrep -f "^nginx: master process /usr/sbin/nginx -c ${_pCnf}" 2> /dev/null); do
    pkill -9 -P "${_mPid}" 2> /dev/null
    kill -9 "${_mPid}" 2> /dev/null
  done
  _mPid=""
  rm -rf "${_pDir}"
  mkdir -p "${_pDir}" || return 1
  chmod 700 "${_pDir}"
  {
    echo "user ${_usr};"
    echo "worker_processes ${_wrk};"
    echo "pid ${_pPid};"
    echo "error_log ${_pLog} notice;"
    echo "quic_bpf on;"
    echo "events {"
    echo "  worker_connections 64;"
    echo "}"
    echo "http {"
    echo "  access_log off;"
    echo "  server {"
    echo "    listen 127.0.0.1:${_pPort} quic reuseport;"
    echo "    ssl_certificate ${_pCrt};"
    echo "    ssl_certificate_key ${_pKey};"
    echo "  }"
    echo "}"
  } > "${_pCnf}"
  if /usr/sbin/nginx -c "${_pCnf}" > /dev/null 2>&1; then
    _w=0
    while [ ! -s "${_pPid}" ] && [ "${_w}" -lt 4 ]; do
      sleep 0.5
      _w=$(( _w + 1 ))
    done
    _mPid=$( { tr -dc '0-9' < "${_pPid}"; } 2> /dev/null )
    if [ -n "${_mPid}" ] \
      && [ "$(cat /proc/${_mPid}/comm 2> /dev/null)" = "nginx" ]; then
      _rc=0
      ### The verdict is read now, before the teardown below can write its
      ### own alert (a worker killed by signal) into the same log.
      if grep -qiE "\[(emerg|alert|crit)\]|bpf.*(fail|error)" "${_pLog}" 2> /dev/null; then
        _rc=1
      fi
    fi
  fi
  ### Stop it whatever the verdict, and by its own identity only -- the pid
  ### file, or failing that the config path in its title: a plain name match
  ### would take the box's real Nginx with it, and a master left behind
  ### would keep the port and read as the real one to the Nginx monitor.
  if [ -z "${_mPid}" ]; then
    _mPid=$(pgrep -f "^nginx: master process /usr/sbin/nginx -c ${_pCnf}" 2> /dev/null | head -n 1)
  fi
  if [ -n "${_mPid}" ] \
    && [ "$(cat /proc/${_mPid}/comm 2> /dev/null)" = "nginx" ]; then
    kill -QUIT "${_mPid}" 2> /dev/null
    _w=0
    while kill -0 "${_mPid}" 2> /dev/null && [ "${_w}" -lt 4 ]; do
      sleep 0.5
      _w=$(( _w + 1 ))
    done
    if kill -0 "${_mPid}" 2> /dev/null; then
      pkill -9 -P "${_mPid}" 2> /dev/null
      kill -9 "${_mPid}" 2> /dev/null
    fi
  fi
  ### Nothing of this title may survive the config it was started from.
  for _mPid in $(pgrep -f "^nginx: master process /usr/sbin/nginx -c ${_pCnf}" 2> /dev/null); do
    pkill -9 -P "${_mPid}" 2> /dev/null
    kill -9 "${_mPid}" 2> /dev/null
  done
  rm -rf "${_pDir}"
  return ${_rc}
}

_nginx_quic_bpf_sync() {
  ### An Nginx reload hands the inherited UDP sockets to the new workers, so
  ### every HTTP/3 transfer in flight is reset within seconds of it -- and a
  ### BOA box reloads every few minutes (tasks, ban lists). quic_bpf routes
  ### each QUIC packet to the worker that owns its connection, which lets
  ### the old workers drain as they do for TCP. It lives in its own main.d
  ### fragment, written only while the live probe passes, because a box
  ### where the eBPF init fails would otherwise have an Nginx that refuses
  ### to start. _NGINX_QUIC_BPF=NO in barracuda.cnf sheds it for good; the
  ### latch is left after an init that failed with the fragment in place
  ### (here on the enabling reload, or by the Nginx monitor after a failed
  ### start) and holds it off until an operator removes it.
  local _mDir="/etc/nginx/main.d"
  local _frag="${_mDir}/quic_bpf.conf"
  local _latch="${_mDir}/quic_bpf.failed"
  local _cnf="/etc/nginx/nginx.conf"
  local _eLog="/var/log/nginx/error.log"
  local _want=NO _why="" _kMaj _kMin _eOld _eNow
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_quic_bpf_sync"
  fi
  [ -e "${_cnf}" ] && [ -x "/usr/sbin/nginx" ] || return 0
  mkdir -p "${_mDir}"
  ### Left only by a monitor killed in the middle of its trial start.
  rm -f "${_frag}.trial"
  if ! grep -q "^include /etc/nginx/main.d/\*\.conf;" "${_cnf}"; then
    ### A nginx.conf from before the template carried the include line: it is
    ### replaced once per release only, so add the line in place.
    cp -af "${_cnf}" "${_cnf}.pre-main-d"
    sed -i "0,/^pid .*;/s|^pid .*;|&\ninclude /etc/nginx/main.d/*.conf;|" "${_cnf}"
    ### Restored by rename, so that a configtest running beside this one
    ### never reads half a file.
    if ! grep -q "^include /etc/nginx/main.d/\*\.conf;" "${_cnf}"; then
      mv -f "${_cnf}.pre-main-d" "${_cnf}"
      _msg "INFO: nginx.conf has no pid line to put the main.d include after; left as it is"
    elif ! nginx -t > /dev/null 2>&1; then
      mv -f "${_cnf}.pre-main-d" "${_cnf}"
      _msg "ALERT: nginx -t rejected the main.d include; previous nginx.conf restored"
    fi
    rm -f "${_cnf}.pre-main-d"
  fi
  _kMaj=$(uname -r | cut -d. -f1 | tr -dc '0-9')
  _kMin=$(uname -r | cut -d. -f2 | tr -dc '0-9')
  if [ "${_NGINX_QUIC_BPF}" = "NO" ]; then
    _why="_NGINX_QUIC_BPF=NO"
  elif [ -e "${_latch}" ]; then
    _why="${_latch} is present, delete it to probe again"
  elif ! grep -q "^include /etc/nginx/main.d/\*\.conf;" "${_cnf}"; then
    _why="nginx.conf does not include main.d"
  elif [ -z "${_kMaj}" ] || [ -z "${_kMin}" ] \
    || [ "${_kMaj}" -lt 5 ] \
    || { [ "${_kMaj}" -eq 5 ] && [ "${_kMin}" -lt 7 ]; }; then
    _why="it needs Linux 5.7 or newer"
  elif ! /usr/sbin/nginx -V 2>&1 | grep -Fq -- ' --with-http_v3_module'; then
    _why="this Nginx has no HTTP/3 module"
  elif _nginx_quic_bpf_probe; then
    _want=YES
  else
    ### Once more before a verdict that withdraws a working fragment: the
    ### probe can lose its port, or be swept up by a monitor's restart.
    sleep 3
    if _nginx_quic_bpf_probe; then
      _want=YES
    else
      _why="the start-up probe failed on this system"
    fi
  fi
  if [ "${_want}" = "YES" ]; then
    if [ ! -e "${_frag}" ]; then
      echo "quic_bpf on;" > "${_frag}"
      if nginx -t > /dev/null 2>&1; then
        _eOld=$( { wc -l < "${_eLog}"; } 2> /dev/null | tr -dc '0-9' )
        [ -n "${_eOld}" ] || _eOld=0
        _mrun "service nginx reload"
        sleep 3
        ### A reload only logs a failed eBPF init and carries on, and this is
        ### the one init that sees the box's real listeners and the running
        ### master's limits. Left alone, the fragment would sit here until
        ### the next real start refused to come up.
        _eNow=$( { wc -l < "${_eLog}"; } 2> /dev/null | tr -dc '0-9' )
        [ -n "${_eNow}" ] || _eNow=0
        [ "${_eNow}" -ge "${_eOld}" ] || _eOld=0
        if tail -n "+$(( _eOld + 1 ))" "${_eLog}" 2> /dev/null \
          | grep -qE "ngx_quic_bpf_module failed|failed to create BPF"; then
          rm -f "${_frag}"
          echo "$(date) The eBPF init failed when quic_bpf was enabled by reload; the fragment was removed. Delete this file to let the next barracuda pass probe again." > "${_latch}"
          _mrun "service nginx reload"
          _msg "ALERT: Nginx could not initialise quic_bpf on reload; left off, see ${_latch}"
        else
          _msg "INFO: HTTP/3 transfers now survive Nginx reloads (quic_bpf enabled)"
        fi
      else
        rm -f "${_frag}"
        _msg "ALERT: nginx -t rejected ${_frag}; quic_bpf left off"
      fi
    fi
  else
    if [ -e "${_frag}" ]; then
      rm -f "${_frag}"
      if nginx -t > /dev/null 2>&1; then
        _mrun "service nginx reload"
      fi
      _msg "INFO: quic_bpf disabled: ${_why}"
    elif [ "${_NGINX_QUIC_BPF}" != "NO" ]; then
      ### Say why: a quiet decline reads exactly like a quiet success.
      _msg "INFO: quic_bpf stays off: ${_why}"
    fi
  fi
}

_nginx_ssl_proxy_local_refusal() {
  ### Every HTTPS proxy in pre.d (a control panel's, or a per-site one made by
  ### xoct ssl-gen) connects to its vhost from the box's own address, which
  ### that vhost admits to its loopback-only paths. A proxy written before the
  ### template refused them gets the template's own block here, taken from
  ### this pass's build tree: a panel would otherwise wait for its instance's
  ### next octopus pass, and nothing regenerates a per-site proxy. A file
  ### without the anchor line is left alone, and every insert is undone when
  ### the config no longer tests clean.
  local _src="${_bldPth}/aegir/tools/system/conf/ssl_proxy.conf"
  local _preD="/var/aegir/config/server_master/nginx/pre.d"
  local _bak _p _any=""
  grep -q boa_panel_local "${_src}" 2>/dev/null || return 0
  _bak=$(mktemp -d /var/backups/.boa-ssl-proxy.XXXXXX 2>/dev/null) || return 0
  awk '/### Loopback-only paths of the vhost behind this proxy/ { p = 1; print "  ###" }
    p && NF { print }
    p && /return 403;/ { r = 1 }
    r && /^  }$/ { exit }' "${_src}" > "${_bak}/.block"
  if ! grep -q 'set $boa_panel_local "";' "${_bak}/.block" \
    || ! grep -q "return 403;" "${_bak}/.block"; then
    rm -rf "${_bak}"
    return 0
  fi
  for _p in "${_preD}"/*ssl_proxy.conf; do
    [ -f "${_p}" ] && [ ! -L "${_p}" ] || continue
    grep -q boa_panel_local "${_p}" && continue
    grep -q "^  log_not_found " "${_p}" || continue
    cp -af "${_p}" "${_bak}/" || continue
    awk -v blk="${_bak}/.block" '{ print }
      !d && /^  log_not_found / { while ((getline _l < blk) > 0) print _l; d = 1 }' \
      "${_bak}/${_p##*/}" > "${_p}"
    _any="yes"
  done
  if [ -n "${_any}" ] && ! nginx -t > /dev/null 2>&1; then
    for _p in "${_bak}"/*ssl_proxy.conf; do
      [ -f "${_p}" ] && cat "${_p}" > "${_preD}/${_p##*/}"
    done
  fi
  rm -rf "${_bak}"
}

_nginx_ssl_proxy_panel_lock() {
  ### The vhost behind every HTTPS proxy in pre.d applies the IDS bans and
  ### its site's IP lists to the proxy's own address, which the lists always
  ### admit and no ban names, so a proxy written before the template judged
  ### the real visitor lets anyone into a locked control panel. It gets the
  ### template's lines, taken from this pass's build tree, for the account in
  ### its header and the domain in its file name; a proxy for a moved account
  ### (server_name _) gets the ban only, as ssl-gen writes it there. A file
  ### without its anchors or with an unexpected account or domain is left
  ### alone, and every insert is undone when the config no longer tests clean.
  local _src="${_bldPth}/aegir/tools/system/conf/ssl_proxy.conf"
  local _preD="/var/aegir/config/server_master/nginx/pre.d"
  local _bak _p _n _dom _oct _any=""
  grep -q boa_panel_lock "${_src}" 2>/dev/null || return 0
  _bak=$(mktemp -d /var/backups/.boa-ssl-lock.XXXXXX 2>/dev/null) || return 0
  awk '/### IDS bans and the IP lists of the site behind this proxy/ { p = 1; print "  ###" }
    p && NF { print }
    p && /includes\/user_admin_access\/_domain_name/ { exit }' "${_src}" > "${_bak}/.block"
  awk '/^### The variables of the \/user \+ \/admin list/ { p = 1 }
    p { print }
    p && /^include / { exit }' "${_src}" > "${_bak}/.map"
  if ! grep -q "return 444;" "${_bak}/.block" \
    || ! grep -q "includes/ip_access/_domain_name" "${_bak}/.block" \
    || ! grep -q "includes/user_admin_access/_domain_name" "${_bak}/.block" \
    || ! grep -q "^include .*/user_admin_access_map/_domain_name" "${_bak}/.map"; then
    rm -rf "${_bak}"
    return 0
  fi
  for _p in "${_preD}"/*ssl_proxy.conf; do
    [ -f "${_p}" ] && [ ! -L "${_p}" ] || continue
    grep -q boa_panel_lock "${_p}" && continue
    grep -q "^  log_not_found " "${_p}" || continue
    grep -q "^server {" "${_p}" || continue
    _n=${_p##*/}
    _dom=${_n#z_}
    _dom=${_dom%_ssl_proxy.conf}
    _oct=$(awk '/^### Secure HTTPS proxy \(START\) / { print $6; exit }' "${_p}")
    [[ "${_dom}" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || continue
    [[ "${_oct}" =~ ^[a-z][a-z0-9_-]*$ ]] || continue
    cp -af "${_p}" "${_bak}/" || continue
    if [ "$(awk '$1 == "server_name" { print $2; exit }' "${_p}")" = "_;" ]; then
      grep -v "^ *include " "${_bak}/.block" > "${_bak}/.use"
      grep -v "^include " "${_bak}/.map" > "${_bak}/.usemap"
    else
      sed -e "s/_oct_uid/${_oct}/g" -e "s/_domain_name/${_dom}/g" \
        "${_bak}/.block" > "${_bak}/.use"
      sed -e "s/_oct_uid/${_oct}/g" -e "s/_domain_name/${_dom}/g" \
        "${_bak}/.map" > "${_bak}/.usemap"
    fi
    awk -v blk="${_bak}/.use" -v map="${_bak}/.usemap" '
      !m && /^server [{]/ { while ((getline _l < map) > 0) print _l; m = 1 }
      { print }
      !d && /^  log_not_found / { while ((getline _l < blk) > 0) print _l; d = 1 }' \
      "${_bak}/${_n}" > "${_p}"
    _any="yes"
  done
  ### One domain's lists never belong in a catch-all proxy: ssl-gen drops
  ### them there, but an older xoct or xcopy run against this template
  ### leaves them in, marker and all, which the loop above then skips.
  for _p in "${_preD}"/*ssl_proxy.conf; do
    [ -f "${_p}" ] && [ ! -L "${_p}" ] || continue
    [ "$(awk '$1 == "server_name" { print $2; exit }' "${_p}")" = "_;" ] || continue
    grep -q "^ *include /data/disk/.*/includes/\(ip_access\|user_admin_access\|user_admin_access_map\)/" "${_p}" || continue
    _n=${_p##*/}
    [ -e "${_bak}/${_n}" ] || cp -af "${_p}" "${_bak}/" || continue
    sed "/^ *include \/data\/disk\/.*\/includes\/\(ip_access\|user_admin_access\|user_admin_access_map\)\//d" \
      "${_p}" > "${_bak}/.strip" || continue
    cat "${_bak}/.strip" > "${_p}"
    _any="yes"
  done
  if [ -n "${_any}" ] && ! nginx -t > /dev/null 2>&1; then
    for _p in "${_bak}"/*ssl_proxy.conf; do
      [ -f "${_p}" ] && cat "${_p}" > "${_preD}/${_p##*/}"
    done
  fi
  rm -rf "${_bak}"
}

_nginx_ssl_proxy_extra_names() {
  ### A control panel's extra names (log/extra_domain.txt) belong to its own
  ### HTTPS proxy. An older ssl-gen gave them to every per-site proxy of a
  ### run too, and nginx keeps whichever proxy in pre.d sorts first, so a
  ### site's proxy could answer for a locked panel from the box's own
  ### address. Drop a panel's extra names from every server_name in pre.d
  ### whose file is not a panel listing them, keeping each file's own name
  ### and its www. alias. Names compare as nginx does, without case; every
  ### change is undone when the config no longer tests clean. edgetest
  ### reports the same names with the same awk. Both files sit in the
  ### account's own log/, so they are read only inside the real directory,
  ### never through a link or blocked on a FIFO put there.
  local _preD="/var/aegir/config/server_master/nginx/pre.d"
  local _map="" _x _lg _hm _e _bak _p _n _dom _any=""
  for _x in /data/disk/*/log/extra_domain.txt; do
    [ -f "${_x}" ] || continue
    _lg="${_x%/extra_domain.txt}"
    _hm=$(_acct_read_in "${_lg}" domain.txt | head -c 256 | tr -d '\r\n' | tr 'A-Z' 'a-z')
    [[ "${_hm}" =~ ^[a-z0-9][a-z0-9.-]*$ ]] && [ "${#_hm}" -le 253 ] || continue
    while IFS= read -r _e || [ -n "${_e}" ]; do
      [[ "${_e}" =~ ^[a-z0-9*][a-z0-9.*-]*$ ]] && [ "${#_e}" -le 253 ] \
        && _map="${_map} ${_e}=${_hm}"
    done < <(_acct_read_in "${_lg}" extra_domain.txt | head -c 65536 \
      | tr -s ' \t\r' '\n' | tr 'A-Z' 'a-z')
  done
  [ -n "${_map}" ] || return 0
  _bak=$(mktemp -d /var/backups/.boa-ssl-names.XXXXXX 2>/dev/null) || return 0
  for _p in "${_preD}"/*ssl_proxy.conf; do
    [ -f "${_p}" ] && [ ! -L "${_p}" ] || continue
    _n=${_p##*/}
    _dom=${_n#z_}
    _dom=${_dom%_ssl_proxy.conf}
    awk -v map="${_map}" -v dom="${_dom}" '
      BEGIN {
        dom = tolower(dom)
        n = split(map, a, " ")
        for (i = 1; i <= n; i++) {
          k = a[i]; v = a[i]; sub(/=.*/, "", k); sub(/^[^=]*=/, "", v)
          own[k] = (k in own) ? own[k] " " v : v
        }
      }
      !d && $1 == "server_name" && $2 != "_;" {
        d = 1; out = ""; drop = 0
        l = $0; gsub("\r", " ", l); nf = split(l, f)
        for (i = 2; i <= nf; i++) {
          t = f[i]; sub(/;$/, "", t); lt = tolower(t)
          if (t == "") continue
          if (i > 2 && lt != "www." dom && (lt in own) &&
            index(" " own[lt] " ", " " dom " ") == 0) { drop = 1; continue }
          out = out " " t
        }
        if (drop && match($0, /^[ \t]*server_name[ \t]+/)) {
          print substr($0, 1, RLENGTH) substr(out, 2) ";"; next
        }
      }
      { print }' "${_p}" > "${_bak}/.names" || continue
    cmp -s "${_bak}/.names" "${_p}" && continue
    cp -af "${_p}" "${_bak}/" || continue
    cat "${_bak}/.names" > "${_p}"
    _any="yes"
  done
  if [ -n "${_any}" ] && ! nginx -t > /dev/null 2>&1; then
    for _p in "${_bak}"/*ssl_proxy.conf; do
      [ -f "${_p}" ] && cat "${_p}" > "${_preD}/${_p##*/}"
    done
  fi
  rm -rf "${_bak}"
}

_nginx_migration_proxy_client() {
  ### A site proxy that xoct or xcopy wrote before its template handed on
  ### the wildcard SSL front's visitor still gives the new host 127.0.0.1
  ### for every HTTPS request that came through the front. It gets the
  ### template's block, taken from this pass's build tree, and its client
  ### headers point at that block's variable. The vhost dirs belong to the
  ### instance users, so each vhost is read and rewritten only inside its
  ### real directory: a link or a FIFO at a name is skipped, never followed,
  ### the text is judged and staged in a root-only dir, and the new file
  ### lands as _nginx_sed_here puts it; every change is undone when the
  ### config no longer tests clean.
  local _src="${_bldPth}/aegir/tools/system/conf/proxy.conf"
  local _d _v _k _p
  grep -q boa_mig_client "${_src}" 2>/dev/null || return 0
  _d=$(mktemp -d /var/backups/.boa-mig-proxy.XXXXXX 2>/dev/null) || return 0
  awk '/### HTTPS for a site without its own certificate reaches this vhost/ { p = 1; print "  ###" }
    p { print }
    p && /^  }$/ { exit }' "${_src}" > "${_d}/block"
  if ! grep -q 'set $boa_mig_client $remote_addr;' "${_d}/block" \
    || ! grep -q 'set $boa_mig_client $http_x_real_ip;' "${_d}/block"; then
    rm -rf "${_d}"
    return 0
  fi
  while IFS= read -r -u 9 _v; do
    _acct_in_real_dir "${_v}" _nginx_migration_proxy_client_here "${_d}" "${_v}"
  done 9< <(_nginx_acct_dirs config/server_master/nginx/vhost.d)
  if ls "${_d}"/*.path > /dev/null 2>&1 && ! nginx -t > /dev/null 2>&1; then
    for _k in "${_d}"/*.path; do
      _p=$(cat "${_k}")
      _acct_in_real_dir "${_p%/*}" \
        _nginx_sed_here "${_p##*/}" -e "1r ${_k%.path}.orig" -e d
    done
  fi
  rm -rf "${_d}"
}
# Every plain HTTP proxy vhost of the current (pinned) vhost.d $2 that still
# lacks the block (one grep lists the proxy vhosts), read as _acct_read_here
# reads it into the root-only dir $1, rewritten there and put back as
# _nginx_sed_here puts it; each one changed leaves <n>.orig and <n>.path in
# $1 for the rollback.
_nginx_migration_proxy_client_here() {
  local _d="${1}" _v="${2}" _f _k
  while IFS= read -r -d '' _f; do
    [ -f "./${_f}" ] && [ ! -L "./${_f}" ] || continue
    _k=$(mktemp "${_d}/v.XXXXXX" 2> /dev/null) || continue
    _acct_read_here "${_f}" > "${_k}.orig"
    if grep -q "Plain HTTP proxy (START)" "${_k}.orig" \
      && ! grep -q boa_mig_client "${_k}.orig" \
      && grep -q 'CF-Connecting-IP  *\$remote_addr;' "${_k}.orig" \
      && grep -q "^  log_not_found " "${_k}.orig"; then
      awk -v blk="${_d}/block" '
        /proxy_set_header[ \t]+(X-Real-IP|CF-Connecting-IP)[ \t]+\$remote_addr;/ { sub(/\$remote_addr;/, "$boa_mig_client;") }
        { print }
        !d && /^  log_not_found / { while ((getline _l < blk) > 0) print _l; d = 1 }' \
        "${_k}.orig" > "${_k}.new"
      if [ -s "${_k}.new" ] \
        && _nginx_sed_here "${_f}" -e "1r ${_k}.new" -e d; then
        printf '%s\n' "${_v}/${_f}" > "${_k}.path"
        continue
      fi
    fi
    rm -f -- "${_k}" "${_k}.orig" "${_k}.new"
  done < <(_nginx_names_with_here "*" -F -e "Plain HTTP proxy (START)")
}

_nginx_config_update_fix() {
  local _tplDir _tpl _incDir _vhDir
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_config_update_fix"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _mrun "service cron start"
    _force_advanced_nginx_config
    sleep 8
    _mrun "service nginx restart"
  else
    if [ -e "/var/aegir/config" ]; then
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/adminer.* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/cgp.* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/chive.* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/sqlbuddy.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:80;/  listen  \*:80;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/adminer.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/cgp.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/chive.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/sqlbuddy.* &> /dev/null
      wait
      sed -i "s/SSLv3 TLSv1;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/SSLv3 TLSv1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/TLSv1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      if [ -d "/data/u" ]; then
        _nginx_acct_sed_if "config/server_*/nginx/vhost.d" "*" \
          -F -e "TLSv1.1 TLSv1.2 TLSv1.3;" -- \
          "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
      fi
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/vhost.d/*
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*gzip_vary .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*gzip_vary .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_buffer_size .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_buffer_size .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_buffers .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_buffers .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_busy_buffers_size .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_busy_buffers_size .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_temp_file_write_size .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_temp_file_write_size .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_buffering .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_buffering .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/proxy_redirect .*/proxy_redirect             off;\n    gzip_vary                  off;\n    proxy_buffering            off;/g" \
        /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/proxy_redirect .*/proxy_redirect             off;\n    gzip_vary                  off;\n    proxy_buffering            off;/g" \
        /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*ssl_stapling .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/.*ssl_stapling_verify .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/.*resolver .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/.*resolver_timeout .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/.*http2.*on;//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/ssl_prefer_server_ciphers .*/ssl_prefer_server_ciphers on;\n  http2 on;/g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/add_header Vary .*//g" /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
      _nginx_ssl_proxy_local_refusal
      _nginx_ssl_proxy_panel_lock
      _nginx_ssl_proxy_extra_names
      _nginx_migration_proxy_client
    fi
    if [ "${_NGINX_SPDY}" = "YES" ]; then
      sed -i "s/:443;/:443 ssl;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443;/:443 ssl;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/:443 ssl spdy;/:443 ssl;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443 ssl spdy;/:443 ssl;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/:443 ssl http2;/:443 ssl;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443 ssl http2;/:443 ssl;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
    fi
    if [ -e "/root/.install.modern.openssl.cnf" ] \
      && [ -x "/usr/local/ssl3/bin/openssl" ]; then
      _SSL_BINARY=/usr/local/ssl3/bin/openssl
    else
      _SSL_BINARY=/usr/local/ssl/bin/openssl
    fi
    _SSL_ITD=$(${_SSL_BINARY} version 2>&1 | tr -d "\n" | cut -d" " -f2 | awk '{ print $1}' 2>&1)
    if [ "${_SSL_ITD}" = "${_OPENSSL_MODERN_VRN}" ] \
      || [ "${_SSL_ITD}" = "${_OPENSSL_EOL_VRN}" ] \
      || [ "${_SSL_ITD}" = "${_OPENSSL_LEGACY_VRN}" ] \
      || [[ "${_SSL_ITD}" =~ "1.1.0" ]] \
      || [[ "${_SSL_ITD}" =~ "1.0.2" ]] \
      || [[ "${_SSL_ITD}" =~ "1.0.1" ]]; then
      _PFS_READY=YES
    else
      _PFS_READY=NO
    fi
    if [ "${_PFS_READY}" = "YES" ] \
      && [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
      _ALLOW_NGINX_FORWARD_SECRECY=YES
      _SSL_PROTOCOLS="TLSv1.2 TLSv1.3;"
      _SSL_CIPHERS="TLS_AES_128_GCM_SHA256:  \
        TLS_AES_256_GCM_SHA384:  \
        TLS_CHACHA20_POLY1305_SHA256:  \
        ECDHE-RSA-AES256-GCM-SHA384:  \
        ECDHE-ECDSA-AES256-GCM-SHA384:  \
        ECDHE-RSA-AES256-SHA384:  \
        ECDHE-ECDSA-AES256-SHA384:  \
        AES256-GCM-SHA384:  \
        ECDHE-ECDSA-CHACHA20-POLY1305:  \
        ECDHE-RSA-CHACHA20-POLY1305:  \
        DHE-RSA-AES256-CCM:  \
        DHE-RSA-AES256-CCM8:  \
        DHE-RSA-AES128-CCM:  \
        DHE-RSA-AES128-CCM8:  \
        ECDHE-RSA-AES128-GCM-SHA256:  \
        ECDHE-ECDSA-AES128-GCM-SHA256:  \
        DHE-RSA-AES128-GCM-SHA256:  \
        DHE-DSS-AES128-GCM-SHA256:  \
        kEDH+AESGCM:  \
        ECDHE-RSA-AES128-SHA256:  \
        ECDHE-ECDSA-AES128-SHA256:  \
        ECDHE-RSA-AES128-SHA:  \
        ECDHE-ECDSA-AES128-SHA:  \
        ECDHE-RSA-AES256-SHA:  \
        ECDHE-ECDSA-AES256-SHA:  \
        DHE-RSA-AES128-SHA256:  \
        DHE-RSA-AES128-SHA:  \
        DHE-DSS-AES128-SHA256:  \
        DHE-RSA-AES256-SHA256:  \
        DHE-DSS-AES256-SHA:  \
        DHE-RSA-AES256-SHA:  \
        AES128-GCM-SHA256:  \
        AES128-SHA256:  \
        AES256-SHA256:  \
        AES128-SHA:  \
        AES256-SHA:  \
        AES:  \
        \!aNULL:  \
        \!eNULL:  \
        \!EXPORT:  \
        \!DES:  \
        \!RC4:  \
        \!MD5:  \
        \!PSK:  \
        \!aECDH:  \
        \!EDH-DSS-DES-CBC3-SHA:  \
        \!EDH-RSA-DES-CBC3-SHA:  \
        \!KRB5-DES-CBC3-SHA:  \
        \!ECDHE-ECDSA-AES128-SHA256:  \
        \!ECDHE-ECDSA-AES256-SHA384;"
      _SSL_CIPHERS=$(echo "${_SSL_CIPHERS}" | sed "s/ //g" 2>&1)
    else
      _ALLOW_NGINX_FORWARD_SECRECY=NO
    fi
    if [ "${_ALLOW_NGINX_FORWARD_SECRECY}" = "YES" ]; then
      sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
        /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
        /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
        /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
        /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
    fi

    ###
    ### Nginx: Convert all vhosts to wildcard mode on Barracuda upgrade
    ### to avoid extended downtime until all Octopus instances will receive
    ### full upgrade, if IP based listen directive was used before.
    ###
    if [ -e "/var/aegir" ]; then
      sed -i "s/.*listen.*127.0.0.1:80;.*//g" \
        /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
      sed -i "s/listen .*\*:80;/listen  \*:80;/g" \
        /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
    fi
    if [ -d "/data/u" ]; then
      _nginx_acct_sed "config/server_*" nginx.conf \
        -e "s/.*listen.*127.0.0.1:80;.*//g" \
        -e "s/listen .*\*:80;/listen  \*:80;/g" &> /dev/null
      ### One grep per vhost.d names the vhosts with a line these change: a
      ### listen line not yet in the exact form written below, an ssl on
      ### line, or the TLSv1.1 list; the others are left untouched.
      _nginx_acct_sed_if "config/server_*/nginx/vhost.d" "*" \
        -P -e '(?:^(?!  listen  \*:80;(?!.*\*:80;)).*listen .*\*:80;)|(?:^(?!  listen  \*:443(?!.*\*:443)).*listen .*\*:443)|(?:ssl .*on;)|(?:TLSv1\.1 TLSv1\.2 TLSv1\.3;)' -- \
        -e "s/.*listen .*\*:80;/  listen  \*:80;/g" \
        -e "s/.*listen .*\*:443/  listen  \*:443/g" \
        -e "s/.*ssl .*on;//g" \
        -e "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" &> /dev/null
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/vhost.d/*
      wait
    fi

    if [ -d "/data/u" ]; then
      for _OCT in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
        _pthPrN="provision/http/Provision/Config/Nginx"
        _tplDir=""
        if [ -e "${_OCT}/.drush/sys/drush_make" ]; then
          _tplDir="${_OCT}/.drush/sys/${_pthPrN}"
        elif [ -e "${_OCT}/.drush/drush_make" ]; then
          _tplDir="${_OCT}/.drush/${_pthPrN}"
        fi
        [ -n "${_tplDir}" ] || continue
        for _tpl in server vhost vhost_disabled; do
          _acct_in_real_dir "${_tplDir}" \
            _nginx_sed_here "${_tpl}.tpl.php" "s/\!empty.*';/'*';/g" &> /dev/null
        done
      done
    fi

    ###
    ### Delete any ghost, outdated or broken config includes and vhosts
    ### in all Octopus instances which could break Nginx restart
    ###
    if [ -d "/data/u" ]; then
      while IFS= read -r -u 8 _incDir; do
        _nginx_drop_marked "${_incDir}" will_expire_in
      done 8< <(_nginx_acct_dirs config/includes)
      for Vght in `ls /data/disk/*/log/CANCELLED 2> /dev/null \
        | cut -d"/" -f4 \
        | awk '{ print $1}'`; do
        while IFS= read -r -u 8 _vhDir; do
          _acct_in_real_dir "${_vhDir}" _nginx_rm_files_here
        done 8< <(_nginx_acct_dirs_below "/data/disk/${Vght}" "config/server_*/nginx/vhost.d")
      done
      _nginx_acct_sed .drush/sys/provision/http/Provision/Service/http "*.conf" \
        -e "s/OctopusMicroNoCacheID/NoCacheID/g" \
        -e "s/OctopusNCookie/AegirCookie/g" \
        -e "s/OctopusNoCacheID/NoCacheID/g" &> /dev/null
    fi
    if [ -e "/var/aegir" ]; then
      _wildPth="/var/aegir/.drush/sys/provision/http/Provision/Service/http/*.conf"
      sed -i "s/OctopusMicroNoCacheID/NoCacheID/g" ${_wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNCookie/AegirCookie/g"      ${_wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNoCacheID/NoCacheID/g"      ${_wildPth} &> /dev/null
      wait
      sed -i "s/60/180/g" /var/aegir/config/server_*/nginx.conf  &> /dev/null
      wait
      sed -i "s/300/180/g" /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
    fi
    _validate_public_ip &> /dev/null
    _CRON_IP=${_THISHTIP//[^0-9.]/}
    if [ ! -e "/root/.local.IP.list" ]; then
      rm -f /root/.tmp.IP.list*
      rm -f /root/.local.IP.list*
      for _IP in `hostname -I`;do echo ${_IP} >> /root/.tmp.IP.list;done
      for _IP in `cat /root/.tmp.IP.list \
        | sort \
        | uniq`; do
        echo "${_IP} # local IP address" >> /root/.local.IP.list
      done
      rm -f /root/.tmp.IP.list*
    fi
    _IP_IF_PRESENT=$(grep "${_CRON_IP}" /root/.local.IP.list 2>&1)
    if [[ "${_IP_IF_PRESENT}" =~ "${_CRON_IP}" ]]; then
      _IP_PRESENT=YES
    else
      _IP_PRESENT=NO
    fi
    if [ ! -z "${_CRON_IP}" ] \
      && [ "${_IP_PRESENT}" = "YES" ] \
      && [ -e "/root/.local.IP.list" ]; then
      _master_fix_multi_ip_cron_access
    fi
    _mrun "service nginx reload"
  fi
}
