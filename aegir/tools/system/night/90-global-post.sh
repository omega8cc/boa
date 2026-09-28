#!/bin/bash

###
### 90-global-post.sh -- global, once-per-run maintenance that must happen after
### the per-account work (in the fan-out model, after all accounts join). Carved
### out of owl.sh (Phase 3 of the owl.sh/night split): shared-codebase + ghost
### cleanup, empty-hostmaster-platform removal, weblog teardown, incident
### detection, the Nginx forward-secrecy / DH-param refresh (+ single reload), and
### the /data tree permission sweep + backup pruning. Sourced by owl.sh today
### and called in place; becomes the post-join step run once by owl.sh later.
###
### Touches shared/global resources (the master /var/aegir tree, /data/all,
### /etc/ssl/private, a single `service nginx reload`), so it must NEVER run inside
### the per-account fan-out. The /run/daily-fix.pid lock stays owned by the
### orchestrator (owl.sh), not released here.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh

# night.inc.sh is delivered by its own fNN fetch, so this worker can land ahead
# of a library that predates the in-flight gate. Every "_provision_running &&
# return" below is fail-OPEN in that state -- an undefined function returns 127,
# which reads as "no Provision task running" and lets the cleanups below delete
# through a live task. Deliberately the BROAD substring form, not a copy of the
# anchored library body: it runs only while the library is behind, and
# over-matching there merely skips a cleanup (see night.inc.sh).
if ! declare -F _provision_running > /dev/null 2>&1; then
  _provision_running() {
    pgrep -f provision > /dev/null 2>&1
  }
fi

# oN owns its /data/disk/oN (config/, .drush/, .tmp/, distro/ and every
# platform there), so any name below it can be a link or a FIFO, and any
# directory on the way can itself be a link. Root reads, edits and sets modes
# there only through the helpers below, inside the real directory. The
# _acct_* bodies are the helper.sh.inc and 20-sites.sh ones (the night family
# never sources helper.sh.inc), carried unless already defined.
if ! declare -F _acct_in_real_dir > /dev/null 2>&1; then
  # Run "$@" inside the real directory $1, never one reached through a link
  # an account planted on the way. Below /home and /data/disk (root's) every
  # name on the path must be a real directory; elsewhere the last name is
  # checked against its resolved parent. Once entered, ./name stays in that
  # directory whatever is swapped.
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
fi
if ! declare -F _acct_read_here > /dev/null 2>&1; then
  # ./$1 in the current (pinned) directory: never through a link, never
  # blocked on a FIFO, at most 1 MiB. Empty for anything else.
  _acct_read_here() {
    timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
      bs=1048576 count=1 status=none 2> /dev/null
  }
fi
if ! declare -F _acct_put_same_here > /dev/null 2>&1; then
  # ./$1 in the current (pinned) directory replaced by the exact bytes $2,
  # only while ./$1 is a regular file below 1 MiB (so a bounded read saw all
  # of it): a fresh file with the owner, group and read/write bits of the
  # file it replaces, then renamed over the name. The temp is created,
  # written, owned and moded through one handle opened O_EXCL|O_NOFOLLOW, so
  # nothing root owns is ever chowned by name in a directory the account can
  # write (a hard link renamed over the temp name before a chown by name
  # would have handed another file to the owner of the file it replaces); a
  # swap before the rename only lands a file the account could have put
  # there itself. The mode keeps only the read/write bits of the file it
  # replaces, as before.
  _ACCT_PUT_PL='use Fcntl; my ($n, $u, $g, $m) = @ARGV; local $/; my $d = <STDIN>; sysopen(my $h, $n, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) or exit 1; (print {$h} $d) or exit 1; chown($u, $g, $h) or exit 1; chmod(oct($m) & 0666, $h) or exit 1; close($h) or exit 1; exit 0'
  _acct_put_same_here() {
    local _t="./.${1}.put.$$.${RANDOM}" _st _typ _uid _gid _mod _sz
    _st=$(stat -c '%F|%u|%g|%a|%s' -- "./${1}" 2> /dev/null) || return 1
    IFS='|' read -r _typ _uid _gid _mod _sz <<< "${_st}"
    case "${_typ}" in
      "regular file"|"regular empty file") ;;
      *) return 1 ;;
    esac
    [[ "${_mod}" =~ ^[0-7]+$ && "${_sz}" =~ ^[0-9]+$ ]] || return 1
    [ "${_sz}" -lt 1048576 ] || return 1
    rm -f -- "${_t}"
    if printf '%s' "${2}" \
      | perl -e "${_ACCT_PUT_PL}" "${_t}" "${_uid}" "${_gid}" "${_mod}" \
      && mv -f -T -- "${_t}" "./${1}"; then
      return 0
    fi
    rm -f -- "${_t}"
    return 1
  }
