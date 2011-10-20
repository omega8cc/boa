; Feature Server for Drupal 6 make
;
; Developed by Miguel Jacq - http://mig5.net
; Contributions from Dave Hall - http://davehall.com.au
; Modified by Albert Szelagowski - http://omega8.cc

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "bzr"
projects[pressflow][download][url] = "lp:pressflow/6.x"

projects[cck] = 2.9
projects[context] = 3.0
projects[ctools] = 1.8
projects[features] = 1.0
projects[filefield] = 3.9
projects[install_profile_api] = 2.1
projects[strongarm] = 2.0
projects[views] = 2.12
projects[nodereference_url] = 1.11

projects[fserver][download][type] = "git"
projects[fserver][download][url] = "git://github.com/omega8cc/FeatureServer.git"
projects[fserver][directory_name] = "fserver"
projects[fserver][destination] = "modules"

projects[tao] = 3.2

projects[singular][download][type] = "git"
projects[singular][download][url] = "git://github.com/omega8cc/singular.git"
projects[singular][type] = "theme"
