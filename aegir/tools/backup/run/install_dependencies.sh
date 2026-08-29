#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_PTN_VRN=3.14.6
_PTN_MNR="${_PTN_VRN%.*}"
_DCY_VRN=3.2.0.2
_DCY_CMD="/usr/local/bin/duplicity"
_DCY_PTN="/usr/local/bin/python${_PTN_MNR}"
_PTN_BIN="/usr/local/bin/python${_PTN_MNR}"
_PIPX_VNV="/opt/pipx/venvs/venvs"

_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 -q --tries=9 --wait=9 --user-agent='iCab'"
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
  _DF_TEST="$(LC_ALL=C command df -P -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="Use%" || $i=="Capacity") u=i }
    NR==2 && u { gsub(/%/,"",$u); print $u }')"
  [[ "${_DF_TEST}" =~ ^[0-9]+$ ]] || _DF_TEST=""
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

_check_disk_headroom() {
  # The Python source build is inode-hungry, not just byte-hungry: a fresh
  # vanilla install measured ~51k inodes and ~1.7G end to end (staged
  # source tree ~6.4k, installed tree ~9.8k, tool venvs ~30k, plus apt
  # deps), an in-place upgrade ~22k -- while df -h still looks fine. On an
  # inode-exhausted box the run fails late, mid-extraction, with a
  # misleading bytes-flavoured "No space left on device" -- and such a box
  # has already lost duplicity itself (no inode for a temp file), so
  # refuse loudly before anything is fetched or written. Reclaiming space
  # is the operator's call, never automated here. Floors are ~1.5x the
  # measured fresh cost; staging, install and venv paths are each checked
  # in case they live on different filesystems. LC_ALL pins the df header
  # tokens; a filesystem without inode accounting (btrfs totals read
  # zero) is exempt from the inode floor, and unparsable df output skips
  # a check rather than blocking the install.
  local _hdr_path _hdr_dev _hdr_seen="" _ino_tot _ino_free _kbs_free _hdr_fail=NO
  local _ino_need=75000
  local _kbs_need=2621440
  for _hdr_path in /var/tmp /usr/local /opt/pipx; do
    [ -d "${_hdr_path}" ] || _hdr_path="${_hdr_path%/*}"
    _hdr_dev="$(LC_ALL=C command df -P -l "${_hdr_path}" 2>/dev/null | awk 'NR==2 { print $1 }')"
    if [ ! -z "${_hdr_dev}" ]; then
      case " ${_hdr_seen} " in *" ${_hdr_dev} "*) continue ;; esac
      _hdr_seen="${_hdr_seen} ${_hdr_dev}"
    fi
    _ino_tot=""
    _ino_free=""
    read -r _ino_tot _ino_free <<< "$(LC_ALL=C command df -P -l -i "${_hdr_path}" 2>/dev/null | awk '
      NR==1 { for (i=1; i<=NF; i++) { if ($i=="Inodes") t=i; if ($i=="IFree") f=i } }
      NR==2 && t && f { print $t, $f }')"
    [[ "${_ino_tot}" =~ ^[0-9]+$ ]] || _ino_tot=0
    [[ "${_ino_free}" =~ ^[0-9]+$ ]] || _ino_free=""
    if [ "${_ino_tot}" -gt 0 ] && [ ! -z "${_ino_free}" ] && [ "${_ino_free}" -lt "${_ino_need}" ]; then
      echo "ERROR: Not enough free inodes on ${_hdr_path}: ${_ino_free} free, ${_ino_need} required"
      echo "ERROR: This is inode exhaustion, not disk space -- df -h can look fine while df -i is full"
      _hdr_fail=YES
    fi
    _kbs_free="$(LC_ALL=C command df -P -l -k "${_hdr_path}" 2>/dev/null | awk '
      NR==1 { for (i=1; i<=NF; i++) if ($i=="Available" || $i=="Avail") u=i }
      NR==2 && u { print $u }')"
    [[ "${_kbs_free}" =~ ^[0-9]+$ ]] || _kbs_free=""
    if [ ! -z "${_kbs_free}" ] && [ "${_kbs_free}" -lt "${_kbs_need}" ]; then
      echo "ERROR: Not enough free disk space on ${_hdr_path}: $(( _kbs_free / 1024 ))M free, $(( _kbs_need / 1024 ))M required"
      _hdr_fail=YES
    fi
  done
  if [ "${_hdr_fail}" = "YES" ]; then
    echo "ERROR: Aborting before any download or change to the installed backup tooling"
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
    _ffList="/var/backups/boa-mirrors-2026-07.txt"
    [ -d "/var/backups" ] || mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "files.boa.io"  > ${_ffList}
      echo "files.o8.io" >> ${_ffList}
      echo "files.host8.biz" >> ${_ffList}
      echo "files.aegir.biz" >> ${_ffList}
      echo "files.aoboshi.com" >> ${_ffList}
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _USE_MIR="${_CHECK_MIRROR}"
        [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.boa.io"
      else
        _USE_MIR="files.boa.io"
      fi
    else
      _USE_MIR="files.boa.io"
    fi
  else
    _USE_MIR="files.boa.io"
  fi
  _urlDev="https://${_USE_MIR}/dev"
  _urlHmr="https://${_USE_MIR}/versions/${_tRee}/boa/aegir"
}

