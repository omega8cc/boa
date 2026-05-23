# Findings: Bash Variable Handling and Injection

Covers unquoted expansions in exec contexts, eval/source with external input,
== vs -eq numeric comparisons, missing strict-mode coverage, and array vs
scalar issues.

Findings are appended below as they are discovered. Each entry follows the schema
defined in CLAUDE.md. Most-recent findings appear at the bottom.

---

## Audit scope coverage

- Every `eval`, `source`, `bash -c`, `dash -c`, `sh -c`, `su -c` invocation
  in BOA scripts.
- All numeric comparisons using `==` / `-eq` to check operator confusion.
- Strict-mode (`set -euo pipefail`) coverage and the BOA convention against it.
- Variables sourced from per-tenant file paths reaching exec.

Per global CLAUDE.md ("Error handling: check exit codes explicitly; do not
rely on `set -e` alone."), the absence of `set -euo pipefail` in BOA scripts
is intentional and not flagged. Every grep-hit had it commented out.

---

## [HIGH] mybackup queued-command file is `.ftp`-writable and shell-interpolated by the root cron
**File:** aegir/tools/bin/mybackup  (lines 393–407 root cron; 439–457 .ftp queue side)
**Category:** variable-handling (also chains into shell-injection and privilege-escalation)
**Status:** PATCHED in follow-up commit

### Description
`mybackup` exposes a CLI to `<user>.ftp` lshell-restricted accounts that
queues backup-restore commands into a per-tenant file. A root-context cron
later picks the file up and runs the queued command via `su` as the
per-tenant system user `<user>` (e.g. `o1`).

The queue file lives at
`/data/disk/<user>/static/control/.run/command.txt`, inside the directory
tree that `manage_ltd_users.sh:2036` chowns recursively to
`<user>.ftp:<usrGroup>`. The `.ftp` operator can therefore write the file
**directly**, bypassing the `_validate_restore_command` gate that
`mybackup` applies when invoked normally (line 445). lshell-allowed
commands (`cat`, `tee` via `mybackup`-flavoured redirection, `rsync`, …)
all provide ways to drop arbitrary bytes into the file.

When the root cron processes the queue, the content is read and
interpolated **unquoted** into the `su -c` shell:

```bash
# mybackup:399
export _command=$(cat "${_user_cmd_file}")
# mybackup:407
su -s /bin/bash - ${_user} -c "mybackup ${_command}"
```

There is no re-validation between read and exec. A queue file containing
e.g. `restore aws "; bash -i; #" 1D` results in the shell parsing the
semicolons inside the `su -c` argument, yielding three commands:
`mybackup restore aws`, then `bash -i`, then `# 1D` (comment). The
`bash -i` runs as the per-tenant system user `${_user}` — **fully
escaping the lshell confinement**.

This violates the boundary Adam articulated in category 1: end users have
access only to limited shell accounts, and "never have access to Aegir
system (bash) user, never have access to Aegir code". The system user
`<user>` is precisely "the Aegir system (bash) user" for that tenant.
Escape from `<user>.ftp` (lshell) → `<user>` (full bash) lets the operator
read/write the Drupal codebase directly (bypassing lshell's drush
restriction list), run arbitrary PHP, modify settings.php, and so on
within the tenant's blast radius.

The escape does **not** reach root. The system user is per-tenant; the
attacker stays within their own octopus instance. But within that
instance they gain everything the BOA model intended to deny operators.

### Evidence
```bash
# mybackup:393–410 (root cron, processes queued commands)
for _user_dir in "${_BASE_DIR}"/*; do
  if [[ -d "${_user_dir}" ]]; then
    export _user=$(basename "${_user_dir}")
    export _user_run_dir="${_user_dir}/${_RUN_SUBDIR}"
    export _user_cmd_file="${_user_run_dir}/${_CMD_FILE}"
    if [[ -f "${_user_cmd_file}" ]]; then
      export _command=$(cat "${_user_cmd_file}")
      echo "Executing backup restore for user ${_user}."
      ...
      su -s /bin/bash - ${_user} -c "mybackup ${_command}"
      ...
      rm -f "${_user_cmd_file}"
      ...

# mybackup:445–453 (.ftp side, validates and queues)
if ! _validate_restore_command "$@"; then
  echo "Error: Invalid command. The command has not been queued."
  ...
  exit 1
fi
echo "$@" > "${_user_run_dir}/${_CMD_FILE}"

# manage_ltd_users.sh:2036 — why .ftp can overwrite the queue file
chown -R ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control
```

### Fix
Two-layer defence that does not require redesigning the queue file format:

1. **Re-validate after read.** Before calling `su -c`, parse the queued
   line into an array and re-apply `_validate_restore_command` to the
   parsed args. Reject the queue file (log + remove + continue) on
   validation failure.

2. **Pass as positional args, not shell-interpolated string.** Replace
   `su -s /bin/bash - ${_user} -c "mybackup ${_command}"` with the
   form that takes positional arguments after `--`:

   ```bash
   read -ra _queued_args <<< "${_command}"
   if ! _validate_restore_command "${_queued_args[@]}"; then
     echo "[$(date)] Invalid queued command for ${_user}: ${_command}" \
       >> /var/log/mybackup_invalid_queued.log
     rm -f "${_user_cmd_file}"
     continue
   fi
   su -s /bin/bash - "${_user}" -c 'exec mybackup "$@"' -- "${_queued_args[@]}"
   ```

   The `-c 'exec mybackup "$@"' -- "${_queued_args[@]}"` form passes each
   queued argument as a separate `$1`/`$2`/`$3`/`$4` to the inner shell;
   no shell metacharacters in any argument are interpreted as syntax.

Adam confirmed on 2026-05-23: go max-robust with mapfile (one arg per
line) and explicitly forbid whitespace in `_restore_path`. The landed
patch implements that:

- **Producer (`.ftp` side, line 501):** `echo "$@" > ...` replaced with
  `printf '%s\n' "$@" > ...`. Each validated argument lands on its own
  line — no whitespace ambiguity round-tripping through the queue file.
- **Validator (line 365-385):** `_restore_path` rejected if it contains
  any whitespace, or any of `; & | \` $ < > ( ) { } " ' \\`. BOA's
  tenant directory layout has no whitespace in real paths, so this
  blocks injection without blocking legitimate restores.
- **Consumer (root cron, lines 401-425):** `cat "${_user_cmd_file}"`
  replaced with `mapfile -t _queued_args < "${_user_cmd_file}"`. The
  validator is re-applied after read; failures log to
  `/var/log/mybackup_invalid_queued.log` and remove the queue file.
  Exec is now `su -s /bin/bash - "${_user}" -c 'exec mybackup "$@"'
  -- "${_queued_args[@]}"` — each arg arrives at the inner mybackup as
  a separate positional, with no shell metacharacter in any field
  interpreted as syntax.
- **System-user execution path (line 522-526):** also re-validates
  before `_restore` runs. Defence in depth — `_restore` then evals
  `_restore_command` (line 255) with operands that are guaranteed free
  of shell metacharacters.

Old space-joined queue files left over from before this change parse
as a single `args[0]` that fails the `"${_action}" != "restore"` check
and are removed.

### Patch commit
PATCHED in follow-up commit.

---

## [LOW] eval-based fd-redirect in lock.inc could use modern auto-fd assignment
**File:** aegir/tools/bin/lock.inc  (lines 26, 50)
**Category:** variable-handling
**Status:** PATCHED in this commit

### Description
The shared `_single_instance_lock` / `_single_instance_unlock` helpers
use `eval` to redirect to a dynamic file descriptor:

```bash
# line 50 (acquire)
eval "exec ${_LOCK_FD}>\"${_LOCK_PATH}\""
# line 26 (release)
eval "exec ${_FD}>&-"
```

This was the only portable way to use a variable as an FD before
bash 4.1. Modern bash supports `{var}` auto-assignment that captures
the next free FD into a variable without needing `eval`:

```bash
exec {_LOCK_FD}>"${_LOCK_PATH}"
```

Neither input is attacker-controlled today (`_LOCK_FD` is an integer set
internally; `_LOCK_PATH` is built from `basename "$0"` or from a caller
that is itself a root-context BOA script). The eval form is therefore
not a live vulnerability — it is brittle to future change. If a caller
ever began passing a `_LOCK_PATH` derived from a per-tenant string, the
eval would interpret embedded metacharacters as shell syntax.

CLAUDE.md (global) puts BOA at bash >= 4.2 (modern Debian/Devuan), so
the auto-fd form is available everywhere this library runs.

### Evidence
```bash
# acquire
eval "exec ${_LOCK_FD}>\"${_LOCK_PATH}\""
# release
eval "exec ${_FD}>&-"
```

### Fix
Replace both `eval "exec ${FD}>..."` constructs with the auto-assigning
`exec {FD}>...` form. The caller no longer specifies the FD number —
bash picks the next free FD and assigns it into the named variable.

### Patch commit
PATCHED — see commit message below.

---

## [INFO] duplicity_backup.sh `eval` lines for variable-by-name assignment are safe
**File:** aegir/tools/backup/run/duplicity_backup.sh  (lines 440, 447, 454, 876)
**Category:** variable-handling
**Status:** INFO — verified safe

### Description
Four `eval` invocations in `duplicity_backup.sh`:

- Lines 440, 447, 454 inside `_validate_or_default_duration`:
  `eval "${_var_name}='${_default}'"`. `_var_name` is one of the two
  string literals `KEEP_WITHIN` or `FULL_BACKUP_FREQUENCY` passed from
  the only call sites (lines 559, 562). `_default` is from an internal
  `_DEFAULT_*` constant. Neither is attacker-influenced. Safe in the
  current shape; could be replaced with `declare -g "${_var_name}"="..."`
  for clarity in the boa-modernisation pass.

- Line 876: `eval "${_restore_command}"`. The restore command is built
  from `_DCY_UTL_CMD` (config), `_BACKUP_TARGET` (config), `_restore_time`
  (validated by mybackup's `_validate_restore_command` to match
  `^[0-9]+[DWMY]$`), `_restore_path` (validated for no leading `/` only),
  and `_final_restore_target`. **This eval shares the
  mybackup-queue-injection threat** documented in finding #1 above: a
  queue file containing shell metacharacters reaches `_restore_path`
  unfiltered and then this eval. The fix for #1 (re-validate + pass as
  positional args via su) closes this eval's exposure too.

