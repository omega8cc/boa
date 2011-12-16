; Managing News 6.x-1.x makefile
;

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "git"
projects[pressflow][download][url] = "git://github.com/omega8cc/pressflow6.git"
projects[pressflow][download][branch] = "master"

projects[managingnews][type] = "profile"
projects[managingnews][download][type] = "git"
projects[managingnews][download][url] = "http://git.drupal.org/project/managingnews.git"
projects[managingnews][download][branch] = "6.x-1.x"