fi
if ! declare -F _acct_read_plain_here > /dev/null 2>&1; then
  # ./$1 of the current (pinned) directory as text: status 1, and nothing,
  # unless it is a regular file; read as _acct_read_here reads it.
  _acct_read_plain_here() {
    [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
    _acct_read_here "${1}"
  }
fi
if ! declare -F _acct_sed_same_here > /dev/null 2>&1; then
  # ./$1 edited by the sed arguments after it, as sed -i edited it (the same
  # bytes: the trailing "x" keeps every newline through the substitutions),
  # and put back as _acct_put_same_here puts it.
  _acct_sed_same_here() {
    local _n="${1}" _c
    shift
    _c=$(_acct_read_plain_here "${_n}" && echo x) || return 1
    _c=$(printf '%s' "${_c%x}" | sed "$@"; echo x)
    _acct_put_same_here "${_n}" "${_c%x}"
  }
fi

# A mode set on names in the current (pinned) directory, never through a
# link: each name is opened without following one and without blocking on a
# FIFO, checked to be the expected type and changed through the open handle.
# Run it inside a pinned directory or from find -execdir: O_NOFOLLOW covers
# the last name only. Args: f|d (regular file or directory), the mode
# (octal), the names.
# A directory keeps its set-user-ID and set-group-ID bits unless the mode has
# five digits (02775, 00755), as chmod(1) does with a numeric mode.
# A regular file is changed only while it has a single link: a hard link put
# at a name (or anywhere in a walked tree) is left alone, so the mode never
# reaches the file it names.
_NIGHT_FCHMOD_PL='use Fcntl;
my ($t, $ms) = (shift @ARGV, shift @ARGV);
my ($m, $k) = (oct($ms), length($ms) < 5 ? 06000 : 0);
for my $f (@ARGV) {
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if ($t eq "f" && -f _ && $s[3] == 1) {
    chmod($m, $h);
  } elsif ($t eq "d" && -d _) {
    chmod($m | ($s[2] & $k), $h);
  }
  close($h);
}'

# Each directory and regular file named (find -execdir, or in a pinned
# directory) made root's, with the mode $1 for a directory (its set-ID bits
# kept, as chmod 0755 keeps them) and $2 for a file, except xmass's two
# records, which xmass writes 0600. An entry is checked by lstat before it is
# opened, so a FIFO or a device is never opened, and is changed through its
# own handle, never through a link. A hard-linked file is taken back too:
# /data/conf is never an account's, so a file an account linked there is
# made root's, as chown -R root:root made it.
_CONF_ROOT_PL='use Fcntl;
my ($dm, $fm) = (oct(shift @ARGV), oct(shift @ARGV));
for my $f (@ARGV) {
  my @l = lstat($f);
  next unless @l && (-d _ || -f _);
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if (@s && $s[0] == $l[0] && $s[1] == $l[1]) {
    if (-d _) {
      chown(0, 0, $h);
      chmod($dm | ($s[2] & 06000), $h);
    } elsif (-f _) {
      chown(0, 0, $h);
      chmod($f =~ m{(^|/)xmass_(state|solr_used)\.cnf(\.tmp\.\d+)?$} ? 0600 : $fm, $h);
    }
  }
  close($h);
}'
# The modes of /data/conf (the current, pinned directory) and everything
# below it, as the Octopus upgrade sets them: directories 0755, files 0644,
# each through the entry's own handle (_CONF_ROOT_PL), and the top 0711.
_global_conf_modes_here() (
  PATH=/usr/local/bin:/usr/bin:/bin
  perl -e "${_CONF_ROOT_PL}" 0755 0644 .
  find . -mindepth 1 \( -type d -o -type f \) \
    -execdir perl -e "${_CONF_ROOT_PL}" 0755 0644 {} +
  chmod 0711 .
)

# The modes of every account platform's sites/all/{libraries,modules,themes}
# trees: directories 02775, files 0664. The account owns distro/ and every
# platform in it, so each tree is walked from inside its real directory and
# every mode goes through a handle that never follows a link.
_distro_sites_all_modes() {
  local _pDis
  for _pDis in /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes}; do
    [ -d "${_pDis}" ] || continue
    _acct_in_real_dir "${_pDis}" find . -type d \
      -execdir perl -e "${_NIGHT_FCHMOD_PL}" d 02775 {} + &> /dev/null
    _acct_in_real_dir "${_pDis}" find . -type f \
      -execdir perl -e "${_NIGHT_FCHMOD_PL}" f 0664 {} + &> /dev/null
  done
}

