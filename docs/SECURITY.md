
## Security Considerations for Multi-Ægir Systems

In a multi-Ægir-instance system, all instances will use the same Nginx server. This means that attempting to install a site with the same domain on two or more instances can affect others. **The instances will not be aware of each other**, so it is your responsibility to manage the system wisely.

It is **critically important** to never give anyone access to the Ægir **system user** on any Octopus instance. This user has almost root access to **all** sites databases hosted across **all** Octopus instances on the same BOA server. Only provide **limited shell** access accounts and **non-admin** Ægir control panel accounts to end-users.

## Security Considerations for Node/NPM Access

Since `node` can be used to easily escape Limited Shell and thus open a very serious security hole in the BOA system, it should not be enabled on any BOA system with many `lshell` users. For this reason Node/NPM support is not enabled in BOA by default and requires that you create an empty control file `/root/.allow.node.lshell.cnf` to remove the limitation. On hosted BOA Node/NPM support is available only on dedicated systems like Phantom and Cluster.

## BOA System Security Features Explained

BOA provides very secure hosting environment for Ægir and Drupal sites, which includes comprehensive built-in security monitoring and autonomous attack prevention systems. Below is a list of the most important features, which together provide robust protection for all hosted sites. You may also want to read about [running performance or load tests](https://learn.omega8.cc/how-to-run-performance-or-load-test-300).

1. **Encrypted Connections**: Only SSH, SFTP (FTP over SSH), and FTPS (FTP over SSL) accounts are created.
2. **Restricted PHP Scripts**: Only known Drupal PHP files are permitted in the BOA secure environment and web server doesn't have write access to website codebase, which blocks all popular attack vectors even for sites running otherwise vulnerable codebase.
3. **Web Server Monitoring**: IPs causing DoS-like activity are temporarily blocked for one hour and permanently after repeated offenses. You can [whitelist your IP on the fly](https://omega8.cc/how-firewall-works-is-my-ip-blocked-121) by keeping your SSH connection active.
4. **Firewall Monitoring**: Repeated failed login attempts for SSH, SFTP, or FTPS result in temporary one-hour blocks, escalating to permanent blocks. Previously whitelisted IPs are not honored if abuse is detected.
5. **Load Management**: The web server may be temporarily disabled during high system loads due to undetected DoS attacks. Normal service resumes within 10 seconds of load stabilization.
6. **Port Scan and Flood Protection**: Detected port scans or floods lead to temporary one-hour blocks, escalating to permanent blocks after repeated offenses. False positives are explained in our [How Firewall Works article](https://omega8.cc/how-firewall-works-is-my-ip-blocked-121).
7. **Resource Scaling**: Automated resource scaling on hosted BOA mitigates high load spikes, ensuring system stability during short-term traffic surges.
8. **Perfect Forward Secrecy and HTTP/2**: All HTTPS services use Perfect Forward Secrecy and HTTP/2 for enhanced security and speed. Non-supportive browsers default to classic HTTPS with SSL and Perfect Forward Secrecy.
9. **PHP Error Protection**: PHP errors are not displayed in browsers. Debugging can be done using protected dev domain aliases.
10. **Password Expiration Policy**: SSH, SFTP, and FTPS passwords expire every 90 days and must be updated, even if SSH keys are used.
11. **Restricted Admin Access**: Admin account access (uid=1) is unavailable in Ægir to prevent potential misuse. Non-admin main account access provides sufficient privileges for safe management in the multi-Ægir environment.
12. **Restricted System Binaries Access**: BOA modifies access permissions to all system binaries and commands that could be potentially used as attack vectors by web shells and other typical intrusion methods. This greatly limits the possible damage even for sites running old Drupal versions.

## Customizing PHP Function Restrictions

### Option in `/root/.barracuda.cnf`

You can define a custom list of functions to disable in addition to those already denied in the system-level `disable_functions`.

```ini
_PHP_FPM_DENY=""
```

**Note:** If this option is left empty, BOA will deny access to the function:

```ini
passthru
```

If `_PHP_FPM_DENY` is **not** empty, its value will **replace** the default `passthru`, so any denied function must be listed explicitly.

**WARNING!** Do not add `shell_exec` here, or you will break cron for all sites, including those hosted on all Satellite Instances. The `shell_exec` function is also required by Collectd Graph Panel, if installed.

This option affects only the Ægir Master Instance plus all scripts running outside of Octopus Satellite Instances.

**Example:**

```ini
_PHP_FPM_DENY="passthru,popen,system"
```

While this improves security, it can also break modules that rely on any disabled functions.

### Option in `/root/.USER.octopus.cnf`

You can define a custom list of functions to disable in addition to those already denied in the system-level `disable_functions`.

```ini
_PHP_FPM_DENY=""
```

**Note:** If this option is left empty, BOA will deny access to the function:

```ini
passthru
```

If `_PHP_FPM_DENY` is **not** empty, its value will **replace** `passthru`, so any denied function must be listed explicitly.

This option affects only this Satellite Instance and is not influenced by the same option set in the Barracuda Master.

**Example:**

```ini
_PHP_FPM_DENY="system,exec,shell_exec"
```

While this improves security, it can also break modules that rely on any disabled functions.

## Strict Binary Permissions

### Option in `/root/.barracuda.cnf`

We highly recommend enabling this option to improve system security when certain PHP functions, especially `exec`, `passthru`, `shell_exec`, `system`, `proc_open`, `popen`, are not disabled via the `_PHP_FPM_DENY` option above.

```ini
_STRICT_BIN_PERMISSIONS=YES
```

**WARNING!** This option is very aggressive and can break any extra service or binary you have installed which BOA doesn't manage and the binary has a system group set to 'root'. BOA will not touch any binary which has a non-root group or has setgid or setuid permissions.

**Recommended setting:**

```ini
_STRICT_BIN_PERMISSIONS=YES
```
