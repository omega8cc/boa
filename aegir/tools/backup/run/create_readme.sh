#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _sPid="f61"

_acct_group() {
  # Group that owns an account's tree. Derived, never a literal: an account
  # converted to a private primary group named after itself gets that group,
  # everything else (an unconverted box, root, www-data, an adopted odd
  # group) falls back to 'users' -- so a tool landing on an unconverted or
  # half-converted box leaves it exactly as it is today. Box-wide paths
  # (/data/conf, /data/u, the shared cores) keep 'users' and never use this.
  # $1 = account name (oN, oN.ftp, oN.<sub>) or a path under /data/disk/<oN>
  # or /var/aegir (the master keeps 'users' in this phase).
  local _a="${1}" _g
  case "${_a}" in
    /var/aegir|/var/aegir/*|aegir|root|www-data) echo "users"; return 0 ;;
    /data/disk/*) _a="${_a#/data/disk/}"; _a="${_a%%/*}" ;;
    */*) echo "users"; return 0 ;;
  esac
  _a="${_a%%.*}"
  [ -n "${_a}" ] || { echo "users"; return 0; }
  _g=$(id -gn "${_a}" 2> /dev/null)
  [ "${_g}" = "${_a}" ] || _g="users"
  echo "${_g}"
}

# Directory for storing README files
_BASE_DIR="/data/disk"

