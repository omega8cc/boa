
# Supported Regions and Bucket Creation Guidelines

This document outlines the supported regions and configuration guidelines for the `multiback` (used by root) and `mybackup` (used by regular users) backup scripts. It consolidates details about supported storage services, region IDs, bucket creation behavior, and user configuration steps.

- New PRO Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_ROOT.md)
- New PRO Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_USER.md)
- New PRO Backups Retention Policy Configuration [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_RETENTION.md)
- New PRO Backups Supported Regions and Bucket Creation Guidelines (this document) [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_REGIONS.md)

---

## General Bucket Behavior

Most providers allow **automatic bucket creation** if sufficient credentials and permissions are provided, so you don't need to figure it out yourself. However, some providers (e.g., **Linode**) require **manual bucket creation** before the first backup and others (e.g., **Amazon S3**) are unreliable for automatic creation due to propagation delays between AWS regions. Manual bucket creation is recommended if you use provider known as not reliable or when manual creation is required. Below is a detailed breakdown for each provider.

---

### Supported Regions by Service

The following regions are supported across various storage services:

---

#### **Wasabi Hot Cloud Storage (wasabi)**

- **Bucket Creation:** Supported automatically.
- **Supported Regions:**

| Data Center Location     | Region Code     |
|--------------------------|-----------------|
| Virginia, USA            | `us-east-1`     |
| Virginia, USA            | `us-east-2`     |
| Oregon, USA              | `us-west-1`     |
| Plano, Texas, USA        | `us-central-1`  |
| Toronto, Canada          | `ca-central-1`  |
| London, England          | `eu-west-1`     |
| Paris, France            | `eu-west-2`     |
| Amsterdam, Netherlands   | `eu-central-1`  |
| Frankfurt, Germany       | `eu-central-2`  |
| Milan, Italy             | `eu-south-1`    |
| Tokyo, Japan             | `ap-northeast-1`|
| Osaka, Japan             | `ap-northeast-2`|
| Singapore                | `ap-southeast-1`|
| Sydney, Australia        | `ap-southeast-2`|

