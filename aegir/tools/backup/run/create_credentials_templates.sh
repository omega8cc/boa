#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Global credentials directory
_GLOBAL_CREDENTIALS_DIR="/root/.remote_backups/credentials"

# Base directory for user-specific credentials
_USER_BASE_DIR="/data/disk"

# An account owns /data/disk/<oN> (log/ included) and, through its .ftp
# login, static/control, so any name below either can be a link or a FIFO,
# and a whole directory on the way can be one. Root acts there only inside
# the real directory. _acct_in_real_dir and _acct_read_here are copies of the
# helpers in lib/functions/helper.sh.inc.
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
# ./$1 in the current (pinned) directory with the content read from stdin,
# born with the mode $2 and handed to $3 (owner:group) when given: a fresh
# file created exclusively, then renamed over the name, so a link or a FIFO
# put at the name is replaced, never followed or opened. A file handed over
# is created, written, owned and moded through one handle opened
# O_EXCL|O_NOFOLLOW (_ACCT_PUT_PL, the read/write bits of $2 as the umask
# gave them), never chowned by name: the directory is the account's, and a
# hard link renamed over the temp name before a chown by name would hand the
# linked file over. Owner names are resolved to numbers first; an owner that
# does not resolve puts nothing.
_ACCT_PUT_PL='use Fcntl; my ($n, $u, $g, $m) = @ARGV; local $/; my $d = <STDIN>; sysopen(my $h, $n, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) or exit 1; (print {$h} $d) or exit 1; chown($u, $g, $h) or exit 1; chmod(oct($m) & 0666, $h) or exit 1; close($h) or exit 1; exit 0'
_acct_put_stdin_here() {
  local _t="./.${1}.put.$$.${RANDOM}" _uid _gid
  if [ -n "${3}" ]; then
    _uid="${3%%:*}"
    _gid="${3#*:}"
    [[ "${_uid}" =~ ^[0-9]+$ ]] || _uid=$(id -u -- "${_uid}" 2> /dev/null)
    [[ "${_gid}" =~ ^[0-9]+$ ]] \
      || _gid=$(getent group "${_gid}" 2> /dev/null | cut -d: -f3)
    [[ "${_uid}" =~ ^[0-9]+$ && "${_gid}" =~ ^[0-9]+$ ]] || return 1
  fi
  rm -f -- "${_t}"
  if [ -n "${3}" ]; then
    if perl -e "${_ACCT_PUT_PL}" "${_t}" "${_uid}" "${_gid}" "${2}" \
      && mv -f -T -- "${_t}" "./${1}"; then
      return 0
    fi
  elif ( umask "$(printf '%03o' $(( 0777 & ~0${2} )))"
    dd of="${_t}" conv=excl status=none 2> /dev/null ); then
    mv -f -T -- "${_t}" "./${1}" && return 0
  fi
  rm -f -- "${_t}"
  return 1
}
# ./$1 made in the current (pinned) directory unless the name is taken.
_acct_mkdir_here() {
  [ -e "./${1}" ] || [ -L "./${1}" ] || mkdir -- "./${1}"
}
# The names $2... made below the real directory $1 where missing, each inside
# its real parent (mkdir never follows a link at the name). True when the
# whole path is a real directory.
_acct_mkdir_in() {
  local _d="${1}" _n
  shift
  for _n in "$@"; do
    _acct_in_real_dir "${_d}" _acct_mkdir_here "${_n}"
    _d="${_d}/${_n}"
  done
  _acct_in_real_dir "${_d}" true
}

# The name ./$1 is free in the current (pinned) directory: nothing at all is
# there, not even a link.
_acct_absent_here() {
  [ ! -e "./${1}" ] && [ ! -L "./${1}" ]
}
# ./$1 in the current (pinned) directory with every FULL_BACKUP_FREQUENCY
# value set to "28D", as sed -i set it: only a regular file of at most
# 1 MiB, read as _acct_read_here reads it and put back as a fresh file with
# its owner and mode.
_acct_set_frequency_here() {
  local _s _o _m _z _b
  [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
  _s="$(stat -c '%u:%g %a %s' -- "./${1}" 2> /dev/null)" || return 1
  read -r _o _m _z <<< "${_s}"
  [[ "${_m}" =~ ^[0-7]{3,4}$ ]] && [[ "${_z}" =~ ^[0-9]+$ ]] || return 1
  [ "${_z}" -le 1048576 ] || return 1
  _b="$(_acct_read_here "${1}" && echo x)" || return 1
  printf '%s' "${_b%x}" \
    | sed "s/FULL_BACKUP_FREQUENCY=.*/FULL_BACKUP_FREQUENCY=\"28D\"/g" \
    | _acct_put_stdin_here "${1}" "${_m}" "${_o}"
}

# Function to ensure a directory exists
_ensure_directory() {
  _dir=$1
  if [ ! -d "${_dir}" ]; then
    mkdir -p "${_dir}"
    chmod 700 "${_dir}"
    echo "Created directory: ${_dir}"
  fi
}

# An account's credentials directory made where missing, each name inside its
# real parent, and set 0700 on the real directory. True when it is one.
_ensure_account_directory() {
  local _dir="${_USER_BASE_DIR}/${1}/static/control/remote_backups/credentials"
  if [ ! -d "${_dir}" ]; then
    _acct_mkdir_in "${_USER_BASE_DIR}/${1}" static control remote_backups credentials \
      && _acct_in_real_dir "${_dir}" chmod 700 . \
      && echo "Created directory: ${_dir}"
  fi
  _acct_in_real_dir "${_dir}" true
}

# The template text of the service $1
_template_body() {
  case "${1}" in
    aws|aws_one_zone|aws_standard_ia)
      cat << EOF
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
    azure)
      cat << EOF
