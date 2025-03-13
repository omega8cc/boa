
# System Administrator Guide: Managing Global Backups

This guide explains the global backup system, its configuration, supported services, and best practices. It covers only the aspects managed by the system administrator (root access), including global backups, vendor selection, and service-specific details.

- New PRO Backups for BOA SysAdmin (this document) [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_ROOT.md)
- New PRO Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md)
- New PRO Backups Retention Policy Configuration [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_RETENTION.md)
- New PRO Backups Supported Regions and Bucket Creation Guidelines [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_REGIONS.md)

---

## **How the Global Backup System Works**
The global backup system is designed to securely back up system-wide data (e.g., `/data`, `/etc`, `/home`, `/opt/solr4`, `/var/aegir`, `/var/solr7`, `/var/www`, `/var/xdrago`) and ensure data integrity and recoverability. It uses **Duplicity** to create encrypted, incremental, and versioned backups stored in remote cloud services.

### **Features**
- **Global Scope**: Includes critical directories like `/data`, `/etc`, `/home`, `/opt/solr4`, `/var/aegir`, `/var/solr7`, `/var/www` and `/var/xdrago`.
- **Encryption**: Ensures that all backups are protected against unauthorized access.
- **Incremental Backups**: Reduces storage usage and bandwidth by saving only changes since the last backup.
- **Retention Policies**: Automatically removes old backups based on administrator-defined retention rules.
- **Vendor Flexibility**: Supports multiple storage services, including AWS S3, Backblaze B2, Wasabi, and more.

---

## **Installer Section**

The backup system includes an installer script to simplify setup and management. This script automates the installation of dependencies, configuration setup, and cron job generation.

### **Installer Script: `dcysetup`**

The `dcysetup` script is located in `/opt/local/bin/dcysetup` and provides the following options:

```bash
dcysetup <command>
```

- **Commands**:
  - `install`: Installs required dependencies for the backup system.
  - `setup`: Configures global backups, generating default configuration files and cron jobs.
  - `update`: Alias for `setup`.

---

### **How to Use the Installer**

1. **Install Dependencies**:
   ```bash
   dcysetup install
   ```

2. **Set Up the Backup System**:
   - Generates default configuration files and schedules cron jobs for global backups.
   ```bash
   dcysetup setup
   ```

3. **Update Configuration**:
   - Run this command after making manual changes to the configuration files.
   ```bash
   dcysetup update
   ```


---

## **Key Terms and Concepts**

1. **Global Backup Scope**:
   - Includes directories crucial for system operations:
     - `/data`
     - `/etc`
     - `/home`
     - `/opt/solr4`
     - `/var/aegir`
     - `/var/solr7`
     - `/var/www`
     - `/var/xdrago`

2. **Absolute Path**:
   - All paths in configuration files must be full absolute paths (e.g., `/var/aegir/`).

3. **Retention Policies**:
   - Defines how long backups are kept, how often full backups occur, and how many full backups are retained.

---

## **Supported Storage Services**

The system supports multiple storage providers. Credentials for these providers are stored in `/root/.remote_backups/credentials/`.

### **Supported Services**
- **Amazon S3** (Standard, One Zone, Standard-IA)
- **Backblaze B2**
- **Cloudflare R2**
- **DigitalOcean Spaces**
- **Google Cloud Storage**
- **IBM Cloud Object Storage**
- **Linode Object Storage by Akamai**
- **Microsoft Azure Blob Storage**
- **Wasabi Hot Cloud Storage**

### **Technical Comparison Table**