For more, refer to [Wasabi Regions](https://wasabi.com/company/storage-regions).

---

#### **Backblaze B2 (b2)**

- **Bucket Creation:** Automatic with proper credentials.
- **Supported Regions:**

| Data Center Location    | Region Code  |
|-------------------------|--------------|
| Amsterdam, Netherlands  | `eu-central` |
| Reston, Virginia        | `us-east`    |
| Sacramento, California  | `us-west`    |
| Stockton, California    | `us-west`    |
| Phoenix, Arizona        | `us-west`    |
| Toronto, Ontario        | `ca-east`    |

Backblaze currently has data centers in Sacramento, California; Stockton, California; Phoenix, Arizona; Reston, Virginia; Amsterdam, Netherlands and Toronto, Ontario.

Accounts that use the US-West region store data in both the Sacramento and Phoenix data centers.

Accounts that use the EU-Central region store data in the Amsterdam data center. If you are in the European Union or in or near Europe, then the transfer rate for Backblaze Computer Backup and Backblaze B2 should have less latency. As a result, you can get better transfer rates and more bandwidth per thread.

Accounts that use the US-East region store data in the Reston, Virginia data center. The data center is operated by Coresight, a well-known and respected data center operator.

The newest region, known as CA East, is located in Toronto, Ontario.

When you create a Backblaze B2 account, you choose whether that account’s data is stored in the US East region, the US West region, the EU Central region or the Canada East region. The choice that you make during account creation dictates where all of that account’s data is stored. After you create your Backblaze B2 account, you cannot change your selected region.

This means that you need separate accounts per region, if needed and the region codes in the table above are for informational purposes only.

More details available at the [Backblaze B2 Regions documentation](https://www.backblaze.com/docs/cloud-storage-data-regions).

---

#### **DigitalOcean Spaces (do-spaces)**

- **Bucket Creation:** Automatic if credentials have write permissions.
- **Supported Regions:**

| Data Center Location       | Region Code |
|----------------------------|-------------|
| New York City, United States | `nyc3`    |
| San Francisco, United States | `sfo2`    |
| San Francisco, United States | `sfo3`    |
| Amsterdam, Netherlands     | `ams3`      |
| Singapore                  | `sgp1`      |
| London, United Kingdom     | `lon1`      |
| Frankfurt, Germany         | `fra1`      |
| Toronto, Canada            | `tor1`      |
| Bangalore, India           | `blr1`      |
| Sydney, Australia          | `syd1`      |

For the most current and detailed information, please refer to DigitalOcean's [Regional Availability documentation](https://docs.digitalocean.com/platform/regional-availability/).

Refer to [DigitalOcean Spaces Regions documentation](https://docs.digitalocean.com/platform/regional-availability/) for details.

---

#### **Amazon Web Services (aws, aws-one-zone, aws-standard-ia)**

- **Bucket Creation:** Supported but unreliable for automatic creation due to propagation delays between AWS regions. Manual bucket creation is recommended -- see Required Bucket Naming Convention below.
- **Supported Regions:**

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

For more details, refer to the [AWS Regional Endpoints documentation](https://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region).

---

#### **Google Cloud Storage (gcs)**

- **Bucket Creation:** Automatic if credentials have write permissions.
- **Supported Regions:** (not all are listed here)

| Data Center Location                 | Region Code     |
|--------------------------------------|-----------------|
| Iowa (US Central)                    | `us-central1`   |
| South Carolina (US East)             | `us-east1`      |
| Northern Virginia (US East)          | `us-east4`      |
| Oregon (US West)                     | `us-west1`      |
| Los Angeles (US West)                | `us-west2`      |
| Salt Lake City (US West)             | `us-west3`      |
| Las Vegas (US West)                  | `us-west4`      |
| Montreal (Canada)                    | `northamerica-northeast1` |
| São Paulo (South America)            | `southamerica-east1`      |
| Santiago (South America)             | `southamerica-west1`      |
| Finland (Europe)                     | `europe-north1`           |
| Belgium (Europe)                     | `europe-west1`            |
| London (Europe)                      | `europe-west2`            |
| Frankfurt (Europe)                   | `europe-west3`            |
| Netherlands (Europe)                 | `europe-west4`            |
| Zurich (Europe)                      | `europe-west6`            |
| Warsaw (Europe)                      | `europe-central2`         |
| Sydney (Australia)                   | `australia-southeast1`    |
| Jakarta (Indonesia)                  | `asia-southeast2`         |
| Singapore                            | `asia-southeast1`         |
| Taiwan                               | `asia-east1`              |
| Hong Kong                            | `asia-east2`              |
| Tokyo                                | `asia-northeast1`         |
| Osaka                                | `asia-northeast2`         |
| Seoul                                | `asia-northeast3`         |
| Mumbai                               | `asia-south1`             |
| Delhi                                | `asia-south2`             |

For complete list please refer to the [Google Cloud Storage Locations documentation](https://cloud.google.com/storage/docs/locations).

---

#### **Microsoft Azure Blob Storage (azure)**

- **Bucket Creation:** Supported automatically with appropriate contributor access.
- **Supported Regions:** (not all are listed here)

| Region Name                          | Region Code     |
|--------------------------------------|-----------------|
| East US                              | `eastus`        |
| East US 2                            | `eastus2`       |
| Central US                           | `centralus`     |
| North Central US                     | `northcentralus`|
| South Central US                     | `southcentralus`|
| West US                              | `westus`        |
| West US 2                            | `westus2`       |
| West US 3                            | `westus3`       |
| Canada Central                       | `canadacentral` |
| Canada East                          | `canadaeast`    |
| Brazil South                         | `brazilsouth`   |
| Brazil Southeast                     | `brazilsoutheast`|
| Europe North                         | `northeurope`   |
| Europe West                          | `westeurope`    |
| France Central                       | `francecentral` |
| France South                         | `francesouth`   |
| Germany North                        | `germanynorth`  |
| Germany West Central                 | `germanywestcentral`|
| Switzerland North                    | `switzerlandnorth`|
| Switzerland West                     | `switzerlandwest`|
| UK South                             | `uksouth`       |
| UK West                              | `ukwest`        |
| Australia East                       | `australiaeast` |
| Australia Southeast                  | `australiasoutheast`|
| Australia Central                    | `australiacentral`|

For detailed regions, refer to [Azure Blob Storage Regions](https://azure.microsoft.com/en-us/global-infrastructure/geographies/).

---

#### **Cloudflare R2 Object Storage (cloudflare)**

- **Bucket Creation:** Must be **manually created** before use -- see Required Bucket Naming Convention below.
- **Supported Regions:**

| Region Name            | Location Hints  |
|------------------------|-----------------|
| Western North America  | `wnam`          |
| Eastern North America  | `enam`          |
| Western Europe         | `weur`          |
| Eastern Europe         | `eeur`          |
| Asia-Pacific           | `apac`          |
| Oceania                | `oc`            |

When you create a new bucket, the data location is set to Automatic by default. Currently, this option chooses a bucket location in the closest available region to the create bucket request based on the location of the caller.

Location Hints are optional parameters you can provide during bucket creation to indicate the primary geographical location you expect data will be accessed from.

Using Location Hints can be a good choice when you expect the majority of access to data in a bucket to come from a different location than where the create bucket request originates. Keep in mind Location Hints are a best effort and not a guarantee, and they should only be used as a way to optimize performance by placing regularly updated content closer to users.

More details available at the [Cloudflare R2 Object Storage documentation](https://developers.cloudflare.com/r2/reference/data-location/#location-hints).

---

#### **IBM Cloud Object Storage (ibm)**

- **Bucket Creation:** Must be **manually created** before use -- see Required Bucket Naming Convention below.
- **Supported Regions:** (not all are listed here)

| Region Name             | Region Code  |
|-------------------------|--------------|
| US Cross Region         | `us`         |
| US South (Dallas)       | `us-south`   |
| US East (Washington DC) | `us-east`    |
| EU Cross Region         | `eu`         |
| EU Central (Frankfurt)  | `eu-de`      |
| EU North (Oslo)         | `eu-north`   |
| EU West (Milan)         | `eu-it`      |
| Asia Pacific Cross Region | `ap`       |
| Asia Pacific North (Tokyo) | `jp-tok`  |
| Asia Pacific South (Sydney) | `au-syd` |

For more details, refer to the [IBM Cloud Regions documentation](https://cloud.ibm.com/docs/cloud-object-storage?topic=cloud-object-storage-endpoints).

---

#### **Akamai Object Storage (linode)**

- **Bucket Creation:** Must be **manually created** before use -- see Required Bucket Naming Convention below.
- **Supported Regions:**

| Data Center Location       | Region Code      |
|----------------------------|------------------|
| Amsterdam, Netherlands     | `nl-ams-1`       |
| Atlanta, GA, USA           | `us-southeast-1` |
| Chennai, India             | `in-maa-1`       |
| Chicago, IL, USA           | `us-ord-1`       |
| Frankfurt, Germany         | `eu-central-1`   |
| Jakarta, Indonesia         | `id-cgk-1`       |
| Los Angeles, CA, USA       | `us-lax-1`       |
| Madrid, Spain              | `es-mad-1`       |
| Miami, FL, USA             | `us-mia-1`       |
| Milan, Italy               | `it-mil-1`       |
| Newark, NJ, USA            | `us-east-1`      |
| Osaka, Japan               | `jp-osa-1`       |
| Paris, France              | `fr-par-1`       |
| São Paulo, Brazil          | `br-gru-1`       |
| Seattle, WA, USA           | `us-sea-1`       |
| Singapore                  | `ap-south-1`     |
| Stockholm, Sweden          | `se-sto-1`       |
| Washington, DC, USA        | `us-iad-1`       |

For more detailed information, please refer to Akamai's official [Object Storage documentation](https://techdocs.akamai.com/cloud-computing/docs/object-storage).

---

### Required Bucket Naming Convention

#### Root (`multiback`) Behavior:
- Ensure buckets are created for each service and region used.
- Use `/root/.remote_backups/credentials/` to store credentials.

#### User (`mybackup`) Behavior:
- Buckets are associated with the Octopus system user running the command.
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

### Configuration Overview

#### Root Configuration (`multiback`)
For system-wide backups managed by `multiback`, ensure that your configuration includes the necessary credentials in `/root/.remote_backups/credentials/` directory. More details in New Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_ROOT.md)

#### User Configuration (`mybackup`)
Regular users should place their backup configurations in the `~/static/control/remote_backups/credentials/` directory. The `mybackup` script automatically uses these credentials to restore backups for the current user. More details in New Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/BACKUP_USER.md)

---

This document includes the complete regions list per service and ensures you have the required configurations for `multiback` and `mybackup` scripts. For further details, refer to the README files generated during installation or contact your system administrator.

The README files for non-root users are available in `~/static/control/remote_backups/credentials/README.txt` and `~/static/control/remote_backups/config/README.txt`

