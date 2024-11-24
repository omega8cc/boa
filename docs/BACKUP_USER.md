
# **User Guide: How the Backup System Works and How to Use It**

This guide explains the backup system, including how it works, how to configure it for your needs, and how to restore your data. The document also covers the supported storage services and key distinctions in path handling.

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
- **Amazon S3**
- **Amazon S3 One Zone**
- **Amazon S3 Standard-IA**
- **Google Cloud Storage**
- **Backblaze B2**
- **Microsoft Azure Blob Storage**
- **UpCloud Object Storage**
- **IBM Cloud Object Storage**
- **Wasabi Hot Cloud Storage**
- **DigitalOcean Spaces**
- **Linode Object Storage by Akamai**

Refer to the **Managing Credentials** section for details on how to create and secure credential files for these services.

---

## **Key Terms and Concepts**

1. **Backup Root**: The top-level directories included in your backups:
   - `~/static/`: Contains your account-specific files, Drupal codebases, and configurations.
   - `/home/john.ftp/`: Your FTP home directory.

2. **Absolute Path**:
   - A full system path starting from the root directory (`/`).
   - **Duplicity ALWAYS requires absolute paths** in configuration files.

3. **Restore Path (No-Slash Absolute Path)**:
   - When using the `restore` command, the restore path must be absolute but without a leading slash. This is specific to Duplicity’s restore syntax.
   - Example:
     - Correct: `data/disk/john/static/projects`
     - Incorrect: `/data/disk/john/static/projects`

4. **Restore Target**: The directory where restored files will be placed. For this system, the default is:
   - `~/static/restores/`


---

## **Backup Scope and Configuration**

The system automatically includes the following directories:

1. **Default Inclusion**:
   - Everything in `~/static/`.
   - System-managed directories like `/home/john.ftp/platforms/`.

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
   - Example:
     ```bash
     --include /data/disk/john/static/custom_data
     --include /home/john.ftp/documents
     ```

2. **`exclude.txt`**:
   - Use this file to exclude specific absolute paths.
   - Example:
     ```bash
     --exclude /data/disk/john/static/tmp
     --exclude /home/john.ftp/logs
     ```

3. **`include_regexp.txt`**:
   - Use regular expressions to include files or directories matching a pattern.
   - Example:
     ```bash
     --include-regexp '^/home/john.ftp/documents/.*\.pdf$'
     --include-regexp '^/data/disk/john/static/.*\.tar\.gz$'
     ```

4. **`exclude_regexp.txt`**:
   - Use regular expressions to exclude files or directories matching a pattern.
   - Example:
     ```bash
     --exclude-regexp '^/data/disk/john/static/cache/.*'
     --exclude-regexp '^/home/john.ftp/tmp/.*'
     ```

---

### **Configuration Rules**

1. **Absolute Paths Only**:
   - All paths in configuration files (include/exclude) must be absolute paths starting from `/`.
   - Example:
     - Correct: `/data/disk/john/static/projects`
     - Incorrect: `~/static/projects`

2. **Order of Precedence**:
   - Exclude directives override include directives. If a file is listed in both, it will not be backed up.

3. **Customizing Defaults**:
   - The entire `~/static/` directory and `/home/john.ftp/platforms/` are included by default. Use exclude files to prevent specific paths from being backed up.

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
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
```

### **Key Variables**
- **`KEEP_WITHIN`**: Specifies how long backups are retained (e.g., `1M` for 1 month).
- **`FULL_BACKUP_FREQUENCY`**: Specifies how often full backups are created.
- **`KEEP_FULL_BACKUPS`**: Specifies the number of full backups to retain.

### **Permissions**
Make sure your credential files are secured:
```bash
chmod 600 ~/static/control/remote_backups/credentials/*.txt
```

---

## **Restoring Files**

To recover data, use the `restoreback` command. The restore process has specific rules for paths, which differ from configuration file paths.

### **Restore Command**

```bash
restoreback restore <SERVICE> <USER> [RESTORE_TARGET] [RESTORE_PATH] [RESTORE_TIME]
```

- `<SERVICE>`: The cloud storage service used for your backups (e.g., `aws`, `b2`, `wasabi`).
- `<USER>`: Your username.
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
   restoreback restore aws john
   ```

2. **Restore a Specific Directory**:
   Restore the `projects` directory:
   ```bash
   restoreback restore aws john ~/static/restores data/disk/john/static/projects
   ```

3. **Restore FTP Files**:
   Restore specific files from your FTP home directory:
   ```bash
   restoreback restore aws john ~/static/restores home/john.ftp/documents
   ```

4. **Restore from a Specific Time**:
   Restore files as they existed 7 days ago:
   ```bash
   restoreback restore aws john ~/static/restores data/disk/john/static/projects 7D
   ```

---

### **Key Rules for Restores**

1. **Restore Path Must Be Absolute Without Leading Slash**:
   - Paths must reflect the full directory structure used during backups, but cannot start with `/`.
   - Example:
     - Correct: `data/disk/john/static/projects`
     - Incorrect: `/data/disk/john/static/projects`

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
     - `~/static/`
     - `/home/john.ftp/`
   - Attempts to include files outside these directories will fail.

2. **Credential Security**:
   - Protect your credentials by setting secure permissions:
     ```bash
     chmod 600 ~/static/control/remote_backups/credentials/*.txt
     ```

3. **Restore Target Permissions**:
   - Ensure your restore target directory is writable.


---

## **Conclusion**

The backup system ensures the security and recoverability of your critical data. By understanding the distinction between configuration paths (absolute with leading slash) and restore paths (absolute without leading slash), and managing your credentials properly, you can confidently manage and restore your data as needed.

For assistance, contact your administrator.