# The pin is only honoured when the venv actually runs on the pinned
# interpreter. A version match alone can hide a mixed venv: a box that
# jumps python and installs the pin in the same run ends with packages
# under the old lib tree, bin/python on the old binary, and pyvenv.cfg
# claiming the new version -- then silently depends on the old binary
# surviving. Field-verified on a box doing exactly that jump.
_duplicity_venv_on_pin() {
  local _VNV_PYT
  _VNV_PYT="$(readlink -f "${_PIPX_VNV}/duplicity/bin/python" 2>/dev/null)"
  [[ "${_VNV_PYT}" == *"python${_PTN_MNR}" ]] \
    && [ -x "${_VNV_PYT}" ] \
    && [ -d "${_PIPX_VNV}/duplicity/lib/python${_PTN_MNR}/site-packages/duplicity" ]
}

# pipx install --force reuses an existing venv AND its interpreter -- it
# ignores --python on that path by design -- so a venv created under an
# older python must be removed first to be recreated on the pin.
_pipx_install_pinned() {
  local _PIP_PKG="$1"
  local _PIP_VNV="$2"
  local _VNV_PYT
  if [ -d "${_PIPX_VNV}/${_PIP_VNV}" ]; then
    _VNV_PYT="$(readlink -f "${_PIPX_VNV}/${_PIP_VNV}/bin/python" 2>/dev/null)"
    if [[ "${_VNV_PYT}" != *"python${_PTN_MNR}" ]] || [ ! -x "${_VNV_PYT}" ]; then
      echo "Recreating the ${_PIP_VNV} venv on python${_PTN_MNR}; found ${_VNV_PYT:-no interpreter}"
      rm -rf "${_PIPX_VNV:?}/${_PIP_VNV:?}"
    fi
  fi
  if [ -d "${_PIPX_VNV}/${_PIP_VNV}" ]; then
    # Existing venv already on the pin; pipx ignores --python next to
    # --force anyway (with a warning), so omit it on this path
    pipx install "${_PIP_PKG}" --include-deps --force
  else
    pipx install "${_PIP_PKG}" --python "${_PTN_BIN}" --include-deps --force
  fi
  _VNV_PYT="$(readlink -f "${_PIPX_VNV}/${_PIP_VNV}/bin/python" 2>/dev/null)"
  if [[ "${_VNV_PYT}" != *"python${_PTN_MNR}" ]]; then
    echo "ERROR: the ${_PIP_VNV} venv runs on ${_VNV_PYT:-no interpreter}, not the pinned python${_PTN_MNR}"
    exit 1
  fi
}

# Function to install other dependencies
_install_other_dependencies() {
  echo "Checking and installing other dependencies..."

  echo "Installing boto3 for S3-compatible services..."
  _pipx_install_pinned boto3 boto3

  echo "Installing awscli for S3-compatible services..."
  _pipx_install_pinned awscli awscli

  echo "Installing azure-storage-blob for Azure Blob Storage..."
  _pipx_install_pinned azure-storage-blob azure-storage-blob

  echo "Installing b2sdk for Backblaze B2..."
  _pipx_install_pinned b2sdk b2sdk

  echo "All dependencies are installed."
}