Both the immediate `su -c` injection (mybackup:407) and this downstream
`eval` are eliminated by the proposed re-validation in #1.

### Fix
None standalone. Resolved as a side effect of fixing #1.

### Patch commit
N/A.

---

## [INFO] `dash -c "${_R_M}"` in websh.sh.txt is the deliberate lshell-bypass for ltd-shell-more group
**File:** aegir/helpers/websh.sh.txt  (lines 12, 1025, 1034, 1043, 1050)
**Category:** variable-handling
**Status:** INFO — verified expected

### Description
`websh` is the BOA shell wrapper that replaces `/bin/sh` for lshell-
session subprocess dispatch. It performs heavy regex-driven routing on
`${_ARGS}` (the `sh -c "$2"` command from lshell) and then forwards to
the appropriate handler — drush via the right PHP version, composer via
PHP, or direct dash for `ltd-shell-more` group members.

The `exec /bin/dash -c "${_R_M}"` calls run the lshell-approved command
without the `sudo_noexec.so` LD_PRELOAD wrapper. This is **deliberate**
for the `ltd-shell-more` group (line 8 `[[ "${_LTD_GID}" =~
"ltd-shell-more"($) ]]`) — those operators need to run sub-processes
that the default noexec would block.

The threat model relies on lshell already filtering the command before
it reaches websh. Per Adam's category-1 confirmation, lshell is treated
as "same-UID confinement", and `ltd-shell-more` is a more-privileged
operator group with full Node/composer/etc. tooling. websh does not
ADD an exploit surface — it just routes lshell-approved commands.

