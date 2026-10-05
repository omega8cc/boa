
export _tRee=dev
export _rLsn="BOA-5.88.855"
export _rlsE="${_rLsn}-${_tRee}"
export _bRnh="5.x-${_tRee}"
_hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"


#
# The master's own .tmp and .drush: the CLI keeps no php.ini there (its
# version's global ini applies, the temp paths come from TMPDIR), only the
# directories and the release serial's stamp.
_php_cli_local_dirs_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_cli_local_dirs_update"
  fi
  if [ ! -z "${1}" ]; then
    _DRUSH_FILE="/var/aegir/drush/${1}"
  else
    _DRUSH_FILE="/var/aegir/drush/drush.php"
  fi
  _U_HD="/var/aegir/.drush"
  _U_TP="/var/aegir/.tmp"
  if [ ! -e "${_DRUSH_FILE}" ]; then
    return 1  # Exit the function but continue the script
  fi
  if [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
    # aegir owns /var/aegir and can swap .tmp or .drush for a link: a link
    # there is removed, the age sweep never resolves a path through a name
    # (bare path, -execdir), and every remove and write happens inside the
    # real directory
    [ -L "${_U_TP}" ] && rm -f "${_U_TP}"
    [ -L "${_U_HD}" ] && rm -f "${_U_HD}"
    mkdir -p ${_U_TP}
    mkdir -p ${_U_HD}
    _U_REAL="$(cd -P -- /var/aegir 2> /dev/null && pwd -P)"
    # aged out only when .tmp is aegir's own (or the empty one just made):
    # a root-owned directory of the tree renamed onto the name is left alone
    ( cd -P -- "${_U_TP}" 2> /dev/null && [ "$(pwd -P)" = "${_U_REAL}/.tmp" ] || exit 0
      [ "$(stat -c %U .)" = "aegir" ] \
        || { [ "$(stat -c %u .)" = "0" ] && [ -z "$(ls -A . 2> /dev/null)" ]; } || exit 0
      touch . && chmod 02755 .
      find . -mindepth 1 -mtime +0 -execdir rm -rf {} \; &> /dev/null )
    # the stamp is created exclusively, never through a link at the name
    ( cd -P -- "${_U_HD}" 2> /dev/null && [ "$(pwd -P)" = "${_U_REAL}/.drush" ] || exit 0
      rm -f -- ./.ctrl.php* "./.ctrl.${_tRee}.${_xSrl}.pid"
      echo | dd of="./.ctrl.${_tRee}.${_xSrl}.pid" conv=excl status=none 2> /dev/null
    )
  fi
  chown -R aegir:aegir ${_U_HD}
  chown -R aegir:aegir ${_U_TP}
}

#
# The master's hostmaster tree holds directories every account can write
# (sites/all/{modules,libraries,themes} in group users, the site's files/
# in group www-data), so any name there can be a link or a hard link an
# account planted. The tree is handed to aegir as chown -R did, and files/
# given its modes (its directories 02775, its files 0664, so never
# set-ID), only inside the real directory $1, from
# the directory find walked (-execdir) and through a handle opened without
# following a link or blocking on a FIFO: a directory, or a regular file
# with a single link, never a link, a FIFO or a hard-linked file (one root
# does not own only loses its set-ID bits).
#
# $1 handed to $2 (owner[:group] names, as chown -R took them).
_master_reown_in() {
  local _u _g=-1
  _u=$(id -u -- "${2%%:*}" 2> /dev/null)
  if [[ "${2}" == *:* ]]; then
    _g=$(getent group "${2#*:}" 2> /dev/null | cut -d: -f3)
  fi
  [[ "${_u}" =~ ^[0-9]+$ && "${_g}" =~ ^(-1|[0-9]+)$ ]] || return 1
  _acct_in_real_dir "${1}" _master_reown_here "${_u}" "${_g}"
}
_master_reown_here() {
  perl -e "${_ACCT_REOWN_PL}" -- "${1}" "${2}" . \
    && env PATH=/usr/local/bin:/usr/bin:/bin find . -mindepth 1 \
      \( -type d -o -type f \) \
      -execdir perl -e "${_ACCT_REOWN_PL}" -- "${1}" "${2}" {} +
}
# A mode set through a handle on each name given (d: a directory, f: a
# regular file with a single link), as chmod(1) sets a numeric one: a
# directory keeps its set-user-ID and set-group-ID bits unless the mode has
# five digits (02775). A hard-linked regular file root does not own only
# loses those two bits, which never widens it.
_MASTER_NOFOLLOW_CHMOD_PL='use Fcntl;
my ($t, $ms) = (shift @ARGV, shift @ARGV);
my ($m, $k) = (oct($ms), length($ms) < 5 ? 06000 : 0);
for my $f (@ARGV) {
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if ($t eq "f" && -f _ && $s[3] == 1) {
    chmod($m, $h);
  } elsif ($t eq "f" && -f _ && $s[4] != 0 && ($s[2] & 06000)) {
    chmod($s[2] & 01777, $h);
  } elsif ($t eq "d" && -d _) {
    chmod($m | ($s[2] & $k), $h);
  }
  close($h);
}'
# $1 and every directory below it set to $2, every regular file below it
# to $3. Files take their own mode, never the directories' set-group-ID one:
# any account can write a file there, and a setgid executable would run
# with the store's group.
_master_mode_all_in() {
  _acct_in_real_dir "${1}" _master_mode_all_here "${2}" "${3}"
}
_master_mode_all_here() {
  perl -e "${_MASTER_NOFOLLOW_CHMOD_PL}" d "${1}" . 2> /dev/null
  env PATH=/usr/local/bin:/usr/bin:/bin find . -mindepth 1 -type d \
    -execdir perl -e "${_MASTER_NOFOLLOW_CHMOD_PL}" d "${1}" {} +
  env PATH=/usr/local/bin:/usr/bin:/bin find . -mindepth 1 -type f \
    -execdir perl -e "${_MASTER_NOFOLLOW_CHMOD_PL}" f "${2}" {} +
}
# As _master_mode_all_in, for a files store of a master converted to its own
# web group: its private set (./private, and the subtrees nginx denies, a
# case-insensitive prefix after any files/) keeps the modes the conversion
# gave it, with no world bits. POSIX extended, read after -regextype
# posix-extended.
_MASTER_DENIED_RE='\./(civicrm/(configandlog|custom|upload|templates_c)|backup_migrate|config_)[^/]*|.*/files/(civicrm/(configandlog|custom|upload|templates_c)|backup_migrate|config_)[^/]*'
_master_mode_pub_in() {
  _acct_in_real_dir "${1}" _master_mode_pub_here "${2}" "${3}"
}
_master_mode_pub_here() {
  perl -e "${_MASTER_NOFOLLOW_CHMOD_PL}" d "${1}" . 2> /dev/null
  env PATH=/usr/local/bin:/usr/bin:/bin find . -mindepth 1 -regextype posix-extended \
    \( -path ./private -o -iregex "${_MASTER_DENIED_RE}" \) -prune -o -type d \
    -execdir perl -e "${_MASTER_NOFOLLOW_CHMOD_PL}" d "${1}" {} +
  env PATH=/usr/local/bin:/usr/bin:/bin find . -mindepth 1 -regextype posix-extended \
    \( -path ./private -o -iregex "${_MASTER_DENIED_RE}" \) -prune -o -type f \
    -execdir perl -e "${_MASTER_NOFOLLOW_CHMOD_PL}" f "${2}" {} +
}

_master_web_group() {
  # The master's own web group, wg-aegir, the way _web_group_state reads an
  # account's: "<state> <gid> wg-aegir", "none - -" when there is none. Its
  # holders are aegir and the master pool users wwwNN; anyone else holding
  # it makes it foreign. The record is /root/.aegir.web-group.txt, root's
  # own file, "wg-aegir gid=<n> phase=<A|B> ...".
  local _e _gid _u _r _rg="" _rgid="" _rph="" IFS=$' \t\n'
  _e=$(getent group wg-aegir 2> /dev/null) || { echo "none - -"; return 0; }
  _gid=$(printf '%s' "${_e}" | cut -d: -f3)
  case "${_gid}" in
    ""|*[!0-9]*) echo "none - -"; return 0 ;;
  esac
  for _u in $(getent group | awk -F: -v g="${_gid}" '$3 == g { print $4 }' | tr ',' ' ') \
    $(getent passwd | awk -F: -v g="${_gid}" '$4 == g { print $1 }'); do
    [[ "${_u}" =~ ^(aegir|www[0-9][0-9])$ ]] \
      || { echo "foreign ${_gid} wg-aegir"; return 0; }
  done
  _r="/root/.aegir.web-group.txt"
  if [ -f "${_r}" ] && [ ! -L "${_r}" ] \
    && [ "$(stat -c %u -- "${_r}" 2> /dev/null)" = "0" ]; then
    read -r _rg _rgid _rph _ < "${_r}" || :
  fi
  if [ "${_rg}" != "wg-aegir" ] || [ "${_rgid}" != "gid=${_gid}" ]; then
    echo "held ${_gid} wg-aegir"
  elif [ "${_rph}" = "phase=B" ]; then
    echo "phaseb ${_gid} wg-aegir"
  elif [ "${_rph}" = "phase=A" ]; then
    echo "converted ${_gid} wg-aegir"
  else
    echo "held ${_gid} wg-aegir"
  fi
}
# The group the hostmaster site's files/ take: the master's own web group,
# wg-aegir, once its record says the master is converted to it; www-data
# otherwise, as always.
_master_files_group() {
  case "$(_master_web_group)" in
    converted\ *|phaseb\ *) echo "wg-aegir" ;;
    *) echo "www-data" ;;
  esac
}


