#
# Noticeable messages.
msg() {
  echo "BOA [$(date +%T 2>&1)] ==> $*"
}

# Simple prompt.
prompt_yes_no() {
if [ "${_AUTOPILOT}" = "YES" ]; then
  return 0
else
  while true; do
    printf "$* [Y/n] "
    read answer
    if [ -z "${answer}" ]; then
      return 0
    fi
    case ${answer} in
      [Yy]|[Yy][Ee][Ss])
        return 0
        ;;
      [Nn]|[Nn][Oo])
        return 1
        ;;
      *)
        echo "Please answer yes or no"
        ;;
    esac
  done
fi
}

#
# Prompt to confirm choice.
prompt_confirm_choice() {
  read -p "$1 [$2]:" _CONFIRMED_ANSWER
  if [ -z "${_CONFIRMED_ANSWER}" ]; then
    _CONFIRMED_ANSWER=$2
  fi
}

#
# Success msg.
success() {
  msg "$1 Succeeded"
}

#
# Error msg.
fatal() {
  echo " "
  msg "Fatal Error Occurred: $1"
  msg "Cannot continue installation"
  clean_pid_exit
}

#
# Not supported OS.
not_supported_os() {
  msg "== FATAL ERROR =="
  msg "Invalid install script or OS used"
  msg "It is not any supported Debian or Ubuntu version"
  msg "You need Debian - Squeeze (recommended) or Wheezy"
  msg "or Ubuntu - Precise or Lucid"
  clean_pid_exit
}

#
# Perform an action, log it, and run the spinner throughout.
runner() {
  CMD="$1"
  touch busy
  if [ "${_SPINNER}" = "YES" ]; then
    bash ${_SRCDIR}/spinner busy &
  fi
  if ${CMD} >> ${_LOG}; then
    rm busy
    sleep 1
    success "${CMD}:"
    return 0
  else
    rm busy
    sleep 1
    echo "${CMD} failed.  Error (if any): $?"
    echo " "
    echo "Displaying the last 15 lines of logfile"
    echo "  ${_LOG}"
    echo "to help troubleshoot this problem"
    echo " "
    echo "If you see any error with advice to run 'dpkg --configure -a', run this"
    echo "command first and choose default answer, then run this installer again"
    echo " "
    tail -15 ${_LOG}
    return 1
  fi
}

#
# Small spinner.
mrun() {
  CMD="$1"
  touch busy
  if [ "${_SPINNER}" = "YES" ]; then
    bash ${_SRCDIR}/spinner busy &
  fi
  if ${CMD} >> ${_LOG}; then
    rm busy
    sleep 1
    return 0
  fi
}

#
# Silent runner.
st_runner() {
  CMD="$1"
  touch busy
  if [ "${_SPINNER}" = "YES" ]; then
    bash ${_SRCDIR}/spinner busy &
  fi
  if ${CMD} >> ${_LOG}; then
    rm busy
    sleep 1
    return 0
  else
    rm busy
    sleep 1
    echo "${CMD} failed.  Error (if any): $?"
    echo " "
    echo "Displaying the last 15 lines of logfile"
    echo "  ${_LOG}"
    echo "to help troubleshoot this problem"
    echo " "
    echo "If you see any error with advice to run 'dpkg --configure -a', run this"
    echo "command first and choose default answer, then run this installer again"
    echo " "
    tail -15 ${_LOG}
    return 1
  fi
}

#
# Remove dangerous stuff from the string.
sanitize_string() {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\$\@\&\|\*]//g; s/\(['"'"'\]\)//g'
}

#
# Extract archive.
extract_archive() {
  if [ ! -z "$1" ]; then
    case $1 in
      *.tar.bz2)   tar xjf $1    ;;
      *.tar.gz)    tar xzf $1    ;;
      *.bz2)       bunzip2 $1    ;;
      *.rar)       unrar x $1    ;;
      *.gz)        gunzip -q $1  ;;
      *.tar)       tar xf $1     ;;
      *.tbz2)      tar xjf $1    ;;
      *.tgz)       tar xzf $1    ;;
      *.zip)       unzip -qq $1  ;;
      *.Z)         uncompress $1 ;;
      *.7z)        7z x $1       ;;
      *)           echo "'$1' cannot be extracted via >extract<" ;;
    esac
    rm -f $1
  fi
}

#
# Download and extract archive from dev mirror.
get_dev_arch() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/$1" -o "$1"
    extract_archive "$1"
  fi
}

#
# Download and extract from dev/version mirror.
get_dev_ext() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/$1" -o "$1"
    extract_archive "$1"
  fi
}

#
# Download and extract from dev/static.
get_dev_stc() {
  if [ ! -z "$1" ]; then
    if [ "$1" = "hosting.tar.gz" ]; then
      curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/$1" -o "$1"
    else
      curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/static/$1" -o "$1"
    fi
    extract_archive "$1"
  fi
}

#
# Download and extract from dev/contrib mirror.
get_dev_contrib() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/contrib/$1" -o "$1"
    extract_archive "$1"
  fi
}

#
# Download and extract archive from dev/src mirror.
get_dev_src() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/src/$1" -o "$1"
    extract_archive "$1"
  fi
}

