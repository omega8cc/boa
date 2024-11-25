
# Supported Regions and Bucket Creation Guidelines

This document outlines the supported regions and configuration guidelines for the `multiback` (used by root) and `mybackup` (used by regular users) backup scripts. It consolidates details about supported storage services, region IDs, bucket creation behavior, and user configuration steps.

- New Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_ROOT.md)
- New Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md)
- New Backups Retention Policy Configuration [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_RETENTION.md)
- Supported Regions and Bucket Creation Guidelines (this document) [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_REGIONS.md)

---

### Configuration Overview

#### Root Configuration (`multiback`)
For system-wide backups managed by `multiback`, ensure that your configuration includes the necessary credentials in `/var/xdrago/backup/credentials/` directory. More details in New Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_ROOT.md)

#### User Configuration (`mybackup`)
Regular users should place their backup configurations in the `~/static/control/remote_backups/credentials/` directory. The `mybackup` script automatically uses these credentials to restore backups for the current user. More details in New Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md)

---

### Supported Regions by Service

The following regions are supported across various storage services:

---

#### **Amazon Web Services (AWS S3)**

| Region Name                  | Region Code       |
|------------------------------|-------------------|
| Africa (Cape Town)           | `af-south-1`      |
| Asia Pacific (Hong Kong)     | `ap-east-1`       |
| Asia Pacific (Hyderabad)     | `ap-south-2`      |
| Asia Pacific (Jakarta)       | `ap-southeast-3`  |
| Asia Pacific (Melbourne)     | `ap-southeast-4`  |
| Asia Pacific (Mumbai)        | `ap-south-1`      |
| Asia Pacific (Osaka)         | `ap-northeast-3`  |
| Asia Pacific (Seoul)         | `ap-northeast-2`  |
| Asia Pacific (Singapore)     | `ap-southeast-1`  |
| Asia Pacific (Sydney)        | `ap-southeast-2`  |
| Asia Pacific (Tokyo)         | `ap-northeast-1`  |
| Canada (Central)             | `ca-central-1`    |
| Canada West (Calgary)        | `ca-west-1`       |
| Europe (Frankfurt)           | `eu-central-1`    |
| Europe (Ireland)             | `eu-west-1`       |
| Europe (London)              | `eu-west-2`       |
| Europe (Milan)               | `eu-south-1`      |
| Europe (Paris)               | `eu-west-3`       |
| Europe (Spain)               | `eu-south-2`      |
| Europe (Stockholm)           | `eu-north-1`      |
| Europe (Zurich)              | `eu-central-2`    |
| Israel (Tel Aviv)            | `il-central-1`    |
| Middle East (Bahrain)        | `me-south-1`      |
| Middle East (UAE)            | `me-central-1`    |
| South America (São Paulo)    | `sa-east-1`       |
| US East (N. Virginia)        | `us-east-1`       |
| US East (Ohio)               | `us-east-2`       |
| US West (N. California)      | `us-west-1`       |
| US West (Oregon)             | `us-west-2`       |
| AWS GovCloud (US-East)       | `us-gov-east-1`   |
| AWS GovCloud (US-West)       | `us-gov-west-1`   |

---

#### **Backblaze B2 (b2)**

| Region Name  | Region Code |
|--------------|-------------|
| Global       | `global`    |

---

#### **Google Cloud Storage (GCS)**

| Region Name                   | Region Code     |
|-------------------------------|-----------------|
| Americas (Iowa)               | `us-central1`   |
| Americas (South Carolina)     | `us-east1`      |
| Americas (Northern Virginia)  | `us-east4`      |
| Americas (Oregon)             | `us-west1`      |
| Americas (Los Angeles)        | `us-west2`      |
| Americas (Salt Lake City)     | `us-west3`      |
| Americas (Las Vegas)          | `us-west4`      |
| Asia Pacific (Tokyo)          | `asia-northeast1` |
| Asia Pacific (Osaka)          | `asia-northeast2` |
| Asia Pacific (Seoul)          | `asia-northeast3` |
| Asia Pacific (Mumbai)         | `asia-south1`   |
| Asia Pacific (Delhi)          | `asia-south2`   |
| Asia Pacific (Singapore)      | `asia-southeast1` |
| Asia Pacific (Jakarta)        | `asia-southeast2` |
| Europe (Frankfurt)            | `europe-central2` |
| Europe (Belgium)              | `europe-west1`  |
| Europe (London)               | `europe-west2`  |
| Europe (Frankfurt)            | `europe-west3`  |
| Europe (Netherlands)          | `europe-west4`  |
| Europe (Finland)              | `europe-north1` |
| South America (São Paulo)     | `southamerica-east1` |

