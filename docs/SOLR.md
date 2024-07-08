
# SOLR Management Documentation

You can easily add, update, or delete Solr cores powered by the very fast Jetty server. This process is fully automated and can be managed via the site-level active INI file. Ensure Solr is already installed on the system with the `SR7` and `SR4` keywords in the `_XTRAS_LIST` in the `/root/.barracuda.cnf` file.

There are three INI variables you can use to control the Solr automated setup:
- `solr_integration_module`
- `solr_update_config`
- `solr_custom_config`

Refer to the documentation below, which is also available in every site's INI template. For more information on how to control BOA on site and platform levels via INI files, check our [documentation](https://github.com/omega8cc/boa/tree/5.x-dev/docs/https://omega8.cc/node/293).

> **NOTE:** This feature works only for site-level INI files because Solr cores belong to sites, not platforms.

## Solr Core Configuration

This option allows you to activate Solr core configuration for the site. Both Solr 7 and Solr 4 powered by the Jetty 9 server are available. Supported integration modules are limited to the latest versions of either `search_api_solr` (D9/Solr7, D8/Solr7, and D7/Solr7) or `apachesolr` (D7/Solr4 and D6/Solr4).

Currently supported versions are listed below:
- [search_api_solr-4.2.6.tar.gz (D9.2+)](https://ftp.drupal.org/files/projects/search_api_solr-4.2.6.tar.gz)
- [search_api_solr-4.1.12.tar.gz (D8.8+)](https://ftp.drupal.org/files/projects/search_api_solr-4.1.12.tar.gz)
- [search_api_solr-7.x-1.15.tar.gz](https://ftp.drupal.org/files/projects/search_api_solr-7.x-1.15.tar.gz)
- [apachesolr-7.x-1.12.tar.gz](https://ftp.drupal.org/files/projects/apachesolr-7.x-1.12.tar.gz)
- [apachesolr-6.x-3.1.tar.gz](https://ftp.drupal.org/files/projects/apachesolr-6.x-3.1.tar.gz)

Note that you still need to add the preferred integration module along with any dependencies to your codebase. This feature doesn't modify your platform or site - it only creates a Solr core with configuration files provided by the integration module: `schema.xml` and `solrconfig.xml`.

> **Important:** `search_api_solr` for D8+ requires Composer to install the module and its dependencies. After installation, configure it and generate customized Solr core config files, which should be uploaded to the path: `sites/foo.com/files/solr/`. The changes will take effect within 5-10 minutes on the Solr 7 core created by the system.
>
> **NOTE:** Set `solr_custom_config = NO` for the changes to take effect. This setting affects the running of the auto-installer every 5-10 minutes, eliminating the need to wait until the next morning to use the new Solr core.

Once the Solr core is ready, a special file, `sites/foo.com/solr.php`, will provide details on accessing your new Solr core with the correct credentials.

Sites with enabled Solr cores can be safely migrated between platforms. The integration module can be moved within your codebase and even upgraded, provided it uses compatible `schema.xml` and `solrconfig.xml` files.

Supported values for the `solr_integration_module` variable:
- `search_api_solr`
- `apachesolr`

To delete an existing Solr core, simply comment out the relevant line. The system will delete the existing Solr core within 15 minutes.

```text
;solr_integration_module = your_module_name_here
```

## Auto-update Solr Core Configuration Files

This option allows the auto-update of your Solr core configuration files:
- `schema.xml`
- `solrconfig.xml`

If a new release is available for either `apachesolr` or `search_api_solr`, your Solr core will not be automatically upgraded to use the newer `schema.xml` and `solrconfig.xml` unless `solr_update_config` is set to `YES`.

This option will be ignored if `solr_custom_config` is set to `YES`.

```text
;solr_update_config = NO
```

## Custom Solr Core Configuration Files

To use customized versions of `schema.xml` or `solrconfig.xml`, set `solr_custom_config` to `YES`. If using a hosted Aegir service, submit a support ticket to update these files with your custom versions. On self-hosted BOA, update these files directly.

Ensure you use Solr-compatible config files.

> **IMPORTANT:** With this option enabled, you won't be able to follow the Drupal 8+ specific procedure for `search_api_solr` with config files generated and uploaded to the `files/solr/` directory in your site. You can still use this option to make your Solr core immutable between upgrades. However, disable this option briefly (5-10 minutes) for changes to take effect.

```text
;solr_custom_config = NO
```

> **NOTE:** The `solr.php` file is not used to connect to the Solr core; it is only for information on configuring Solr in the given site. Once you clone the site, the new clone will receive its own Solr core in a few minutes, with the `solr.php` file populated with unique, new credentials. Update the site admin area configuration to use the new Solr core on the cloned site. Cron is not enabled on the cloned site by default, preventing the overwriting of the original site index.

## Handling Errors

If you encounter the error:

```text
Apache Solr Attachments Java executable not found; Could not execute
a java command. You may need to set the path of the correct java
executable as the variable 'apachesolr_attachments_java'
in settings.php.
```

To fix this, add the following line to the site's `local.settings.php` file:

```php
$conf['apachesolr_attachments_java'] = '/usr/bin/java7 -Xms32m -Xmx64m';
```

On Debian Stretch or newer, modify the line to:

```php
$conf['apachesolr_attachments_java'] = '/usr/bin/java8 -Xms32m -Xmx64m';
```
