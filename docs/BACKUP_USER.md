# **User Guide: How the Backup System Works and How to Use It**

This guide explains the backup system, including how it works, how to configure it for your needs, and how to restore your data. The document also covers the supported storage services and key distinctions in path handling.

- New Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_ROOT.md)
- New Backups for Octopus Lshell User (this document) [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md)
- New Backups Retention Policy Configuration [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_RETENTION.md)
- Supported Regions and Bucket Creation Guidelines [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_REGIONS.md)

---

## **How the Backup System Works**

The backup system automates the process of securely backing up your critical data and allows recovery when needed. It uses a tool called **Duplicity**, which is responsible for encrypting, storing, and managing backups.

### **What is Duplicity?**
Duplicity is software designed for secure and efficient backups. It:
1. **Encrypts Your Data**: Keeps your backups secure.
2. **Manages Incremental Backups**: Saves space by only storing changes since the last backup.
3. **Supports Versioning**: Enables restoration of files from specific points in time.

Duplicity ensures your backups are both secure and efficient.

---

## **Supported Storage Services**

The system supports backups to the following storage services. Each service requires a properly formatted credential file stored in:

```bash
~/static/control/remote_backups/credentials/
```

### **Supported Services**
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

## **Key Terms and Concepts**

1. **Backup Root**: The top-level directories included in your backups:
   - `/data/disk/your_username/static/`: Contains your account-specific files, Drupal codebases, and configurations.
   - `/home/your_username.ftp/`: Your FTP home directory.

2. **Absolute Path**:
   - A full system path starting from the root directory (`/`).
   - **Duplicity ALWAYS requires absolute paths** in configuration files.

3. **Restore Path (No-Leading-Slash Absolute Path)**:
   - When using the `restore` command, the restore path must be absolute but **without a leading slash**. This is specific to Duplicity’s restore syntax.
   - Example:
     - Correct: `data/disk/your_username/static/projects`
     - Incorrect: `/data/disk/your_username/static/projects`

4. **Restore Target**: The directory where restored files will be placed. For this system, the default is:
   - `~/static/restores/`

---

## **Backup Scope and Configuration**

The system automatically includes the following directories:

1. **Default Inclusion**:
   - Everything in `/data/disk/your_username/static/`.
   - System-managed directories like `/home/your_username.ftp/platforms/`.

2. **Customization**:
   - You can include or exclude additional directories using configuration files located in:
     ```bash
     ~/static/control/remote_backups/config/
     ```

---

## **Configuring Your Backups**

You can customize what is included or excluded in your backups by editing configuration files stored in:

```bash
~/static/control/remote_backups/config/
```

### **Configuration Files**

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

### **Configuration Rules**

1. **Absolute Paths Only**:
   - All paths in configuration files (include/exclude) must be absolute paths starting from `/`.
   - Example:
     - Correct: `/data/disk/your_username/static/projects`
     - Incorrect: `~/static/projects`

2. **Allowed Directories Only**:
   - You are restricted to including paths within:
     - `/data/disk/your_username/static/`
     - `/home/your_username.ftp/`
   - Attempts to include paths outside these directories will be rejected.

3. **Regex Patterns Must Start with Allowed Base Paths**:
   - Regex patterns must begin with `^` followed by one of your allowed base paths.
   - This ensures that the regex cannot match paths outside your permitted directories.

   - **Valid Regex Pattern**:
     ```bash
     --include-regexp '^/data/disk/your_username/static/documents/.*\.pdf$'
     ```
     - Starts with `^/data/disk/your_username/static`, which is allowed.

   - **Invalid Regex Pattern**:
     ```bash
     --include-regexp '^/etc/.*'
     ```
     - Starts with `^/etc`, which is not within your allowed directories.