| **Service**                | **Storage Class**                     | **Redundancy**        | **Regions** | **Encryption**                         | **Interface**          |
|----------------------------|---------------------------------------|-----------------------|-------------|----------------------------------------|------------------------|
| **Amazon S3**              | Standard, One Zone-IA, Standard-IA    | Multi-AZ / Single AZ  | Global      | Server-side (AES-256) + Client-side    | S3 API (boto3)         |
| **Backblaze B2**           | Hot                                   | Multi-region          | US, Europe  | Server-side (AES-256) + Client-side    | B2 API, S3 Compatible  |
| **Cloudflare R2**          | Hot                                   | Multi (Regionless)    | Global      | Server-side (AES-256) + In-transit TLS | S3 API (boto3)         |
| **DigitalOcean Spaces**    | Standard (Hot)                        | Multi-region          | Global      | Server-side (AES-256) + Client-side    | S3 API (boto3)         |
| **Google Cloud Storage**   | Standard, Nearline, Coldline, Archive | Multi-region          | Global      | Server-side (AES-256) + Client-side    | Native, S3 Compatible  |
| **IBM Cloud**              | Standard, Vault, Cold Vault, Archive  | Multi-region          | Global      | Server-side (AES-256) + Client-side    | S3 API (boto3)         |
| **Linode Object Storage**  | Standard (Hot)                        | Multi-region          | Global      | Server-side (AES-256) + Client-side    | S3 API (boto3)         |
| **Microsoft Azure**        | Hot, Cool, Archive                    | LRS, ZRS, GRS, RA-GRS | Global      | Server-side (AES-256) + Client-side    | Azure Blob API         |
| **Wasabi**                 | Hot                                   | Multi-region          | Global      | Server-side (AES-256) + Client-side    | S3 API (boto3)         |

---

### **Pricing Comparison Table**

| **Service**                | **Storage Cost (per GB)** | **Egress Cost (per GB)**  | **Free Tier**                     | **Notes**                                       |
|----------------------------|---------------------------|---------------------------|-----------------------------------|-------------------------------------------------|
| **Amazon S3**              | $0.0230 (Standard)        | $0.090                    | 5 GB (12 months)                  | Wide region availability, multiple classes      |
| **Backblaze B2**           | $0.0050                   | $0.010                    | 10 GB storage + 1 GB/day download | Cost-effective, ideal for archival storage      |
| **Cloudflare R2**          | $0.0150                   | Free                      | 10 GB storage + 1 TB egress/month | Zero egress fees, integrates with their network |
| **DigitalOcean Spaces**    | $0.0200 > 250 GB          | $0.020 per GB beyond 1 TB | None                              | Free bandwidth up to the first 1 TB             |
| **Google Cloud**           | $0.0200 (Standard)        | $0.120                    | 5 GB (12 months)                  | Multiple storage classes                        |
| **IBM Cloud**              | $0.0200 (Standard)        | $0.090                    | Lite plan (25 GB)                 | Supports advanced archival options              |
| **Linode Object Storage**  | $0.0050                   | $0.010                    | None                              | Affordable and Akamai-backed                    |
| **Microsoft Azure**        | $0.0180 (Cool)            | $0.085                    | $200 credit for first 30 days     | Flexible tiering                                |
| **Wasabi**                 | $0.0059                   | Free                      | None                              | Unlimited egress, good for high traffic         |

---

## **Global Configuration**

The global backup configuration files are stored in:

```bash
/root/.remote_backups/
```

### **Configuration Files Examples**

Configuration files which merge all other configuration files per bucket when you run `dcysetup update` command:

1. **`/root/.remote_backups/paths/global_paths.txt`**:
   - Defines which global directories are included in backups.
   - Example:
     ```bash
     _SOURCE="/etc /opt/solr4 /var/aegir /var/solr7 /var/solr9 /var/www /var/xdrago"
     _INCLUDE_PATHS="--include /data/disk/arch --include-regexp '^/var/backups/barracuda.*'"
     _EXCLUDE_PATHS="--exclude /data/disk --exclude /var/aegir/backups"
     _INCLUDE_LIST="/root/.remote_backups/paths/.backboa.include.list"
     _EXCLUDE_LIST="/root/.remote_backups/paths/.backboa.exclude.list"
     ```

2. **`/root/.remote_backups/paths/data_paths.txt`**:
   - Defines which data directories are included in backups.
   - Example:
     ```bash
     _SOURCE=""
     _INCLUDE_PATHS="--include /data/disk/o1 --include /data/disk/o2"
     _EXCLUDE_PATHS="--exclude-regexp '^/data/disk/.*/backups'"
     _INCLUDE_LIST="/root/.remote_backups/paths/.backboa.include.list"
     _EXCLUDE_LIST="/root/.remote_backups/paths/.backboa.exclude.list"
     ```

