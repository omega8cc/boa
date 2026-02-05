
# User Guide: How the Backup System Works and How to Use It

This guide explains the backup system, including how it works, how to configure it for your needs, and how to restore your data. It also covers the supported storage services, key distinctions in path handling, and the default retention policies for your local database backups.

- New PRO Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_ROOT.md)
- New PRO Backups for Octopus Lshell User (this document) [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md)
- New PRO Backups Retention Policy Configuration [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_RETENTION.md)
- New PRO Backups Supported Regions and Bucket Creation Guidelines [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_REGIONS.md)

---

## **Important Note on Database Backups**

All **active sites databases** are now automatically backed up to the following directory in your account:

```
/data/disk/your_username/static/files/dbackup/
```

These local database backups are retained for **14 days** by default. You can modify the retention period (in days) by creating or editing the file:

```
/data/disk/your_username/static/control/dBackupCycle.info
```

This file should contain only digits (e.g., `7` for 7 days, `30` for 30 days, etc.). Keep in mind that **these database backup archives count toward your overall file-space usage limit**, according to your subscription plan if you are on hosted BOA.

**Important**: Databases which belong to **disabled sites** are still backed up on the system level, but **will not be added to your archives** in `/data/disk/your_username/static/files/dbackup/`.

---

## **Basic Use (Simple Configuration)**

This section covers a quick-start approach, focusing on minimal setup.

1. **Where DB Backups Are Stored by Default**
   - Local database backups: `/data/disk/your_username/static/files/dbackup/`
   - Retained for 14 days by default (modifiable via `/data/disk/your_username/static/control/dBackupCycle.info`).
   - Local database backups count toward your file-space quota.

2. **Enable or Verify That Backups Are Enabled**
   - By default, backups for your account are typically enabled. If in doubt, contact support to confirm that scheduled backups are running.

3. **Add Your Preferred Remote Storage Credentials**
   - To send backups offsite (e.g., AWS S3, Wasabi, Backblaze B2), edit a credential file in:
     ```
     /data/disk/your_username/static/control/remote_backups/credentials/
     ```
   - Follow the specific format required by each service (see **AWS Example** in the advanced section for reference).
   - Secure your credentials by running:
     ```bash
     chmod 600 /data/disk/your_username/static/control/remote_backups/credentials/*.txt
     ```

4. **Restore Basics**
   - For quick restores, you can use:
     ```bash
     mybackup restore <SERVICE>
     ```
   - This command will restore everything to your `/data/disk/your_username/static/restores/` folder.
   - If you need to restore just a specific directory or from a certain date, see the **Advanced Use** section below.

5. **Monitor Usage**
   - Remember that **all backup files** stored locally (`/data/disk/your_username/static/files/dbackup/`) **count toward your usage limit**.
   - If you’re nearing your quota, consider:
     - Shortening your retention period in `/data/disk/your_username/static/control/dBackupCycle.info`.
     - Removing old backups.
     - Upgrading your plan if you need more space.

That’s it for the basics! If you need more control—like custom includes/excludes, restoring specific directories, or advanced scheduling—read on.

---

## **Advanced Use (Detailed Configuration and Instructions)**

Below is the full, detailed documentation that covers **how the backup system works**, how to **configure** it for more granular scenarios, **how to restore** data with precision, and how to manage and troubleshoot the system.

### **How the Backup System Works**

The backup system automates the process of securely backing up your critical data and allows recovery when needed. It uses a tool called **Duplicity**, which is responsible for encrypting, storing, and managing backups.

#### **What is Duplicity?**
Duplicity is software designed for secure and efficient backups. It:
1. **Encrypts Your Data**: Keeps your backups secure.
2. **Manages Incremental Backups**: Saves space by only storing changes since the last backup.
3. **Supports Versioning**: Enables restoration of files from specific points in time.

Duplicity ensures your backups are both secure and efficient.

---

### **Supported Storage Services**

The system supports backups to the following storage services. Each service requires a properly formatted credential file stored in:

```bash
/data/disk/your_username/static/control/remote_backups/credentials/
```

**Supported Services:**
- **Amazon S3 One Zone**
- **Amazon S3 Standard-IA**
- **Amazon S3**
- **Backblaze B2**
- **DigitalOcean Spaces**
- **Google Cloud Storage**
- **IBM Cloud Object Storage**
- **Linode Object Storage by Akamai**
- **Microsoft Azure Blob Storage**
- **Wasabi Hot Cloud Storage**

