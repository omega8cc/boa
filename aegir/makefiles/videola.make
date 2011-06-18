; Videola master makefile
;

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "bzr"
projects[pressflow][download][url] = "lp:pressflow/6.x"

projects[videola][type] = "profile"
projects[videola][download][type] = "git"
projects[videola][download][url] = "git://github.com/Lullabot/videola.git"
