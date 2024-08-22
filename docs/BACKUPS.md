# Automated, encrypted backups to Amazon S3 bucket

  * This feature is available on self-hosted **BOA** and hosted Phantom+ Engines.
  * Note that provided `backboa` tool uses symmetric password-only encryption.
  * You can configure AWS Region you prefer to use and Backup Rotation policy.

  It will archive all directories required to restore your data (sites files,
  databases archives, Nginx configuration and more) on a freshly installed BOA:

```text
    /etc /var/aegir /var/www /home /data
```

  It will start to run nightly at 1:15 AM (server time) only once you will add
  all required `_AWS_*` variables in the `/root/.barracuda.cnf` file and run the
  special command `backboa install` while logged in as root.

  Full backups are scheduled on Sunday, unless `_AWS_FLC` is set to custom value.

  To restore any file from backups created with `backboa` tool, you can use
  the same script on the same or any other **BOA** server.

  Please read below for details.


## CONFIGURATION

  Add listed below four (4) required lines to your `/root/.barracuda.cnf` file.
  Required lines are marked with `[R]` and optional with `[O]`:

```ini
    _AWS_KEY='Your AWS Access Key ID'     ### [R] From your AWS S3 settings
    _AWS_SEC='Your AWS Secret Access Key' ### [R] From your AWS S3 settings
    _AWS_PWD='Your Secret Password'       ### [R] Generate with 'openssl rand -base64 32'
    _AWS_REG='Your AWS Region ID'         ### [R] By default 'us-east-1'

    _AWS_TTL='Your Backup Rotation'       ### [O] By default '30D'
    _AWS_FLC='Your Backup Full Cycle'     ### [O] By default '7D'
    _AWS_VLV='Your Backup Log Verbosity'  ### [O] By default 'warning' -- [ewnid]
    _AWS_EXB='Exclude Aegir Backups'      ### [O] By default 'YES' -- can be YES/NO
```

    For more detailed include/exclude configuration see notes further below.

    Supported values to use as `_AWS_REG` (the symbol after the # comment):

```ini
      Africa (Cape Town)         # af-south-1
      Asia Pacific (Hong Kong)   # ap-east-1
      Asia Pacific (Hyderabad)   # ap-south-2
      Asia Pacific (Jakarta)     # ap-southeast-3
      Asia Pacific (Melbourne)   # ap-southeast-4
      Asia Pacific (Mumbai)      # ap-south-1
      Asia Pacific (Osaka)       # ap-northeast-3
      Asia Pacific (Seoul)       # ap-northeast-2
      Asia Pacific (Singapore)   # ap-southeast-1
      Asia Pacific (Sydney)      # ap-southeast-2
      Asia Pacific (Tokyo)       # ap-northeast-1
      Canada (Central)           # ca-central-1
      Canada West (Calgary)      # ca-west-1
      Europe (Frankfurt)         # eu-central-1
      Europe (Ireland)           # eu-west-1
      Europe (London)            # eu-west-2
      Europe (Milan)             # eu-south-1
      Europe (Paris)             # eu-west-3
      Europe (Spain)             # eu-south-2
      Europe (Stockholm)         # eu-north-1
      Europe (Zurich)            # eu-central-2
      Israel (Tel Aviv)          # il-central-1
      Middle East (Bahrain)      # me-south-1
      Middle East (UAE)          # me-central-1
      South America (São Paulo)  # sa-east-1
      US East (N. Virginia)      # us-east-1
      US East (Ohio)             # us-east-2
      US West (N. California)    # us-west-1
      US West (Oregon)           # us-west-2

      ### Special regions, see: https://aws.amazon.com/govcloud-us/

      AWS GovCloud (US-East)     # us-gov-east-1
      AWS GovCloud (US-West)     # us-gov-west-1
```

    Source: http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region

    You have to use S3 Console at https://console.aws.amazon.com/s3/home
    (before attempting to run initial backup!) to create S3 bucket in the
    desired region with correct name as shown below.

    Replace only the `srv-foo-bar` part after `daily-boa-` static prefix with
    your system hostname, typically displayed when you type `uname -n`
    where all dots are replaced with dashes, for compatibility reasons:

      `daily-boa-srv-foo-bar`

    While duplicity should be able to create new bucket on demand, in practice
    it almost never works due to typical delays between various AWS regions.

    Please run: `backboa test` to make sure that the connection works.

## INSTALLATION

```sh
  $ backboa install
```

## USAGE

```sh
  $ backboa backup
  $ backboa cleanup
  $ backboa list
  $ backboa status
  $ backboa test
  $ backboa restore file [time] destination
  $ backboa retrieve file [time] destination hostname
```

## RESTORE EXAMPLES

  Note: Be careful while restoring not to prepend a slash to the path!

  Restoring a single file to `tmp/`

```sh
  $ backboa restore data/disk/o1/backups/foo.tar.gz tmp/foo.tar.gz
```

  Restoring an older version of a directory to `tmp/` - interval or full date

```sh
  $ backboa restore data/disk/o1/backups 7D8h8s tmp/backups
  $ backboa restore data/disk/o1/backups 2014/11/11 tmp/backups
```

  Restoring data on a different server

```sh
  $ backboa retrieve data/disk/o1/backups/foo.tar.gz tmp/foo.tar.gz srv.foo.bar
  $ backboa retrieve data/disk/o1/backups 2014/11/11 tmp/backups srv.foo.bar
```

## NOTES

  The `srv.foo.bar` is a hostname of the BOA system backed up before.
  In the `retrieve` mode it will use the `_AWS_*` variables configured
  in the current system `/root/.barracuda.cnf` file - so make sure to edit
  this file to set/replace temporarily all four required `_AWS_*` variables
  used originally on the host you are retrieving data from! You should
  keep them secret and manage in your offline password manager app.

  There is also another tool to run extra remote backups: `duobackboa`.
  The only differences are listed below. If you wish to receive daily
  backup reports generated by `duobackboa` via email, please add also
  `_MY_EMAIL="my@email"` line in the `/root/.duobackboa.cnf` file, if used.

  * The extra script filename and command: `duobackboa`
  * Separate configuration file: `/root/.duobackboa.cnf`
  * S3 bucket naming convention: `daily-remote-srv-foo-bar`
  * Cron entry set to start at 5:55 AM (server time)
  * Full backups are scheduled on Saturday

  The `duobackboa` script has also built-in how-to: just type `duobackboa`
  when logged in as system root.

  You can use a file that lists folders and files that should be included
  or excluded from the backups.

  * If `/root/.backboa.exclude` exists it will be passed as the
    `--exclude-filelist` parameter of duplicity
  * If `/root/.backboa.include` exists it will be passed as the
    `--include-filelist` parameter of duplicity

  Note: for `duobackboa` the optional files should use these filenames:

  * If `/root/.duobackboa.exclude` exists it will be passed as the
    `--exclude-filelist` parameter of duplicity
  * If `/root/.duobackboa.include` exists it will be passed as the
    `--include-filelist` parameter of duplicity

  The format of both files should be as described in the documentation of
  duplicity:

  See also: https://duplicity.gitlab.io