Refer to the **Managing Credentials** section for details on how to create and secure credential files for these services.

---

### **Key Terms and Concepts**

1. **Backup Root**: The top-level directories included in your backups:
   - `/data/disk/your_username/static/`: Contains your account-specific files, Drupal codebases, and configurations.
   - `/home/your_username.ftp/`: Your FTP home directory.

2. **Absolute Path**:
   - A full system path starting from the root directory (`/`).
   - **Duplicity ALWAYS requires absolute paths** in configuration files.

3. **Restore Path (No-Leading-Slash Absolute Path)**:
   - When using the `restore` command, the restore path must be absolute but **without a leading slash** (specific to Duplicity’s syntax).
   - Example:
     - Correct: `data/disk/your_username/static/projects`
     - Incorrect: `/data/disk/your_username/static/projects`

4. **Restore Target**: The directory where restored files will be placed. For this system, the default is:
   - `/data/disk/your_username/static/restores/`

---

### **Backup Scope and Configuration**

The system automatically includes the following directories:

1. **Default Inclusion**:
   - Everything in `/data/disk/your_username/static/`.
   - System-managed directories like `/home/your_username.ftp/platforms/`.
   - Platforms without codebase access in `/data/disk/your_username/distro/`.

2. **Default Exclusion**:
   - Everything in `/data/disk/your_username/static/trash/`.
   - Everything in `/data/disk/your_username/static/restores/`.

3. **Customization**:
   - You can include or exclude additional directories using configuration files located in:
     ```bash
     /data/disk/your_username/static/control/remote_backups/config/
     ```

---

### **Required Bucket Naming Convention**

Most providers allow **automatic bucket creation** if sufficient credentials and permissions are provided, so you don't need to figure it out yourself. However, some providers (e.g., **Linode**) require **manual bucket creation** before the first backup and others (e.g., **Amazon S3**) are unreliable for automatic creation due to propagation delays between AWS regions. Manual bucket creation is recommended if you use provider known as not reliable or when manual creation is required -- check all details in the docs Supported Regions and Bucket Creation Guidelines [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_REGIONS.md).

- User-specific bucket names follow the convention: `back-to-USER-HOSTNAME-PROVIDER`.
- The `USER` is your Ægir system user as visible in the `/data/disk/USER/static` path.
- The `HOSTNAME` is your system hostname, but with dots replaced by hyphens.
- The `PROVIDER` is the short name of the vendor, with underscores replaced by hyphens:

```sh
  aws -------------- Amazon S3 (Standard)
  aws-one-zone ----- Amazon S3 (One Zone)
  aws-standard-ia -- Amazon S3 (Standard-IA)
  azure ------------ Azure Blob Storage
  b2 --------------- Backblaze B2
  cloudflare ------- Cloudflare R2 Object Storage
  do-spaces -------- DigitalOcean Spaces
  gcs -------------- Google Cloud Storage
  ibm -------------- IBM Cloud Object Storage
  linode ----------- Linode Object Storage by Akamai
  wasabi ----------- Wasabi Hot Cloud Storage
```

How to determine correct `HOSTNAME` and `USER` to be used as your Bucket name?

It's easy to find because your Ægir URL is actually `USER`.`HOSTNAME` -- For example in `o123.fr8.eu.aegir.cc` the `o123` is `USER` and `fr8.eu.aegir.cc` is a `HOSTNAME`

However, when used in the bucket name, it becomes `back-to-USER-HOSTNAME-PROVIDER`, so in this example: `back-to-o123-fr8-eu-aegir-cc-wasabi`

---

### **Managing Credentials**

To enable backups and restores, you must provide valid credentials for your cloud storage service. Credential files are stored in:

```bash
/data/disk/your_username/static/control/remote_backups/credentials/
```

Each credential file corresponds to a specific cloud storage service and must follow the required format. For example:

#### **AWS Example (`aws.txt`)**
```bash
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # Example: "us-east-1"
export KEEP_WITHIN="3M"              # Retain backups from the last 3 months
export FULL_BACKUP_FREQUENCY="28D"   # Create a full backup every 28 days
```

**Key Variables**:
- **`KEEP_WITHIN`**: Specifies how long backups are retained (e.g., `1M` for 1 month).
- **`FULL_BACKUP_FREQUENCY`**: Specifies how often full backups are created.

**Permissions**:
```bash
chmod 600 /data/disk/your_username/static/control/remote_backups/credentials/*.txt
```

