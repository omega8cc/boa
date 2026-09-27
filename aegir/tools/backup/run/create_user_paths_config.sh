#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _sPid="f60"

# Log file for escape attempts and validation issues
_VALIDATION_LOG_FILE="/var/log/backup_validation_issues.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  fi
}
_check_root

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

# An account owns /data/disk/<oN>, so it can rename root's remote_backups
# there and put a directory or a link of its own in its place, and through
# its .ftp login it owns static/control. Root reads and writes there only
# inside the real directory: in remote_backups and paths only when root alone
# can write them, the account's config files read without following a link
# or blocking on a FIFO. _acct_in_real_dir and _acct_read_here are copies of
# the helpers in lib/functions/helper.sh.inc, _root_only of the one in
# multiback.
#
# Run "$@" inside the real directory $1: below /data/disk and /home every name
# on the path must be a real directory; once entered, ./name stays there
# whatever is swapped.
_acct_in_real_dir() {
  local _d="${1}" _a="" _want
  shift
  case "${_d}" in
    /home/?*) _a=/home ;;
    /data/disk/?*) _a=/data/disk ;;
  esac
  if [ -n "${_a}" ]; then
    _want="$(cd -P -- "${_a}" 2> /dev/null && pwd -P)${_d#"${_a}"}"
  else
    _want="$(cd -P -- "${_d%/*}" 2> /dev/null && pwd -P)/${_d##*/}"
  fi
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_want}" ] && "$@" )
}
# ./$1 in the current (pinned) directory: never through a link, never blocked
# on a FIFO, at most 1 MiB. Empty for anything else.
_acct_read_here() {
  timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
    bs=1048576 count=1 status=none 2> /dev/null
}
# ./$1 in the current (pinned) directory is a regular file, not a link.
_acct_is_file_here() {
  [ -f "./${1}" ] && [ ! -L "./${1}" ]
}
# ./$1 read as _acct_read_here reads it, only when it is a regular file (what
# [ -f ] accepted before); fails otherwise.
_acct_read_file_here() {
  _acct_is_file_here "${1}" || return 1
  _acct_read_here "${1}"
}
# True when $1 is root's and no one else can write it: owned by root, not
# writable by others, group-writable only for group root.
_root_only() {
  local _s _u _g _m
  _s="$(stat -c '%u %g %a' -- "${1}" 2> /dev/null)" || return 1
  read -r _u _g _m <<< "${_s}"
  [ "${_u}" = 0 ] || return 1
  (( 0${_m} & 2 )) && return 1
  (( 0${_m} & 16 )) && [ "${_g}" != 0 ] && return 1
  return 0
}
# ./$1 in the current (pinned) directory with the content read from stdin,
# born with the mode $2 and handed to $3 (owner:group) when given: a fresh
# file created exclusively, then renamed over the name, so a link or a FIFO
# put at the name is replaced, never followed or opened.
_acct_put_stdin_here() {
  local _t="./.${1}.put.$$.${RANDOM}"
  rm -f -- "${_t}"
  if ( umask "$(printf '%03o' $(( 0777 & ~0${2} )))"
    dd of="${_t}" conv=excl status=none 2> /dev/null ); then
    [ -z "${3}" ] || chown -h -- "${3}" "${_t}"
    mv -f -T -- "${_t}" "./${1}" && return 0
  fi
  rm -f -- "${_t}"
  return 1
}
# ./$1 made in the current (pinned) directory unless the name is taken.
_acct_mkdir_here() {
  [ -e "./${1}" ] || [ -L "./${1}" ] || mkdir -- "./${1}"
}
# ./$1 made as _acct_mkdir_here makes it, only in a directory root alone can
# write.
_acct_root_mkdir_here() {
  _root_only . && _acct_mkdir_here "${1}"
}

# The passphrase, made only inside root's own real remote_backups. Returns 3
# when one is there already, 4 when it could not be made, 2 when the
# directory is not root's alone.
_user_secret_here() {
  local _s
  _root_only . || return 2
  [ -s ./.secret.txt ] && return 3
  _s="$(openssl rand -base64 32)" && [ -n "${_s}" ] || return 4
  printf '%s\n' "${_s}" | _acct_put_stdin_here .secret.txt 600 || return 4
  chattr +i ./.secret.txt
  return 0
}

# Function to generate passphrase for user level backups
_generate_user_secret_file() {
  local _user=$1
  local _secret_file="/data/disk/${_user}/remote_backups/.secret.txt"
  local _rc
  _acct_in_real_dir "/data/disk/${_user}/remote_backups" _user_secret_here
  _rc=$?
  if [ "${_rc}" = 0 ]; then
    echo "User secret file created at ${_secret_file} and made immutable."
  elif [ "${_rc}" = 3 ]; then
    echo "User secret file already exists at ${_secret_file}."
  elif [ "${_rc}" = 4 ]; then
    echo "User secret file could not be created at ${_secret_file}."
  else
    echo "User secret file not created at ${_secret_file}: not root's own directory."
  fi
}

