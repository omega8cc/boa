; CiviCRM 4 master makefile
;

api = 2
core = 7.x

projects[drupal][type] = core

projects[civicrm][type] = "module"
projects[civicrm][directory_name] = "civicrm"
projects[civicrm][download][type] = "get"
projects[civicrm][download][url] = "http://voxel.dl.sourceforge.net/project/civicrm/civicrm-stable/4.0.7/civicrm-4.0.7-drupal.tar.gz"

projects[civicrml10n][type] = "module"
projects[civicrml10n][subdir] = "civicrm"
projects[civicrml10n][download][type] = "get"
projects[civicrml10n][download][url] = "http://voxel.dl.sourceforge.net/project/civicrm/civicrm-stable/4.0.7/civicrm-4.0.7-l10n.tar.gz"

projects[admin_menu][subdir] = "contrib"
projects[admin_menu][version] = "3.0-rc1"