**Credential Security Measures**:
- **Avoid Forbidden Characters**: Credential values must not contain `$`, `` ` ``, `(`, `)`, `{`, `}`, `;`, `&`, `|`, `<`, `>`.
- **Proper Syntax**: Ensure each line is a valid variable assignment in the form `VARIABLE="value"`.

---

### **Configuring Your Backups**

You can customize what is included or excluded in your backups by editing configuration files stored in:

```bash
/data/disk/your_username/static/control/remote_backups/config/
```

#### **Configuration Files**

1. **`include.txt`**:
   - Use this file to include additional absolute paths in the backup.
   - **Important**: Paths must be within your allowed directories.

   - Example:
     ```bash
     --include /data/disk/your_username/static/custom_data
     --include /home/your_username.ftp/documents
     ```

2. **`exclude.txt`**:
   - Use this file to exclude specific absolute paths.
   - Example:
     ```bash
     --exclude /data/disk/your_username/static/tmp
     --exclude /home/your_username.ftp/logs
     ```

3. **`include_regexp.txt`**:
   - Use regular expressions to include files or directories matching a pattern.
   - **Important**: Regex patterns must start with `^` and match paths within your allowed directories.
   - Example:
     ```bash
     --include-regexp '^/data/disk/your_username/static/documents/.*\.pdf$'
     --include-regexp '^/home/your_username\.ftp/images/.*\.(jpg|png)$'
     ```

4. **`exclude_regexp.txt`**:
   - Use regular expressions to exclude files or directories matching a pattern.
   - **Important**: Regex patterns must start with `^` and match paths within your allowed directories.
   - Example:
     ```bash
     --exclude-regexp '^/data/disk/your_username/static/cache/.*'
     --exclude-regexp '^/home/your_username\.ftp/tmp/.*'
     ```

---

#### **Configuration Rules**

1. **Absolute Paths Only**:
   - All paths in configuration files (exclude/include) must be absolute paths starting from `/`.
   - Example:
     - Correct: `/data/disk/your_username/static/projects`
     - Incorrect: `~/static/projects`

2. **Allowed Directories Only**:
   - You are restricted to including paths within:
     - `/data/disk/your_username/static/`
     - `/home/your_username.ftp/`
   - Attempts to include paths outside these directories will be rejected.
   - Platforms without codebase access in `/data/disk/your_username/distro/` are included automatically.

3. **Regex Patterns Must Start with Allowed Base Paths**:
   - Regex patterns must begin with `^` followed by one of your allowed base paths.
   - This ensures that the regex cannot match paths outside your permitted directories.

   - **Valid Regex Pattern**:
     ```bash
     --include-regexp '^/data/disk/your_username/static/documents/.*\.pdf$'
     ```
     - Starts with `^data/disk/your_username/static`, which is allowed.

   - **Invalid Regex Pattern**:
     ```bash
     --include-regexp '^//data/disk/your_username/static/foo/.*'
     ```
     - Starts with `^/data/disk`, while in regexp the first slash should be omitted.

4. **Forbidden Characters**:
   - Paths and regex patterns must not contain forbidden characters that could pose security risks:
     - Forbidden characters: `$`, `` ` ``, `(`, `)`, `{`, `}`, `;`, `&`, `|`, `<`, `>`
   - Lines containing these characters will be rejected.

5. **Order of Precedence**:
   - Exclude directives override include directives. If a file or directory is listed in both, it will not be backed up.

6. **Customizing Defaults**:
   - The entire `/data/disk/your_username/static/` directory and `/home/your_username.ftp/` are included by default. Use exclude files to prevent specific paths from being backed up.

---

### **Restoring Files**

To recover data, use the `mybackup` command. The restore process has specific rules for paths, which differ from configuration file paths.

#### **Restore Command**

```bash
mybackup restore <SERVICE> [RESTORE_PATH] [RESTORE_TIME]
```

- `<SERVICE>`: The cloud storage service used for your backups (e.g., `aws`, `b2`, `wasabi`).
- `[RESTORE_PATH]` (optional): The absolute path (no leading slash) of the file or directory to restore.
- `[RESTORE_TIME]` (optional): The point in time for the restore, specified in human-readable formats like:
  - `1D` (1 day ago)
  - `7D` (7 days ago)
  - `1M` (1 month ago)

---

#### **Restore Examples**

1. **Restore All Files to Default Directory**:
   ```bash
   mybackup restore aws
   ```
   - Restores the entire backup to `/data/disk/your_username/static/restores/`.

