; CiviCRM 3 master makefile
;

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "bzr"
projects[pressflow][download][url] = "lp:pressflow/6.x"

projects[civicrm][type] = "module"
projects[civicrm][directory_name] = "civicrm"
projects[civicrm][download][type] = "get"
projects[civicrm][download][url] = "http://voxel.dl.sourceforge.net/project/civicrm/civicrm-stable/3.4.7/civicrm-3.4.7-drupal.tar.gz"

projects[civicrm_l10n][type] = "module"
projects[civicrm_l10n][subdir] = "civicrm"
projects[civicrm_l10n][download][type] = "get"
projects[civicrm_l10n][download][url] = "http://voxel.dl.sourceforge.net/project/civicrm/civicrm-stable/3.4.7/civicrm-3.4.7-l10n.tar.gz"
projects[civicrm_l10n][overwrite] = TRUE

projects[civicrm_theme][subdir] = "contrib"
projects[civicrm_theme][version] = "1.4"

projects[admin_menu][subdir] = "contrib"
projects[admin_menu][version] = "1.8"
