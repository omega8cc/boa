## Security Considerations for Multi-Ægir Systems

In a multi-Ægir instance system, all instances utilize the same Nginx server. Consequently, installing a site with the same domain on multiple instances can cause conflicts. **The instances are not aware of each other**, so it is crucial to manage the system responsibly.

It is **imperative** to never grant anyone access to the Ægir **system user** on any Octopus instance. This user has near-root access to **all** sites databases hosted across **all** Octopus instances on the same BOA server. Only provide **restricted shell** access accounts and **non-admin** Ægir control panel accounts to end-users.

## Security Considerations for Node/NPM Access

Given that `node` can be exploited to bypass Limited Shell and pose a significant security risk to the BOA system, it should not be enabled on any BOA system with multiple `lshell` users. Consequently, Node/NPM support is not enabled in BOA by default. To enable it, you must create an empty control file `/root/.allow.node.lshell.cnf` to lift the restriction. In hosted BOA environments, Node/NPM support is available only on dedicated systems such as Phantom and Cluster.

## BOA System Security Features Explained

BOA offers a highly secure hosting environment for Ægir and Drupal sites, featuring comprehensive built-in security monitoring and autonomous attack prevention systems. Below is a list of key features that collectively provide robust protection for all hosted sites. For additional information, consider reading about [running performance or load tests](https://learn.omega8.cc/how-to-run-performance-or-load-test-300).

1. **Encrypted Connections**: Account access is restricted to SSH, SFTP (FTP over SSH), and FTPS (FTP over SSL).
2. **Restricted PHP Scripts**: Only recognized Drupal PHP files are allowed in the BOA secure environment. The web server does not have write access to the website codebase, blocking common attack vectors even for sites with otherwise vulnerable codebases.
3. **Web Server Monitoring**: IP addresses exhibiting DoS-like activity are temporarily blocked for one hour and permanently blocked after repeated offenses. You can [whitelist your IP on the fly](https://omega8.cc/how-firewall-works-is-my-ip-blocked-121) by maintaining an active SSH connection.
4. **Firewall Monitoring**: Repeated failed login attempts for SSH, SFTP, or FTPS result in temporary one-hour blocks, escalating to permanent blocks. Whitelisted IPs are not exempt if abuse is detected.
5. **Load Management**: The web server may be temporarily disabled during high system loads due to undetected DoS attacks. Normal service resumes within 10 seconds after load stabilization.
6. **Port Scan and Flood Protection**: Detected port scans or floods result in temporary one-hour blocks, escalating to permanent blocks after repeated offenses. False positives are detailed in our [How Firewall Works article](https://omega8.cc/how-firewall-works-is-my-ip-blocked-121).
7. **Resource Scaling**: Automated resource scaling on hosted BOA mitigates high load spikes, ensuring system stability during short-term traffic surges.
8. **Perfect Forward Secrecy and HTTP/2**: All HTTPS services utilize Perfect Forward Secrecy and HTTP/2 for enhanced security and speed. Non-supportive browsers default to classic HTTPS with SSL and Perfect Forward Secrecy.
9. **PHP Error Protection**: PHP errors are not displayed in browsers. Debugging can be performed using protected dev domain aliases.
10. **Password Expiration Policy**: SSH, SFTP, and FTPS passwords expire every 90 days and must be updated, even if SSH keys are in use.
11. **Restricted Admin Access**: Admin account access (uid=1) is unavailable in Ægir to prevent potential misuse. Non-admin main account access provides sufficient privileges for safe management in a multi-Ægir environment.
12. **Restricted System Binaries Access**: BOA modifies access permissions to system binaries and commands that could potentially be used as attack vectors by web shells and other intrusion methods, significantly limiting damage potential even for sites running older Drupal versions.

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
