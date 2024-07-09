# Support for New Relic Monitoring with Per Octopus Instance License Key

`~/static/control/newrelic.info`

This new feature will disable global New Relic monitoring by deactivating the server-level license key. This allows it to safely auto-enable or auto-disable every 5 minutes, but per Octopus instance—for all sites hosted on the given instance—when a valid license key is present in the special `~/static/control/newrelic.info` control file.

Please note that a valid license key is a 40-character hexadecimal string that New Relic provides when you sign up for an account.

## Disabling New Relic Monitoring

To disable New Relic monitoring for the Octopus instance, simply delete its `~/static/control/newrelic.info` control file and wait a few minutes.

## Important Considerations

On a self-hosted BOA, you still need to add your valid license key as `_NEWRELIC_KEY` in the `/root/.barracuda.cnf` file and run a system upgrade with at least `barracuda up-lts` first. This step is not required on Omega8.cc hosted service, where the New Relic agent is already pre-installed for you.

For more information, please visit the [documentation](https://github.com/omega8cc/boa/tree/5.x-dev/docs).

