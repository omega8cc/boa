; Open Atrium master makefile
;

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "get"
projects[pressflow][download][url] = "http://files.aegir.cc/dev/pressflow6.tar.gz"
projects[pressflow][download][branch] = "master"

projects[openatrium][type] = "profile"
projects[openatrium][download][type] = "git"
projects[openatrium][download][url] = "git://github.com/omega8cc/openatrium.git"
projects[openatrium][download][branch] = "master"
