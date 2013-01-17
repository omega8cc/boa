; CiviCRM 4.2-d7 master makefile
;

api = 2
core = 7.x

projects[drupal][type] = "core"
projects[drupal][download][type] = "get"
projects[drupal][download][url] = "http://files.aegir.cc/dev/drupal-7.19.1.tar.gz"

projects[civicrm][type] = "module"
projects[civicrm][directory_name] = "civicrm"
projects[civicrm][download][type] = "get"
projects[civicrm][download][url] = "http://sourceforge.net/projects/civicrm/files/civicrm-stable/4.2.6/civicrm-4.2.6-drupal.tar.gz/download?use_mirror=autoselect"

projects[civicrml10n][type] = "module"
projects[civicrml10n][subdir] = "civicrm"
projects[civicrml10n][download][type] = "get"
projects[civicrml10n][download][url] = "http://sourceforge.net/projects/civicrm/files/civicrm-stable/4.2.6/civicrm-4.2.6-l10n.tar.gz/download?use_mirror=autoselect"

projects[admin_menu][subdir] = "contrib"
projects[admin_menu][version] = "3.0-rc2"
