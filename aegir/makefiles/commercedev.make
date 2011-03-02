; Commerce 7.x dev master makefile
;

api = 2
core = 7.x

projects[drupal][type] = core

projects[commercedev][type] = "profile"
projects[commercedev][download][type] = "git"
projects[commercedev][download][url] = "git://github.com/omega8cc/commercedev.git"
projects[commercedev][download][branch] = "master"