# Function to log validation issues
_log_issue() {
  local _type=$1
  local _file=$2
  local _message=$3
  echo "[$(date)] Validation issue: [${_type}] in file: [${_file}] with error: ${_message}" >> "${_VALIDATION_LOG_FILE}"
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "ALL" ]; then
    # Alert the admin
    echo "Sending Backup Validation Alert to ${_MY_EMAIL} on $(date)" >> ${_VALIDATION_LOG_FILE}
    s-nail -s "Backup Validation Alert for [$(hostname)] on $(date)" ${_MY_EMAIL} < ${_VALIDATION_LOG_FILE}
  fi
}

# Function to validate and merge configuration files
# Appends to the output file -- the caller truncates it once per merge group,
# so a validated user file extends the default set instead of replacing it
# (README: user directives are merged with default system directives).
# Invalid lines are logged and skipped individually; valid lines still apply.
# Runs inside the pinned paths directory (see _user_paths_config_here): the
# output and root's own files are ./names there, the account's file (the one
# validated) is read inside its real directory, never through a link or
# from a FIFO.
_validate_and_merge_paths() {
  local _file=$1
  local _user=$2
  local _output_file=$3
  local _if_validate=$4
  local _invalid_paths_found=false
  local _body
  if [ "${_if_validate}" = "YES" ]; then
    _body="$(_acct_in_real_dir "${_file%/*}" _acct_read_file_here "${_file##*/}")"
  else
    _body="$(cat "${_file}")"
  fi
  # Validation matches the whole line: directive, one space, one argument,
  # end of line, in a conservative character set -- merged lines are
  # flattened into a single duplicity command line, so every line must stay
  # exactly one directive plus one safe argument, with no whitespace inside
  # the argument. Regex metacharacters are accepted only after the -regexp
  # directives, whose argument may begin with the documented ^ anchor and
  # may regex-escape the FTP-home dot.
  local _bs='\\'
  local _path_shape="^--(include|exclude) /((data/disk/${_user}/static)|(home/${_user}[.]ftp))(/[A-Za-z0-9_.,+=@~/-]*)?$"
  local _rgx_shape="^--(include|exclude)-regexp \^?/((data/disk/${_user}/static)|(home/${_user}${_bs}?[.]ftp))(/[][A-Za-z0-9_.,+=@~/\^*?-]*)?$"

  while IFS= read -r _line || [ -n "${_line}" ]; do
    # Trim edge whitespace, including the CR of a CRLF-edited file -- a
    # cosmetic margin must not refuse an otherwise valid line
    _line="${_line#"${_line%%[![:space:]]*}"}"
    _line="${_line%"${_line##*[![:space:]]}"}"

    # Drop empty lines and comments -- the merged file is flattened into
    # duplicity arguments, so they must never reach it
    if [[ "${_line}" =~ ^[[:space:]]*(#|$) ]]; then
      continue
    fi

    if [ "${_if_validate}" = "YES" ]; then
      # Validate directives
      if [[ "${_line}" =~ ^--(include|exclude|include-regexp|exclude-regexp) ]]; then
        if echo "${_line}" | grep -Eq "${_path_shape}" \
          || echo "${_line}" | grep -Eq "${_rgx_shape}"; then
          echo "${_line}" >> "${_output_file}"
        else
          _log_issue "${_user}" "${_file}" "Invalid path: ${_line}"
          _invalid_paths_found=true
        fi
      else
        _log_issue "${_user}" "${_file}" "Invalid directive: ${_line}"
        _invalid_paths_found=true
      fi
    elif [ "${_if_validate}" = "NO" ]; then
      echo "${_line}" >> "${_output_file}"
    fi
  done <<< "${_body}"

  if [ "${_invalid_paths_found}" = true ]; then
    echo "Skipped invalid lines in '${_file}' for user '${_user}'."
  fi
}

# Function to append unique entries from source to target file
_append_unique_entries() {
  _source_file=$1
  _target_file=$2
  if [ -f "${_source_file}" ]; then
    grep -v -F -x -f "${_target_file}" "${_source_file}" >> "${_target_file}"
  fi
}

# The account's config file $1 is there as a regular file in the real config
# directory.
_control_file_present() {
  _acct_in_real_dir "${_user_control_dir}" _acct_is_file_here "${1}"
}

# Runs inside the real paths directory, pinned by _acct_in_real_dir, and only
# when it and remote_backups above it are root's alone: no account can put a
# name here, so the files root keeps here are read and written as ./names,
# never by a path the account can redirect.
_user_paths_config_here() {
  _root_only . && _root_only .. || return 1
  chown root:root .
  chmod 755 .

  if [ ! -f "${_user_ctrl_file}" ]; then

    ### Migrate legacy exclude/include files if present and merge unique entries

    # _include_list
    if [ -f "/root/.backboa.include" ]; then
      if [ ! -f "${_include_list}" ]; then
        cp "/root/.backboa.include" "${_include_list}"
      else
        _append_unique_entries "/root/.backboa.include" "${_include_list}"
      fi
    fi

    # _exclude_list
    if [ -f "/root/.backboa.exclude" ]; then
      if [ ! -f "${_exclude_list}" ]; then
        cp "/root/.backboa.exclude" "${_exclude_list}"
      else
        _append_unique_entries "/root/.backboa.exclude" "${_exclude_list}"
      fi
    else
      cat << EOF > "${_exclude_list}"
**files/advagg_css/**
**files/advagg_js/**
**files/css/**
**files/js/**
**private/temp/**
EOF
    fi

    ### Create default exclude/include files if they don't exist

    # _include_file
    if [ ! -f "${_include_ctrl_file}" ]; then
      cat << EOF > "${_include_file}"
--include /data/disk/${_user}/distro
--include /data/disk/${_user}/platforms
--include /data/disk/${_user}/static
--include /home/${_user}.ftp
EOF
      rm -f ./.backboa."${_user}".*.include.ctrl.file
      touch "${_include_ctrl_file}"
    fi

    # _exclude_file
    if [ ! -f "${_exclude_ctrl_file}" ]; then
      cat << EOF > "${_exclude_file}"
--exclude /data/disk/${_user}/.tmp
--exclude /data/disk/${_user}/clients
--exclude /data/disk/${_user}/static/restores
--exclude /data/disk/${_user}/static/tmp
--exclude /data/disk/${_user}/static/trash
--exclude /data/disk/${_user}/u
--exclude /data/disk/${_user}/undo
--exclude /home/${_user}.ftp/.tmp
--exclude /home/${_user}.ftp/backups
--exclude /home/${_user}.ftp/clients
--exclude /home/${_user}.ftp/platforms
--exclude /home/${_user}.ftp/static
EOF
      rm -f ./.backboa."${_user}".*.exclude.ctrl.file
      touch "${_exclude_ctrl_file}"
    fi

    # Cleanup for empty or not used include config files
    if ! _control_file_present include_regexp.txt; then
      [ -e "${_include_regexp_file}" ] && rm -f "${_include_regexp_file}"
      [ -e "${_merged_regexp_include_file}" ] && rm -f "${_merged_regexp_include_file}"
    fi

    # Cleanup for empty or not used exclude config files
    if ! _control_file_present exclude_regexp.txt; then
      [ -e "${_exclude_regexp_file}" ] && rm -f "${_exclude_regexp_file}"
      [ -e "${_merged_regexp_exclude_file}" ] && rm -f "${_merged_regexp_exclude_file}"
    fi

    # Validate and merge system and user-space include files
    # Each merged file starts fresh once per run; the passes below append
    > "${_merged_include_file}"
    _validate_and_merge_paths "${_include_file}" "${_user}" "${_merged_include_file}" NO
    if _control_file_present include.txt; then
      _validate_and_merge_paths "${_user_control_dir}/include.txt" "${_user}" "${_merged_include_file}" YES
    fi

    # Validate and merge system and user-space exclude files
    > "${_merged_exclude_file}"
    _validate_and_merge_paths "${_exclude_file}" "${_user}" "${_merged_exclude_file}" NO
    if _control_file_present exclude.txt; then
      _validate_and_merge_paths "${_user_control_dir}/exclude.txt" "${_user}" "${_merged_exclude_file}" YES
    fi

    # The account's regexp files, looked up once for both passes below
    local _ctl_irx=NO _ctl_erx=NO
    _control_file_present include_regexp.txt && _ctl_irx=YES
    _control_file_present exclude_regexp.txt && _ctl_erx=YES

    # Validate and merge regexp include files
    if [ -f "${_include_regexp_file}" ] || [ "${_ctl_irx}" = "YES" ]; then
      > "${_merged_regexp_include_file}"
    fi
    if [ -f "${_include_regexp_file}" ]; then
      _validate_and_merge_paths "${_include_regexp_file}" "${_user}" "${_merged_regexp_include_file}" NO
    fi
    if [ "${_ctl_irx}" = "YES" ]; then
      _validate_and_merge_paths "${_user_control_dir}/include_regexp.txt" "${_user}" "${_merged_regexp_include_file}" YES
    fi

    # Validate and merge regexp exclude files
    if [ -f "${_exclude_regexp_file}" ] || [ "${_ctl_erx}" = "YES" ]; then
      > "${_merged_regexp_exclude_file}"
    fi
    if [ -f "${_exclude_regexp_file}" ]; then
      _validate_and_merge_paths "${_exclude_regexp_file}" "${_user}" "${_merged_regexp_exclude_file}" NO
    fi
    if [ "${_ctl_erx}" = "YES" ]; then
      _validate_and_merge_paths "${_user_control_dir}/exclude_regexp.txt" "${_user}" "${_merged_regexp_exclude_file}" YES
    fi

    # Merge all include path directives into single file
    cat "${_merged_include_file}" > "${_merged_all_include_file}"
    cat "${_merged_regexp_include_file}" >> "${_merged_all_include_file}"

    # Merge all exclude path directives into single file
    cat "${_merged_exclude_file}" > "${_merged_all_exclude_file}"
    cat "${_merged_regexp_exclude_file}" >> "${_merged_all_exclude_file}"

    # Convert the include file contents to a single-line variable without extra backslashes and excessive whitespace
    local _MERGED_ALL_INCLUDE=$(cat "${_merged_all_include_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

    # Convert the exclude file contents to a single-line variable without extra backslashes and excessive whitespace
    local _MERGED_ALL_EXCLUDE=$(cat "${_merged_all_exclude_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

    # Create the final paths configuration file
    cat << EOF > "${_user_paths_file}"
_SOURCE=""
_USER_INCLUDE_PATHS="${_MERGED_ALL_INCLUDE}"
_USER_EXCLUDE_PATHS="${_MERGED_ALL_EXCLUDE}"
_INCLUDE_LIST="${_user_config_dir}/${_include_list#./}"
_EXCLUDE_LIST="${_user_config_dir}/${_exclude_list#./}"
EOF

    rm -f ./.backboa*paths.ctrl.file
    touch "${_user_ctrl_file}"
    echo "Paths configuration for '${_user}' created or updated at '${_user_config_dir}/${_user_paths_file#./}'."
  fi
  return 0
}

# Function to create or update a user's paths configuration file
_create_user_paths_config() {
  local _user=$1
  local _user_backup_dir="/data/disk/${_user}/remote_backups"
  local _user_config_dir="${_user_backup_dir}/paths"
  local _user_control_dir="/data/disk/${_user}/static/control/remote_backups/config"
  # Names in the paths directory, used only inside it
  local _include_list="./.backboa.${_user}.include.list"
  local _exclude_list="./.backboa.${_user}.exclude.list"
  local _include_file="./.backboa.${_user}.include.file"
  local _exclude_file="./.backboa.${_user}.exclude.file"
  local _include_regexp_file="./.backboa.${_user}.include_regexp.file"
  local _exclude_regexp_file="./.backboa.${_user}.exclude_regexp.file"
  local _merged_include_file="./.backboa.${_user}.include.merged.file"
  local _merged_exclude_file="./.backboa.${_user}.exclude.merged.file"
  local _merged_regexp_include_file="./.backboa.${_user}.include_regexp.merged.file"
  local _merged_regexp_exclude_file="./.backboa.${_user}.exclude_regexp.merged.file"
  local _user_ctrl_file="./.backboa.${_sPid}.paths.ctrl.file"
  local _include_ctrl_file="./.backboa.${_user}.${_sPid}.include.ctrl.file"
  local _exclude_ctrl_file="./.backboa.${_user}.${_sPid}.exclude.ctrl.file"
  local _merged_all_include_file="./.backboa.${_user}.all.include.merged.file"
  local _merged_all_exclude_file="./.backboa.${_user}.all.exclude.merged.file"
  local _user_paths_file="./paths.txt"

  # Ensure user configuration directory exists and is owned by root: each
  # missing name is made inside its real parent, and nothing is done where
  # remote_backups is not root's own directory (the account can put one of
  # its own there, never make one root owns)
  _acct_in_real_dir "/data/disk/${_user}" _acct_mkdir_here remote_backups
  _acct_in_real_dir "${_user_backup_dir}" _acct_root_mkdir_here paths
  if ! _acct_in_real_dir "${_user_config_dir}" _user_paths_config_here; then
    echo "Skipped paths configuration for '${_user}': ${_user_config_dir} is not root's own directory."
  fi
}

# Generate paths configuration for each user
for _user_dir in /data/disk/*; do
  if [ -d "${_user_dir}" ]; then
    _user=$(basename "${_user_dir}")
    if [ "${_user}" != "arch" ] \
      && [ "${_user}" != "data" ] \
      && [ "${_user}" != "global" ] \
      && [ "${_user}" != "static" ] \
      && [ "${_user}" != "custom" ]; then
      _create_user_paths_config "${_user}"
      _generate_user_secret_file "${_user}"
    fi
  fi
done