3. **`/root/.remote_backups/paths/.backboa.*`**:
   - Configuration files with good defaults which are merged per system user bucket and referenced in either `global_paths.txt` or `data_paths.txt` when you run `dcysetup update` command, used to include or exclude additional absolute paths and regex patterns for fine-grained control of exclude/include logic:

     ```bash
     .backboa.data_exclude.merged.file
     .backboa.data_include.merged.file
     .backboa.exclude.file
     .backboa.exclude.list
     .backboa.exclude_data_regexp.file
     .backboa.global_exclude.merged.file
     .backboa.global_include.merged.file
     .backboa.include_data.file
     .backboa.include_global.file
     .backboa.include_global_regexp.file
     ```

---

### **Configuration Rules**

1. **Absolute Paths Only**:
   - All paths in configuration files (exclude/include) must be absolute paths starting from `/`.
   - Example:
     - Correct: `/root/projects`
     - Incorrect: `~/projects`

2. **Order of Precedence**:
   - Exclude directives override include directives. If a file is listed in both, it will not be backed up.

---

## **Managing Credentials**

Credentials for global backups are stored in `/root/.remote_backups/credentials/`. Each file corresponds to a specific storage service.

### **Backblaze B2 (`b2.txt`)**
```bash
export B2_ACCOUNT_ID="your_b2_account_id"
export B2_APPLICATION_KEY="your_b2_application_key"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
```

### **Permissions**
Ensure all credentials are secured:
```bash
chmod 600 /root/.remote_backups/credentials/*.txt
```

---

## **Restoring Global Backups**

Restoring global backups follows the same logic as [user backups](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md), except administrators manage the entire system. Use the `multiback` command for global restores:

```bash
multiback restore <SERVICE> <USER> <RESTORE_TARGET> <RESTORE_PATH> [RESTORE_TIME]
```

---

### **Restore Examples**

1. **Restore All Files per System User to Default Directory**:
   ```bash
   multiback restore b2 global /var/backups/restored
   multiback restore b2 data /var/backups/restored
   multiback restore b2 custom /var/backups/restored
   ```

2. **Restore a Specific Directory**:
   ```bash
   multiback restore b2 global /var/backups/restored var/www/example
   multiback restore b2 data /var/backups/restored data/disk/o1
   multiback restore b2 custom /var/backups/restored custom/path/foo/bar
   ```

3. **Restore from a Specific Time**:
   ```bash
   multiback restore b2 data /var/backups/restored data/disk/o1/static/platform 7D
   ```

---

### **Key Rules for Restores**

1. **Restore Path Must Be Absolute Without Leading Slash**:
   - Paths must reflect the full directory structure used during backups, but cannot start with `/`.
   - Example:
     - Correct: `data/disk/o1/static/platform`
     - Incorrect: `/data/disk/o1/static/platform`

2. **Restore Target Directory Can Be Relative or Absolute**:
   - Default: `/var/backups/restored/`
   - You may specify a custom restore target directory.

3. **Default Behavior**:
   - If `[RESTORE_PATH]` is omitted, the entire backup is restored.
   - If `[RESTORE_TIME]` is omitted, the latest backup is restored.


---

## **Best Practices**

1. **Test Restores Regularly**:
   - Verify your backups by restoring critical data periodically.

2. **Monitor Storage Usage**:
   - Use retention policies to control costs and prevent storage overuse.

3. **Secure Credentials**:
   - Regularly rotate access keys and audit credentials.

4. **Automate Monitoring**:
   - Use system logs or monitoring tools to ensure backups run as expected.

---

## **Conclusion**

The global backup system ensures system-wide data protection and disaster recovery capabilities. By using the configuration and management tools provided, administrators can manage backups efficiently while keeping costs under control.

For user-specific backups, refer to the separate [**User Backup Guide**](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md)

For assistance, contact BOA developers team.
