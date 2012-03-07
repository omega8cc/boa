; Managing News 6.x-1.x makefile
;

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "get"
projects[pressflow][download][url] = "http://files.aegir.cc/dev/pressflow-6.25.1.tar.gz"
projects[pressflow][download][branch] = "master"

projects[managingnews][type] = "profile"
projects[managingnews][download][type] = "git"
projects[managingnews][download][url] = "http://git.drupal.org/project/managingnews.git"
projects[managingnews][download][branch] = "6.x-1.x"
