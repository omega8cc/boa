; Commerce 7.x dev master makefile
;

api = 2
core = 7.x

projects[drupal][type] = "core"
projects[drupal][download][type] = "get"
projects[drupal][download][url] = "http://files.aegir.cc/dev/drupal-7.16.1.tar.gz"

projects[commercedev][type] = "profile"
projects[commercedev][download][type] = "git"
projects[commercedev][download][url] = "git://github.com/omega8cc/commercedev.git"
projects[commercedev][download][branch] = "master"
