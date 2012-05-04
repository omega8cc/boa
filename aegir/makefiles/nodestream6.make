; NodeStream makefile
;

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "get"
projects[pressflow][download][url] = "http://files.aegir.cc/dev/pressflow-6.26.1.tar.gz"

projects[nodestream][type] = "profile"
projects[nodestream][download][type] = "git"
projects[nodestream][download][url] = "http://git.drupal.org/project/nodestream.git"
projects[nodestream][download][branch] = "6.x-1.x"
