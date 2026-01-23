#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_PTN_VRN=3.13.9
_DCY_VRN=3.0.6
_DCY_CMD="/usr/local/bin/duplicity"

_crlGet="-L --max-redirs 3 -k -s --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 --no-check-certificate -q --tries=9 --wait=9 --user-agent='iCab'"
_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"

_apt_clean_update() {
  ${_APT_UPDATE} -qq 2>/dev/null
  _CALLER_SCRIPT="$(basename "${BASH_SOURCE[-1]}")"
  _CALLER_SCRIPT="${_CALLER_SCRIPT//[^a-zA-Z0-9._-]/_}"
  date +%s > "/run/_latest_apt_clean_update.${_CALLER_SCRIPT}.pid"
}

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 0 -p $$
    chmod a+w /dev/null
    [ -e "/root/.gnupg" ] && chmod 700 /root/.gnupg
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}

_check_openssl() {
  # New OpenSSL 3.x version is required
  if [ ! -x "/usr/local/ssl3/bin/openssl" ]; then
    echo "New OpenSSL 3.x version is required"
    exit 1
  fi
}

_os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)
  _OS_LIST="excalibur daedalus chimaera beowulf buster bullseye bookworm trixie"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}

_find_fast_mirror_early() {
  _isNetc="$(which netcat)"
  if [ ! -x "${_isNetc}" ] || [ -z "${_isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    _apt_clean_update
    apt-get install netcat-traditional ${_aptYesUnth}
    wait
  fi
  _ffMirr=/opt/local/bin/ffmirror
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2025-01.txt"
    [ -d "/var/backups" ] || mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "eu.files.aegir.cc"  > ${_ffList}
      echo "us.files.aegir.cc" >> ${_ffList}
      echo "ao.files.aegir.cc" >> ${_ffList}
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
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
  _urlDev="http://${_USE_MIR}/dev"
  _urlHmr="http://${_USE_MIR}/versions/${_tRee}/boa/aegir"
}

# Function to install other dependencies
_install_other_dependencies() {
  echo "Checking and installing other dependencies..."

  echo "Installing boto3 for S3-compatible services..."
  pipx install boto3 --include-deps --force

  echo "Installing awscli for S3-compatible services..."
  pipx install awscli --include-deps --force

  echo "Installing azure-storage-blob for Azure Blob Storage..."
  pipx install azure-storage-blob --include-deps --force

  echo "Installing b2sdk for Backblaze B2..."
  pipx install b2sdk --include-deps --force

  echo "Installing google-cloud-storage for Google Cloud Storage..."
  pipx install google-cloud-storage --include-deps --force

  echo "Installing ibm-cos-sdk for IBM Cloud Object Storage..."
  pipx install ibm-cos-sdk --include-deps --force

  echo "All dependencies are installed."
}

_install_duplicity() {
  pip3 install --upgrade pip --root-user-action ignore
  echo "Installing pipx..."

  ${_DCY_PTN} -m pip install pipx --break-system-packages --root-user-action ignore

  export PIPX_BIN_DIR=/usr/local/bin
  export PIPX_HOME=/opt/pipx/venvs

  if [ -x "${_DCY_CMD}" ]; then
    _DCY_TEST=$(${_DCY_CMD} --version 2>&1)
    if [[ "${_DCY_TEST}" =~ "duplicity ${_DCY_VRN}" ]]; then
      echo "Already Installed ${_DCY_TEST}"
      if [ ! -e "/root/.force.duplicity.reinstall.cnf" ]; then
        exit 1
      fi
    fi
  fi

  echo "Installing Duplicity ${_DCY_VRN}..."
  pipx install duplicity --include-deps --force

  _DCY_TEST=$(${_DCY_CMD} --version 2>&1)
  echo "Just Installed ${_DCY_TEST}"

  if [[ "${_DCY_TEST}" =~ "duplicity 3." ]]; then
    echo "Duplicity installation complete!"
  else
    echo "Duplicity installation failed with ${_DCY_TEST}"
    exit 1
  fi
}

_python_install_src() {
  if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
    && [ -e "/etc/apt/apt.conf.d" ]; then
    echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
  fi
  _find_fast_mirror_early
  _apt_clean_update
  apt-get install ${_aptYesUnth} \
    intltool \
    jq \
    libdb-dev \
    libffi-dev \
    libgdbm-compat-dev \
    libgdbm-dev \
    liblzma-dev \
    libncursesw5-dev \
    libreadline-dev \
    par2 \
    python3 \
    python3-pip \
    python3-venv \
    rclone \
    rdiff \
    tk-dev \
    tzdata \
    uuid-dev

  _PTN_TEST=$(python3 --version 2>&1)
  if [[ ! "${_PTN_TEST}" =~ "Python ${_PTN_VRN}" ]] \
    || [ ! -x "${_DCY_PTN}" ]; then
    cd /var/opt
    rm -rf Python*
    wget ${_wgetGet} ${_urlDev}/src/Python-${_PTN_VRN}.tgz
    tar -xzf Python-${_PTN_VRN}.tgz
    cd Python-${_PTN_VRN}
    bash ./configure --with-openssl=/usr/local/ssl3
    make -j $(nproc) --quiet
    make install --quiet
    cd
  fi
  _PTN_TEST=$(/usr/local/bin/python3.12 --version 2>&1)
  if [[ "${_PTN_TEST}" =~ "Python ${_PTN_VRN}" ]]; then
    echo "Python ${_PTN_VRN} installed"
    _DCY_PTN="/usr/local/bin/python3.12"
    export PYTHONPATH="/usr/local/lib/python3.12/site-packages"
  else
    echo "Python ${_PTN_VRN} installation failed with ${_PTN_TEST}"
    exit 1
  fi

  echo "Locating pip3..."
  if [ -x "/usr/local/bin/pip3" ]; then
    _usePip=/usr/local/bin/pip3
  elif [ -x "/usr/bin/pip3" ]; then
    _usePip=/usr/bin/pip3
  fi
  echo "_usePip is ${_usePip}"

  echo "Installing pip..."
  _PIP_TEST=$(${_usePip} --version 2>&1)
  if [[ "${_PIP_TEST}" =~ "python 3.11" ]] \
    || [[ "${_PIP_TEST}" =~ "python 3.12" ]] \
    || [[ "${_PIP_TEST}" =~ "python 3.13" ]]; then
    ${_usePip} install --upgrade pip --root-user-action ignore
  else
    ${_usePip} install --upgrade pip
  fi

  _install_duplicity
  _install_other_dependencies
}

_if_python_install_src() {
  _PYTHON_INSTALL=NO
  [ -e "/root/.gnupg" ] && chmod 700 /root/.gnupg
  _PYTHON_TEST=$(python3 --version 2>&1)
  if [[ ! "${_PYTHON_TEST}" =~ "Python ${_PTN_VRN}" ]]; then
    echo "Python ${_PTN_VRN} installation is required to support Duplicity ${_DCY_VRN}"
    _python_install_src
  else
    if ! ${_DCY_PTN} -c "import boto3" &> /dev/null; then
      _PYTHON_INSTALL=YES
    fi
    if ! ${_DCY_PTN} -c "import b2sdk" &> /dev/null; then
      _PYTHON_INSTALL=YES
    fi
    if [ "${_PYTHON_INSTALL}" = "YES" ]; then
      _python_install_src
    fi
  fi
}

_check_root
_check_openssl
_os_detection_minimal
_if_python_install_src

