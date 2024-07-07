
# Security Considerations for Multi-Aegir-Instance Systems

In a multi-Aegir-instance system, all instances will use the same Nginx server. This means that attempting to install a site with the same domain on two or more instances can affect others. The instances will not be aware of each other, so it is your responsibility to manage the system wisely.

It is critically important to never give anyone access to the Aegir system user on any Octopus instance. This user has almost root access to all site databases hosted across all Octopus instances on the same BOA server. Only provide limited shell access accounts and non-admin Aegir control panel accounts to end-users.

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

This option affects only the Aegir Master Instance plus all scripts running outside of Octopus Satellite Instances.

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
