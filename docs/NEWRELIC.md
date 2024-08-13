## New Relic Monitoring with Octopus/Platform/Site Configuration

This feature disables global New Relic monitoring by deactivating the server-level license key. This allows it to safely auto-enable or auto-disable every 5 minutes, but per Octopus instance—for all sites hosted on the given instance or per platform or per site via INI directives—when a valid license key is present in the special `~/static/control/newrelic.info` control file.

### INI (platform level) directive for New Relic

```text
;enable_newrelic_integration = FALSE
;;
;;  When set to TRUE it will enable New Relic monitoring for all sites on this
;;  platform, but only if there is a valid New Relic license key present in the
;;  ~/static/control/newrelic.info control file.
```

See also [more details in platform/INI.md docs](https://github.com/omega8cc/boa/blob/5.x-dev/docs/ini/platform/INI.md)

### INI (site level) directive for New Relic

```text
;enable_newrelic_integration = FALSE
;;
;;  When set to TRUE it will enable New Relic monitoring for this site only.
;;  You still need a valid New Relic license key present in the control file:
;;  ~/static/control/newrelic.info
```

See also [more details in site/INI.md docs](https://github.com/omega8cc/boa/blob/5.x-dev/docs/ini/site/INI.md)

Please note that a valid license key is a 40-character hexadecimal string that New Relic provides when you sign up for an account.

### Disabling New Relic Monitoring

To disable New Relic monitoring for all sites on the Octopus instance, simply delete its `~/static/control/newrelic.info` control file and wait a few minutes.

### Important Considerations

On a self-hosted BOA, you still need to add your valid license key as `_NEWRELIC_KEY` in the `/root/.barracuda.cnf` file and run a system upgrade with `barracuda up-lts system` first. This step is not required on Omega8.cc hosted service, where the New Relic agent is already pre-installed for you.

For more information, please visit the [documentation](https://github.com/omega8cc/boa/tree/5.x-dev/docs).