### Fix
None. websh is part of the trusted security layer rather than a
vulnerability.

### Patch commit
N/A.

---

## [INFO] `su -c "..."` callers across daily.sh / satellite.sh.inc interpolate `${_HM_U}` / `${_Dom}` unquoted
**File:** aegir/tools/system/daily.sh:227,229,239,248,258,260,2230,2234,2354; lib/functions/satellite.sh.inc:2685,2738,2742,2745
**Category:** variable-handling
**Status:** INFO — bounded by upstream validation

### Description
Most `su -c "..."` lines in daily.sh and satellite.sh.inc interpolate
`${_HM_U}` (the system user, basename of `/data/disk/o*`), `${_Dom}`
(site domain extracted from the per-site loop), `$1` (function arg from
internal callers), `${_exeLe}` (path to dehydrated), and `${_leParams}`
(LE parameter string). None of these flow from end-user input.

- `_HM_U` = `basename ${_usEr}` where `_usEr = /data/disk/<oct>` — all
  characters are alphanumeric/underscore by the time it reaches `su -c`.
  `useradd` in BOA enforces this naming.
- `_Dom` = field 9 of the vhost.d file path, sliced and de-`www`d. The
  vhost.d filename is the domain, written by Aegir/Provision. Compromised
  aegir context could write a malformed filename, but that already
  represents a serious incident.
- `$1` to the `_run_drush8_*` helpers comes from internal callers
  (string literals like `"vset hosting_queue_tasks_items 3"`).
- `_exeLe` is the dehydrated binary path, set internally.
- `_leParams` / `_dhArgs` are LE parameters set per-environment.

Verified safe in the current shape; recorded here because they would
become a vulnerability if any of these variables ever started flowing
from a per-tenant or HTTP-derived source.

### Fix
None standalone. If the boa-modernisation pass touches these helpers,
adopt `su -c '... "$1" ...' -- "${arg}"` positional-arg form for
defence-in-depth.

### Patch commit
N/A.

---

## [INFO] BOA convention: no `set -euo pipefail`
**File:** all `.sh*` / `.inc` files
**Category:** variable-handling
**Status:** INFO — by design

### Description
Grep across the codebase shows `set -euo pipefail` is commented out
everywhere it appears (e.g. scan_nginx.sh:41, create_cron_entries.sh:59,
cf-simple-hook.sh:4, fix-fstab-to-uuid.sh:4, le-hook.sh:5). Global
CLAUDE.md explicitly states: "Error handling: check exit codes
explicitly; do not rely on `set -e` alone."

This is a deliberate BOA coding style. The codebase instead uses
defensive `[ -e ... ]` / `[[ -n ... ]]` / explicit exit-code checks.
Not flagged.

### Fix
N/A.

### Patch commit
N/A.
