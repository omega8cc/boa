; Open Atrium master makefile
;

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "get"
projects[pressflow][download][url] = "http://files.aegir.cc/dev/pressflow-6.28.2.tar.gz"

projects[cod][type] = "profile"
projects[cod][download][type] = "git"
projects[cod][download][revision] = "6.x-1.0-beta2"
projects[cod][download][url] = "git://git.drupal.org/project/cod.git"