# An account owns /data/disk/<oN> (log/ included) and, through its .ftp
# login, static/control, so any name below either can be a link or a FIFO,
# and a whole directory on the way can be one. Root acts there only inside
# the real directory. _acct_in_real_dir is a copy of the helper in
# lib/functions/helper.sh.inc.
#
# Run "$@" inside the real directory $1: below /data/disk and /home every name
# on the path must be a real directory; once entered, ./name stays there
# whatever is swapped.
# The uids root's walks over the account $1's trees act on, comma-separated:
# root's own (0) and those of every identity of the account as passwd names
# them: oN and oN.<name> (its .ftp login, its client sub-accounts oN.<client>
# and oN.<client>-dev) and its PHP-FPM users oN.web and oN.<ver>.web. An
# account name holds no dot, so the match is exact: o1 never takes o10's.
# Status 1, and nothing, unless the account itself is in passwd.
_acct_walk_uids() {
  local _a="${1}" _n _p _u _r _x="0" _self=NO
  case "${_a}" in
    ""|*[!a-z0-9-]*) return 1 ;;
  esac
  while IFS=: read -r _n _p _u _r; do
    [[ "${_n}" =~ ^${_a}(\.[a-z0-9]+(-dev)?|\.[0-9]+\.web)?$ ]] || continue
    [[ "${_u}" =~ ^[1-9][0-9]*$ ]] || continue
    _x="${_x},${_u}"
    [ "${_n}" = "${_a}" ] && _self=YES
  done < <(getent passwd 2> /dev/null)
  [ "${_self}" = "YES" ] || return 1
  echo "${_x}"
}
# The whole of an account's control/, judged once before a run acts on it:
# run inside the account's real static/, it prints OK when control/ and
# everything in it, never followed through a link, and static/ and every
# directory above it up to /, are root's or one of the account's identities'
# (the uids given first, _acct_walk_uids; a uid no passwd entry names counts
# too), ABSENT when there is no control/, and otherwise why not, on one line.
# Every other account's .ftp login is in the box-wide group, which an account
# not yet on its own group still has on static/: such a login could put a
# control/ of its own there, or a file of its own in a group-writable
# directory below it, for root to act on as the account's.
_ACCT_CTRL_OWN_PL='use Fcntl;
my %own = map { $_ => 1 } grep { /^[0-9]+$/ } split(/,/, shift @ARGV // "");
sub own { my $u = shift; unless (exists $own{$u}) { local $! = 0; $own{$u} = defined(getpwuid($u)) ? 0 : ($! == 0 || $!{ENOENT} || $!{ESRCH} || $!{EBADF} || $!{EPERM}) ? 1 : 0; } return $own{$u}; }
sub isd { ($_[0] & 0170000) == 0040000 }
sub nm { (my $v = shift) =~ s/[^\x20-\x7e]/?/g; return substr($v, 0, 200); }
sub refuse { print "$_[0]\n"; exit 0; }
my ($p, $top, @d, @x) = (".", 0);
for (1 .. 256) {
  @x = stat($p) or refuse("static/ cannot be read");
  own($x[4]) or refuse("a directory above control/ is owned by uid $x[4]");
  if (@d && $x[0] == $d[0] && $x[1] == $d[1]) { $top = 1; last; }
  @d = @x;
  $p .= "/..";
}
$top or refuse("static/ is too deep");
my @s = lstat("./control");
unless (@s) { print(($!{ENOENT} ? "ABSENT" : "control/ cannot be read") . "\n"); exit 0; }
isd($s[2]) or refuse("control is not a directory");
my ($n, @q) = (0, ["control", @s]);
while (my $e = shift @q) {
  my ($f, @t) = @$e;
  own($t[4]) or refuse(nm($f) . " is owned by uid $t[4]");
  next unless isd($t[2]);
  opendir(my $h, "./$f") or refuse(nm($f) . " cannot be read");
  for my $b (readdir($h)) {
    next if $b eq "." || $b eq "..";
    ++$n > 100000 and refuse("control/ holds more than 100000 entries");
    my @u = lstat("./$f/$b") or next;
    push @q, ["$f/$b", @u];
  }
  closedir($h);
}
print "OK\n";
exit 0;'
# 0 when the account $1's control/ is its own as _ACCT_CTRL_OWN_PL judges it
# (or it has none); otherwise why not on stdout, status 1. A run that acts
# on what control/ says leaves the account as it is when it is not.
_acct_ctrl_own() {
  local _a="${1}" _o _r _want
  # an account not in passwd (not made yet, or removed) has nothing to
  # judge it by: read as before
  _o=$(_acct_walk_uids "${_a}" 2> /dev/null) || return 0
  [ -e "/data/disk/${_a}/static" ] || [ -L "/data/disk/${_a}/static" ] || return 0
  _want="$(cd -P -- /data/disk 2> /dev/null && /bin/pwd -P)/${_a}/static"
  _r=$(cd -P -- "/data/disk/${_a}/static" 2> /dev/null && [ "$(/bin/pwd -P)" = "${_want}" ] \
    && perl -e "${_ACCT_CTRL_OWN_PL}" -- "${_o}" 2> /dev/null)
  case "${_r}" in
    OK|ABSENT) return 0 ;;
  esac
  echo "${_r:-static/ is not a real directory}"
  return 1
}
_acct_in_real_dir() {
  local _d="${1}" _a="" _want
  shift
  case "${_d}" in
    /home/?*) _a=/home ;;
    /data/disk/?*) _a=/data/disk ;;
  esac
  if [ -n "${_a}" ]; then
    _want="$(cd -P -- "${_a}" 2> /dev/null && /bin/pwd -P)${_d#"${_a}"}"
  else
    _want="$(cd -P -- "${_d%/*}" 2> /dev/null && /bin/pwd -P)/${_d##*/}"
  fi
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(/bin/pwd -P)" = "${_want}" ] && "$@" )
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
# Every directory and single-link regular file from the current (pinned)
# directory down handed to the user $1 and the group $2, as chown -R handed
# them, each through a handle opened without following a link
# (_ACCT_REOWN_PL): the directory is the account's, so a hard link, a link or
# a FIFO put in it is left alone and no file outside it is handed over.
# Owner names are resolved to numbers first; nothing changes when one does
# not resolve.
_ACCT_REOWN_PL='use Fcntl; my ($u, $g, @f) = @ARGV; for my $f (@f) { sysopen(my $h, $f, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or next; my @s = stat($h); chown($u, $g, $h) if @s && (-d _ || (-f _ && $s[3] == 1)); close($h); } exit 0'
_acct_reown_here() {
  local _uid _gid
  _uid=$(id -u -- "${1}" 2> /dev/null)
  _gid=$(getent group "${2}" 2> /dev/null | cut -d: -f3)
  [[ "${_uid}" =~ ^[0-9]+$ && "${_gid}" =~ ^[0-9]+$ ]] || return 1
  env PATH=/usr/local/bin:/usr/bin:/bin find . \( -type d -o -type f \) \
    -execdir perl -e "${_ACCT_REOWN_PL}" "${_uid}" "${_gid}" {} +
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

# Function to ensure the README directory exists
_ensure_readme_dir() {
  _user=$1
  _grp=$(_acct_group "${_user}")
  _credentials_dir="${_BASE_DIR}/${_user}/static/control/remote_backups/credentials"
  _dir_ctrl_file="${_BASE_DIR}/${_user}/log/.backboa.${_user}.${_sPid}.credentials.dir.ctrl"
  if [ ! -d "${_credentials_dir}" ] || [ ! -e "${_dir_ctrl_file}" ]; then
    if _acct_mkdir_in "${_BASE_DIR}/${_user}" static control remote_backups credentials; then
      # Owner and mode set on the real directory, never through a link,
      # and the owner on what is in it through a handle (_acct_reown_here)
      _acct_in_real_dir "${_credentials_dir}" _acct_reown_here "${_user}.ftp" "${_grp}"
      _acct_in_real_dir "${_credentials_dir}" chmod 700 .
      _acct_in_real_dir "${_BASE_DIR}/${_user}/log" \
        _acct_put_stdin_here "${_dir_ctrl_file##*/}" 644 < /dev/null
      echo "Created credentials directory for user: ${_user}"
    else
      echo "Skipped credentials directory for user: ${_user} (not a real directory)"
    fi
  fi
}

# Function to create a README file for a specific user
_create_readme_file() {
  _user=$1
  _grp=$(_acct_group "${_user}")
  _credentials_dir="${_BASE_DIR}/${_user}/static/control/remote_backups/credentials"
  _readme_file="${_credentials_dir}/README.txt"
  _readme_ctrl_file="${_BASE_DIR}/${_user}/log/.backboa.${_user}.${_sPid}.credentials.readme.ctrl"

  _ensure_readme_dir "${_user}"

  if [ ! -f "${_readme_ctrl_file}" ]; then
    # A fresh 0600 file of the .ftp login inside the real credentials directory
    _acct_in_real_dir "${_credentials_dir}" \
      _acct_put_stdin_here "${_readme_file##*/}" 600 "${_user}.ftp:${_grp}" << EOF
# Backup Credentials README

This directory contains credentials files for the backup services supported by the system.
Each file corresponds to a specific backup service and must follow the correct format.

## Supported Services and Corresponding Files:
Amazon S3 (Standard, One Zone, Standard-IA)
  File: aws.txt
  export AWS_ACCESS_KEY_ID="your_aws_access_key"
  export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
  export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
  export KEEP_WITHIN="3M"              # Retain backups from the last 3 months
  export FULL_BACKUP_FREQUENCY="28D"   # Create a full backup every 28 days

Google Cloud Storage
  File: gcs.txt
  export GCS_ACCESS_KEY_ID="your_gcs_hmac_access_key"
  export GCS_SECRET_ACCESS_KEY="your_gcs_hmac_secret"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"
  Note: create an HMAC key pair for a service account with Storage Admin
  access (Cloud Storage -> Settings -> Interoperability); backups use the
  S3-compatible XML API endpoint storage.googleapis.com

Backblaze B2
  File: b2.txt
  export B2_ACCOUNT_ID="your_b2_account_id"
  export B2_APPLICATION_KEY="your_b2_application_key"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

Cloudflare R2 Object Storage
  File: cloudflare.txt
  export R2_ACCOUNT_ID="your_account_id"
  export R2_ACCESS_KEY_ID="your_access_key_id"
  export R2_SECRET_ACCESS_KEY="your_secret_access_key"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

Azure Blob Storage
  File: azure.txt
  export AZURE_STORAGE_ACCOUNT="your_azure_storage_account"
  export AZURE_STORAGE_KEY="your_azure_storage_key"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

IBM Cloud Object Storage
  File: ibm.txt
  export IBM_ACCESS_KEY_ID="your_ibm_hmac_access_key_id"
  export IBM_SECRET_ACCESS_KEY="your_ibm_hmac_secret_access_key"
  export IBM_REGION="your_ibm_region"  # E.g., "eu-de"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"
  Note: create the service credential with HMAC enabled (Include HMAC
  Credential); backups use the S3-compatible endpoint
  s3.<region>.cloud-object-storage.appdomain.cloud

Wasabi Hot Cloud Storage
  File: wasabi.txt
  export WASABI_ACCESS_KEY="your_wasabi_access_key"
  export WASABI_SECRET_KEY="your_wasabi_secret_key"
  export WASABI_REGION="your_wasabi_region"  # E.g., "us-east-1"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

DigitalOcean Spaces
  File: do_spaces.txt
  export DO_SPACES_KEY="your_do_spaces_key"
  export DO_SPACES_SECRET="your_do_spaces_secret"
  export DO_SPACES_REGION="your_do_spaces_region"  # E.g., "nyc3"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

Linode Object Storage by Akamai
  File: linode.txt
  export LINODE_ACCESS_KEY="your_linode_access_key"
  export LINODE_SECRET_KEY="your_linode_secret_key"
  export LINODE_REGION="your_linode_region"  # E.g., "us-east-1"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

## Security
- Ensure credentials files are securely managed:
  - Files should have permissions set to 600 (\`chmod 600 <file>\`).
  - The credentials directory should have permissions set to 700 (\`chmod 700 <directory>\`).

## Notes
- The backup process will fail if the credentials file for a required service is missing or contains invalid placeholders.
- Users are responsible for managing these credentials files securely.

EOF
    if [ $? -eq 0 ]; then
      echo "Created README file for user: ${_user}"
      _acct_in_real_dir "${_BASE_DIR}/${_user}/log" \
        _acct_put_stdin_here "${_readme_ctrl_file##*/}" 644 < /dev/null
    else
      echo "Skipped README file for user: ${_user} (not a real directory)"
    fi
  else
    echo "README file already updated for user: ${_user}"
  fi
}

# Main function to create README files for all users
_main() {
  for _user_dir in "${_BASE_DIR}"/*; do
    if [ -d "${_user_dir}" ]; then
      _user=$(basename "${_user_dir}")
      if [ "${_user}" != "arch" ] \
        && [ "${_user}" != "data" ] \
        && [ "${_user}" != "global" ] \
        && [ "${_user}" != "static" ] \
        && [ "${_user}" != "custom" ]; then
        if _why=$(_acct_ctrl_own "${_user}"); then
          _create_readme_file "${_user}"
        else
          echo "Skipping ${_user}: static/control is not the account's own (${_why})."
        fi
      fi
    fi
  done
}

# Execute the script
_main
