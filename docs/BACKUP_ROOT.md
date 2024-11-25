
# **System Administrator Guide: Managing Global Backups**

This guide explains the global backup system, its configuration, supported services, and best practices. It covers only the aspects managed by the system administrator (root access), including global backups, vendor selection, and service-specific details.

- New Backups for BOA SysAdmin (this document) [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_ROOT.md)
- New Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md)
- New Backups Retention Policy Configuration [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_RETENTION.md)
- Supported Regions and Bucket Creation Guidelines [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_REGIONS.md)

---

## **How the Global Backup System Works**
The global backup system is designed to securely back up system-wide data (e.g., `/data`, `/home`, `/etc`, `/var/aegir`, `/var/www`, `/var/solr7`, `/opt/solr4`, `/var/xdrago`) and ensure data integrity and recoverability. It uses **Duplicity** to create encrypted, incremental, and versioned backups stored in remote cloud services.

### **Features**
- **Global Scope**: Includes critical directories like `/data`, `/home`, `/etc`, `/var/aegir`, `/var/www`, `/var/solr7`, `/opt/solr4` and `/var/xdrago`.
- **Encryption**: Ensures that all backups are protected against unauthorized access.
- **Incremental Backups**: Reduces storage usage and bandwidth by saving only changes since the last backup.
- **Retention Policies**: Automatically removes old backups based on administrator-defined retention rules.
- **Vendor Flexibility**: Supports multiple storage services, including AWS S3, Backblaze B2, Wasabi, and more.

---

## **Installer Section**

The backup system includes an installer script to simplify setup and management. This script automates the installation of dependencies, configuration setup, and cron job generation.

### **Installer Script: `dcysetup`**

The `dcysetup` script is located in `/var/xdrago/backup/run/` and provides the following options:

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
     - `/home`
     - `/etc`
     - `/var/aegir`
     - `/var/www`
     - `/var/solr7`
     - `/opt/solr4`
     - `/var/xdrago`

2. **Absolute Path**:
   - All paths in configuration files must be full absolute paths (e.g., `/var/aegir/`).

3. **Retention Policies**:
   - Defines how long backups are kept, how often full backups occur, and how many full backups are retained.

---

## **Supported Storage Services**

The system supports multiple storage providers. Credentials for these providers are stored in `/var/xdrago/backup/credentials/`.

### **Supported Services**
- **Amazon S3** (Standard, One Zone, Standard-IA)
- **Backblaze B2**
- **DigitalOcean Spaces**
- **Google Cloud Storage**
- **IBM Cloud Object Storage**
- **Linode Object Storage by Akamai**
- **Microsoft Azure Blob Storage**
- **UpCloud Object Storage**
- **Wasabi Hot Cloud Storage**

### **Technical Comparison Table**

| **Service**           | **Storage Class**        | **Redundancy**       | **Regions Available**                   | **Encryption**           | **Interface**          |
|------------------------|--------------------------|----------------------|-----------------------------------------|--------------------------|-------------------------|
| **Amazon S3**          | Standard, One Zone, IA  | Multi-AZ / Single AZ | Global                                  | Server-side + Client-side | S3 (boto3)             |
| **Backblaze B2**       | Hot                     | Multi-region         | US/Europe                               | Client-side only          | B2 Native              |
| **DigitalOcean Spaces** | Hot                   | Multi-region         | US, Europe                              | Client-side only          | S3 (boto3)             |
| **Google Cloud Storage** | Standard, Nearline     | Multi-region / Single | Global                                  | Server-side + Client-side | Native                 |
| **IBM Cloud**          | Standard, Archive       | Multi-region         | Global                                  | Server-side + Client-side | S3 (boto3)             |
| **Linode Object Storage** | Hot                 | Multi-region         | US, Europe                              | Client-side only          | S3 (boto3)             |
| **Microsoft Azure**    | Hot, Cool, Archive      | Multi-region         | Global                                  | Server-side + Client-side | Blob Storage (Azure)   |
| **UpCloud Object Storage** | Hot                | Multi-region         | Europe / US                             | Client-side only          | S3 (boto3)             |
| **Wasabi**             | Hot                     | Multi-region         | Global (US, Europe, APAC)               | Client-side only          | S3 (boto3)             |

