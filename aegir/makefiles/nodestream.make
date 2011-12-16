; NodeStream makefile
;

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "git"
projects[pressflow][download][url] = "git://github.com/omega8cc/pressflow6.git"
projects[pressflow][download][branch] = "master"

projects[nodestream][type] = "profile"
projects[nodestream][download][type] = "git"
projects[nodestream][download][url] = "http://git.drupal.org/project/nodestream.git"
projects[nodestream][download][branch] = "6.x-1.x"
