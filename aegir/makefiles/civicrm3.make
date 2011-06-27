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
projects[civicrm][download][url] = "http://voxel.dl.sourceforge.net/project/civicrm/civicrm-stable/3.4.4/civicrm-3.4.4-drupal.tar.gz"
;projects[civicrm][patch][] = "http://issues.civicrm.org/jira/secure/attachment/12814/civi-doSiteMove.patch"

projects[civicrml10n][type] = "module"
projects[civicrml10n][subdir] = "civicrm"
projects[civicrml10n][download][type] = "get"
projects[civicrml10n][download][url] = "http://voxel.dl.sourceforge.net/project/civicrm/civicrm-stable/3.4.4/civicrm-3.4.4-l10n.tar.gz"

projects[simplycivi][download][type] = "git"
projects[simplycivi][download][url] = "https://github.com/kylejaster/SimplyCivi.git"
projects[simplycivi][type] = "theme"

projects[civicrm_theme][subdir] = "contrib"
projects[civicrm_theme][version] = "1.4"

projects[admin_menu][subdir] = "contrib"
projects[admin_menu][version] = "1.6"