4. **Forbidden Characters**:
   - Paths and regex patterns must not contain forbidden characters that could pose security risks:
     - Forbidden characters: `$`, `` ` ``, `(`, `)`, `{`, `}`, `;`, `&`, `|`, `<`, `>`
   - Lines containing these characters will be rejected.

5. **Order of Precedence**:
   - Exclude directives override include directives. If a file or directory is listed in both, it will not be backed up.

6. **Customizing Defaults**:
   - The entire `/data/disk/your_username/static/` directory and `/home/your_username.ftp/` are included by default. Use exclude files to prevent specific paths from being backed up.

---

## **Managing Credentials**

To enable backups and restores, you must provide valid credentials for your cloud storage service. Credential files are stored in:

```bash
~/static/control/remote_backups/credentials/
```

Each credential file corresponds to a specific cloud storage service and must follow the required format. For example:

### **AWS Example (`aws.txt`)**
```bash
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # Example: "us-east-1"
export KEEP_WITHIN="3M"              # Retain backups from the last 3 months
export FULL_BACKUP_FREQUENCY="28D"   # Create a full backup every 28 days
```

### **Key Variables**
- **`KEEP_WITHIN`**: Specifies how long backups are retained (e.g., `1M` for 1 month).
- **`FULL_BACKUP_FREQUENCY`**: Specifies how often full backups are created.

### **Permissions**
Make sure your credential files are secured:
```bash
chmod 600 ~/static/control/remote_backups/credentials/*.txt
```

### **Credential Security Measures**
- **Avoid Forbidden Characters**: Credential values must not contain forbidden characters (`$`, `` ` ``, `(`, `)`, `{`, `}`, `;`, `&`, `|`, `<`, `>`).
- **Proper Syntax**: Ensure each line is a valid variable assignment in the form `VARIABLE="value"`.

---

## **Restoring Files**

To recover data, use the `mybackup` command. The restore process has specific rules for paths, which differ from configuration file paths.

### **Restore Command**

```bash
mybackup restore <SERVICE> [RESTORE_TARGET] [RESTORE_PATH] [RESTORE_TIME]
```

- `<SERVICE>`: The cloud storage service used for your backups (e.g., `aws`, `b2`, `wasabi`).
- `[RESTORE_TARGET]` (optional): The directory where restored files will be placed. Defaults to `~/static/restores/`.
- `[RESTORE_PATH]` (optional): The absolute path (no leading slash) of the file or directory to restore.
- `[RESTORE_TIME]` (optional): The point in time for the restore, specified in human-readable formats like:
  - `1D` (1 day ago)
  - `7D` (7 days ago)
  - `1M` (1 month ago)

---

### **Restore Examples**

1. **Restore All Files to Default Directory**:
   Restore your entire backup to `~/static/restores/`:
   ```bash
   mybackup restore aws
   ```

2. **Restore a Specific Directory**:
   Restore the `projects` directory:
   ```bash
   mybackup restore aws ~/static/restores data/disk/your_username/static/projects
   ```

3. **Restore FTP Files**:
   Restore specific files from your FTP home directory:
   ```bash
   mybackup restore aws ~/static/restores home/your_username.ftp/documents
   ```

4. **Restore from a Specific Time**:
   Restore files as they existed 7 days ago:
   ```bash
   mybackup restore aws ~/static/restores data/disk/your_username/static/projects 7D
   ```

---

### **Key Rules for Restores**

1. **Restore Path Must Be Absolute Without Leading Slash**:
   - Paths must reflect the full directory structure used during backups, but cannot start with `/`.
   - Example:
     - Correct: `data/disk/your_username/static/projects`
     - Incorrect: `/data/disk/your_username/static/projects`

2. **Restore Target Directory Can Be Relative or Absolute**:
   - Default: `~/static/restores/`
   - You may specify a custom restore target directory.

3. **Default Behavior**:
   - If `[RESTORE_PATH]` is omitted, the entire backup is restored.
   - If `[RESTORE_TIME]` is omitted, the latest backup is restored.

---

## **Security Notes**

1. **Backup Scope**:
   - The system restricts backups to:
     - `/data/disk/your_username/static/`
     - `/home/your_username.ftp/`
   - Attempts to include files outside these directories will fail.

2. **Path Validation and Security**:
   - **Validation of Paths**: The system strictly validates all paths and regex patterns in your configuration files to prevent inclusion of unauthorized directories.
   - **Regex Patterns**:
     - Must start with `^` and an allowed base path (`/data/disk/your_username/static` or `/home/your_username\.ftp` (note the requirement to escape the dot in the regex mode).
     - Cannot contain forbidden characters.

3. **Credential Security**:
   - Protect your credentials by setting secure permissions:
     ```bash
     chmod 600 ~/static/control/remote_backups/credentials/*.txt
     ```
   - Ensure credential files contain only valid variable assignments.

4. **Restore Target Permissions**:
   - Ensure your restore target directory is writable.

5. **Forbidden Characters in Configurations**:
   - Avoid using forbidden characters in your configuration files:
     - Forbidden characters: `$`, `` ` ``, `(`, `)`, `{`, `}`, `;`, `&`, `|`, `<`, `>`
   - Lines containing these characters will be rejected for security reasons.

6. **No Execution of User-Provided Code**:
   - The backup system does not execute any code from your configuration files. It reads and processes the files securely to prevent code injection or execution of unauthorized commands.

---

## **Troubleshooting**

If you encounter issues with your backups or restores:

1. **Check Logs**:
   - Validation issues are logged in:
     ```bash
     /var/log/backup_validation_issues.log
     ```
   - Ask your host to review this log to see if any lines in your configuration files were rejected.

2. **Common Validation Errors**:
   - **Unauthorized Path**: Attempting to include paths outside your allowed directories.
   - **Invalid Syntax**: Incorrect formatting in configuration files.
   - **Forbidden Characters**: Use of forbidden characters in paths or credential values.

3. **Correcting Validation Errors**:
   - Ensure all paths are within `/data/disk/your_username/static/` or `/home/your_username.ftp/`.
   - Verify that regex patterns start with `^` followed by an allowed base path.
   - Remove any forbidden characters from paths and credential values.
   - Confirm that credential files contain valid variable assignments.

---

## **Best Practices**

1. **Regularly Review Configuration Files**:
   - Keep your include and exclude lists up to date with your backup needs.

2. **Secure Your Credentials**:
   - Limit access to your credential files and update your credentials if you suspect they have been compromised.

3. **Test Restores Periodically**:
   - Perform test restores to ensure that your backups are functioning correctly and data can be recovered when needed.

4. **Monitor Backup Logs**:
   - Regularly check the backup logs to identify and address any issues promptly.

5. **Understand Regex Limitations**:
   - Be cautious when using regex patterns. Ensure they only match the intended files within your allowed directories.

---

## **Conclusion**

The backup system ensures the security and recoverability of your critical data. By understanding the distinction between configuration paths (absolute with leading slash) and restore paths (absolute without leading slash), adhering to the validation rules, and managing your credentials properly, you can confidently manage and restore your data as needed.

For assistance, contact your administrator.

---

**Note**: Replace `your_username` with your actual Aegir **system** (not lshell/ftp) username in all the examples above.
