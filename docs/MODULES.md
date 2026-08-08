```ini
There are some useful and/or performance related modules
added to all 6.x and 7.x platforms -- even to your custom
platforms created in the ~/static directory tree.

Some core and contrib modules are either enabled or disabled
by default, by running weekly (on Tuesday) maintenance monitor.
This applies to Drupal 6 and Drupal 7 sites only -- nothing is
enabled or disabled on Drupal 8+; see the last section.

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

NOTE: Enforcement acts on the module, never on its files. Modules are
      matched and switched off by name in the site's own enabled list,
      so it makes no difference whether the module sits in the bundled
      o_contrib tree, in sites/all/modules, in a single site's modules
      directory, or in a codebase you maintain yourself. Duplicate
      copies on disk collapse to one registry entry, so one disable
      covers them all. Nothing is ever deleted, moved or edited on disk
      to enforce this -- a disabled module stays exactly where you put it.

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
 tag1_d7es ------------------ [D7] --------- [S] [B]
 taxonomy_edge -------------- [D6,D7] ------ [S] [B]
 variable_clean ------------- [D6,D7] ------ [S] [B]
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
 devel ---------------------- [D6,D7] ----------- [FD]
 filefield_nginx_progress --- [D7] -------------- [FD]
 hacked --------------------- [D6,D7] ----------- [FD]
 l10n_update ---------------- [D6,D7] ----------- [FD]
 linkchecker ---------------- [D6,D7] ----------- [FD] Banned: self-DoS (synchronous URL probes in web cron). On D8+ it is reported, never disabled -- see below
 mydropwizard --------------- [D6,D7] ----------- [FD] Banned: the myDropWizard update service closed in 2022; its synchronous cron call can never succeed
 performance ---------------- [D6,D7] ----------- [FD]
 poormanscron --------------- [D6] -------------- [FD]
 security_review ------------ [D6,D7] ----------- [FD]
 site_audit ----------------- [D7] -------------- [FD]
 supercron ------------------ [D6] -------------- [FD]
 watchdog_live -------------- [D6,D7] ----------- [FD]
 xhprof --------------------- [D6,D7] ----------- [FD]

No longer [F]orce[D]isabled -- no code disables these any more.
Kept here as the answer for anyone who remembers the older list:

 css_gzip, javascript_aggregator, memcache, memcache_admin,
 search_krumo, stage_file_proxy -- dropped from the maintenance
      lists; nothing in owl.sh or the night workers refers to them.

 automated_cron ------------- [D8-D11] ---------- a D8+ core module,
      and nothing is disabled on D8+ at all. It is still listed in
      _MODULES_FORCE, but that only changes how a module already on
      the day's OFF list is handled, and it is on no OFF list.

 varnish -------------------- [D6,D7] ----------- never disabled
      per site: it is purged from the bundled o_contrib tree by
      _RMMODULES instead, so no site can enable it from the bundle.

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
 environment_indicator ------ [D7] ------ [S] [B] [FE] [ES]
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

## Drupal 8+: nothing is enabled or disabled

Everything above is a Drupal 6/7 mechanism. BOA does not enable or disable
any module on a Drupal 8+ site, and there is no D8+ force-enable or
force-disable list in the sense the flags describe. The reason is general:
a Drush8 full bootstrap against a Drupal 8+ site can corrupt the site's
internals (cached container/router state), so outside the controlled Aegir
backend path BOA never bootstraps a D8+ site with Drush8 — and Drush8 is
what performs these actions on D6/D7.

`linkchecker` is the single exception, and it is handled without Drush
entirely: it is reported, never disabled. On D8+ platforms the Tuesday
pass only PROBES each
site's database directly (root mysql; db name parsed from the site
drushrc; on D8+ a banned module's table presence is an exact installed
signal, since uninstall drops the schema and no disabled state exists) and
mails the operator (`_MY_EMAIL`) on a hit, repeating every Tuesday until the
module is gone. `_MODULES_SKIP` whitelists a module on D8+ exactly as it
does on D6/D7.

To remove a banned module from a D8+ site, use the site's own admin UI in
web context: **Extend → Uninstall → the module**. For `linkchecker`, core's
uninstall page first offers the required *Remove LinkChecker link type
entities* step — complete it, then uninstall. Do **not** run Drush8 commands
against a Drupal 8+ site.