---

### **Pricing Comparison Table**

| **Service**           | **Storage Cost (per GB)** | **Egress Cost (per GB)** | **Free Tier**       | **Notes**                                             |
|------------------------|---------------------------|---------------------------|---------------------|------------------------------------------------------|
| **Amazon S3**          | $0.023 (Standard)         | $0.09                     | 5 GB (12 months)    | Wide region availability, multiple classes           |
| **Backblaze B2**       | $0.005                   | $0.01                     | 10 GB               | Cost-effective, ideal for archival storage           |
| **DigitalOcean Spaces** | $0.01                  | $0.01                     | 250 GB for 2 months | Free bandwidth up to the first 1 TB                  |
| **Google Cloud**        | $0.02 (Nearline)         | $0.12                     | 5 GB (12 months)    | Excellent for hybrid backups                         |
| **IBM Cloud**          | $0.02                   | $0.09                     | Lite plan (25 GB)   | Supports advanced archival options                   |
| **Linode Object Storage** | $0.005                | $0.01                     | None                | Affordable and Akamai-backed                         |
| **Microsoft Azure**    | $0.018 (Cool)            | $0.085                    | $200 for 12 months  | Flexible tiering                                     |
| **UpCloud Object Storage** | $0.01               | $0.07                     | None                | Reliable S3-compatible storage                       |
| **Wasabi**             | $0.0059                 | Free                      | None                | Unlimited egress, good for high traffic              |

---

## **Global Configuration**

The global backup configuration files are stored in:

```bash
/var/xdrago/backup/config/
```

### **Configuration Files**

1. **`paths.txt`**:
   - Defines which global directories are included in backups.
   - Example:
     ```bash
     _SOURCE="/etc /var/www /home /data"
     ```

2. **`include.txt`** and **`exclude.txt`**:
   - Used to include or exclude additional absolute paths.

3. **`include_regexp.txt`** and **`exclude_regexp.txt`**:
   - Use regex patterns for fine-grained control of include/exclude logic.

---

### **Configuration Rules**

1. **Absolute Paths Only**:
   - All paths in configuration files (include/exclude) must be absolute paths starting from `/`.
   - Example:
     - Correct: `/root/projects`
     - Incorrect: `~/projects`

2. **Order of Precedence**:
   - Exclude directives override include directives. If a file is listed in both, it will not be backed up.

---

## **Managing Credentials**

Credentials for global backups are stored in `/var/xdrago/backup/credentials/`. Each file corresponds to a specific storage service.

### **AWS Example (`aws.txt`)**
```bash
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # Example: "us-east-1"
export KEEP_WITHIN="3M"              # Retain backups from the last 3 months
export FULL_BACKUP_FREQUENCY="7D"    # Create a full backup every 7 days
```

### **Permissions**
Ensure all credentials are secured:
```bash
chmod 600 /var/xdrago/backup/credentials/*.txt
```

---

## **Restoring Global Backups**

Restoring global backups follows the same logic as [user backups](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md), except administrators manage the entire system. Use the `multiback` command for global restores:

```bash
multiback restore <SERVICE> <RESTORE_TARGET> <RESTORE_PATH> [RESTORE_TIME]
```

---

### **Restore Examples**

1. **Restore All Global Files to Default Directory**:
   ```bash
   multiback restore aws /var/backups
   ```

2. **Restore a Specific Directory**:
   ```bash
   multiback restore aws /var/backups var/www/example
   ```

3. **Restore from a Specific Time**:
   ```bash
   multiback restore aws /var/backups data/disk/john/static/platform 7D
   ```

---

### **Key Rules for Restores**

1. **Restore Path Must Be Absolute Without Leading Slash**:
   - Paths must reflect the full directory structure used during backups, but cannot start with `/`.
   - Example:
     - Correct: `data/disk/john/static/platform`
     - Incorrect: `/data/disk/john/static/platform`

2. **Restore Target Directory Can Be Relative or Absolute**:
   - Default: `/var/backups/`
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