---

#### **Microsoft Azure Blob Storage (azure)**

| Region Name                    | Region Code        |
|--------------------------------|--------------------|
| East US                        | `eastus`          |
| East US 2                      | `eastus2`         |
| Central US                     | `centralus`       |
| North Central US               | `northcentralus`  |
| South Central US               | `southcentralus`  |
| West US                        | `westus`          |
| West US 2                      | `westus2`         |
| Canada Central                 | `canadacentral`   |
| Canada East                    | `canadaeast`      |
| North Europe                   | `northeurope`     |
| West Europe                    | `westeurope`      |
| UK South                       | `uksouth`         |
| UK West                        | `ukwest`          |
| France Central                 | `francecentral`   |
| France South                   | `francesouth`     |
| Germany Central                | `germanycentral`  |
| Germany North                  | `germanynorth`    |
| Australia East                 | `australiaeast`   |
| Australia Southeast            | `australiasoutheast` |
| Japan East                     | `japaneast`       |
| Japan West                     | `japanwest`       |

---

#### **UpCloud Object Storage**

| Region Name         | Region Code   |
|---------------------|---------------|
| Amsterdam           | `ams`         |
| Frankfurt           | `fra`         |
| Helsinki            | `hel`         |
| London              | `lon`         |
| San Jose            | `sjc`         |
| Singapore           | `sin`         |
| Sydney              | `syd`         |

---

#### **IBM Cloud Object Storage (ibm)**

| Region Name                   | Region Code     |
|-------------------------------|-----------------|
| Dallas (US South)             | `us-south`      |
| Washington DC (US East)       | `us-east`       |
| Frankfurt (Germany)           | `eu-de`         |
| London (United Kingdom)       | `eu-gb`         |
| Sydney (Australia)            | `au-syd`        |
| Tokyo (Japan)                 | `jp-tok`        |

---

#### **Wasabi**

| Region Name        | Region Code |
|--------------------|-------------|
| US East 1          | `us-east-1` |
| US West 1          | `us-west-1` |
| EU Central 1       | `eu-central-1` |
| Asia Pacific North 1 | `ap-northeast-1` |

---

#### **DigitalOcean Spaces (do_spaces)**

| Region Name  | Region Code |
|--------------|-------------|
| New York 3   | `nyc3`      |
| Amsterdam 3  | `ams3`      |
| Singapore 1  | `sgp1`      |

---

#### **Linode Object Storage**

| Region Name         | Region Code  |
|---------------------|--------------|
| Newark              | `us-east`    |
| Dallas              | `us-central` |
| Fremont             | `us-west`    |
| Frankfurt           | `eu-central` |

---

### Bucket Creation Behavior

#### Root (`multiback`) Behavior:
- Ensure buckets are created for each service and region used.
- Use `/var/xdrago/backup/credentials/` to store credentials.

#### User (`mybackup`) Behavior:
- Buckets are associated with the Octopus system user running the command.
- User-specific bucket names follow the convention: `back-to-USER-HOSTNAME-REGIONCODE`.
- The `USER` is your Aegir system user as visible in the `/data/disk/USER/static` path.
- The `HOSTNAME` is your system hostname, but with dots replaced by hyphens.
- The `REGIONCODE` is the symbol of the region from the vendors tables above.

How to determine correct `HOSTNAME` and `USER` to be used as your Bucket name?

It's easy to find because your Aegir URL is actually `USER`.`HOSTNAME` -- For example in `o123.fr8.eu.aegir.cc` the `o123` is `USER` and `fr8.eu.aegir.cc` is a `HOSTNAME`

However, when used in the bucket name, it becomes `back-to-USER-HOSTNAME-REGIONCODE`, so in this example: `back-to-o1-fr8-eu-aegir-cc-eu-central-1`

---

This document includes the complete regions list per service and ensures you have the required configurations for `multiback` and `mybackup` scripts. For further details, refer to the README files generated during installation or contact your system administrator.

The README files for non-root users are available in `~/static/control/remote_backups/credentials/README.txt` and `~/static/control/remote_backups/config/README.txt`



