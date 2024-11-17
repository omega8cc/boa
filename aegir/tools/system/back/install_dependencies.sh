#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_PTN_VRN=3.12.5
_DCY_VRN=3.0.2
_DCY_CMD="/usr/local/bin/duplicity"
_LOGPTH="/var/xdrago/log"
_crlGet="-L --max-redirs 3 -k -s --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 --no-check-certificate -q --tries=9 --wait=9 --user-agent='iCab'"
_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"

_check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 9 -p $$
    chmod a+w /dev/null
    [ -e "/root/.gnupg" ] && chmod 700 /root/.gnupg
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}')
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
_check_root

if [ -e "/root/.pause_heavy_tasks_maint.cnf" ]; then
  exit 0
fi

# New OpenSSL 3.x version is required
if [ ! -x "/usr/local/ssl3/bin/openssl" ]; then
  echo "New OpenSSL 3.x version is required"
  exit 1
fi

_if_hosted_sys() {
  _CHECK_HOST=$(uname -n 2>&1)
  if [ -e "/root/.host8.cnf" ] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
    _hostedSys=YES
  else
    _hostedSys=NO
  fi
}
_if_hosted_sys


[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf

_os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  _OS_LIST="daedalus chimaera beowulf buster bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}
_os_detection_minimal

_apt_clean_update() {
  ${_APT_UPDATE} -qq
}

_python_install_src() {
  _apt_clean_update
  apt-get install ${_aptYesUnth} \
    intltool \
    libffi-dev \
    par2 \
    python3-pip \
    python3-venv \
    python3 \
    rclone \
    rdiff \
    tzdata
  _PTN_TEST=$(${_DCY_PTN} --version 2>&1)
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
  _PTN_TEST=$(${_DCY_PTN} --version 2>&1)
  if [[ "${_PTN_TEST}" =~ "Python ${_PTN_VRN}" ]]; then
    echo "Python ${_PTN_VRN} installed"
  else
    echo "Python ${_PTN_VRN} installation failed with ${_PTN_TEST}"
    exit 1
  fi
}

_if_python_install_src() {
  if [ -x "/usr/bin/python3" ]; then
    _DCY_PTN="/usr/bin/python3"
    _PYTHON_TEST=$(${_DCY_PTN} --version 2>&1)
  elif [ -x "/usr/local/bin/python3" ]; then
    _DCY_PTN="/usr/local/bin/python3"
    _PYTHON_TEST=$(${_DCY_PTN} --version 2>&1)
  else
    _PYTHON_TEST=$(python3 --version 2>&1)
  fi
  if [[ ! "${_PYTHON_TEST}" =~ Python\ 3\.(11|12) ]]; then
    echo "Python ${_PTN_VRN} installation is required to support Duplicity ${_DCY_VRN}"
    _DCY_PTN="/usr/local/bin/python3"
    _python_install_src
  fi
}


_vars_adjust() {
  if [ -x "/usr/bin/python3" ]; then
    _DCY_PTN="/usr/bin/python3"
    _PYTHON_TEST=$(${_DCY_PTN} --version 2>&1)
    [[ "${_PYTHON_TEST}" =~ "Python 3.12" ]] && export PYTHONPATH="/usr/lib/python3.12/site-packages"
    [[ "${_PYTHON_TEST}" =~ "Python 3.11" ]] && export PYTHONPATH="/usr/lib/python3.11/site-packages"
  elif [ -x "/usr/local/bin/python3" ]; then
    _DCY_PTN="/usr/local/bin/python3"
    _PYTHON_TEST=$(${_DCY_PTN} --version 2>&1)
    [[ "${_PYTHON_TEST}" =~ "Python 3.12" ]] && export PYTHONPATH="/usr/local/lib/python3.12/site-packages"
    [[ "${_PYTHON_TEST}" =~ "Python 3.11" ]] && export PYTHONPATH="/usr/local/lib/python3.11/site-packages"
  fi
}

    _PTN_TEST=$(${_DCY_PTN} --version 2>&1)
    if [[ "${_PTN_TEST}" =~ "Python ${_PTN_VRN}" ]]; then
      python3 -m pip install pipx --break-system-packages --root-user-action ignore
      pip3 install --upgrade pip --root-user-action ignore
      export PIPX_BIN_DIR=/usr/local/bin
      export PIPX_HOME=/opt/pipx/venvs
      pipx install duplicity --include-deps --force
      pipx install awscli --include-deps --force
      pipx install boto3 --include-deps --force
    else
      echo "Python ${_PTN_VRN} installation failed with ${_PTN_TEST}"
      exit 1
    fi

if [ "$1" != "help" ]; then
  # Check the Python version to ensure we're using the correct one
  echo "Checking expected Python ${_PTN_VRN} version..."
  ${_DCY_PTN} --version
  # Check the Duplicity version to ensure we're using the correct one
  echo "Checking expected Duplicity ${_DCY_VRN} version..."
  ${_DCY_CMD} --version
fi




_check_vps() {
  _BENG_VS=NO
  _VM_TEST=$(uname -a 2>&1)
  if [[ "${_VM_TEST}" =~ "-beng" ]]; then
    _BENG_VS=YES
  fi
}
_check_vps

_find_fast_mirror_early() {
  _isNetc=$(which netcat 2>&1)
  if [ ! -x "${_isNetc}" ] || [ -z "${_isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    _apt_clean_update
    apt-get install netcat ${_aptYesUnth}
    apt-get install netcat-traditional ${_aptYesUnth}
    wait
  fi
  _ffMirr=$(which ffmirror 2>&1)
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2025-02.txt"
    mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "eu.files.aegir.cc"  > ${_ffList}
      echo "us.files.aegir.cc" >> ${_ffList}
      echo "ao.files.aegir.cc" >> ${_ffList}
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
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
_if_install_other_dependencies() {
  echo "Checking and installing other dependencies..."

    _apt_clean_update
    _mrun "${_INSTAPP} python3-pip"
    if [ -x "/usr/bin/pip3" ]; then
      _usePip=/usr/bin/pip3
    elif [ -x "/usr/local/bin/pip3" ]; then
      _usePip=/usr/local/bin/pip3
    fi
    _PIP_TEST=$(${_usePip} --version 2>&1)
    if [[ "${_PIP_TEST}" =~ "python 3.11" ]] \
      || [[ "${_PIP_TEST}" =~ "python 3.12" ]]; then
      _mrun "${_usePip} install --upgrade pip --root-user-action ignore"
    else
      _mrun "${_usePip} install --upgrade pip"
    fi

    _PIP_TEST=$(${_usePip} --version 2>&1)
    if [[ "${_PIP_TEST}" =~ "python 3.11" ]] \
      || [[ "${_PIP_TEST}" =~ "python 3.12" ]]; then
      _mrun "${_usePip} install . --break-system-packages --root-user-action ignore"
    else
      _mrun "${_usePip} install . "
    fi

    _PTN_TEST=$(${_DCY_PTN} --version 2>&1)
    if [[ "${_PTN_TEST}" =~ "Python ${_PTN_VRN}" ]]; then
      python3 -m pip install pipx --break-system-packages --root-user-action ignore
      pip3 install --upgrade pip --root-user-action ignore
      export PIPX_BIN_DIR=/usr/local/bin
      export PIPX_HOME=/opt/pipx/venvs
      pipx install duplicity --include-deps --force
      pipx install awscli --include-deps --force
      pipx install boto3 --include-deps --force
    else
      echo "Python ${_PTN_VRN} installation failed with ${_PTN_TEST}"
      exit 1
    fi

  # Update package list
  _apt_clean_update

  # Install Duplicity
  if ! command -v duplicity; then
    echo "Installing Duplicity..."
    sudo apt-get install -y duplicity
  fi

  # Install Python pip
  if ! command -v pip; then
    echo "Installing pip..."
    sudo apt-get install -y python3-pip
  fi

  # Install boto3 for S3-compatible services
  if ! python3 -c "import boto3"; then
    echo "Installing boto3..."
    pip install boto3
  fi

  # Install google-cloud-storage for Google Cloud Storage
  if ! python3 -c "import google.cloud.storage"; then
    echo "Installing google-cloud-storage..."
    pip install google-cloud-storage
  fi

  # Install b2sdk for Backblaze B2
  if ! python3 -c "import b2sdk"; then
    echo "Installing b2sdk..."
    pip install b2sdk
  fi

  # Install azure-storage-blob for Azure Blob Storage
  if ! python3 -c "import azure.storage.blob"; then
    echo "Installing azure-storage-blob..."
    pip install azure-storage-blob
  fi

  # Install ibm-cos-sdk for IBM Cloud Object Storage
  if ! python3 -c "import ibm_boto3"; then
    echo "Installing ibm-cos-sdk..."
    pip install ibm-cos-sdk
  fi

  echo "All dependencies are installed."
}

_install() {
  if [ ! -d "${_LOGPTH}" ]; then
    mkdir -p ${_LOGPTH}
  fi
  [ -e "/root/.gnupg" ] && chmod 700 /root/.gnupg
  _DUPLICITY_ITD=$(duplicity --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_DUPLICITY_ITD}" = "${_DCY_VRN}" ] \
    && [ -L "/usr/local/bin/jp.py" ] \
    && [ -L "/usr/local/bin/duplicity" ] \
    && [ -L "/usr/local/bin/aws" ]; then
    echo "Latest duplicity version ${_DCY_VRN} already installed"
    _if_install_other_dependencies
  else
    echo "Installing duplicity dependencies..."
    cd
    _find_fast_mirror_early
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    _apt_clean_update
    aptitude purge duplicity -y
    rm -f /usr/local/bin/duplicity
    rm -f /usr/local/bin/jp.py
    rm -f /usr/local/bin/aws*
    apt-get install ${_aptYesUnth} \
        intltool \
        libffi-dev \
        par2 \
        python3-pip \
        python3-venv \
        python3 \
        rclone \
        rdiff \
        tzdata
    _PTN_TEST=$(${_DCY_PTN} --version 2>&1)
    if [[ ! "${_PTN_TEST}" =~ "Python ${_PTN_VRN}" ]] \
      || [ ! -x "${_DCY_PTN}" ]; then
      cd /var/opt
      rm -rf Python*
      wget ${_wgetGet} ${_urlDev}/src/Python-${_PTN_VRN}.tgz
      tar -xzf Python-${_PTN_VRN}.tgz
      cd Python-${_PTN_VRN}
      if [ -d "/usr/local/ssl3" ]; then
        bash ./configure --with-openssl=/usr/local/ssl3
      else
        bash ./configure --with-openssl=/usr/local/ssl
      fi
      make -j $(nproc) --quiet
      make install --quiet
      cd
    fi
    _PTN_TEST=$(${_DCY_PTN} --version 2>&1)
    if [[ "${_PTN_TEST}" =~ "Python ${_PTN_VRN}" ]]; then
      python3 -m pip install pipx --break-system-packages --root-user-action ignore
      pip3 install --upgrade pip --root-user-action ignore
      export PIPX_BIN_DIR=/usr/local/bin
      export PIPX_HOME=/opt/pipx/venvs
      pipx install duplicity --include-deps --force
      pipx install awscli --include-deps --force
      pipx install boto3 --include-deps --force
    else
      echo "Python ${_PTN_VRN} installation failed with ${_PTN_TEST}"
      exit 1
    fi
    _DCY_TEST=$(${_DCY_CMD} --version 2>&1)
    if [[ "${_DCY_TEST}" =~ "duplicity ${_DCY_VRN}" ]]; then
      echo "Installation complete!"
    else
      echo "Installation failed with ${_DCY_TEST}"
      exit 1
    fi
  fi
}

_check_aws() {
  if [ ! -x "/usr/local/bin/aws" ]; then
    echo "Upgrade to add multiback tools required..."
    install
  fi
}

if [ `ps aux | grep -v "grep" | grep --count "duplicity"` -gt "0" ]; then
  echo "The duplicity backup is already running!"
  echo "Active duplicity process detected..."
  exit 1
fi

exit 0