_install_duplicity() {
  pip3 install --upgrade pip --root-user-action ignore
  echo "Installing pipx..."

  ${_DCY_PTN} -m pip install pipx --break-system-packages --root-user-action ignore

  export PIPX_BIN_DIR=/usr/local/bin
  export PIPX_HOME=/opt/pipx/venvs

  # Skip only the duplicity reinstall on a matching version; the other
  # dependencies must still install on every run. The venv check keeps a
  # version match from masking a mixed venv -- that state must fall
  # through to the reinstall below so already-affected boxes converge
  if [ -x "${_DCY_CMD}" ]; then
    _DCY_TEST=$(${_DCY_CMD} --version 2>&1)
    if [[ "${_DCY_TEST}" =~ "duplicity ${_DCY_VRN}" ]]; then
      if _duplicity_venv_on_pin; then
        echo "Already Installed ${_DCY_TEST}"
        if [ ! -e "/root/.force.duplicity.reinstall.cnf" ]; then
          return 0
        fi
      else
        echo "Duplicity ${_DCY_VRN} venv is not on python${_PTN_MNR}, rebuilding it"
      fi
    fi
  fi

  # Pinned: an unpinned install delivers latest-at-install-time, so the
  # fleet drifts across duplicity versions and the check above can
  # never match once upstream moves
  echo "Installing Duplicity ${_DCY_VRN}..."
  _pipx_install_pinned "duplicity==${_DCY_VRN}" duplicity

  _DCY_TEST=$(${_DCY_CMD} --version 2>&1)
  echo "Just Installed ${_DCY_TEST}"

  if [[ ! "${_DCY_TEST}" =~ "duplicity ${_DCY_VRN}" ]]; then
    echo "Duplicity installation failed with ${_DCY_TEST}"
    exit 1
  fi
  if ! _duplicity_venv_on_pin; then
    echo "Duplicity ${_DCY_VRN} installed, but its venv is not on python${_PTN_MNR}"
    echo "Interpreter: $(readlink -f "${_PIPX_VNV}/duplicity/bin/python" 2>/dev/null)"
    exit 1
  fi
  echo "Duplicity installation complete!"
}

# Build in a private directory under /var/tmp, never in the shared
# /var/opt: a concurrent BARRACUDA or OCTOPUS pass clears that directory
# wholesale with 'rm -rf /var/opt/*' (system.sh.inc _finale at the end of
# every pass, and five more sites), and such passes run right through the
# first post-install hour -- exactly when an operator is told to run the
# install verb. On a fresh box that hour's first run died inside configure
# with "cannot find input file: 'Makefile.pre.in'" because the tree went
# out from under it. /opt/tmp is no refuge, it is blanket-purged just as
# widely. Nothing sweeps /var/tmp, so this build cleans up after itself.
_python_build_cleanup() {
  [ ! -z "${_PTN_DIR}" ] && [ -d "${_PTN_DIR}" ] && rm -rf "${_PTN_DIR}"
  return 0
}

_python_stage_src() {
  mkdir -p /var/tmp
  rm -rf /var/opt/Python*
  # A run killed outright never reaches its trap; reap only trees old
  # enough that no live build can own one
  find /var/tmp -maxdepth 1 -name 'boa-python-build-*' -type d -mtime +0 \
    -exec rm -rf {} + 2>/dev/null
  _PTN_DIR="$(mktemp -d /var/tmp/boa-python-build-XXXXXX 2>/dev/null)"
  if [ -z "${_PTN_DIR}" ] || [ ! -d "${_PTN_DIR}" ]; then
    echo "Could not create a private Python build directory under /var/tmp"
    return 1
  fi
  trap _python_build_cleanup EXIT
  cd "${_PTN_DIR}" || { echo "Cannot enter ${_PTN_DIR}"; return 1; }
  # wget rc alone proves nothing on a soft-404, so the guarded
  # extraction doubles as the payload check
  wget ${_wgetGet} ${_urlDev}/src/Python-${_PTN_VRN}.tgz
  if [ ! -s "Python-${_PTN_VRN}.tgz" ] \
    || ! tar -xzf "Python-${_PTN_VRN}.tgz"; then
    echo "Python ${_PTN_VRN} source archive missing or invalid on ${_urlDev}"
    return 1
  fi
  cd
  return 0
}

_python_install_src() {
  _check_disk_headroom
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
    _python_stage_src || exit 1
    cd "${_PTN_DIR}/Python-${_PTN_VRN}" || { echo "Cannot enter the Python source tree"; exit 1; }
    if ! bash ./configure --with-openssl=/usr/local/ssl3; then
      echo "Python ${_PTN_VRN} configure failed"
      exit 1
    fi
    if ! make -j $(nproc) --quiet; then
      echo "Python ${_PTN_VRN} make failed"
      exit 1
    fi
    if ! make install --quiet; then
      echo "Python ${_PTN_VRN} make install failed"
      exit 1
    fi
    cd
  fi
  _PTN_TEST=$(${_DCY_PTN} --version 2>&1)
  if [[ "${_PTN_TEST}" =~ "Python ${_PTN_VRN}" ]]; then
    echo "Python ${_PTN_VRN} installed"
    export PYTHONPATH="/usr/local/lib/python${_PTN_MNR}/site-packages"
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
    || [[ "${_PIP_TEST}" =~ "python 3.13" ]] \
    || [[ "${_PIP_TEST}" =~ "python ${_PTN_MNR}" ]]; then
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