# Every vhost in the current (pinned) vhost.d still carrying TLSv1.1 in its
# protocol list, edited as sed -i edited it; the others are left untouched.
# One grep lists them, reading only the regular files under 1 MiB directly
# there (the ones _acct_sed_same_here edits) for at most 60 seconds; -D skip
# never blocks on a FIFO or a device put at a name since the listing, and
# _acct_sed_same_here refuses a link or a FIFO swapped in after it. When the
# listing or grep cannot tell (an error, a timeout), each vhost is read
# bounded and edited only when it holds the line. Names in subdirectories
# and dot-names are not vhosts nginx reads. A record starting with / carries
# a status: no name listed here holds one.
_vhost_tls11_drop_here() {
  local _f _rc=""
  local -a _n=() _m=()
  while IFS= read -r -d '' _f; do
    case "${_f}" in
      /rc=*) _rc="${_f#/rc=}"; continue ;;
    esac
    _f="${_f#./}"
    case "${_f}" in
      */*|.*) continue ;;
    esac
    _n+=( "${_f}" )
  done < <(find . -mindepth 1 -maxdepth 1 -type f -size -1048576c -print0 2> /dev/null
    printf '/rc=%s\0' "$?")
  # A failed listing is never read as grep's "no match".
  [ "${_rc}" = "0" ] || _rc="list"
  if [ "${_rc}" = "0" ] && [ "${#_n[@]}" -gt 0 ]; then
    _rc=""
    while IFS= read -r -d '' _f; do
      case "${_f}" in
        /rc=*) _rc="${_f#/rc=}" ;;
        *) _m+=( "${_f}" ) ;;
      esac
    done < <(LC_ALL=C timeout 60 grep -lZ -F -d skip -D skip \
      -e "TLSv1.1 TLSv1.2 TLSv1.3;" -- "${_n[@]}" 2> /dev/null
      printf '/rc=%s\0' "$?")
  fi
  case "${_rc}" in
    0|1)
      for _f in "${_m[@]}"; do
        _acct_sed_same_here "${_f}" "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
      done
      ;;
    *)
      for _f in ./*; do
        _f="${_f#./}"
        _acct_read_plain_here "${_f}" | grep -qF -- "TLSv1.1 TLSv1.2 TLSv1.3;" || continue
        _acct_sed_same_here "${_f}" "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
      done
      ;;
  esac
}

_delete_this_empty_hostmaster_platform() {
  _run_drush8_hmr_master_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

_check_old_empty_hostmaster_platforms() {
  _provision_running && { echo "INFO: provision task active -- skipping empty-platform cleanup"; return; }
  if [ -n "${_DEL_OLD_EMPTY_PLATFORMS}" ] \
	&& [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
	_DO_NOTHING=YES
  else
    if [ "${_hostedSys}" = "YES" ]; then
	  _DEL_OLD_EMPTY_PLATFORMS="3"
	else
	  _DEL_OLD_EMPTY_PLATFORMS="7"
	fi
  fi
  if [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
    if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to \
        ${_DEL_OLD_EMPTY_PLATFORMS} days on /var/aegir instance"
      for _Platform in `find /var/aegir/.drush/platform_* -maxdepth 1 -mtime \
        +${_DEL_OLD_EMPTY_PLATFORMS} -type f | sort`; do
        _T_PFM_NAME=$(echo "${_Platform}" \
          | sed "s/.*platform_//g; s/.alias.drushrc.php//g" \
          | awk '{ print $1}' 2>&1)
        _T_PFM_ROOT=$(cat ${_Platform} \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        # The alias keeps the path the platform was registered with, which for
        # a Composer build can be its app root; site_path and sites/all live
        # under the docroot Provision serves, so both tests below read that
        # (the site test keeps the raw-root spelling too, so it only gains).
        _T_PFM_DOC=$(_detect_real_docroot "${_T_PFM_ROOT}")
        _T_PFM_SITE=$(grep -e "${_T_PFM_ROOT}/sites/" \
          -e "${_T_PFM_DOC:-${_T_PFM_ROOT}}/sites/" \
          /var/aegir/.drush/*.drushrc.php \
          | grep site_path 2>&1)
        if [ -z "${_T_PFM_DOC}" ]; then
          # Version-agnostic emptiness: no index.php at the alias root nor
          # under web/docroot/html. Do NOT key on sites/all, which D8+ dropped.
          if _cnf_flag_yes /root/.barracuda.cnf _GHOST_PLATFORMS_CLEANUP; then
            mkdir -p /var/aegir/undo
            mv -f /var/aegir/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php /var/aegir/undo/ &> /dev/null
            echo "GHOST platform ${_T_PFM_ROOT} detected and moved to /var/aegir/undo/"
          else
            echo "GHOST platform ${_T_PFM_ROOT} detected (dry-run; set _GHOST_PLATFORMS_CLEANUP=YES in /root/.barracuda.cnf to move)"
          fi
        fi
        if [[ "${_T_PFM_SITE}" =~ ".restore" ]]; then
          echo "WARNING: ghost site leftover found: ${_T_PFM_SITE}"
        fi
        if [ -z "${_T_PFM_SITE}" ] \
          && [ -e "${_T_PFM_DOC:-${_T_PFM_ROOT}}/sites/all" ]; then
          _delete_this_empty_hostmaster_platform
        fi
      done
    fi
  fi
}

_shared_codebases_cleanup() {
  _provision_running && { echo "INFO: provision task active -- skipping shared-codebases cleanup"; return; }
  if [ -L "/data/all" ]; then
    _CLD="/data/disk/codebases-cleanup"
  else
    _CLD="/var/backups/codebases-cleanup"
  fi
  for i in `dir -d /data/all/*/`; do
    if [ -d "${i}o_contrib" ]; then
      for _Codebase in `find ${i}* -maxdepth 1 -mindepth 1 -type d \
        | grep "/profiles$" 2>&1`; do
        _CodebaseDir=$(echo ${_Codebase} \
          | sed 's/\/profiles//g' \
          | awk '{print $1}' 2> /dev/null)
        # Defensive: a tree with a detectable docroot is a real codebase of any
        # version -- never reap it. This loop targets the legacy D6/D7 shared
        # /data/all store (anchored on a root-level profiles/); D8+ codebases are
        # self-contained under distro/ and are not managed here.
        [ -n "$(_detect_real_docroot "${_CodebaseDir}")" ] && continue
        # 2>&1 belongs to find, not to sort: bound to sort, find's own error
        # never reached the variable and any failed enumeration read as "no
        # references". A failed find (glob unexpanded, unreadable tree) is
        # not evidence the codebase is unused, so it is skipped, not moved.
        _CodebaseTest=$(find /data/disk/*/distro/*/*/ -maxdepth 1 -mindepth 1 \
          -type l -lname ${_Codebase} 2>&1 | sort)
        if [[ "${_CodebaseTest}" =~ "No such file or directory" ]]; then
          echo "Skipping ${_CodebaseDir}: could not enumerate platform symlinks (${_CodebaseTest})"
          continue
        fi
        if [ -z "${_CodebaseTest}" ]; then
          if _cnf_flag_yes /root/.barracuda.cnf _SHARED_CODEBASES_CLEANUP; then
            mkdir -p ${_CLD}${i}
            echo "Moving no longer used ${_CodebaseDir} to ${_CLD}${i}"
            mv -f ${_CodebaseDir} ${_CLD}${i}
          else
            echo "Unused ${_CodebaseDir} detected (dry-run; set _SHARED_CODEBASES_CLEANUP=YES in /root/.barracuda.cnf to move)"
          fi
        fi
      done
    fi
  done
}

# The text of every platform alias in the current (pinned) .drush, one
# after another, each read bounded and never through a link or a FIFO.
_platform_aliases_text_here() {
  local _a
  for _a in ./platform_*.alias.drushrc.php; do
    _acct_read_plain_here "${_a#./}"
    echo
  done
}

# True when a registered platform alias names the tree $1: the master's
# aliases as they always were, the accounts' ones in the text $2 holds, read
# once per run inside each real .drush.
_platform_alias_names() {
  grep -qsF -e "'${1}'" -e "'${1}/" \
    /var/aegir/.drush/platform_*.alias.drushrc.php && return 0
  grep -qsF -e "'${1}'" -e "'${1}/" -- "${2}"
}

_ghost_codebases_cleanup() {
  _provision_running && { echo "INFO: provision task active -- skipping ghost-codebases cleanup"; return; }
  local _aliasText _u
  # Without the aliases nothing is known to be unused, so nothing is moved.
  _aliasText=$(mktemp) \
    || { echo "INFO: no temporary file for the platform aliases -- skipping ghost-codebases cleanup"; return; }
  for _u in /data/disk/*; do
    [ -d "${_u}/.drush" ] || continue
    _acct_in_real_dir "${_u}/.drush" _platform_aliases_text_here >> "${_aliasText}"
  done
  _CLD="/var/backups/ghost-codebases-cleanup"
  for i in `dir -d /data/disk/*/distro/*/*/`; do
    _CodebaseTest=$(find ${i} -maxdepth 1 -mindepth 1 \
      -type d -name vendor | sort 2>&1)
    for _vendor in ${_CodebaseTest}; do
      _ParentDir=`echo ${_vendor} | sed "s/\/vendor//g"`
      ### The platform root is group-writable, so what is on disk there is
      ### not evidence that a tree is unused: a tree still named by a
      ### registered platform alias is never treated as a ghost.
      if _platform_alias_names "${_ParentDir}" "${_aliasText}"; then
        continue
      fi
      if [ -n "$(_detect_real_docroot "${_ParentDir}")" ]; then
        # A detectable docroot (index.php at root or under web/docroot/html)
        # means a real codebase of ANY Drupal version -- never a ghost. Do NOT
        # key on sites/all, which D8+ dropped (web/sites/default, no sites/all).
        _CLEAN_THIS=SKIP
      else
        _CLEAN_THIS="${_ParentDir}"
        _TSTAMP=$(date +%y%m%d-%H%M%S)
        if _cnf_flag_yes /root/.barracuda.cnf _GHOST_CODEBASES_CLEANUP; then
          mkdir -p "${_CLD}${i}${_TSTAMP}"
          ### Moved from inside its real parent, so a name on the way that
          ### the account swapped for a link since the checks moves nothing.
          if _acct_in_real_dir "${_CLEAN_THIS%/*}" \
            mv -f -- "./${_CLEAN_THIS##*/}" "${_CLD}${i}${_TSTAMP}/"; then
            echo "Moved ghost ${_CLEAN_THIS} to ${_CLD}${i}${_TSTAMP}/"
          else
            rmdir "${_CLD}${i}${_TSTAMP}" 2> /dev/null
            echo "Ghost ${_CLEAN_THIS} detected and not moved: not a real directory on its path, or the move failed"
          fi
        else
          echo "Ghost ${_CLEAN_THIS} detected (dry-run; set _GHOST_CODEBASES_CLEANUP=YES in /root/.barracuda.cnf to move)"
        fi
      fi
    done
  done
  rm -f -- "${_aliasText}"
}

_goaccess_vhosts() {
  ### Standalone vhosts under /etc/nginx/sites-enabled have no Octopus account,
  ### so the per-site arm in 20-sites.sh can never reach them. Enumerate every
  ### literal server_name and build one report per name, plus the box-wide ALL
  ### aggregate. Reports land in the xdr9000 archive tree (already pulled by the
  ### operator's fleet tooling), not the tenant-facing adminer path.
  local _vhDom _vhTgt _isWblgx
  local -a _vhDoms=()
  _isWblgx="$(which weblogx)"
  [ -x "${_isWblgx}" ] || return 0
  [ -d "/etc/nginx/sites-enabled" ] || return 0
  ### Multi-line server_name directives are valid nginx config, so collect
  ### tokens from the directive up to its terminating semicolon, drop what
  ### follows the semicolon, and lowercase (nginx normalizes server names, the
  ### $host log field is lowercase, and lowercasing also keeps any name from
  ### matching weblogx's uppercase ALL trigger). The while-read keeps tokens
  ### away from pathname expansion, unlike a for-in over a substitution.
  while IFS= read -r _vhDom; do
    ### Names become filesystem paths and weblogx arguments; accept only sane
    ### hostnames (alnum edges), which also rejects wildcards, "_" catch-alls,
    ### dot-runs and anything option-shaped.
    if [[ ! "${_vhDom}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] \
      || [[ "${_vhDom}" =~ \.\. ]] \
      || [ "${_vhDom}" = "localhost" ]; then
      continue
    fi
    _vhDoms+=("${_vhDom}")
  done < <(awk '
    /^[[:space:]]*server_name([[:space:]]|$)/ { inns=1; sub(/^[[:space:]]*server_name/, "") }
    inns {
      end = index($0, ";")
      line = (end ? substr($0, 1, end - 1) : $0)
      sub(/#.*/, "", line)
      n = split(line, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (tok[i] != "") print tok[i]
      if (end) inns = 0
    }' /etc/nginx/sites-enabled/* 2>/dev/null | tr 'A-Z' 'a-z' | sort -u)
  ### No standalone vhosts -- nothing to report on, including no ALL run.
  [ "${#_vhDoms[@]}" -eq 0 ] && return 0
  _vhTgt=/var/log/boa/xdr9000/goaccess
  mkdir -p "${_vhTgt}"
  ### The engine keeps the archive root 0700; assert it in case this created it.
  chmod 700 /var/log/boa/xdr9000 "${_vhTgt}" &> /dev/null
  ### Stage the log corpus ONCE for the whole loop. weblogx's internal prepare
  ### never plants the .global.pid sentinel, so without it every call would
  ### re-prepare the corpus; in the nightly, _prepare_weblogx (owl.sh) has
  ### already staged it and planted the sentinel. Standalone, do the same:
  ### first call prepares, then the sentinel makes the rest reuse the corpus.
  if [ ! -e "/var/www/adminer/access/archive/unzip/.global.pid" ]; then
    if command -v _prepare_weblogx > /dev/null 2>&1; then
      _prepare_weblogx
    else
      ${_isWblgx} --site="${_vhDoms[0]}" --env=vhosts
      wait
      touch /var/www/adminer/access/archive/unzip/.global.pid
    fi
  fi
  ### Build in weblogx's standard working area (it stages its merged-log
  ### scratch beside the report), then publish ONLY the finished HTML into the
  ### archive tree, atomically -- the hourly fleet pull must never catch a
  ### multi-MB scratch corpus or a half-written report.
  for _vhDom in "${_vhDoms[@]}" ALL; do
    ${_isWblgx} --site="${_vhDom}" --env=vhosts
    wait
    if [ -e "/var/www/adminer/access/vhosts/${_vhDom}/index.html" ]; then
      mkdir -p "${_vhTgt}/${_vhDom}"
      cp -af "/var/www/adminer/access/vhosts/${_vhDom}/index.html" \
        "${_vhTgt}/${_vhDom}/.index.html.new"
      mv -f "${_vhTgt}/${_vhDom}/.index.html.new" \
        "${_vhTgt}/${_vhDom}/index.html"
    fi
  done
}

_cleanup_weblogx() {
  _ARCHLOGS=/var/www/adminer/access/archive
  if [ -e "${_ARCHLOGS}/unzip" ]; then
    rm -f ${_ARCHLOGS}/unzip/access*
    rm -f ${_ARCHLOGS}/unzip/.global.pid
  fi
}

_incident_email_report() {
  if [ -e "/root/.barracuda.cnf" ]; then
    _MY_EMAIL=
    # shellcheck disable=SC1091
    source /root/.barracuda.cnf
    export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
    : "${_INCIDENT_REPORT:=MINI}"
  fi
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" != "OFF" ]; then
    echo "Sending Incident Report Email on $(date)" >> ${_thisLog}
    ###
    ### Send the matching error lines WITH context, not a blind tail: this is
    ### the global (orchestrator) log, and per-account work now lives in its own
    ### acct-*.log, so a tail here would only show late global-post output, never
    ### the incident itself. -F treats the token as a fixed string.
    ###
    {
      echo "Incident '${1}' detected during owl.sh on ${_hName} at $(date)"
      echo
      echo "Matching log lines (with context) from ${_thisLog}:"
      echo
      grep -F -n -a -A3 -B3 -- "${1}" "${_thisLog}" 2>/dev/null | head -n 120
      echo
      echo "Full log: ${_thisLog}"
    } | s-nail -s "Incident Report during owl.sh: ${1} on ${_hName} at $(date)" ${_MY_EMAIL}
  fi
}

_incident_detection() {
  # Array of errors to search for
  declare -a _errors=(
    "urn:ietf:params:acme:error:unauthorized"
    "urn:ietf:params:acme:error:badNonce"
    "urn:ietf:params:acme:error:rateLimited"
    "urn:ietf:params:acme:error:dns"
    "urn:acme:error:serverInternal"
    "Remote PerformValidation RPC failed"
    "ModuleNotFoundError"
    "Traceback"
    "Drush command terminated abnormally"
    "ArgumentCountError"
  )

  # Loop through errors and check if any exist in the log file
  for _error in "${_errors[@]}"; do
    if grep -q "${_error}" "${_thisLog}"; then
      _incident_email_report "${_error}"
      break  # Exit the loop after the first detected error
    fi
  done
}

_fix_nginx_forward_secrecy() {
  _dhpWildPath="/etc/ssl/private/nginx-wild-ssl.dhp"
  if [ -e "/etc/ssl/private/4096.dhp" ]; then
    _dhpPath="/etc/ssl/private/4096.dhp"
    _DIFF_T=$(diff -w -B ${_dhpPath} ${_dhpWildPath} 2>&1)
    if [ ! -z "${_DIFF_T}" ]; then
      cp -af ${_dhpPath} ${_dhpWildPath}
    fi
  fi

  if [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    if [ ! -e "/etc/ssl/private/4096.dhp" ]; then
      echo "Generating 4096.dhp -- it may take a very long time..."
      openssl dhparam -out /etc/ssl/private/4096.dhp 4096 > /dev/null 2>&1 &
    fi
    for f in `find /etc/ssl/private/*.crt -type f`; do
      _sslName=$(echo ${f} | cut -d'/' -f5 | awk '{ print $1}' | sed "s/.crt//g")
      _sslFile="/etc/ssl/private/${_sslName}.dhp"
      _sslFileZ=${_sslFile//\//\\\/}
      if [ -e "${f}" ] && [ ! -z "${_sslName}" ]; then
        if [ ! -e "${_sslFile}" ]; then
          openssl dhparam -out ${_sslFile} 2048 &> /dev/null
        else
          _PFS_TEST=$(grep "DH PARAMETERS" ${_sslFile} 2>&1)
          if [[ ! "${_PFS_TEST}" =~ "DH PARAMETERS" ]]; then
            openssl dhparam -out ${_sslFile} 2048 &> /dev/null
          fi
          _sslRootd="/var/aegir/config/server_master/nginx/pre.d"
          _sslFileX="${_sslRootd}/z_${_sslName}_ssl_proxy.conf"
          _sslFileY="${_sslRootd}/${_sslName}_ssl_proxy.conf"
          if [ -e "${_sslFileX}" ]; then
            _DHP_TEST=$(grep "_sslFile" ${_sslFileX} 2>&1)
            if [[ "${_DHP_TEST}" =~ "_sslFile" ]]; then
              sed -i "s/.*_sslFile.*//g" ${_sslFileX} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${_sslFileX} &> /dev/null
              wait
            fi
          fi
          if [ -e "${_sslFileY}" ]; then
            _DHP_TEST=$(grep "_sslFile" ${_sslFileY} 2>&1)
            if [[ "${_DHP_TEST}" =~ "_sslFile" ]]; then
              sed -i "s/.*_sslFile.*//g" ${_sslFileY} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${_sslFileY} &> /dev/null
              wait
            fi
          fi
          if [ -e "${_sslFileX}" ]; then
            _DHP_TEST=$(grep "ssl_dhparam" ${_sslFileX} 2>&1)
            if [[ ! "${_DHP_TEST}" =~ "ssl_dhparam" ]]; then
              sed -i "s/ssl_session_timeout .*/ssl_session_timeout          5m;\n  ssl_dhparam                  ${_sslFileZ};/g" ${_sslFileX} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${_sslFileX} &> /dev/null
              wait
            fi
          fi
          if [ -e "${_sslFileY}" ]; then
            _DHP_TEST=$(grep "ssl_dhparam" ${_sslFileY} 2>&1)
            if [[ ! "${_DHP_TEST}" =~ "ssl_dhparam" ]]; then
              sed -i "s/ssl_session_timeout .*/ssl_session_timeout          5m;\n  ssl_dhparam                  ${_sslFileZ};/g" ${_sslFileY} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${_sslFileY} &> /dev/null
              wait
            fi
          fi
        fi
      fi
    done
    if [ -e "/var/aegir/config" ]; then
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
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
    fi
    ### sed -i rewrites every file it is handed, match or no match, so running
    ### it blind over the vhost tree refreshed the mtime of every vhost on the
    ### system every night. That destroyed the only freshness signal the ghost
    ### vhost reaper has (see _cleanup_ghost_vhosts), and long after the last
    ### TLSv1.1 line was gone it still rewrote thousands of files for nothing.
    ### Rewrite only the files that actually still carry the old directive.
    ### An account's vhost.d is its own: each is read and rewritten only
    ### inside its real directory, never through a link or a FIFO put there.
    if [ -d "/data/u" ]; then
      local _vhD
      for _vhD in /data/disk/*/config/server_*/nginx/vhost.d; do
        [ -d "${_vhD}" ] || continue
        _acct_in_real_dir "${_vhD}" _vhost_tls11_drop_here
      done
    fi
    if [ -e "/var/aegir/config" ]; then
      grep -Zl "TLSv1.1 TLSv1.2 TLSv1.3;" /var/aegir/config/server_*/nginx.conf 2>/dev/null \
        | xargs -0 -r sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
      grep -Zl "TLSv1.1 TLSv1.2 TLSv1.3;" /var/aegir/config/server_*/nginx/vhost.d/* 2>/dev/null \
        | xargs -0 -r sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
      grep -Zl "TLSv1.1 TLSv1.2 TLSv1.3;" /var/aegir/config/server_*/nginx/pre.d/*.conf 2>/dev/null \
        | xargs -0 -r sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
    fi
    service nginx reload
  fi
}

# The credential backups (.<name>.pass.{txt,php}-pre-*) in the current
# (pinned) account home: each made 0600 through a handle that never follows
# a link, only while it has a single link (a hard link the account names to
# match is left alone), then only the newest 3 per credential file kept, the
# older ones removed by name here. The globs expand in this directory only.
_pass_backups_heal_here() (
  local _live _old
  local -a _baks
  shopt -s nullglob
  perl -e "${_NIGHT_FCHMOD_PL}" f 0600 \
    ./.*.pass.txt-pre-* ./.*.pass.php-pre-* &> /dev/null
  for _live in ./.*.pass.txt ./.*.pass.php; do
    [ -e "${_live}" ] || continue
    _baks=( "${_live}"-pre-* )
    [ "${#_baks[@]}" -gt 3 ] || continue
    ls -t -- "${_baks[@]}" 2> /dev/null | tail -n +4 \
      | while IFS= read -r _old; do
          rm -f -- "${_old}"
        done
  done
)
# The cron and busy markers in the current (pinned) .tmp; the globs expand
# in this directory only.
_run_marks_drop_here() {
  rm -f -- ./.cron.*.pid ./.busy.*.pid
}

# An owner set through the entry's own handle: each name is opened without
# following a link and without blocking on a FIFO, and a directory, or a
# regular file with a single link, is changed through the open handle; a
# hard-linked file, a link, a FIFO or a socket is left alone. Args: uid, gid
# (numbers; -1 keeps that id), the names.
_ACCT_REOWN_PL='use Fcntl; my ($u, $g, @f) = @ARGV; for my $f (@f) { sysopen(my $h, $f, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or next; my @s = stat($h); chown($u, $g, $h) if @s && (-d _ || (-f _ && $s[3] == 1)); close($h); } exit 0'
# The trees after $1 and $2 handed to uid $1 and gid $2 (numbers) as chown
# -R handed them: find follows no link, at the top or below, and each entry
# is changed from inside the directory walked (_ACCT_REOWN_PL). The shared
# code store's sites/all/{modules,libraries,themes} are group-writable by
# every account's identities, so a hard link one of them puts there to a file
# of another account is left alone, never handed to root.
_global_reown() {
  local _u="${1}" _g="${2}"
  shift 2
  [[ "${_u}" =~ ^[0-9]+$ && "${_g}" =~ ^[0-9]+$ ]] || return 0
  env PATH=/usr/local/bin:/usr/bin:/bin find "$@" \
    -execdir perl -e "${_ACCT_REOWN_PL}" "${_u}" "${_g}" {} + &> /dev/null
  return 0
}

_global_cleanup() {
  if [ "${_PERMISSIONS_FIX}" = "YES" ] \
    && [ ! -z "${_X_VERSION}" ] \
    && [ -e "/opt/tmp/barracuda-release.txt" ] \
    && [ ! -e "/var/backups/permissions-fix-${_xSrl}-${_X_VERSION}-fixed-dz.info" ]; then
    echo "INFO: Fixing permissions in the /data/all tree..."
    ### /data/conf is root's: every site loads its global includes from it.
    ### chown -R first, which follows no link and takes a file an account
    ### hard-linked there back to root, then the modes through each entry's
    ### own handle, never through a name swapped for a link.
    _acct_in_real_dir /data/conf chown -R root:root . &> /dev/null
    _acct_in_real_dir /data/conf _global_conf_modes_here &> /dev/null
    ### sites/all/{modules,libraries,themes} stay 02775 group 'users', and
    ### every account's identities carry 'users' (primary on an unconverted
    ### instance, supplementary once it has its per-instance group), so this
    ### stays the one box-wide group-writable code path by design. Anything
    ### under them can be renamed between find's
    ### stat and the chmod it execs, and chmod follows a symlink named on its
    ### command line: that race is a root chmod on an arbitrary path. Prune
    ### those leaves; their own modes are asserted right below, where the
    ### parent (sites/all, 0755 root:users) is not tenant-writable. The
    ### owner walks do reach those leaves, so each entry is changed through
    ### its own handle and a hard-linked file never (_global_reown).
    local _usersGid
    _usersGid=$(getent group users 2> /dev/null | cut -d: -f3)
    if [ -e "/data/all" ]; then
      find /data/all -path '*/sites/all/*' -prune -o -type d -exec chmod 0755 {} \; &> /dev/null
      find /data/all -path '*/sites/all/*' -prune -o -type f -exec chmod 0644 {} \; &> /dev/null
      chmod 02775 /data/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
      chmod 02775 /data/all/000/core/*/sites/all/{modules,libraries,themes} &> /dev/null
      _global_reown 0 0 /data/all
      _global_reown 0 "${_usersGid}" /data/all/*/*/sites
      _global_reown 0 "${_usersGid}" /data/all/000/core/*/sites
    elif [ -e "/data/disk/all" ]; then
      find /data/disk/all -path '*/sites/all/*' -prune -o -type d -exec chmod 0755 {} \; &> /dev/null
      find /data/disk/all -path '*/sites/all/*' -prune -o -type f -exec chmod 0644 {} \; &> /dev/null
      chmod 02775 /data/disk/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
      chmod 02775 /data/disk/all/000/core/*/sites/all/{modules,libraries,themes} &> /dev/null
      _global_reown 0 0 /data/disk/all
      _global_reown 0 "${_usersGid}" /data/disk/all/*/*/sites
      _global_reown 0 "${_usersGid}" /data/disk/all/000/core/*/sites
    fi
    ### distro/NNN and every platform in it belong to the account, so any of
    ### these three names can be a link. Only a real directory is changed,
    ### as '.' once inside it, so no name on the way is followed through a
    ### link.
    local _pDis
    for _pDis in /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes}; do
      [ -d "${_pDis}" ] || continue
      _acct_in_real_dir "${_pDis}" chmod 02775 . &> /dev/null
    done
    ### Stamp in /var/backups: the gate above reads it there, and /data/all
    ### does not exist on /data/disk/all boxes (the sweep re-ran every night).
    echo fixed > /var/backups/permissions-fix-${_xSrl}-${_X_VERSION}-fixed-dz.info
  fi
  if [ ! -e "/var/backups/fix-sites-all-permsissions-${_xSrl}.txt" ]; then
    ### distro/NNN belongs to the account (every Ægir task and site-local
    ### Drush run as it), so sites/ and the names below it can be links, and
    ### a plain chmod follows a link named on its command line. Only a real
    ### directory is changed, as '.' once inside it, so no name on the way is
    ### followed through a link. None of these names is legitimately a link.
    local _pSit _pSub
    for _pSit in /data/disk/*/distro/*/*/sites; do
      [ -d "${_pSit}" ] || continue
      _acct_in_real_dir "${_pSit}" chmod 0751 . &> /dev/null || continue
      _acct_in_real_dir "${_pSit}/all" chmod 0755 . &> /dev/null || continue
      for _pSub in modules libraries themes; do
        _acct_in_real_dir "${_pSit}/all/${_pSub}" chmod 02775 . &> /dev/null
      done
    done
    echo FIXED > /var/backups/fix-sites-all-permsissions-${_xSrl}.txt
    echo "Permissions in sites/all tree just fixed"
  fi
  find /var/backups/old-sql* -mtime +1 -exec rm -rf {} \; &> /dev/null
  find /var/backups/ltd/*/* -mtime +0 -type f -exec rm -f {} \; &> /dev/null
  find /var/backups/solr/*/* -mtime +0 -type f -exec rm -f {} \; &> /dev/null
  find /var/backups/solr-archive -mindepth 1 -maxdepth 1 -type f -mtime +30 -exec rm -f {} \; &> /dev/null
  find /var/backups/jetty* -mtime +0 -exec rm -rf {} \; &> /dev/null
  find /var/backups/dragon/* -maxdepth 0 ! -name config -mtime +7 -exec rm -rf {} \; &> /dev/null
  # dragon/config is a low-volume, high-value config archive -- never auto-purged.
  ### Account password backups written by the rotation-on-update path: heal any
  ### copy left world-readable by older code (the account home allows traversal,
  ### so a lax mode is readable by local users by exact path), then keep only
  ### the newest 3 per credential file -- only the newest can hold a
  ### half-failed-rotation recovery value; older ones are dead history that
  ### only assists password guessing.
  ### The account home is 0711 but owned by oN, the identity every Ægir task
  ### and site-local Drush run as, so a backup name there can be a link, and
  ### chmod follows a link. Only real files are healed, from inside the real
  ### account home, through a handle that never follows a link, and pruned
  ### there by name.
  local _pBak _aHome
  for _aHome in /data/disk/*; do
    [ -d "${_aHome}" ] || continue
    _acct_in_real_dir "${_aHome}" _pass_backups_heal_here
  done
  for _pBak in /var/aegir/backups/system/.*.pass.txt-pre-*; do
    [ -f "${_pBak}" ] && [ ! -L "${_pBak}" ] \
      && chmod 0600 "${_pBak}" &> /dev/null
  done
  for _P_LIVE in /var/aegir/backups/system/.*.pass.txt; do
    [ -e "${_P_LIVE}" ] || continue
    ls -t ${_P_LIVE}-pre-* 2>/dev/null | tail -n +4 | xargs -r rm -f
  done
  if [ "${_hostedSys}" = "YES" ]; then
    if [ -d "/var/backups/codebases-cleanup" ]; then
      find /var/backups/codebases-cleanup/* -mtime +7 -exec rm -rf {} \; &> /dev/null
    elif [ -d "/data/disk/codebases-cleanup" ]; then
      find /data/disk/codebases-cleanup/* -mtime +7 -exec rm -rf {} \; &> /dev/null
    fi
  fi
  rm -f /tmp/.cron.*.pid
  rm -f /tmp/.busy.*.pid
  ### An account's .tmp is its own: its markers go only from inside the real
  ### directory, never from wherever a link put there points.
  local _aTmp
  for _aTmp in /data/disk/*/.tmp; do
    [ -d "${_aTmp}" ] || continue
    _acct_in_real_dir "${_aTmp}" _run_marks_drop_here
  done

  ###
  ### Delete duplicity ghost pid file if older than 2 days
  ###
  find /run/*_backup.pid /run/*backboa.pid -mtime +1 -exec rm -f {} \; &> /dev/null
}

# Prune the SHARED master /var/aegir backup trees once per run. Hoisted out of the
# per-account _purge_cruft_machine (it touched these shared paths inside per-account
# work) so parallel account workers never race on them; run once by the orchestrator
# after the account loop. Mirrors _purge_cruft_machine's _PURGE_TMP/_PURGE_BACKUPS
# derivation (reads _DEL_OLD_TMP/_DEL_OLD_BACKUPS from .barracuda.cnf + _hostedSys).
_purge_shared_aegir_backups() {
  if [ ! -z "${_DEL_OLD_TMP}" ] && [ "${_DEL_OLD_TMP}" -gt 0 ]; then
    _PURGE_TMP="${_DEL_OLD_TMP}"
  else
    _PURGE_TMP="0"
  fi
  if [ ! -z "${_DEL_OLD_BACKUPS}" ] && [ "${_DEL_OLD_BACKUPS}" -gt 0 ]; then
    _PURGE_BACKUPS="${_DEL_OLD_BACKUPS}"
  else
    _PURGE_BACKUPS="14"
    if [ "${_hostedSys}" = "YES" ]; then
      _PURGE_BACKUPS="7"
    fi
  fi
  find /var/aegir/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null
}

# Archive past-month night logs into MM-YYYY subdirectories so /var/log/boa/daily
# does not grow unbounded -- WITHOUT deleting anything, since the logs may be
# needed later for incident analysis. Idempotent: only top-level *.log files
# whose month (by mtime) differs from the current month are moved, so the current
# run's daily-*.log and acct-*.log stay in place and already-archived files inside
# the MM-YYYY subdirs are never re-scanned (-maxdepth 1). Safe to run every night.
_archive_old_daily_logs() {
  _logDir="/var/log/boa/daily"
  [ -d "${_logDir}" ] || return 0
  _curMY=$(date +%m-%Y)
  for _f in `find "${_logDir}" -maxdepth 1 -type f -name '*.log' 2>/dev/null`; do
    _logMY=$(date -r "${_f}" +%m-%Y 2>/dev/null)
    [ -z "${_logMY}" ] && continue
    [ "${_logMY}" = "${_curMY}" ] && continue
    mkdir -p "${_logDir}/${_logMY}"
    mv -f "${_f}" "${_logDir}/${_logMY}/" 2>/dev/null
  done
}

# Hand the migration-source sweep back to the module's own daily hosting queue
# on every hosted instance that carries it. The nightly pass below switches that
# queue off per instance because the paused nightly run is the only executor on
# a BOA box -- so when the nightly executor is itself switched off, the queue has
# to be switched back on, or nothing revokes migration-source grants here again.
# Enabling is all this does: what the queue then runs is the module's own
# documented daily cadence, the one plain Aegir installs use.
_migrate_source_queue_fallback_on() {
  local _armPth _armUsr _armHas
  for _armPth in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    if [ -e "${_armPth}/config/server_master/nginx/vhost.d" ] \
      && [ ! -e "${_armPth}/log/proxied.pid" ] \
      && [ ! -e "${_armPth}/log/CANCELLED" ]; then
      _armUsr=$(echo "${_armPth}" | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
      _armHas=$(su -s /bin/bash - "${_armUsr}" -c "drush8 @hostmaster php-eval \"echo (int) module_exists('hosting_migrate_source');\"" 2>/dev/null | tr -dc '0-9')
      if [ "${_armHas}" = "1" ]; then
        echo "migrate-sweep: ${_armUsr} daily fallback queue re-armed"
        su -s /bin/bash - "${_armUsr}" -c "drush8 @hostmaster vset hosting_queue_migrate_source_enabled 1" &> /dev/null
      fi
    fi
  done
}

_migrate_source_sweep_all() {
  # Nightly migration-source sweep for every hosted instance, executed inside
  # a box-wide task-queue pause (/run/boa_queue_stop.pid -- the same marker
  # the backups relocation and updatesymlinks hold, honoured by runner.sh
  # before it dispatches any instance queue) so no verify can revoke the same
  # grant concurrently with a sweep pass. The sweep's own frontend hosting
  # queue stays registered as a daily fallback for plain Aegir; on BOA boxes
  # it is switched off per instance every night below, making this paused run
  # the only scheduled executor here -- so switching this run off switches the
  # fallback back on (_migrate_source_queue_fallback_on), never leaving the box
  # with no executor at all. A leaked marker self-heals: clear.sh removes one
  # whose recorded owner PID is gone.
  local _stop="/run/boa_queue_stop.pid" _madeStop=NO _drain=0
  local _swpPth _swpUsr _swpHas _lockfd _armOwned=NO
  local _armed="/var/log/boa/migrate-sweep-fallback-on.info"
  local _armSeed="/var/log/boa/.migrate-sweep-ownership-seeded.info"
  # One-time transition to the ownership stamp above. The previous serial gave
  # the same file the opposite meaning and REMOVED it on every real pass, so a
  # box that was already sweeping nightly carries none -- and the kill-switch
  # branch below would then leave it with the daily queue off and no executor
  # at all, the one state this function must never produce. Seed the stamp
  # once per box, and only where the nightly logs prove a real pass ran here,
  # so an operator's own panel-off on a box that never swept is untouched.
  # This can only ever ADD the stamp; the seed marker makes it once, so a
  # genuine re-arm's consumption of the stamp is never undone.
  if [ ! -e "${_armSeed}" ]; then
    if [ ! -e "${_armed}" ] \
      && grep -qsE 'migrate-sweep: [^ ]+ pass$' /var/log/boa/daily/*.log \
        /var/log/boa/daily/*/*.log; then
      touch "${_armed}" 2>/dev/null
    fi
    touch "${_armSeed}" 2>/dev/null
  fi
  if [ -e "/data/conf/disable_migrate_sweep_night.cnf" ]; then
    # The night run is off. Undo ONLY a queue-off this runner wrote: the stamp
    # is set by a real pass when it switches the daily queue off, so a box
    # whose queue was never disabled by us -- an operator's own panel setting,
    # a box that never swept -- is left exactly as found, and the re-arm fires
    # once, on the genuine transition (nights ran, then the kill-switch
    # appeared). Consuming the stamp is what makes it once.
    if [ -e "${_armed}" ]; then
      echo "migrate-sweep: nightly run disabled; handing the sweep back to the daily queue"
      _migrate_source_queue_fallback_on
      rm -f "${_armed}" 2>/dev/null
    fi
    return 0
  fi
  if ! command -v _provision_running > /dev/null 2>&1; then
    # Delivery-skew stub, deliberately broad -- over-matching only lengthens
    # the wait, never shortens it.
    _provision_running() { pgrep -f provision > /dev/null 2>&1; }
  fi
  exec {_lockfd}>/run/.boa_migrate_sweep.flock 2>/dev/null || return 0
  if ! flock -n "${_lockfd}"; then
    # Another nightly pass is sweeping right now -- say so, so a night with no
    # sweep output is never silent.
    echo "migrate-sweep: another pass holds the sweep lock; skipping this night"
    exec {_lockfd}>&-
    return 0
  fi
  # Created only when absent, so a pause another operation took meanwhile
  # is never overwritten.
  if ( set -C; echo "$$" > "${_stop}" ) 2> /dev/null; then
    _madeStop=YES
  fi
  if [ "${_madeStop}" != "YES" ]; then
    # Another operation already holds the pause; its window is not ours to
    # piggyback on or to extend.
    echo "migrate-sweep: queue pause held elsewhere; skipping this night"
    flock -u "${_lockfd}"
    exec {_lockfd}>&-
    return 0
  fi
  # A runner.sh pass that cleared the gate before the marker landed can still
  # fork a task within its minute; the grace outlives that window, then the
  # drain waits out anything already running.
  sleep 90
  while _provision_running && [ "${_drain}" -lt 30 ]; do
    sleep 5
    _drain=$((_drain + 1))
  done
  if _provision_running; then
    echo "migrate-sweep: provision task still active after grace and drain; skipping this night"
  else
    for _swpPth in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
      if [ -e "${_swpPth}/config/server_master/nginx/vhost.d" ] \
        && [ ! -e "${_swpPth}/log/proxied.pid" ] \
        && [ ! -e "${_swpPth}/log/CANCELLED" ]; then
        _swpUsr=$(echo ${_swpPth} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        _swpHas=$(su -s /bin/bash - ${_swpUsr} -c "drush8 @hostmaster php-eval \"echo (int) module_exists('hosting_migrate_source');\"" 2>/dev/null | tr -dc '0-9')
        if [ "${_swpHas}" = "1" ]; then
          # This paused nightly run is the executor on BOA boxes; keep the
          # frontend daily queue off so an unpaused pass never runs. The stamp
          # written after this loop records that THIS runner owns the
          # queue-off -- the only state the kill-switch branch above undoes.
          su -s /bin/bash - ${_swpUsr} -c "drush8 @hostmaster vset hosting_queue_migrate_source_enabled 0" &> /dev/null
          _armOwned=YES
          echo "migrate-sweep: ${_swpUsr} pass"
          timeout 300 su -s /bin/bash - ${_swpUsr} -c "drush8 @hostmaster hosting-migrate-source-sweep" 2>&1
        fi
      fi
    done
    [ "${_armOwned}" = "YES" ] && touch "${_armed}" 2>/dev/null
    wait
  fi
  if [ "${_madeStop}" = "YES" ] \
    && [ "$(tr -dc '0-9' < "${_stop}" 2>/dev/null)" = "$$" ]; then
    rm -f "${_stop}"
  fi
  flock -u "${_lockfd}"
  exec {_lockfd}>&-
}