2. **Restore a Specific Directory**:
   ```bash
   mybackup restore aws data/disk/your_username/static/projects
   ```
   - Restores the `projects` directory.

3. **Restore FTP Files**:
   ```bash
   mybackup restore aws home/your_username.ftp/documents
   ```
   - Restores files from your FTP home directory.

4. **Restore from a Specific Time**:
   ```bash
   mybackup restore aws data/disk/your_username/static/projects 7D
   ```
   - Restores files as they were 7 days ago.

---

#### **Key Rules for Restores**

1. **Restore Path Must Be Absolute Without Leading Slash**:
   - Paths must reflect the full directory structure used during backups, but cannot start with `/`.
   - Example:
     - Correct: `data/disk/your_username/static/projects`
     - Incorrect: `/data/disk/your_username/static/projects`

2. **Default Behavior**:
   - If `[RESTORE_PATH]` is omitted, the entire backup is restored.
   - If `[RESTORE_TIME]` is omitted, the latest backup is restored.

---

### **Security Notes**

1. **Backup Scope**:
   - The system restricts user-configured backups to:
     - `/data/disk/your_username/static/`
     - `/home/your_username.ftp/`
   - Attempts to include files outside these directories will fail.
   - Platforms without codebase access in `/data/disk/your_username/distro/` are included automatically.

2. **Path Validation and Security**:
   - **Validation of Paths**: Strictly enforced to prevent unauthorized directories from being backed up.
   - **Regex Patterns**:
     - Must start with `^` and an allowed base path.
     - Cannot contain forbidden characters.

3. **Credential Security**:
   - Protect your credentials by setting secure permissions:
     ```bash
     chmod 600 /data/disk/your_username/static/control/remote_backups/credentials/*.txt
     ```
   - Ensure credential files contain only valid variable assignments.

4. **Restore Target Permissions**:
   - Make sure your restore target directory is writable.

5. **Forbidden Characters in Configurations**:
   - `$`, `` ` ``, `(`, `)`, `{`, `}`, `;`, `&`, `|`, `<`, `>` are disallowed in paths/credentials.
   - Lines containing these characters will be rejected.

6. **No Execution of User-Provided Code**:
   - The backup system does not execute user-provided code. It securely parses config files to prevent any code injection.

---

### **Troubleshooting**

If you encounter issues with your backups or restores:

1. **Check Logs**:
   - Latest backup actions are logged in:
     ```bash
     /data/disk/your_username/static/control/remote_backups/logs/
     ```
   - Validation issues are logged in:
     ```bash
     /var/log/backup_validation_issues.log
     ```
   - Ask your host to review this log if any lines in your config files were rejected.

2. **Common Validation Errors**:
   - **Unauthorized Path**: Attempting to include paths outside allowed directories.
   - **Invalid Syntax**: Incorrectly formatted config files.
   - **Forbidden Characters**: Using `$`, `` ` ``, `(`, `)`, `{`, `}`, `;`, `&`, `|`, `<`, `>`.

3. **Correcting Validation Errors**:
   - Ensure all paths are within `/data/disk/your_username/static/` or `/home/your_username.ftp/`.
   - Verify that regex patterns start with `^` followed by an allowed base path.
   - Remove any forbidden characters from paths and credential values.
   - Confirm that credential files contain valid variable assignments.

---

### **Best Practices**

1. **Review Configuration Files Regularly**:
   - Keep your include and exclude lists up to date with your backup needs.

2. **Secure Your Credentials**:
   - Limit access to your credential files and update your credentials if you suspect they have been compromised.

3. **Test Restores Periodically**:
   - Perform test restores to ensure that your backups are functioning correctly and data can be recovered when needed.

4. **Monitor Backup Logs**:
   - Regularly check the backup logs to identify and address any issues promptly.

5. **Use Regex with Caution**:
   - Ensure patterns match only intended files/directories within allowed paths.

---

### **Conclusion**

By following the **Basic Use** section, you can quickly get your backups running—just add your preferred remote service credentials and rely on the default local database backups stored in `/data/disk/your_username/static/files/dbackup/`. For more granular control, use the **Advanced Use** section to configure includes, excludes, custom retention, advanced restore options, and more.

Remember that **all local backups count toward your storage quota**, so adjust your retention period or remove old backups as needed. If you have questions or run into any issues, please contact your administrator or hosting support.

---

**Note**: Replace `your_username` with your actual Ægir **system** username (not lshell/FTP username) in all examples above.
