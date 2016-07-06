
You can very easily add, update or delete Solr 4 cores powered by very fast
Jetty server. It's fully automated and can be managed very easily via site level
active INI file. Of course Solr 4 must be already installed on the system
with SR4 keyword present in _XTRAS_LIST in the /root/.barracuda.cnf file.

There are three INI variables you can use to control Solr automated setup:
solr_integration_module, solr_update_config and solr_custom_config -- just
take a look at the documentation below, which can be found also in every site's
INI template. For more information on how to control BOA on site and platform
level via INI files, check our docs at https://omega8.cc/node/293

  NOTE: This feature works only for site level INI files, because
        Solr cores belong to sites, not to platforms.

;;
;;  This option allows to activate Solr 4 core configuration for the site.
;;
;;  Only Solr 4 powered by Jetty server is available. Supported integration
;;  modules are limited to latest versions of either search_api_solr (D7 only)
;;  or apachesolr (will use Drupal core specific version automatically).
;;
;;  Currently used versions are listed below:
;;
;;    https://ftp.drupal.org/files/projects/search_api_solr-7.x-1.11.tar.gz
;;    https://ftp.drupal.org/files/projects/apachesolr-7.x-1.8.tar.gz
;;    https://ftp.drupal.org/files/projects/apachesolr-6.x-3.1.tar.gz
;;
;;  Note that you still need to add preferred integration module along with
;;  any its dependencies in your codebase since this feature doesn't modify
;;  your platform or site - it only creates Solr core with configuration
;;  files provided by integration module: schema.xml and solrconfig.xml
;;
;;  This setting affects only the running daily maintenance system behaviour,
;;  so you need to wait until next morning to be able to use new Solr 4 core.
;;
;;  Once the Solr core is ready to use, you will find a special file in your
;;  site directory: sites/foo.com/solr.php with details on how to access
;;  your new Solr core with correct credentials.
;;
;;  The site with enabled Solr core can be safely migrated between platforms,
;;  integration module can be moved within your codebase and even upgraded,
;;  as long as it is using compatible schema.xml and solrconfig.xml files.
;;
;;  Supported values for the solr_integration_module variable:
;;
;;    apachesolr
;;    search_api_solr
;;
;;  To delete existing Solr core simply comment out this line.
;;  The system will cleanly delete existing Solr core next morning.
;;
;;  IMPORTANT if you are using self-hosted BOA: _MODULES_FIX=YES must be set
;;  in the /root/.barracuda.cnf file (default is NO) to make this
;;  feature active.
;;
;solr_integration_module = your_module_name_here

;;
;;  This option allows to auto-update your Solr 4 core configuration files:
;;
;;    schema.xml
;;    solrconfig.xml
;;
;;  If there is new release for either apachesolr or search_api_solr, your
;;  Solr core will not be automatically upgraded to use newer schema.xml and
;;  solrconfig.xml, unless allowed by switching solr_update_config to YES.
;;
;;  This option will be ignored if you will set solr_custom_config to YES.
;;
;solr_update_config = NO

;;
;;  This option allows to protect custom Solr 4 core configuration files:
;;
;;    schema.xml
;;    solrconfig.xml
;;
;;  To use customized version of either schema.xml or solrconfig.xml, you need
;;  to switch solr_custom_config to YES below and if you are using hosted
;;  Aegir service, submit a support ticket to get these files updated with
;;  your custom versions. On self-hosted BOA simply update these files directly.
;;
;;  Please remember to use Solr 4 compatible config files.
;;
;solr_custom_config = NO


  NOTE: The solr.php file is not used to connect to the Solr cor; it is only
        for your information to know how to configure Solr in the given site.

        It is important, because once you clone the site, the new clone will
        receive its own Solr core the next morning, so its solr.php file will be
        populated with unique, new credentials to use, which will overwrite the
        solr.php file copied automatically during Clone task. It is the
        configuration inside the site admin area which tells Drupal which Solr
        core to use, and you need to update it on the cloned site, of course,
        once the new core is created.

  NOTE on ERRORS:

       "Apache Solr Attachments Java executable not found; Could not execute
        a java command. You may need to set the path of the correct java
        executable as the variable 'apachesolr_attachments_java'
        in settings.php."

        To fix add in the site's local.settings.php file this line:

        $conf['apachesolr_attachments_java'] = '/usr/bin/java7 -Xms32m -Xmx64m';
