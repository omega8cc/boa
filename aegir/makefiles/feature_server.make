; Feature Server for Drupal 6 make
;
; Developed by Miguel Jacq - http://mig5.net
; Contributions from Dave Hall - http://davehall.com.au
; Modified by Albert Szelagowski - http://omega8.cc

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "get"
projects[pressflow][download][url] = "http://files.aegir.cc/dev/pressflow-6.28.1.tar.gz"

projects[cck] = 2.9
projects[context] = 3.0
projects[ctools] = 1.10
projects[features] = 1.2
projects[filefield] = 3.10
projects[install_profile_api] = 2.2
projects[strongarm] = 2.1
projects[views] = 2.16
projects[nodereference_url] = 1.11

projects[fserver][download][type] = "git"
projects[fserver][download][url] = "git://github.com/omega8cc/FeatureServer.git"
projects[fserver][directory_name] = "fserver"
projects[fserver][destination] = "modules"

projects[tao] = 3.3

projects[singular][download][type] = "git"
projects[singular][download][url] = "git://github.com/omega8cc/singular.git"
projects[singular][type] = "theme"
