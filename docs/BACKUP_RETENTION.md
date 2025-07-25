
# Backup Retention Policy and Default Settings

The backup system is designed to reliably manage **live backups** while optimizing storage usage. This document explains the retention policies and settings, focusing entirely on managing **active backups** without disruptions.

- New PRO Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_ROOT.md)
- New PRO Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_USER.md)
- New PRO Backups Retention Policy Configuration (this document) [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_RETENTION.md)
- New PRO Backups Supported Regions and Bucket Creation Guidelines [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_REGIONS.md)

---

#### Retention Policies Overview

The retention system for live backups relies entirely on **time-based retention** to manage backup cleanup. This approach ensures that older backups are safely removed without disrupting the integrity of active incremental chains.

1. **Time-Based Retention (`KEEP_WITHIN`)**:
   - Specifies how long backups are retained.
   - Deletes all backups (full and incremental) older than the specified timeframe.
   - **Example**: `KEEP_WITHIN="3M"` retains all backups created within the last 3 months and deletes older ones.
   - Only values specified in M (months) or Y (years) are accepted; otherwise will automatically default to 3M.

2. **Full Backup Frequency (`FULL_BACKUP_FREQUENCY`)**:
   - Defines how often a new full backup is created.
   - Incremental backups are created between full backups to save storage and backup time.
   - **Example**: `FULL_BACKUP_FREQUENCY="28D"` creates a new full backup every 28 days.
   - Only values specified in D (days) are accepted.
   - The value must be between 7D and 60D; otherwise will automatically default to 28D.

---

#### Default Retention Settings

The system is preconfigured with these default settings:

```bash
export KEEP_WITHIN="3M"             # Retain backups from the last 3 months
export FULL_BACKUP_FREQUENCY="28D"  # Create a full backup every 28 days
```

These settings ensure:

1. **Live backups are retained for 3 months**:
   - This timeframe is sufficient for most recovery scenarios.
   - All backups older than 3 months are automatically removed.

2. **A full backup every 28 days**:
   - Full backups ensure the integrity of the backup chain.
   - Incremental backups store changes between full backups, reducing storage usage.

---

#### How Cleanup Works

1. **Time-Based Cleanup Only**:
   - The system runs the following command to remove backups older than the specified timeframe:
     ```bash
     duplicity remove-older-than "${KEEP_WITHIN}" --force "${_BACKUP_TARGET}"
     ```
   - This deletes all backups (full and incremental) older than `KEEP_WITHIN`.

2. **Incremental Chains Remain Intact**:
   - The system retains all incremental backups linked to full backups within the `KEEP_WITHIN` period.
   - This ensures backup chains remain valid for restoration.

3. **No Use of `remove-all-but-n-full`**:
   - The `remove-all-but-n-full` command is not used in this system, as it is unsuitable for live backups. It deletes full backups and their associated incremental chains, which can disrupt active backup sets.

---

#### Example Workflow

**Scenario**:
- Current Date: November 22
- Full Backups: August 1, August 15, September 1, September 15, October 1, October 15, November 1, November 15
- Incremental backups created every 6 hours between full backups.

**Settings**:
```bash
KEEP_WITHIN="3M"
FULL_BACKUP_FREQUENCY="7D"
```

**Retention Behavior**:
1. **Time-Based Cleanup**:
   - Deletes backups older than August 22.
   - Retains full and incremental backups from August 22 onward.

2. **Remaining Backups**:
   - Retained full backups: September 1, September 15, October 1, October 15, November 1, November 15.
   - Retained incremental backups: All backups between these full backups.

---

#### Modifying Retention Settings

If needed, you can adjust the retention settings to better fit your needs.

**Examples**:

1. **Extend Retention Period**:
   - To retain backups for 6 months:
     ```bash
     export KEEP_WITHIN="6M"
     ```

2. **Create Full Backups Weekly**:
   - To create a new full backup every 7 days:
     ```bash
     export FULL_BACKUP_FREQUENCY="7D"
     ```

3. **Shorten Retention Period**:
   - To retain backups for only 1 month:
     ```bash
     export KEEP_WITHIN="1M"
     ```

---

#### Important Considerations for Live Backups

1. **Retention Period (`KEEP_WITHIN`)**:
   - All backups older than the specified timeframe are deleted.
   - Ensure the retention period is long enough to meet your recovery needs.

2. **Full Backup Frequency**:
   - Frequent full backups reduce the dependency on long incremental chains but use more storage.
   - Balance the frequency of full backups (`FULL_BACKUP_FREQUENCY`) with your available storage capacity.

3. **No Incremental Chain Disruption**:
   - The system ensures incremental chains remain intact by avoiding commands that delete intermediate full backups (e.g., `remove-all-but-n-full`).

---

#### Verifying Cleanup Behavior (for sysadmins only)

To ensure your retention settings work as intended:

1. **Simulate Cleanup**:
   - Use the `--dry-run` option to preview which backups will be deleted:
     ```bash
     duplicity remove-older-than "${KEEP_WITHIN}" --force "${_BACKUP_TARGET}" --dry-run
     ```

2. **Monitor Storage**:
   - Regularly check your storage usage to ensure retention settings align with available space.

---

#### FAQ

1. **What happens if `KEEP_WITHIN` is too short?**
   - Backups older than the `KEEP_WITHIN` period are deleted, which may reduce the number of available recovery points.

2. **Why isn't `remove-all-but-n-full` used?**
   - `remove-all-but-n-full` deletes full backups and their associated incremental chains, which can disrupt live backups.
   - It is better suited for managing static, archived backups, which are outside the scope of this system.

3. **Can I customize settings for different storage services?**
   - Yes, you can define different retention settings for each service (e.g., AWS, B2) in their respective credentials files.

---
