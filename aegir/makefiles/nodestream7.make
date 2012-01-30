; NodeStream 7.x makefile
;

api = 2
core = 7.x

projects[drupal][type] = core

projects[nodestream][type] = "profile"
projects[nodestream][download][type] = "git"
projects[nodestream][download][url] = "http://git.drupal.org/project/nodestream.git"
projects[nodestream][download][branch] = "7.x-2.x"
