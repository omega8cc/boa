```ini
There are some useful and/or performance related modules
added to all 6.x and 7.x platforms -- even to your custom
platforms created in the ~/static directory tree.

Some core and contrib modules are either enabled or disabled
by default, by running weekly (on Saturday) maintenance monitor.

NOTE: You can disable this feature with _MODULES_FIX=NO in the
      standard Barracuda configuration file: /root/.barracuda.cnf

There are also modules supported by Octopus, but not bundled
by default and/or not enabled.

Some modules require custom rewrites on the web server level,
but since there is no .htaccess available/used in Nginx,
we have added all required rewrites and associated supported
configuration settings on the system level. This is the real
meaning of [S]upported flag here.

Note that while some of them are enabled by default on initial
install of "blank" site in the supported platform, they are
not forced as enabled by the running weekly maintenance monitor,
so we marked them as [S]oft[E]nabled.

Here is a complete list with corresponding flags for every
module/theme: [S]upported, [B]undled, [F]orce[E]nabled,
[S]oft[E]nabled or [F]orce[D]isabled. [NA] means that
this module is used without the need to enable it.

NOTE: Both [F]orce[E]nabled and [F]orce[D]isabled list can be skipped
      with _MODULES_FIX=NO in /root/.barracuda.cnf (default is YES)
      However, this procedure is now smart enough to check if the module
      is defined as required by any other module or feature and will
      skip such module automatically, to avoid disabling innocent modules
      via feature or any other dependency. You can also use _MODULES_SKIP
      variable to list modules which should never be disabled by
      the running weekly maintenance agent.

Supported core version is listed for every module or theme
as [D6] and/or [D7].

Contrib [S]upported:

 ais ------------------------ [D7] ------ [S]
 ckeditor ------------------- [D6,D7] --- [S]
 fbconnect ------------------ [D6,D7] --- [S]
 fckeditor ------------------ [D6] ------ [S]
 imageapi_optimize ---------- [D6,D7] --- [S] when IMG XTRAS is installed
 imagecache ----------------- [D6,D7] --- [S]
 imagecache_external -------- [D6,D7] --- [S]
 responsive_images ---------- [D7] ------ [S]
 tinybrowser ---------------- [D6,D7] --- [S]
 tinymce -------------------- [D6] ------ [S]
 wysiwyg_spellcheck --------- [D6,D7] --- [S]

Contrib [S]upported and [B]undled:

 adminer -------------------- [D7] --------- [S] [B]
 advagg --------------------- [D6,D7] ------ [S] [B]
 autoslave ------------------ [D7] --------- [S] [B]
 blockcache_alter ----------- [D6,D7] ------ [S] [B]
 boost ---------------------- [D6,D7] ------ [S] [B]
 cache_consistent ----------- [D7] --------- [S] [B]
 cdn ------------------------ [D6,D7] ------ [S] [B]
 config_perms --------------- [D6,D7] ------ [S] [B]
 css_emimage ---------------- [D6,D7] ------ [S] [B]
 dbtuner -------------------- [D6] --------- [S] [B]
 display_cache -------------- [D7] --------- [S] [B]
 entity_print --------------- [D7] --------- [S] [B]
 esi ------------------------ [D6,D7] ------ [S] [B]
 file_resup ----------------- [D7] --------- [S] [B]
 flood_control -------------- [D7] --------- [S] [B]
 force_password_change ------ [D6,D7] ------ [S] [B]
 fpa ------------------------ [D6,D7] ------ [S] [B]
 httprl --------------------- [D6,D7] ------ [S] [B]
 js ------------------------- [D6,D7] ------ [S] [B]
 login_security ------------- [D6,D7] ------ [S] [B]
 nocurrent_pass ------------- [D7] --------- [S] [B]
 panels_content_cache ------- [D6,D7] ------ [S] [B]
 phpass --------------------- [D6] --------- [S] [B]
 private_upload ------------- [D6] --------- [S] [B]
 readonlymode --------------- [D6-D10] ----- [S] [B]
 reroute_email -------------- [D6,D7] ------ [S] [B]
 securesite ----------------- [D6,D7] ------ [S] [B]
 session_expire ------------- [D6,D7] ------ [S] [B]
 site_verify ---------------- [D6,D7] ------ [S] [B]
 speedy --------------------- [D7] --------- [S] [B]
 taxonomy_edge -------------- [D6,D7] ------ [S] [B]
 variable_clean ------------- [D6,D7] ------ [S] [B]
 vars ----------------------- [D7] --------- [S] [B]
 views_accelerator ---------- [D7] --------- [S] [B]
 views_cache_bully ---------- [D6,D7] ------ [S] [B]
 views_content_cache -------- [D6,D7] ------ [S] [B]
 views404 ------------------- [D6,D7] ------ [S] [B]

Contrib [F]orce[E]nabled

 entitycache ---------------- [D7] --------- [S] [B] [FE] unless entitycache_dont_enable = TRUE
 robotstxt ------------------ [D6,D7] ------ [S] [B] [FE] static file is generated in sites/foo.com/files/robots.txt

Core [F]orce[D]isabled:

 cookie_cache_bypass -------- [D6] -------------- [FD]
 dblog ---------------------- [D6,D7] ----------- [FD]
 syslog --------------------- [D6,D7] ----------- [FD]

Contrib [F]orce[D]isabled

 backup_migrate ------------- [D6,D7] ----------- [FD]
 coder ---------------------- [D6,D7] ----------- [FD]
 css_gzip ------------------- [D6] -------------- [FD]
 devel ---------------------- [D6,D7] ----------- [FD]
 filefield_nginx_progress --- [D7] -------------- [FD]
 hacked --------------------- [D6,D7] ----------- [FD]
 javascript_aggregator ------ [D6] -------------- [FD]
 l10n_update ---------------- [D6,D7] ----------- [FD]
 linkchecker ---------------- [D6,D7] ----------- [FD]
 memcache ------------------- [D6,D7] ----------- [FD]
 memcache_admin ------------- [D6,D7] ----------- [FD]
 performance ---------------- [D6,D7] ----------- [FD]
 poormanscron --------------- [D6] -------------- [FD]
 search_krumo --------------- [D6,D7] ----------- [FD]
 security_review ------------ [D6,D7] ----------- [FD]
 site_audit ----------------- [D7] -------------- [FD]
 stage_file_proxy ----------- [D6,D7] ----------- [FD]
 supercron ------------------ [D6] -------------- [FD]
 varnish -------------------- [D6,D7] ----------- [FD]
 watchdog_live -------------- [D6,D7] ----------- [FD]
 xhprof --------------------- [D6,D7] ----------- [FD]

Contrib [NA]:

 cache_backport ------------- [D6] --------- [S] [B] [NA]
 redis ---------------------- [D6-D10] ----- [S] [B] [NA]

Contrib [S]oft[E]nabled:

 admin ---------------------- [D6,D7] --- [S] [B] [SE]
 rubik ---------------------- [D6,D7] --- [S] [B] [SE]

Core [F]orce[E]nabled:

 path_alias_cache ----------- [D6] -------------- [FE]

Drush [E]xtensions [M]aster [S]atellite:

 clean_missing_modules ------ [D6,D7] --- [S] [B] [EM,ES]
 drupalgeddon --------------- [D7] ------ [S] [B] [EM,ES]
 drush_ecl ------------------ [D7] ------ [S] [B] [EM,ES]
 registry_rebuild ----------- [D6,D7] --- [S] [B] [EM,ES]
 safe_cache_form_clear ------ [D7] ------ [S] [B] [EM,ES]
 security_review ------------ [D6,D7] --- [S] [B] [EM,ES]
 utf8mb4_convert ------------ [D7] ------ [S] [B] [EM,ES]

Provision [E]xtensions [M]aster [S]atellite:

 provision_boost ------------ [D7] ------ [S] [B] [EM,ES]

Hostmaster [E]xtensions [M]aster [S]atellite:

 aegir_objects -------------- [D7] ------ [S] [B] [FE] [ES]
 hosting_civicrm ------------ [D7] ------ [S] [B] [FE] [ES]
 hosting_custom_settings ---- [D7] ------ [S] [B] [FE] [ES]
 hosting_deploy ------------- [D7] ------ [S] [B] [FE] [ES]
 hosting_git ---------------- [D7] ------ [S] [B]      [ES]
 hosting_le ----------------- [D7] ------ [S] [B] [FE] [ES]
 hosting_remote_import ------ [D7] ------ [S] [B]      [ES]
 hosting_site_backup_manager  [D7] ------ [S] [B] [FE] [ES]
 hosting_tasks_extra -------- [D7] ------ [S] [B] [FE] [ES]
 idna_convert --------------- [D7] ------ [S] [B] [FE] [ES]
 revision_deletion ---------- [D7] ------ [S] [B] [FE] [ES]
 userprotect ---------------- [D7] ------ [S] [B] [FE] [ES]
```