export AZURE_STORAGE_ACCOUNT="your_azure_storage_account"
export AZURE_STORAGE_KEY="your_azure_storage_key"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
    b2)
      cat << EOF
export B2_ACCOUNT_ID="your_b2_account_id"
export B2_APPLICATION_KEY="your_b2_application_key"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
    cloudflare)
      cat << EOF
export R2_ACCOUNT_ID="your_account_id"
export R2_ACCESS_KEY_ID="your_access_key_id"
export R2_SECRET_ACCESS_KEY="your_secret_access_key"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
    do_spaces)
      cat << EOF
export DO_SPACES_KEY="your_do_spaces_key"
export DO_SPACES_SECRET="your_do_spaces_secret"
export DO_SPACES_REGION="your_do_spaces_region"  # E.g., "nyc3"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
    gcs)
      cat << EOF
export GCS_ACCESS_KEY_ID="your_gcs_hmac_access_key"
export GCS_SECRET_ACCESS_KEY="your_gcs_hmac_secret"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
    ibm)
      cat << EOF
export IBM_ACCESS_KEY_ID="your_ibm_hmac_access_key_id"
export IBM_SECRET_ACCESS_KEY="your_ibm_hmac_secret_access_key"
export IBM_REGION="your_ibm_region"  # E.g., "eu-de"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
    linode)
      cat << EOF
export LINODE_ACCESS_KEY="your_linode_access_key"
export LINODE_SECRET_KEY="your_linode_secret_key"
export LINODE_REGION="your_linode_region"  # E.g., "us-east-1"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
    wasabi)
      cat << EOF
export WASABI_ACCESS_KEY="your_wasabi_access_key"
export WASABI_SECRET_KEY="your_wasabi_secret_key"
export WASABI_REGION="your_wasabi_region"  # E.g., "us-east-1"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
      ;;
  esac
}

# One service template in an account's credentials directory: the name is
# read, rewritten and created only inside the real directory, never through
# a link or into a FIFO put there. $1 = directory, $2 = service.
_create_account_template() {
  local _dir="${1}" _service="${2}"
  local _tpl_ctrl=".backboa.${_user}.credentials.${_service}.tpl.ctrl"
  if [ -e "${_user_pid_dir}" ] && [ ! -e "${_user_pid_dir}/${_tpl_ctrl}" ]; then
    _acct_in_real_dir "${_dir}" _acct_set_frequency_here "${_service}.txt"
    _acct_in_real_dir "${_user_pid_dir}" \
      _acct_put_stdin_here "${_tpl_ctrl}" 644 < /dev/null
  fi
  if _acct_in_real_dir "${_dir}" _acct_absent_here "${_service}.txt"; then
    if _template_body "${_service}" \
      | _acct_in_real_dir "${_dir}" _acct_put_stdin_here "${_service}.txt" 600; then
      echo "Created template for service: ${_service} at ${_dir}/${_service}.txt"
    else
      echo "Skipped template for service: ${_service} at ${_dir}/${_service}.txt"
    fi
  else
    echo "Template for service: ${_service} already exists at ${_dir}/${_service}.txt"
  fi
}

# Function to create credentials template files
_create_credentials_templates() {
  _target_dir=$1

  # List of supported services
  _services=(
    "aws_one_zone"
    "aws_standard_ia"
    "aws"
    "azure"
    "b2"
    "cloudflare"
    "do_spaces"
    "gcs"
    "ibm"
    "linode"
    "wasabi"
  )

  for _service in "${_services[@]}"; do
    _template_file="${_target_dir}/${_service}.txt"

    case "${_target_dir}" in
      /data/disk/*)
        _create_account_template "${_target_dir}" "${_service}"
        continue
        ;;
    esac

    if [ ! -f "${_template_file}" ]; then
      _template_body "${_service}" > "${_template_file}"
      chmod 600 "${_template_file}"
      echo "Created template for service: ${_service} at ${_template_file}"
    else
      echo "Template for service: ${_service} already exists at ${_template_file}"
    fi
  done
}

# Main function to create templates globally and for all users
_main() {
  # Create templates in the global credentials directory
  _ensure_directory "${_GLOBAL_CREDENTIALS_DIR}"
  _create_credentials_templates "${_GLOBAL_CREDENTIALS_DIR}"

  # Iterate over user directories and create templates for each user
  for _user_dir in "${_USER_BASE_DIR}"/*; do
    if [ -d "${_user_dir}" ]; then
      _user=$(basename "${_user_dir}")
      if [ "${_user}" != "arch" ] \
        && [ "${_user}" != "data" ] \
        && [ "${_user}" != "global" ] \
        && [ "${_user}" != "static" ] \
        && [ "${_user}" != "custom" ]; then
        _user_pid_dir="${_USER_BASE_DIR}/${_user}/log"
        _user_credentials_dir="${_USER_BASE_DIR}/${_user}/static/control/remote_backups/credentials"
        if _ensure_account_directory "${_user}"; then
          _create_credentials_templates "${_user_credentials_dir}"
        else
          echo "Skipped templates for user: ${_user} (not a real directory)"
        fi
      fi
    fi
  done
}

# Execute the script
_main