#
# Download and extract from core archive.
_get_core_ext() {
  if [ ! -z "${1}" ]; then
    _max_attempts=10
    _attempt_num=1
    _success=0
    while [ ${_attempt_num} -le ${_max_attempts} ]; do
      [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Attempt ${_attempt_num} of ${_max_attempts}: Downloading $1..."
      if curl ${_crlGet} "https://${_USE_MIR}/core/$1" -o "$1"; then
        _success=1
        break
      else
        [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Attempt ${_attempt_num} failed."
        _attempt_num=$((_attempt_num+1))
        if [ "${_attempt_num}" -le "${_max_attempts}" ]; then
          [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Retrying in 9 seconds..."
          sleep 9
        fi
      fi
    done
    if [ "${_success}" -eq 1 ]; then
      if [ ! -z "${2}" ]; then
        _extract_archive "${1}" "${2}"
      else
        _extract_archive "${1}"
      fi
    else
      _msg "OOPS: Failed to download https://${_USE_MIR}/core/$1 after ${_max_attempts} attempts"
      return 1  # Exit the function but continue the script
    fi
  fi
}

#
# Generate provision backend db_passwd.
_provision_backend_dbpass_generate() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _provision_backend_dbpass_generate"
  fi
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
    if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt 128 ]; then
      _PWD_CHARS=128
    fi
  fi

  if [ "${_STRONG_PASSWORDS}" = "YES" ] \
    || [ "${_PWD_CHARS}" -gt 32 ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
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
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
      else
        _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _isPythonTwo="$(which python2)"
    _isPythonThree="$(which python3)"
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    if [ -x "${_isPythonThree}" ]; then
      _ENC_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${_ESC_PASS}'''))")
    elif [ -x "${_isPythonTwo}" ]; then
      _ENC_PASS=$(python2 -c "import urllib; print urllib.quote('''${_ESC_PASS}''')")
    fi
    _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
  fi

  if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt 9 ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
      _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
      _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
      else
        _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _ENC_PASS="${_ESC_PASS}"
  fi

  echo "${_ESC_PASS}" > ${_L_SYS}
  chown aegir:aegir ${_L_SYS} &> /dev/null
  chmod 0600 ${_L_SYS}

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _THIS_DB_HOST="${_hName}"
      _SQL_CONNECT=localhost
    elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    else
      _THIS_DB_HOST=localhost
      _SQL_CONNECT=localhost
    fi
    _AEGIR_HOST="${_hName}"
  else
    _AEGIR_HOST="${_hName}"
    ### _SQL_CONNECT="${_THIS_DB_HOST}"
    ### Master Instance will use local DB server
    _SQL_CONNECT=localhost
  fi

  if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
    _AEGIR_HOST="${_hName}"
    _SQL_CONNECT=localhost
  fi

  _ESC="*.*"
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null

  if [ "${_STATUS}" = "INIT" ]; then
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL7 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_ADBU}'@'localhost';
CREATE USER IF NOT EXISTS '${_ADBU}'@'%';
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' WITH GRANT OPTION;
ALTER USER '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
  else
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL8 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
        _write_proxysql_adm_cnf &> /dev/null
        mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
      fi
      _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
      ${_C_SQL} "DROP USER '${_ADBU}'@'${_AEGIR_HOST}';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'${_RESOLVEIP}';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'localhost';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'127.0.0.1';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'%';" &> /dev/null
      mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_ADBU}'@'localhost';
CREATE USER IF NOT EXISTS '${_ADBU}'@'%';
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' WITH GRANT OPTION;
ALTER USER '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    fi
  fi

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    _EXTRA_GRANTS=NO
  else
    _LOCAL_HOST="${_hName}"
    _find_correct_ip
    _LOCAL_IP="${_LOC_IP}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL9 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_ADBU}'@'localhost';
CREATE USER IF NOT EXISTS '${_ADBU}'@'%';
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' WITH GRANT OPTION;
ALTER USER '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
  fi
  mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
}

#
# Ensure Ægir's task queue dispatcher is enabled. BOA always drives the queue
# through hosting-dispatch, so a disabled dispatcher is drift -- it is left
# behind when hosting-setup's self-test exits non-zero during a (re)install.
# Detect and re-enable it, reporting only when a correction was needed.
_ensure_hosting_dispatch_enabled() {
  local _disp_fix
  _disp_fix=$(su -s /bin/bash - aegir -c "drush8 @hostmaster ev 'if (!variable_get(\"hosting_dispatch_enabled\", FALSE)) { variable_set(\"hosting_dispatch_enabled\", TRUE); echo \"REENABLED\"; }'" 2>/dev/null)
  if [[ "${_disp_fix}" =~ REENABLED ]]; then
    _msg "INFO: hosting_dispatch_enabled was off; task queue dispatcher re-enabled"
  fi
}

#
# Sync provision backend db_passwd.
_provision_backend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _provision_backend_dbpass_sync"
  fi
  _find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"
  _RESOLVEIP="${_LOC_IP}"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Syncing provision backend db_passwd..."
  fi
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _ADBU=aegir_root
  _L_SYS="/var/aegir/backups/system/.${_ADBU}.pass.txt"
  ### Never trust the moved file's inherited mode -- set 0600 explicitly.
  mv -f ${_L_SYS} ${_L_SYS}-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
  chmod 0600 ${_L_SYS}-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
  _provision_backend_dbpass_generate
  if [ ! -z "${_ESC_PASS}" ] && [ ! -z "${_ENC_PASS}" ]; then
    su -s /bin/bash - aegir -c "drush8 @hostmaster \
      sqlq \"UPDATE hosting_db_server SET db_passwd='${_ESC_PASS}' \
      WHERE db_user='${_ADBU}'\"" &> /dev/null
    wait
    _SQL_CONNECT=localhost
    if [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    fi
    _ESC="*.*"
    _USE_DB_USER="${_ADBU}"
    _USE_AEGIR_HOST="${_hName}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL10 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    sed -i "s/mysql:\/\/${_ADBU}:.*/mysql:\/\/${_ADBU}:${_ENC_PASS}@${_SQL_CONNECT}',/g" \
      /var/aegir/.drush/server_*.alias.drushrc.php &> /dev/null
    wait
  fi
  mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
  # Only now, with its rows made for the last time and the server alias
  # holding the new password: the broker proves aegir_root by a login with
  # the password that alias holds.
  case "${_SQL_CONNECT}" in
    localhost|127.0.0.1) _dbctl_rerecord aegir_root ;;
  esac
  su -s /bin/bash - aegir -c "drush8 cc drush" &> /dev/null
  wait
  rm -rf /var/aegir/.tmp/cache
  if [ -e "/var/aegir/.drush/server_localhost.alias.drushrc.php" ]; then
    su -s /bin/bash aegir -c "drush8 @hostmaster hosting-task @server_localhost \
      verify --force" &> /dev/null
  else
    su -s /bin/bash aegir -c "drush8 @hostmaster hosting-task @server_master \
      verify --force" &> /dev/null
  fi
  wait
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Running hosting-dispatch/hosting-tasks..."
  fi
  _ensure_hosting_dispatch_enabled
  su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-dispatch" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  # The sweeps above run their tasks synchronously (--fork=0), but a runner
  # forked by the regular dispatch can still be in flight. The master
  # upgrade is about to swap the live drush/provision trees under
  # /var/aegir; a task runner still executing from them dies on its next
  # lazy include without ever writing its final status - that write only
  # happens in the runner's own shutdown handler - leaving the task parked
  # at PROCESSING and the queue wedged behind it for the whole running-items
  # window. Give in-flight runners a bounded window to finish instead of
  # racing them; the dispatcher-side reaper heals whatever this misses.
  _QUIESCE_WAIT=0
  while pgrep -u aegir -f "drush.php.*hosting-task" > /dev/null 2>&1; do
    _QUIESCE_WAIT=$(( _QUIESCE_WAIT + 1 ))
    if [[ "${_QUIESCE_WAIT}" -ge 60 ]]; then
      break
    fi
    sleep 5
  done
}

#
# Sync hostmaster frontend db_passwd.
_hostmaster_frontend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _hostmaster_frontend_dbpass_sync"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Syncing hostmaster frontend db_passwd..."
  fi
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _THIS_HM_SPTH=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
    | grep "site_path'" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1)
  _THIS_HM_DBUR=$(cat ${_THIS_HM_SPTH}/drushrc.php \
    | grep "options\['db_user'\] = " \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g" 2>&1)
  _THIS_HM_DBPD=$(cat ${_THIS_HM_SPTH}/drushrc.php \
    | grep "options\['db_passwd'\] = " \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g" 2>&1)
  _THIS_HM_DBNM=$(cat ${_THIS_HM_SPTH}/drushrc.php \
    | grep "options\['db_name'\] = " \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g" 2>&1)
  if [ -e "${_THIS_HM_SPTH}" ] \
    && [ ! -z "${_THIS_HM_DBUR}" ] \
    && [ ! -z "${_THIS_HM_DBPD}" ]; then
    _SQL_CONNECT=localhost
    if [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    fi
    ### The panel works in its own database only: grant just that one,
    ### escaped as provisioning writes it (a bare _ matches any character).
    ### An unreadable name keeps the old grant rather than locking the panel
    ### out mid-upgrade.
    if [[ "${_THIS_HM_DBNM}" =~ ^[A-Za-z0-9_]{1,64}$ ]]; then
      _ESC="\`${_THIS_HM_DBNM//_/\\_}\`.*"
      _GOPT=""
    else
      _ESC="*.*"
      _GOPT="WITH GRANT OPTION"
      _msg "ALRT: master hostmaster db_name not readable, its panel user keeps rights on all databases"
    fi
    _USE_DB_USER="${_THIS_HM_DBUR}"
    _USE_AEGIR_HOST="${_hName}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL11 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_THIS_HM_DBPD}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' ${_GOPT};
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' ${_GOPT};
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_THIS_HM_DBPD}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_THIS_HM_DBPD}';
EOFMYSQL
    _hostmaster_oldhost_dbuser_drop
    case "${_SQL_CONNECT}" in
      localhost|127.0.0.1) _dbctl_rerecord master-panel ;;
    esac
  fi
  mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
}

#
# Where the files of this box name each of the database users given, one
# line per mention:
#   db <user> <alias>         the master_db of a server alias: an instance's
#                             own backend user
#   panel <user> <site path>  the drushrc.php of a control panel: the site of
#                             a hostmaster or hm alias, in its root's
#                             hostmaster tree
#   site <user> <site path>   the drushrc.php of any other site
# Every alias in /var/aegir/.drush and each /data/disk/*/.drush is read, and
# each site path an alias names inside its own root has its drushrc.php
# read, both as _acct_read_whole_in reads them; a site path outside that
# root is no site of that root. Non-zero, the last line "unread <path>",
# when a file cannot be read whole, or an alias name or a site path inside
# the root is not a plain one: an unread file never counts as naming
# nothing. One link is passed over, since it names nothing of its own: an
# alias name, no server alias's, that is a link whose text is exactly
# hostmaster.alias.drushrc.php or that file's full path in the same .drush,
# while that file is there as a regular file. Every other link is unread.
# One text in master.sh.inc and satellite.sh.inc.
_hostmaster_db_users_named() {
  local _a _f _h _t _p _s _k _u _e=()
  for _u in "$@"; do
    _e+=( -e "${_u}" )
  done
  for _a in /var/aegir /data/disk/*; do
    [ -d "${_a}/.drush" ] || continue
    for _f in "${_a}"/.drush/*.alias.drushrc.php; do
      [ -e "${_f}" ] || [ -L "${_f}" ] || continue
      case "${_f##*/}" in
        *[!A-Za-z0-9._-]*)
          echo "unread ${_f}"
          return 1
          ;;
      esac
      # the link earlier releases left under the panel's name: what it
      # leads to is read in this loop under its own name, as a panel's
      _h="${_a}/.drush/hostmaster.alias.drushrc.php"
      if [ -L "${_f}" ] && [[ "${_f##*/}" != server_* ]] \
        && [ -f "${_h}" ] && [ ! -L "${_h}" ]; then
        _t=$(readlink -n "${_f}" 2> /dev/null; echo .)
        case "${_t%.}" in
          hostmaster.alias.drushrc.php|"${_h}") continue ;;
        esac
      fi
      if ! _t=$(_acct_read_whole_in "${_a}/.drush" "${_f##*/}"); then
        echo "unread ${_f}"
        return 1
      fi
      case "${_f##*/}" in
        server_*)
          while IFS= read -r _u; do
            echo "db ${_u} ${_f}"
          done < <(printf '%s\n' "${_t}" \
            | sed -n "s#^ *'master_db' => '[a-z]*://\([^:@']*\):.*#\1#p" \
            | grep -xF "${_e[@]}")
          ;;
      esac
      while IFS= read -r _p; do
        case "${_p}" in
          "${_a}"/*) ;;
          *) continue ;;
        esac
        case "${_p}" in
          *[!A-Za-z0-9._/-]*|*//*|*/|*/./*|*/../*|*/.|*/..)
            echo "unread ${_p}"
            return 1
            ;;
        esac
        [ -e "${_p}/drushrc.php" ] || [ -L "${_p}/drushrc.php" ] || continue
        if ! _s=$(_acct_read_whole_in "${_p}" drushrc.php); then
          echo "unread ${_p}/drushrc.php"
          return 1
        fi
        _k=site
        case "${_f##*/}" in
          hostmaster.alias.drushrc.php|hm.alias.drushrc.php)
            case "${_p}" in
              "${_a}"/aegir/distro/*/sites/?*|/var/aegir/*/sites/?*) _k=panel ;;
            esac
            ;;
        esac
        while IFS= read -r _u; do
          echo "${_k} ${_u} ${_p}"
        done < <(printf '%s\n' "${_s}" | grep -owF "${_e[@]}" | sort -u)
      done < <(printf '%s\n' "${_t}" \
        | sed -n "s/^ *'site_path' => '\([^']*\)',.*/\1/p")
    done
  done
  return 0
}
# How the log names the database user $1: after the longest of this box's
# account names, or the first label of the master's uri, that it begins
# with and then a non-digit, else after $2 (an account's name, or master).
# One text in master.sh.inc and satellite.sh.inc.
_hostmaster_db_user_label() {
  local _a _n _uri _o="${2}" _l=0
  for _a in /data/disk/*; do
    [ -d "${_a}/.drush" ] || continue
    _n="${_a##*/}"
    [[ "${1}" == "${_n}"[!0-9]* ]] && [ "${#_n}" -gt "${_l}" ] || continue
    _o="${_n}"
    _l="${#_n}"
  done
  _uri=$(sed -n "s/^ *'uri' => '\([^']*\)',.*/\1/p" \
    /var/aegir/.drush/hm.alias.drushrc.php 2> /dev/null | head -n 1)
  _n="${_uri%%.*}"
  if [ "${_n}" != "${_uri}" ] && [[ "${1}" == "${_n}"[!0-9]* ]] \
    && [ "${#_n}" -gt "${_l}" ]; then
    _o=master
  fi
  if [ "${_o}" = "master" ]; then
    echo "earlier master panel database user"
  else
    echo "${_o} earlier panel database user"
  fi
}
# The candidates given after $1 (the pass's own: an account's name, or
# master) are users of this box's own plain server with the shape and
# prefix of an earlier panel's, none the live panel's user or an account's
# name, each with SUPER on a host row. One whose host names are not all
# plain ones is left alone. Then one that the master_db of a server alias
# or a panel's drushrc.php names stays as it is (an instance's own user, or
# a panel's that its own pass converges); one that another site's
# drushrc.php names keeps its database grants and loses its global rights
# on every row (a site that took over a leftover's name gets a row of its
# own without them); one with a database of its name, or without SUPER on
# every row, stays as it is (the files read are this box's only, and a
# server other boxes keep their databases on holds their panels' users);
# any other is dropped, the rows a read right before the drop finds, and
# only while that read still finds SUPER on every row and no database of
# its name. A read that fails leaves that user alone, and a file that
# cannot be read leaves every one. One text in master.sh.inc and
# satellite.sh.inc.
_hostmaster_db_users_settle() {
  local _own="${1}" _u _h _s _c _rows _named _ok _all _w _l _list=() _schema=" " _part=" "
  local _C=(mysql --silent --skip-column-names -u root -h"${_SQL_CONNECT}"
    -P"${_THIS_DB_PORT}" --protocol=tcp --database=mysql -e)
  shift
  for _u in "$@"; do
    _rows=$("${_C[@]}" "SELECT Host, Super_priv FROM mysql.user WHERE User='${_u}'" \
      2> /dev/null) || continue
    _c=$("${_C[@]}" "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${_u}'" \
      2> /dev/null) || continue
    [[ "${_c}" =~ ^[0-9]+$ ]] && [ -n "${_rows}" ] || continue
    _ok=YES
    _all=YES
    while IFS=$'\t' read -r _h _s; do
      [ "${_s}" = "Y" ] || _all=NO
      case "${_h}" in
        ""|*[!A-Za-z0-9._%:-]*) _ok=NO ;;
      esac
    done <<< "${_rows}"
    [ "${_ok}" = "YES" ] || continue
    _list+=( "${_u}" )
    [ "${_c}" = "0" ] || _schema+="${_u} "
    [ "${_all}" = "YES" ] || _part+="${_u} "
  done
  [ "${#_list[@]}" -gt 0 ] || return 0
  if ! _named=$(_hostmaster_db_users_named "${_list[@]}"); then
    _w=$(printf '%s\n' "${_named}" | sed -n 's/^unread //p' | tail -n 1 \
      | tr -d '\n' | tr -c 'A-Za-z0-9._/-' '?' | cut -c1-200)
    case "${_w}" in
      /data/disk/?*) _l="${_w#/data/disk/}"; _l="account ${_l%%/*}" ;;
      *) _l="master" ;;
    esac
    if [ "${_own}" = "master" ]; then
      _msg "ALRT: earlier master panel database users kept: ${_w} (${_l}) could not be read"
    else
      _msg "ALRT: ${_own} earlier panel database users kept: ${_w} (${_l}) could not be read"
    fi
    return 0
  fi
  for _u in "${_list[@]}"; do
    printf '%s\n' "${_named}" | grep -qE "^(db|panel) ${_u} " && continue
    _l=$(_hostmaster_db_user_label "${_u}" "${_own}")
    _w=$(printf '%s\n' "${_named}" | sed -n "s#^site ${_u} ##p" | head -n 1)
    if [ -n "${_w}" ]; then
      _rows=$("${_C[@]}" "SELECT Host FROM mysql.user WHERE User='${_u}'" \
        2> /dev/null) || continue
      [ -n "${_rows}" ] || continue
      if _hostmaster_db_user_global_revoke "${_u}" "${_rows}"; then
        _msg "INFO: ${_l} ${_u} kept with its database grants only, global rights revoked (site ${_w} names it)"
      else
        _msg "ALRT: ${_l} ${_u} global rights not revoked, or a database grant lost (site ${_w} names it)"
      fi
      continue
    fi
    [[ "${_schema}${_part}" == *" ${_u} "* ]] && continue
    # the walk takes seconds, and a site created meanwhile brings a
    # database of this name and a row without SUPER: read both again
    _rows=$("${_C[@]}" "SELECT Host, Super_priv FROM mysql.user WHERE User='${_u}'" \
      2> /dev/null) || continue
    _c=$("${_C[@]}" "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${_u}'" \
      2> /dev/null) || continue
    [ "${_c}" = "0" ] && [ -n "${_rows}" ] || continue
    _all=YES
    while IFS=$'\t' read -r _h _s; do
      [ "${_s}" = "Y" ] || _all=NO
      case "${_h}" in
        ""|*[!A-Za-z0-9._%:-]*) _all=NO ;;
      esac
    done <<< "${_rows}"
    [ "${_all}" = "YES" ] || continue
    while IFS=$'\t' read -r _h _s; do
      "${_C[@]}" "DROP USER '${_u}'@'${_h}'" &> /dev/null
    done <<< "${_rows}"
    _c=$("${_C[@]}" "SELECT COUNT(*) FROM mysql.user WHERE User='${_u}'" 2> /dev/null)
    if [ "${_c}" = "0" ]; then
      _msg "INFO: ${_l} ${_u} dropped (every global right, no database, no drushrc.php names it)"
    else
      _msg "ALRT: ${_l} ${_u} could not be dropped"
    fi
  done
}
# Takes from the user $1, on each host row given in $2 (one per line), the
# global privileges SHOW GRANTS lists for that row, each by name, and its
# global grant option: a REVOKE ALL on *.* takes the database grants too
# (measured on Percona 8.4). A database grant that goes all the same is
# granted back as it read before. Zero when no row keeps a global right and
# every row has the database grants it had. One text in master.sh.inc and
# satellite.sh.inc.
_hostmaster_db_user_global_revoke() {
  local _u="${1}" _h _g _d _p _n=0 _b=0 _a=0
  local _C=(mysql --silent --skip-column-names --raw -u root -h"${_SQL_CONNECT}"
    -P"${_THIS_DB_PORT}" --protocol=tcp --database=mysql -e)
  while IFS= read -r _h; do
    case "${_h}" in
      ""|*[!A-Za-z0-9._%:-]*) return 1 ;;
    esac
    _g=$("${_C[@]}" "SHOW GRANTS FOR '${_u}'@'${_h}'" 2> /dev/null) || return 1
    _d=$(printf '%s\n' "${_g}" | grep '^GRANT .* ON .* TO ' | grep -v ' ON \*\.\* TO ')
    _b=$((_b + $(printf '%s\n' "${_d}" | grep -c .)))
    while IFS= read -r _p; do
      _p="${_p#GRANT }"
      _p="${_p%% ON \*.\* TO *}"
      [[ "${_p}" =~ ^[A-Z_][A-Z_\ ,]*$ ]] && [ "${_p}" != "USAGE" ] || continue
      "${_C[@]}" "REVOKE ${_p} ON *.* FROM '${_u}'@'${_h}'" &> /dev/null
    done < <(printf '%s\n' "${_g}" | grep '^GRANT .* ON \*\.\* TO ')
    "${_C[@]}" "REVOKE GRANT OPTION ON *.* FROM '${_u}'@'${_h}'" &> /dev/null
    _g=$("${_C[@]}" "SHOW GRANTS FOR '${_u}'@'${_h}'" 2> /dev/null) || return 1
    while IFS= read -r _p; do
      [ -n "${_p}" ] || continue
      printf '%s\n' "${_g}" | grep -qxF -- "${_p}" && continue
      case "${_p}" in
        *";"*) continue ;;
      esac
      "${_C[@]}" "${_p}" &> /dev/null
    done <<< "${_d}"
    _g=$("${_C[@]}" "SHOW GRANTS FOR '${_u}'@'${_h}'" 2> /dev/null) || return 1
    _a=$((_a + $(printf '%s\n' "${_g}" | grep '^GRANT .* ON .* TO ' | grep -vc ' ON \*\.\* TO ')))
    _n=$((_n + $(printf '%s\n' "${_g}" | grep ' ON \*\.\* TO ' | grep -vc '^GRANT USAGE ON ')))
  done <<< "${2}"
  [ "${_n}" = "0" ] && [ "${_a}" = "${_b}" ]
}

#  A master panel database user an earlier release left with every global
# right under a name no upgrade reuses: named from the master's uri before
# the host was renamed, provisioning never re-grants, re-creates or drops
# it, and it still answers to the password its old drushrc.php held. A
# candidate has the shape provisioning gives a panel database (16
# characters of the uri without dots and dashes, or 14 of them and _0 to
# _9, or 13 and _10 to _99), begins with the first label of the master's
# uri (master, as in master.<host>) and then a non-digit, and has SUPER on
# a host row; the master panel's own user and an account's own user (named
# as the account) never are. _hostmaster_db_users_settle leaves alone one
# that a server alias names as its master_db or a panel's drushrc.php
# names; takes every global right, and nothing else, from one that another
# site's drushrc.php names, whether or not a database of its name exists;
# leaves alone any other with a database of its name or without SUPER on
# every host row; and drops the rest. No box keeps a record of a former
# panel name for good, so an operator's own user of exactly that shape
# under that prefix is treated the same: dropped when it holds SUPER on
# every host row, nothing names it and no database of its name exists,
# stripped of its global rights when a site names it. Only on the box's
# own plain server. The files read are this box's only, so a database of
# its name keeps a user: a server other boxes keep their databases on also
# holds their panels' users, which no file here names.
_hostmaster_oldhost_dbuser_drop() {
  local _uri _b _u _rows _cand=()
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _hostmaster_oldhost_dbuser_drop"
  fi
  case "${_SQL_CONNECT}" in
    localhost|127.0.0.1) ;;
    *) return 0 ;;
  esac
  [ "${_THIS_DB_PORT}" = "3306" ] || return 0
  [ -e "/root/.my.cluster_root_pwd.txt" ] && return 0
  _uri=$(sed -n "s/^ *'uri' => '\([^']*\)',.*/\1/p" \
    /var/aegir/.drush/hm.alias.drushrc.php 2> /dev/null | head -n 1)
  _b="${_uri%%.*}"
  [ "${_b}" != "${_uri}" ] || return 0
  [[ "${_b}" =~ ^[a-z][a-z0-9]{0,14}$ ]] || return 0
  _rows=$(mysql --silent --skip-column-names -u root -h"${_SQL_CONNECT}" \
    -P"${_THIS_DB_PORT}" --protocol=tcp --database=mysql \
    -e "SELECT DISTINCT User FROM mysql.user WHERE Super_priv='Y'" 2> /dev/null) \
    || return 0
  while IFS= read -r _u; do
    [[ "${_u}" =~ ^([a-z0-9]{16}|[a-z0-9]{14}_[0-9]|[a-z0-9]{13}_[1-9][0-9])$ ]] \
      || continue
    [[ "${_u}" == "${_b}"[!0-9]* ]] || continue
    [ "${_u}" = "${_THIS_HM_DBUR}" ] && continue
    [ -e "/data/disk/${_u}" ] && continue
    _cand+=( "${_u}" )
  done <<< "${_rows}"
  [ "${#_cand[@]}" -gt 0 ] || return 0
  _hostmaster_db_users_settle master "${_cand[@]}"
}

#
# Download for Drush Make Local build.
_master_download_for_local_build() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _master_download_for_local_build"
  fi
  _mL="/opt/tmp/make_local"
  mkdir -p ${_mL}
  if [ ! -e "${_mL}/hostmaster/hostmaster.make" ] \
    || [ ! -e "${_mL}/hosting/hosting.module" ] \
    || [ ! -e "${_mL}/drupal/modules/system/system.module" ]; then
    rm -rf ${_mL}
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading hostmaster modules..."
    fi
    if [ "${_DL_MODE}" = "BATCH" ]; then
      rm -rf /opt/tmp/make_local
      cd /opt/tmp
      _get_dev_ext "make_local.tar.gz"
      if [ -e "${_mL}/hostmaster/hostmaster.make" ] \
        && [ -e "${_mL}/hosting/hosting.module" ] \
        && [ -e "${_mL}/drupal/modules/system/system.module" ]; then
        [ -e "make_local.tar.gz" ] && rm -f make_local.tar.gz
      fi
    else
      mkdir -p ${_mL}
      cd ${_mL}
      ### Drupal Core
      _get_core_ext "${_DRUPAL7}.tar.gz"
      mv -f ${_mL}/${_DRUPAL7} ${_mL}/drupal
      ### Ægir Core
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hostmaster.git    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting.git       &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/eldir.git         &> /dev/null
      ### Ægir Golden + BOA Settings
        ${_gCb} 5.x-${_tRee} ${_gitHub}/aegir_objects.git                  &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_civicrm.git                &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_custom_settings.git        &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_deploy.git                 &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_git.git                    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_le.git                     &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_remote_import.git          &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_site_backup_manager.git    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_tasks_extra.git            &> /dev/null
        rm -rf */.git
      ### Ægir Drupal Contrib
      _get_dev_stc "admin_menu-7.x-3.0-rc7.tar.gz"
      _get_dev_stc "betterlogin-7.x-1.5.tar.gz"
      _get_dev_stc "ctools-7.x-1.21.tar.gz"
      _get_dev_stc "entity-7.x-1.12.tar.gz"
      _get_dev_stc "libraries-7.x-2.5.tar.gz"
      _get_dev_stc "module_filter-7.x-2.3.tar.gz"
      _get_dev_stc "openidadmin-7.x-1.0.tar.gz"
      _get_dev_stc "overlay_paths-7.x-1.3.tar.gz"
      _get_dev_stc "r4032login-7.x-1.8.tar.gz"
      _get_dev_stc "tfa_basic-7.x-1.1.tar.gz"
      _get_dev_stc "tfa-7.x-2.1.tar.gz"
      _get_dev_stc "timeago-7.x-2.3.tar.gz"
      _get_dev_stc "views_bulk_operations-7.x-3.7.tar.gz"
      _get_dev_stc "views-7.x-3.30.tar.gz"
      ### Ægir Third Party Libraries
      _get_dev_stc "qrcodejs.tar.gz"
      _get_dev_stc "timeagojs.tar.gz"
      _get_dev_stc "vuejs.tar.gz"
      ### BOA Drupal Contrib
      _get_dev_stc "environment_indicator-7.x-2.9.tar.gz"
      _get_dev_stc "features_extra-7.x-1.2.tar.gz"
      _get_dev_stc "features-7.x-2.15.tar.gz"
      _get_dev_stc "idna_convert-7.x-1.0.tar.gz"
      _get_dev_stc "revision_deletion-7.x-1.3.tar.gz"
      _get_dev_stc "strongarm-7.x-2.0.tar.gz"
      _get_dev_stc "tag1_d7es-7.x-1.4.tar.gz"
      _get_dev_stc "userprotect-7.x-1.3.tar.gz"
    fi
    find ${_mL} -type d -exec chmod 0755 {} \; &> /dev/null
    find ${_mL} -type f -exec chmod 0644 {} \; &> /dev/null
    chown -R root:root ${_mL}
  fi
}

#
_php_cli_drush_update() {
  if [ ! -z "${1}" ]; then
    _DRUSH_FILE="${_ROOT}/drush/${1}"
  else
    _DRUSH_FILE="${_ROOT}/drush/drush.php"
  fi
  if [ ! -e "${_DRUSH_FILE}" ]; then
    return 1  # Exit the function but continue the script
  fi
  if [ "${_PHP_CLI_VERSION}" = "8.6" ] \
    && [ -x "/opt/php86/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php86\/bin\/php/g" \
      ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.5" ] \
    && [ -x "/opt/php85/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php85\/bin\/php/g" \
      ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.4" ] \
    && [ -x "/opt/php84/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php84\/bin\/php/g" \
      ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.3" ] \
    && [ -x "/opt/php83/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php83\/bin\/php/g" \
      ${_DRUSH_FILE} &> /dev/null
  else
    _msg "FATAL ERROR: _PHP_CLI_VERSION must be set to one of supported values"
    _msg "FATAL ERROR: Aborting AegirM installer NOW!"
    rm -f /opt/tmp/status-AegirM-FAIL
    touch /opt/tmp/status-AegirM-FAIL
    exit 1
  fi
  # The shebang pin on drush.php is bypassed whenever the drush 8 finder
  # runs: it execs drush.launcher, which re-selects PHP via `which php`.
  # The launcher also cannot run at all via its stock `env sh` shebang,
  # because /bin/sh is websh, which refuses user-area scripts. Run it
  # under bash and default its native DRUSH_PHP to the pin -- default,
  # not override: websh exports DRUSH_PHP per invocation from the
  # static/control files (cli.info + instant phpNN.info switches), and
  # that runtime choice must always win over the baked pin.
  _DRUSH_LNCH="${_ROOT}/drush/drush.launcher"
  _LNCH_PHP="/opt/php${_PHP_CLI_VERSION//./}/bin/php"
  if [ -e "${_DRUSH_LNCH}" ] && [ -x "${_LNCH_PHP}" ]; then
    sed -i "1s/^#\!.*/#\!\/bin\/bash/" ${_DRUSH_LNCH} &> /dev/null
    sed -i "/^export DRUSH_PHP=/d" ${_DRUSH_LNCH} &> /dev/null
    sed -i "1a export DRUSH_PHP=\"\${DRUSH_PHP:-${_LNCH_PHP}}\"" ${_DRUSH_LNCH} &> /dev/null
  fi
}

#
_provision_backend_up() {
  if [ "${_DL_MODE}" = "BATCH" ]; then
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/drush_make
    rm -rf ${_ROOT}/.drush/sys/drush_make
    cd ${_ROOT}/.drush
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    _get_dev_ext "backend.tar.gz"
    mv -f ${_ROOT}/.drush/backend/sys ${_ROOT}/.drush/
    mv -f ${_ROOT}/.drush/backend/xts ${_ROOT}/.drush/
    mv -f ${_ROOT}/.drush/backend/usr ${_ROOT}/.drush/
    if [ -e "${_ROOT}/.drush/sys/provision/provision.inc" ] \
      && [ -d "${_ROOT}/.drush/xts/security_review" ] \
      && [ -d "${_ROOT}/.drush/usr/registry_rebuild" ]; then
      [ -e "${_ROOT}/.drush/backend" ] && rm -rf ${_ROOT}/.drush/backend*
    fi
  elif [ "${_DL_MODE}" = "GIT" ]; then
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/drush_make
    rm -rf ${_ROOT}/.drush/sys/drush_make
    cd ${_ROOT}/.drush
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    _rD="${_ROOT}/.drush"
    ${_gCb} ${_BRANCH_PRN} ${_gitHub}/provision.git      ${_rD}/sys/provision &> /dev/null
    ${_gCb} 7.x-1.x-dev ${_gitHub}/drupalgeddon.git      ${_rD}/usr/drupalgeddon &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/drush_ecl.git             ${_rD}/usr/drush_ecl &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/security_review.git       ${_rD}/xts/security_review &> /dev/null
    ${_gCb} 7.x-2.x ${_gitHub}/provision_boost.git       ${_rD}/xts/provision_boost &> /dev/null
    ${_gCb} 7.x-2.x ${_gitHub}/registry_rebuild.git      ${_rD}/usr/registry_rebuild &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/safe_cache_form_clear.git ${_rD}/usr/safe_cache_form_clear &> /dev/null
    rm -rf ${_rD}/*/.git
    rm -rf ${_rD}/*/*/.git
    cd ${_rD}/usr
    _get_dev_ext "clean_missing_modules.tar.gz"
    _get_dev_ext "utf8mb4_convert-7.x-1.3.tar.gz"
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    cd ${_ROOT}/.drush/sys
    _get_dev_ext "provision.tar.gz"
    cd ${_ROOT}/.drush/usr
    _get_dev_ext "clean_missing_modules.tar.gz"
    _get_dev_ext "drupalgeddon.tar.gz"
    _get_dev_ext "drush_ecl.tar.gz"
    _get_dev_ext "registry_rebuild.tar.gz"
    _get_dev_ext "safe_cache_form_clear.tar.gz"
    _get_dev_ext "utf8mb4_convert-7.x-1.3.tar.gz"
    cd ${_ROOT}/.drush/xts
    _get_dev_ext "provision_boost.tar.gz"
    _get_dev_ext "security_review.tar.gz"
  fi
}

#
_hostmaster_dr_up() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Downloading drush ${_DRUSH_VERSION}..."
  fi
  # Master-only helper: resolve the master home when the caller exported no
  # _ROOT (the barracuda process), and never run against an empty, missing
  # or '/' root -- the relative mv and the copy below would otherwise act on
  # root's HOME and the filesystem root.
  if [ -z "${_ROOT}" ] || [ ! -d "${_ROOT}" ]; then
    _ROOT=$(getent passwd aegir 2> /dev/null | cut -d: -f6)
    _ROOT="${_ROOT:-/var/aegir}"
  fi
  if [ -z "${_ROOT}" ] || [ ! -d "${_ROOT}" ] || [ "${_ROOT}" = "/" ]; then
    _msg "OOPS: master home '${_ROOT}' unusable; Drush not refreshed"
    return 1
  fi
  mkdir -p ${_ROOT}/backups/system
  chmod 700 ${_ROOT}/backups/system
  if ! cd ${_ROOT}; then
    _msg "OOPS: cannot enter ${_ROOT}; Drush not refreshed"
    return 1
  fi
  # Heal what the empty-_ROOT form left behind on earlier passes: a Drush
  # tree at /drush and its rotated copies under /backups/system, both
  # BOA-named and never legitimate at the filesystem root.
  [ -d "/drush" ] && [ ! -L "/drush" ] && [ -f "/drush/drush.php" ] \
    && [ -f "/drush/drush.info" ] && [ -f "/drush/includes/boa_extension_filter.inc" ] && rm -rf /drush
  [ -d "/backups/system" ] && rm -rf /backups/system/drush-pre-* &> /dev/null
  local _drCpFail=""
  if [ -f "/opt/tools/drush/8/drush/drush.php" ]; then
    mv -f drush ${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW} &> /dev/null
    cp -af /opt/tools/drush/8/drush ${_ROOT}/ || _drCpFail=YES
  else
    mv -f drush ${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW} &> /dev/null
    _get_dev_ext "drush-${_DRUSH_VERSION}.tar.gz"
    cd ${_ROOT}/drush/
    find ${_ROOT}/drush -type d -exec chmod 0755 {} \; &> /dev/null
    find ${_ROOT}/drush -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 755 ${_ROOT}/drush/drush
    chmod 755 ${_ROOT}/drush/drush.complete.sh
    chmod 755 ${_ROOT}/drush/drush.launcher
    chmod 755 ${_ROOT}/drush/drush.php
    chmod 755 ${_ROOT}/drush/unish.sh
    chmod 755 ${_ROOT}/drush/examples/drush.wrapper
    chmod 755 ${_ROOT}/drush/examples/git-bisect.example.sh
    chmod 755 ${_ROOT}/drush/examples/helloworld.script
  fi
  ### A failed copy or download left the master without Drush: put the tree
  ### rotated aside above back, rather than run without one until next pass.
  ### A copy that fails part way still leaves a drush.php behind, so its own
  ### status counts too; a failed download leaves no tree.
  if [ -n "${_ROOT}" ] \
    && { [ -n "${_drCpFail}" ] || [ ! -f "${_ROOT}/drush/drush.php" ]; } \
    && [ -f "${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW}/drush.php" ]; then
    rm -rf ${_ROOT}/drush
    mv -f ${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW} ${_ROOT}/drush
  fi
}

#
# Upgrade Ægir Master Instance.
_aegir_master_upgrade() {
  # Reached from the barracuda process, which exports no _ROOT: every
  # ${_ROOT}/... below then resolves against the filesystem root, and
  # _hostmaster_dr_up copied a full Drush tree to /drush and rotated the old
  # one into /backups/system on every pass (found 2026-09-02). The master
  # home is the aegir account's home, /var/aegir on every BOA box.
  if [ -z "${_ROOT}" ] || [ ! -d "${_ROOT}" ]; then
    _ROOT=$(getent passwd aegir 2> /dev/null | cut -d: -f6)
    _ROOT="${_ROOT:-/var/aegir}"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _aegir_master_upgrade"
  fi
  if _prompt_yes_no "Do you want to upgrade Ægir Master Instance?" ; then
    true
    _msg "INFO: Running Ægir Master Instance upgrade"
    if [ -x "/usr/bin/mysql_upgrade" ]; then
      _check_mysql_version
      if [ "${_DB_V}" = "5.7" ]; then
        _mrun "mysql_upgrade -u root --force"
      fi
    fi
    if [ -e "/var/aegir/use_proxysql.txt" ]; then
      _SQL_CONNECT=127.0.0.1
      _THIS_DB_PORT=6033
    else
      _THIS_DB_PORT=3306
    fi
    rm -f /opt/tmp/testecho*
    usermod -aG users aegir
    _sudoers_safe_append /etc/sudoers \
      "aegir ALL=NOPASSWD: /etc/init.d/nginx" "aegir ALL=NOPASSWD"
    _SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership fix-drupal-site-symlinks lock-local-drush-permissions)
    for SCRIPT in ${_SCRIPTS[@]}; do
      _sudoers_safe_append /etc/sudoers.d/${SCRIPT} \
        "aegir ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh"
    done

    _hostmaster_dr_up

    if [ ! -d "/var/aegir/.drush/sys/provision/http" ] \
      || [ ! -d "/var/aegir/drush/includes" ]; then
      rm -rf /var/aegir/.drush/{sys,xts,usr}
      rm -rf /var/aegir/.drush/{provision,drush_make}
      mkdir -p /var/aegir/.drush/{sys,xts,usr}
      ${_gCb} ${_BRANCH_PRN} ${_gitHub}/provision.git /var/aegir/.drush/sys/provision &> /dev/null
    fi
    _THIS_HM_ROOT=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
      | grep "root'" \
      | cut -d: -f2 \
      | awk '{ print $3}' \
      | sed "s/[\,']//g" 2>&1)
    _THIS_HM_SITE=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
      | grep "site_path'" \
      | cut -d: -f2 \
      | awk '{ print $3}' \
      | sed "s/[\,']//g" 2>&1)
    mkdir -p ${_THIS_HM_ROOT}/sites/all/{modules,themes,libraries}
    _master_reown_in "${_THIS_HM_ROOT}/sites/all" aegir:aegir
    # a CLI php.ini an earlier release left (+i) would refuse the chown;
    # the ltd worker removes it
    _U_HD="/var/aegir/.drush"
    if [ -f "${_U_HD}/php.ini" ] && [ ! -L "${_U_HD}/php.ini" ]; then
      chattr -i ${_U_HD}/php.ini
    fi
    mkdir -p /var/aegir/backups/system
    chmod 700 /var/aegir/backups/system
    chown -R aegir:aegir /var/aegir/.drush
    chown -R aegir:aegir /var/aegir/backups
    chown -R aegir:aegir /var/aegir/clients
    chown -R aegir:aegir /var/aegir/config
    chown -R aegir:aegir /var/aegir/drush
    # every account can write sites/all/* (group users) and the site's
    # files/ (group www-data) of this tree: walked as _master_reown_in and
    # _master_mode_all_in walk, never handing over or widening a link or a
    # file another account hard-linked there; a file there never keeps a
    # set-ID bit, nor a single-link one an execute bit. Once the master is
    # converted to its own web group, files/ take that group (wg-aegir) and
    # keep their private set's modes.
    _master_reown_in "${_THIS_HM_ROOT}" aegir
    _MWG_FILES=$(_master_files_group)
    _master_reown_in "${_THIS_HM_SITE}/files" "aegir:${_MWG_FILES}"
    if [ "${_MWG_FILES}" = "wg-aegir" ]; then
      _master_mode_pub_in "${_THIS_HM_SITE}/files" 02775 0664
    else
      _master_mode_all_in "${_THIS_HM_SITE}/files" 02775 0664
    fi

    # Never serialize an empty PHP version: the drush shebang update just
    # below hard-exits on an unresolved value, and the appends further down
    # shadow the template's shipped default, so an empty value here would
    # reach the su'd child as-is and break its version branch table
    if [ -z "${_PHP_CLI_VERSION}" ]; then
      _cliPhpBin=$(readlink -f /usr/bin/php 2>/dev/null)
      _cliPhpNum="${_cliPhpBin%/bin/php}"
      _cliPhpNum="${_cliPhpNum##*php}"
      if [ -n "${_cliPhpNum}" ] && [ -x "/opt/php${_cliPhpNum}/bin/php" ]; then
        _PHP_CLI_VERSION="${_cliPhpNum:0:1}.${_cliPhpNum:1}"
      else
        for _fbV in 84 85 86 83; do
          if [ -x "/opt/php${_fbV}/bin/php" ]; then
            _PHP_CLI_VERSION="${_fbV:0:1}.${_fbV:1}"
            break
          fi
        done
      fi
      if [ -z "${_PHP_CLI_VERSION}" ]; then
        _PHP_CLI_VERSION=8.4
      fi
    fi
    if [ -z "${_PHP_FPM_VERSION}" ]; then
      _PHP_FPM_VERSION="${_PHP_CLI_VERSION}"
    fi

    _DRUSH_FILES="drush.php drush"
    for _df in ${_DRUSH_FILES}; do
      _php_cli_drush_update "${_df}"
    done

    export _xSrl=588855devT01
    export _X_VERSION="${_X_VERSION}"

    # Refuse to hand off provably broken values: an empty front domain or
    # mirror here means a guaranteed child fatal much later, with far
    # worse diagnostics than failing loudly now
    for _hndVar in _THIS_FRONT _USE_MIR; do
      if [ -z "${!_hndVar}" ]; then
        _msg "FATAL ERROR: ${_hndVar} is empty, AegirUpgrade hand-off aborted"
        _msg "FATAL ERROR: Aborting Barracuda installer NOW!"
        rm -f /opt/tmp/status-Barracuda-FAIL
        touch /opt/tmp/status-Barracuda-FAIL
        _clean_pid_exit _aegir_master_upgrade_b
      fi
    done

    # Build the per-spawn child include on a private same-dir temp copy
    # and swap it in place 0600 aegir-owned: AegirUpgrade sources ONLY
    # this file and the values must never be half-written nor readable
    # by other local users; the shared barracuda.sh.cnf stays root's own
    # load path and no longer carries these appends
    _hndIncB="${_filIncB}.AegirUpgrade"
    _tmpIncB="${_vBs}/.${_hndIncB}.tmp"
    rm -f ${_tmpIncB}
    cp -af ${_vBs}/${_filIncB} ${_tmpIncB}
    chown aegir:aegir ${_tmpIncB} &> /dev/null
    chmod 0600 ${_tmpIncB}

    echo "_AEGIR_VERSION=\"${_AEGIR_VERSION}\""         >> ${_tmpIncB}
    echo "_AEGIR_XTS_VRN=\"${_tRee}\""                  >> ${_tmpIncB}
    echo "_BOA_REPO_GIT_URL=\"${_BOA_REPO_GIT_URL}\""   >> ${_tmpIncB}
    echo "_BOA_REPO_NAME=\"${_BOA_REPO_NAME}\""         >> ${_tmpIncB}
    echo "_BRANCH_BOA=\"${_BRANCH_BOA}\""               >> ${_tmpIncB}
    echo "_BRANCH_PRN=\"${_BRANCH_PRN}\""               >> ${_tmpIncB}
    echo "_DEBUG_MODE=\"${_DEBUG_MODE}\""               >> ${_tmpIncB}
    echo "_DL_MODE=\"${_DL_MODE}\""                     >> ${_tmpIncB}
    echo "_DOMAIN=\"${_THIS_FRONT}\""                   >> ${_tmpIncB}
    echo "_DRUPAL7=\"${_DRUPAL7}\""                     >> ${_tmpIncB}
    echo "_DRUSH_VERSION=\"${_DRUSH_VERSION}\""         >> ${_tmpIncB}
    echo "_NOW=\"${_NOW}\""                             >> ${_tmpIncB}
    echo "_PHP_CLI_VERSION=\"${_PHP_CLI_VERSION}\""     >> ${_tmpIncB}
    echo "_PHP_FPM_VERSION=\"${_PHP_FPM_VERSION}\""     >> ${_tmpIncB}
    echo "_SMALLCORE7_V=\"${_SMALLCORE7_V}\""           >> ${_tmpIncB}
    echo "_STRONG_PASSWORDS=\"${_STRONG_PASSWORDS}\""   >> ${_tmpIncB}
    echo "_THIS_DB_HOST=\"${_THIS_DB_HOST}\""           >> ${_tmpIncB}
    echo "_USE_MIR=\"${_USE_MIR}\""                     >> ${_tmpIncB}
    echo "_xSrl=\"${_xSrl}\""                           >> ${_tmpIncB}
    echo "_X_VERSION=\"${_X_VERSION}\""                 >> ${_tmpIncB}
    # The seal must stay the LAST line: the child asserts it after
    # sourcing, so any truncated append sequence is detected, not used
    echo "_HANDOFF_SEAL=\"AegirUpgrade\""               >> ${_tmpIncB}

    mv -f ${_tmpIncB} ${_vBs}/${_hndIncB}

    mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG HOSTS" &> /dev/null
    _RST=$(syncpass fix aegir 2>&1)
    _find_correct_ip
    _USE_RESOLVEIP="${_LOC_IP}"
    _RESOLVEIP="${_LOC_IP}"
    _provision_backend_dbpass_sync
    _hostmaster_frontend_dbpass_sync
    _master_download_for_local_build

    ### Make sure that required web services are up and running
    _mrun "webserver up"

    ###
    AegirUpgrade="${_bldPth}/aegir/scripts/AegirUpgrade.sh.txt"
    # Same state dir AegirSetupM signals in: root owns the state root, aegir
    # owns its own dir. Stale markers from an earlier run are purged first, so
    # an old FAIL cannot veto a clean run and an old OK cannot vouch for a run
    # that died before stamping (the satellite twin does this in its
    # pre-cleanup; the master had no purge at all).
    mkdir -p /opt/tmp/state/aegir &> /dev/null
    chown root:root /opt/tmp/state &> /dev/null
    chmod 0755 /opt/tmp/state &> /dev/null
    chown aegir:aegir /opt/tmp/state/aegir &> /dev/null
    chmod 0700 /opt/tmp/state/aegir &> /dev/null
    rm -f /opt/tmp/state/aegir/status-AegirUpgrade-FAIL \
      /opt/tmp/state/aegir/status-AegirUpgrade-OK \
      /opt/tmp/status-AegirUpgrade-FAIL &> /dev/null
    su -s /bin/bash - aegir -c "/bin/bash ${AegirUpgrade} aegir"
    wait
    ###

    if [ -e "/opt/tmp/state/aegir/status-AegirUpgrade-FAIL" ] \
      || [ ! -e "/opt/tmp/state/aegir/status-AegirUpgrade-OK" ]; then
      _msg "FATAL ERROR: AegirUpgrade installer failed"
      _msg "FATAL ERROR: Aborting Barracuda installer NOW!"
      rm -f /opt/tmp/status-Barracuda-FAIL
      touch /opt/tmp/status-Barracuda-FAIL
      _clean_pid_exit _aegir_master_upgrade_a
    else
      # Consumed once; kept only on failure for post-mortem reading
      rm -f ${_vBs}/${_hndIncB}
      _hostmaster_frontend_dbpass_sync
    fi
    if [ ! -L "${_mtrInc}/global.inc" ] && [ -e "${_mtrInc}/global.inc" ]; then
      mv -f ${_mtrInc}/global.inc \
        ${_mtrInc}/global.inc-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    fi
    ### Deploy the full global include set (per-core chain + dispatcher);
    ### the dispatcher alone would be inert without the chain.
    _global_inc_conf_update
    if [ -e "${_mtrInc}" ] && [ ! -L "${_mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sfn /data/conf/global.inc ${_mtrInc}/global.inc
    fi
    if [ -e "/etc/init.d/valkey-server" ]; then
      _valkey_password_update
    fi
    _force_advanced_nginx_config
    cd /var/aegir
    if [ -d "${_mtrNgx}/conf.d" ]; then
      if [ ! -d "${_mtrNgx}/pre.d" ]; then
        cd ${_mtrNgx}
        cp -a conf.d pre.d
      else
        rm -rf ${_mtrNgx}/conf.d
      fi
      if [ -e "${_mtrNgx}/pre.d/custom_nginx.conf" ]; then
        rm -f ${_mtrNgx}/pre.d/custom_nginx.conf
      fi
    fi
    find /var/aegir/host_master/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/host_master/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    chown -R aegir:aegir /var/aegir/.drush &> /dev/null
    chown -R aegir:aegir /var/aegir/.tmp &> /dev/null
    find /var/aegir/.drush -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/.drush -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 0440 /var/aegir/.drush/*.php &> /dev/null
    chmod 0711 /var/aegir/.drush &> /dev/null
    _msg "INFO: Ægir Master Instance upgrade completed"
  else
    _msg "INFO: Ægir Master Instance not upgraded this time"
  fi
  rm -f /var/aegir/*install.sh.txt
}

#
# Update php-cli in the cron entry.
_php_cli_cron_update() {
  local _mCron
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_cli_cron_update"
  fi
  # Key the target name on the ROLE, not on runner.sh's artifact: on a
  # standby the dispatch must stay parked across an Aegir master upgrade
  # (a live crontab minted beside the parked copy re-armed it), while on
  # every other box -- including a CI box mid-upgrade, whose "fail toward
  # enabled" contract needs the dispatch LIVE for its verify tasks -- the
  # live name wins and a leftover parked copy is cleared; runner.sh's own
  # grace logic re-parks an idle CI box afterwards.
  if [ -e "/root/.standby.cnf" ]; then
    _mCron="/var/spool/cron/crontabs/.aegir"
    rm -f /var/spool/cron/crontabs/aegir
  else
    _mCron="/var/spool/cron/crontabs/aegir"
    rm -f /var/spool/cron/crontabs/.aegir
  fi
  rm -f "${_mCron}"
  if [ ! -e "${_mCron}" ]; then
    #_DRUSH_HOSTING_TASKS_CMD="/usr/bin/drush @hostmaster hosting-tasks --force;"
    _DRUSH_HOSTING_DISPATCH_CMD="/usr/bin/env php /var/aegir/drush/drush.php @hostmaster hosting-dispatch"
    echo -e \
    "\nSHELL=/bin/sh\nPATH=/opt/php84/bin:/usr/bin\n\n*/1 * * * * \
    ${_DRUSH_HOSTING_DISPATCH_CMD}" \
    | fmt -su -w 2500 \
    | tee -a "${_mCron}" >/dev/null 2>&1
  fi
  if [ -e "${_mCron}" ]; then
    if [ "${_PHP_CLI_VERSION}" = "8.6" ] && [ -x "/opt/php86/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php86\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        "${_mCron}" &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "8.5" ] && [ -x "/opt/php85/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php85\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        "${_mCron}" &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "8.4" ] && [ -x "/opt/php84/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php84\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        "${_mCron}" &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "8.3" ] && [ -x "/opt/php83/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php83\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        "${_mCron}" &> /dev/null
    fi
    chown aegir:crontab "${_mCron}" &> /dev/null
    chmod 600 "${_mCron}"
  fi
}

#
# Add allow-snail group if not exists.
_add_allow_snail_if_not_exists() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _add_allow_snail_if_not_exists"
  fi
  _SNAIL_EXISTS=$(getent group allow-snail 2>&1)
  if [[ ! "${_SNAIL_EXISTS}" =~ "allow-snail" ]]; then
    addgroup --system allow-snail &> /dev/null
  fi
}

#
# Unlock sendmail for allow-snail group
_unlock_sendmail_for_snail() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _unlock_sendmail_for_snail"
  fi
  _add_allow_snail_if_not_exists
  chown root /usr/sbin/sendmail &> /dev/null
  chgrp allow-snail /usr/sbin/sendmail &> /dev/null
}

_aegir_master_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _aegir_master_install_upgrade"
  fi

  if [ "${_STATUS}" = "INIT" ]; then

  ###--------------------###
    if [ ! -e "/run/mysqld/mysqld.pid" ] \
      || [ ! -e "/run/mysqld/mysqld.sock" ]; then
      _msg "ALRT! ${_DB_SERVER} server not running properly!"
      _msg "EXIT: We can't proceed and will exit now"
      _msg "HINT: Please check for more information two log files:"
      _msg "INFO:   ${_LOG_INFO}"
      _msg "ERRR:   ${_LOG_ERRR}"
      _msg "HINT: (re)start ${_DB_SERVER} server, then run the installer again"
      _msg "Bye"
      [ -e "/root/.my.pass.txt" ] && rm -f /root/.my.pass.txt
      mkdir -p /var/aegir
      _clean_pid_exit _aegir_master_install_upgrade_a
    fi

  ###--------------------###
    _msg "INFO: Installing Ægir Master Instance..."
    adduser --system --group --home /var/aegir aegir &> /dev/null
    usermod -aG www-data aegir
    usermod -aG users aegir
    _sudoers_safe_append /etc/sudoers \
      "aegir ALL=NOPASSWD: /etc/init.d/nginx" "aegir ALL=NOPASSWD"

    _unlock_sendmail_for_snail
    if getent group allow-snail >/dev/null 2>&1 && \
      ! id -nG "aegir" 2>/dev/null | tr ' ' '\n' | grep -qxF "allow-snail"; then
      usermod -aG allow-snail aegir
    fi
    chmod 755 /usr/sbin/sendmail &> /dev/null

    ln -sfn /var/aegir/config/nginx.conf /etc/nginx/conf.d/aegir.conf &> /dev/null
    _nginx_conf_update

    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        _THIS_DB_HOST="${_hName}"
        _SQL_CONNECT=localhost
      elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
        _SQL_CONNECT=127.0.0.1
      else
        _THIS_DB_HOST=localhost
        _SQL_CONNECT=localhost
      fi
      _AEGIR_HOST="${_hName}"
    else
      _AEGIR_HOST="${_hName}"
      ### _SQL_CONNECT="${_THIS_DB_HOST}"
      ### Master Instance will use local DB server
      _SQL_CONNECT=localhost
    fi
    if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
      _AEGIR_HOST="${_hName}"
      _SQL_CONNECT=localhost
    fi

    _find_correct_ip
    _RESOLVEIP="${_LOC_IP}"
    if [ -z "${_RESOLVEIP}" ]; then
      _msg "FATAL ERROR: DNS looks broken for server ${_AEGIR_HOST}"
      _clean_pid_exit _aegir_master_install_upgrade_b
    else
      _AEGIR_HOST_IP="${_RESOLVEIP}"
    fi

    if [ "${_VMFAMILY}" != "AWS" ]; then
      _MYSQLTEST=$(mysql --silent -u root -h${_AEGIR_HOST_IP} -uINVALIDLOGIN -pINVALIDPASS 2>&1 >/dev/null | cat)
      if [ -z `echo ${_MYSQLTEST} | grep -q "ERROR \(2003\|1130\)"` ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: ${_DB_SERVER} is listening on ${_AEGIR_HOST_IP}."
        fi
      else
        _msg "FATAL ERROR: ${_DB_SERVER} is not configured to listen on ${_AEGIR_HOST_IP}"
        _clean_pid_exit _aegir_master_install_upgrade_c
      fi
    fi

    _AEGIR_DB_USER=aegir_root
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
      if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt 128 ]; then
        _PWD_CHARS=128
      fi
    fi

    if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt 32 ]; then
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
        || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
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
      else
        if [ -e "/root/.my.pass.txt" ]; then
          _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
        else
          _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
        fi
      fi
      _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
      _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
    fi

    if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt 9 ]; then
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
        || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
      else
        if [ -e "/root/.my.pass.txt" ]; then
          _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
        else
          _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
        fi
      fi
    fi

    _ESC="*.*"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL12 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_AEGIR_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_AEGIR_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_AEGIR_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_AEGIR_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_AEGIR_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_AEGIR_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_AEGIR_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL

    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _EXTRA_GRANTS=NO
    else
      _LOCAL_HOST="${_hName}"
      _find_correct_ip
      _LOCAL_IP="${_LOC_IP}"
      [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL13 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
        _write_proxysql_adm_cnf &> /dev/null
        mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_AEGIR_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_AEGIR_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_AEGIR_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
      fi
      mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_AEGIR_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_AEGIR_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_AEGIR_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_AEGIR_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    fi

    export _xSrl=588855devT01
    export _X_VERSION="${_X_VERSION}"

    # Never serialize an empty PHP version: these appends shadow the
    # template's shipped default, so an empty value here would reach the
    # su'd child as-is and break its version branch table
    if [ -z "${_PHP_CLI_VERSION}" ]; then
      _cliPhpBin=$(readlink -f /usr/bin/php 2>/dev/null)
      _cliPhpNum="${_cliPhpBin%/bin/php}"
      _cliPhpNum="${_cliPhpNum##*php}"
      if [ -n "${_cliPhpNum}" ] && [ -x "/opt/php${_cliPhpNum}/bin/php" ]; then
        _PHP_CLI_VERSION="${_cliPhpNum:0:1}.${_cliPhpNum:1}"
      else
        for _fbV in 84 85 86 83; do
          if [ -x "/opt/php${_fbV}/bin/php" ]; then
            _PHP_CLI_VERSION="${_fbV:0:1}.${_fbV:1}"
            break
          fi
        done
      fi
      if [ -z "${_PHP_CLI_VERSION}" ]; then
        _PHP_CLI_VERSION=8.4
      fi
    fi
    if [ -z "${_PHP_FPM_VERSION}" ]; then
      _PHP_FPM_VERSION="${_PHP_CLI_VERSION}"
    fi

    # Refuse to hand off provably broken values: each of these fatals the
    # child (aegir_host/db_user/db_pass args, the distro path, the mirror
    # fetches) and none is a legitimate empty state on the INIT path
    for _hndVar in _AEGIR_HOST _AEGIR_DB_USER _ESC_PASS \
      _AEGIR_VERSION _USE_MIR; do
      if [ -z "${!_hndVar}" ]; then
        _msg "FATAL ERROR: ${_hndVar} is empty, AegirSetupM hand-off aborted"
        _msg "FATAL ERROR: Aborting Barracuda installer NOW!"
        rm -f /opt/tmp/status-Barracuda-FAIL
        touch /opt/tmp/status-Barracuda-FAIL
        _clean_pid_exit _aegir_master_install_upgrade_h
      fi
    done

    # Build the per-spawn child include on a private same-dir temp copy
    # and swap it in place 0600 aegir-owned: the Ægir DB password lands in
    # this file, so it must never be half-written nor readable by other
    # local users; AegirSetupM sources ONLY this file and the shared
    # barracuda.sh.cnf stays root's own load path
    _hndIncB="${_filIncB}.AegirSetupM"
    _tmpIncB="${_vBs}/.${_hndIncB}.tmp"
    rm -f ${_tmpIncB}
    cp -af ${_vBs}/${_filIncB} ${_tmpIncB}
    chown aegir:aegir ${_tmpIncB} &> /dev/null
    chmod 0600 ${_tmpIncB}

    echo "_AEGIR_DB_USER=\"${_AEGIR_DB_USER}\""         >> ${_tmpIncB}
    echo "_AEGIR_HOST=\"${_AEGIR_HOST}\""               >> ${_tmpIncB}
    echo "_AEGIR_VERSION=\"${_AEGIR_VERSION}\""         >> ${_tmpIncB}
    echo "_AEGIR_XTS_VRN=\"${_tRee}\""                  >> ${_tmpIncB}
    echo "_BOA_REPO_GIT_URL=\"${_BOA_REPO_GIT_URL}\""   >> ${_tmpIncB}
    echo "_BOA_REPO_NAME=\"${_BOA_REPO_NAME}\""         >> ${_tmpIncB}
    echo "_BRANCH_BOA=\"${_BRANCH_BOA}\""               >> ${_tmpIncB}
    echo "_BRANCH_PRN=\"${_BRANCH_PRN}\""               >> ${_tmpIncB}
    echo "_DEBUG_MODE=\"${_DEBUG_MODE}\""               >> ${_tmpIncB}
    echo "_DL_MODE=\"${_DL_MODE}\""                     >> ${_tmpIncB}
    echo "_DOMAIN=\"${_THIS_FRONT}\""                   >> ${_tmpIncB}
    echo "_DRUSH_VERSION=\"${_DRUSH_VERSION}\""         >> ${_tmpIncB}
    echo "_ESC_PASS=\"${_ESC_PASS}\""                   >> ${_tmpIncB}
    echo "_LOCAL_NETWORK_IP=\"${_LOCAL_NETWORK_IP}\""   >> ${_tmpIncB}
    echo "_MY_OWNIP=\"${_MY_OWNIP}\""                   >> ${_tmpIncB}
    echo "_NOW=\"${_NOW}\""                             >> ${_tmpIncB}
    echo "_PHP_CLI_VERSION=\"${_PHP_CLI_VERSION}\""     >> ${_tmpIncB}
    echo "_PHP_FPM_VERSION=\"${_PHP_FPM_VERSION}\""     >> ${_tmpIncB}
    echo "_STRONG_PASSWORDS=\"${_STRONG_PASSWORDS}\""   >> ${_tmpIncB}
    echo "_THIS_DB_HOST=\"${_THIS_DB_HOST}\""           >> ${_tmpIncB}
    echo "_USE_MIR=\"${_USE_MIR}\""                     >> ${_tmpIncB}
    echo "_xSrl=\"${_xSrl}\""                           >> ${_tmpIncB}
    echo "_X_VERSION=\"${_X_VERSION}\""                 >> ${_tmpIncB}
    # The seal must stay the LAST line: the child asserts it after
    # sourcing, so any truncated append sequence is detected, not used
    echo "_HANDOFF_SEAL=\"AegirSetupM\""                >> ${_tmpIncB}

    mv -f ${_tmpIncB} ${_vBs}/${_hndIncB}

    ###  Download Drupal core and modules
    _master_download_for_local_build

    ### Make sure that required web services are up and running
    _mrun "webserver up"

    ###
    AegirSetupM="${_bldPth}/aegir/scripts/AegirSetupM.sh.txt"
    mkdir -p /opt/tmp/state/aegir &> /dev/null
    chown root:root /opt/tmp/state &> /dev/null
    chmod 0755 /opt/tmp/state &> /dev/null
    chown aegir:aegir /opt/tmp/state/aegir &> /dev/null
    chmod 0700 /opt/tmp/state/aegir &> /dev/null
    # Per-run purge, the master-side mirror of _satellite_pre_cleanup: a FAIL
    # left by an earlier attempt would veto every later run, a stale OK would
    # vouch for a child killed before it could stamp.
    rm -f /opt/tmp/state/aegir/status-AegirSetupM-FAIL \
      /opt/tmp/state/aegir/status-AegirSetupM-OK &> /dev/null
    ###

    touch /var/log/boa/aegir_install.log
    chown aegir:aegir /var/log/boa/aegir_install.log
    # 0600 (not the default 0644): the install log captures the Ægir
    # one-time-login URL — readable by any local user during the URL's
    # TTL would let a tenant race the admin to redeem it as Hostmaster.
    chmod 0600 /var/log/boa/aegir_install.log

    if [ "${_DEBUG_MODE}" = "YES" ]; then
      su -s /bin/bash - aegir -c "/bin/bash ${AegirSetupM} ${_THIS_FRONT} \
        --http_service_type='nginx' \
        --aegir_db_host='${_THIS_DB_HOST}' \
        --client_email='${_MY_EMAIL}' -y -d" \
      2>&1 | tee /var/log/boa/aegir_install.log
    else
      su -s /bin/bash - aegir -c "/bin/bash ${AegirSetupM} ${_THIS_FRONT} \
        --http_service_type='nginx' \
        --aegir_db_host='${_THIS_DB_HOST}' \
        --client_email='${_MY_EMAIL}' -y" \
      >/var/log/boa/aegir_install.log 2>&1
    fi
    wait

    _php_cli_local_dirs_update

    if [ -e "/opt/tmp/state/aegir/status-AegirSetupM-FAIL" ] \
      || [ ! -e "/opt/tmp/state/aegir/status-AegirSetupM-OK" ]; then
      _msg "FATAL ERROR: AegirSetupM installer failed"
      _msg "FATAL ERROR: Aborting Barracuda installer NOW!"
      _msg "HINT: Please check /var/log/boa/aegir_install.log"
      _msg "HINT: for more information on errors occured"
      rm -f /opt/tmp/status-Barracuda-FAIL
      touch /opt/tmp/status-Barracuda-FAIL
      _clean_pid_exit _aegir_master_install_upgrade_d
    fi
    # Consumed once and it carries the Ægir DB password; kept only on
    # failure (the exit above) for post-mortem reading
    rm -f ${_vBs}/${_hndIncB}
    if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      _THIS_HM_ROOT=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -e "${_THIS_HM_ROOT}/sites/all" ] \
        && [ ! -e "${_THIS_HM_ROOT}/sites/all/libraries" ]; then
        mkdir -p \
          ${_THIS_HM_ROOT}/sites/all/{modules,themes,libraries} &> /dev/null
      fi
    fi
    su -s /bin/bash - aegir -c "drush8 cc drush" &> /dev/null
    wait
    rm -rf /var/aegir/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Running hosting-dispatch/hosting-tasks..."
    fi
    _ensure_hosting_dispatch_enabled
    su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-dispatch" &> /dev/null
    wait
    sleep 5
    su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
    wait
    sleep 5
    su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
    wait
    sleep 5
    su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
    wait
    if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      _THIS_HM_ROOT=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -e "${_THIS_HM_ROOT}/sites/all" ] \
        && [ ! -e "${_THIS_HM_ROOT}/sites/all/libraries" ]; then
        mkdir -p \
          ${_THIS_HM_ROOT}/sites/all/{modules,themes,libraries} &> /dev/null
      fi
    fi
    _master_reown_in "${_THIS_HM_ROOT}/sites/all" aegir:aegir &> /dev/null

  ###--------------------###
    if [ -e "${_mtrInc}/nginx_vhost_common.conf" ]; then
      _DO_NOTHING=YES
      [ -e "/root/.force.reinstall.cnf" ] && rm -f /root/.force.reinstall.cnf
    else
      _msg "FATAL ERROR: Something went wrong, Ægir Master Instance not installed!"
      _msg "HINT: Please check /var/log/boa/aegir_install.log for details, and then"
      _msg "HINT: run the same install command again to complete installation."
      _msg "HINT: You can also enforce installation with empty control file:"
      _msg "      touch /root/.force.reinstall.cnf -- and then try again."
      _clean_pid_exit _aegir_master_install_upgrade_e
    fi

  ###--------------------###
    if [ ! -L "${_mtrInc}/global.inc" ] && [ -e "${_mtrInc}/global.inc" ]; then
      mv -f ${_mtrInc}/global.inc \
        ${_mtrInc}/global.inc-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    fi
    ### Deploy the full global include set (per-core chain + dispatcher);
    ### the dispatcher alone would be inert without the chain.
    _global_inc_conf_update
    if [ -e "${_mtrInc}" ] \
      && [ ! -L "${_mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sfn /data/conf/global.inc ${_mtrInc}/global.inc
    fi
    if [ -e "/etc/init.d/valkey-server" ]; then
      _valkey_password_update
    fi
    _force_advanced_nginx_config
    chmod 0711 ${_mtrInc} &> /dev/null
    chmod 0711 /var/aegir/config &> /dev/null
    find /var/aegir/host_master/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/host_master/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    chown -R aegir:aegir /var/aegir/.drush &> /dev/null
    find /var/aegir/.drush -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/.drush -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 0440 /var/aegir/.drush/*.php &> /dev/null
    chmod 0711 /var/aegir/.drush &> /dev/null
    cd /var/aegir
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/modules-enabled/*
    if [ -e "${_locCnf}/nginx/nginx.conf" ]; then
      mv -f /etc/nginx/nginx.conf /etc/nginx/nginx.conf-old &> /dev/null
      cp -af ${_locCnf}/nginx/nginx.conf /etc/nginx/nginx.conf
      mkdir -p /etc/nginx/main.d
    fi
    _mrun "service nginx reload"
    _msg "INFO: Ægir Master Instance installed"
  else
    if [ "${_tRee}" = "lts" ]; then
      _SERIES_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
      if [[ "${_SERIES_TEST}" =~ "Barracuda ${_rLsn}-pro" ]]; then
        _msg "ERROR: Your system has been already upgraded to ${_rLsn}-pro"
        _msg "You can not downgrade back to previous/older/lts BOA version"
        _msg "Please use 'barracuda up-pro system' to upgrade this server"
        _msg "Display all supported commands with: barracuda help"
        _msg "Bye"
        _clean_pid_exit _aegir_master_install_upgrade_f
      fi
    fi
    echo " "
    if [ -e "/root/.debug-barracuda-installer.cnf" ] \
      || [ -e "/root/.skip-aegir-master-upgrade.cnf" ]; then
      _SYSTEM_UP_ONLY=YES
    fi
    _if_to_do_fix
    if [ "${_DO_FIX}" = "YES" ]; then
      _msg "INFO: Ægir Master Instance upgrade skipped!"
      echo " "
      _msg "NOTE! You must reboot the server and run barracuda upgrade"
      _msg "NOTE! again to complete all system upgrades and upgrade also"
      _msg "NOTE! Ægir Master Instance."
      echo " "
    elif [ "${_SYSTEM_UP_ONLY}" = "YES" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Ægir Master Instance upgrade skipped"
      fi
    elif [ -e "/root/.standby.cnf" ]; then
      # The standby steer guarantees only the FLAVOR (_outP=system); the
      # _SYSTEM_UP_ONLY probe above keys on two master artefacts and fails
      # OPEN when either is missing, which on a damaged standby would run
      # the master upgrade -- drush updb plus DROP USER/GRANT churn --
      # against the replicated hostmaster DB. The role marker wins.
      _msg "NOTE: replication standby -- Ægir Master Instance upgrade refused"
    else
      if [ ! -e "/run/mysqld/mysqld.pid" ] \
        || [ ! -e "/run/mysqld/mysqld.sock" ]; then
        _msg "ALRT! ${_DB_SERVER} server not running properly!"
        _msg "EXIT: We can't proceed and will exit now"
        _msg "HINT: Please check for more information two log files:"
        _msg "INFO:   ${_LOG_INFO}"
        _msg "ERRR:   ${_LOG_ERRR}"
        _msg "HINT: (re)start ${_DB_SERVER} server, then run the installer again"
        _msg "Bye"
        _clean_pid_exit _aegir_master_install_upgrade_g
      fi
      _php_cli_cron_update
      _aegir_master_upgrade
      _php_cli_cron_update
    fi
  fi
}

_if_upgrade_only_aegir_master() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_upgrade_only_aegir_master"
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    if [ "${_AEGIR_UPGRADE_ONLY}" = "YES" ] \
      && [ "${_SYSTEM_UP_ONLY}" = "NO" ]; then
      _php_cli_cron_update
      _aegir_master_upgrade
      _php_cli_cron_update
      sleep 8
      _mrun "service nginx reload"
      _finale
      exit 0
    fi
  fi
}

_aegir_master_display_login_link() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _aegir_master_display_login_link"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ "${_EASY_SETUP}" != "LOCAL" ] && [ -x "/usr/sbin/apticron" ]; then
      _mrun "bash /usr/sbin/apticron"
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      _AEGIR_LOGIN_URL=$(tail --lines=11 /var/log/boa/aegir_install.log | grep --text "^http:" 2>&1)
      if [ ! -z "${_AEGIR_LOGIN_URL}" ]; then
        echo " "
        _msg "INFO: Congratulations, Ægir Master have been installed successfully!"
#         _msg "NOTE! Please wait 3 min before visiting Ægir at:"
#         echo " "
#         _msg "LINK: ${_AEGIR_LOGIN_URL}"
#         echo " "
#         _msg "NOTE! The initial one-time login link will no longer work."
#         sleep 3
#         _msg "To access your Barracuda Ægir control panel after the procedure is finished..."
#         _msg "...please generate a new link by running the following command:"
#         sleep 3
#         echo " "
#         echo "  su -s /bin/bash aegir -c \"drush @hm uli\""
#         echo " "
        sleep 3
      else
        _msg "ALRT! Something went wrong"
        _msg "ALRT! Please check the install log for details:"
        _msg "ALRT! /var/log/boa/aegir_install.log"
      fi
    fi
  fi
  if [ ! -e "${_pthLog}/cron_aegir_off.pid" ]; then
    touch ${_pthLog}/cron_aegir_off.pid
  fi
}

