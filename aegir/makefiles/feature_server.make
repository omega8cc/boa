; Feature Server for Drupal 6 make
;
; Developed by Miguel Jacq - http://mig5.net
; Contributions from Dave Hall - http://davehall.com.au
; Modified by Albert Szelagowski - http://omega8.cc

api = 2
core = 6.x

projects[pressflow][type] = "core"
projects[pressflow][download][type] = "get"
projects[pressflow][download][url] = "http://files.aegir.cc/core/pressflow-6.30.1.tar.gz"

projects[cck][type] = "module"
;projects[cck][version] = "2.9"
projects[cck][download][type] = "get"
projects[cck][download][url] = "http://files.aegir.cc/dev/contrib/cck-6.x-2.9.tar.gz"

projects[context][type] = "module"
;projects[context][version] = "3.1"
projects[context][download][type] = "get"
projects[context][download][url] = "http://files.aegir.cc/dev/contrib/context-6.x-3.3.tar.gz"

projects[ctools][type] = "module"
;projects[ctools][version] = "1.10"
projects[ctools][download][type] = "get"
projects[ctools][download][url] = "http://files.aegir.cc/dev/contrib/ctools-6.x-1.10.tar.gz"

projects[features][type] = "module"
;projects[features][version] = "1.2"
projects[features][download][type] = "get"
projects[features][download][url] = "http://files.aegir.cc/dev/contrib/features-6.x-1.2.tar.gz"

projects[filefield][type] = "module"
;projects[filefield][version] = "3.11"
projects[filefield][download][type] = "get"
projects[filefield][download][url] = "http://files.aegir.cc/dev/contrib/filefield-6.x-3.11.tar.gz"

projects[install_profile_api][type] = "module"
;projects[install_profile_api][version] = "2.2"
projects[install_profile_api][download][type] = "get"
projects[install_profile_api][download][url] = "http://files.aegir.cc/dev/contrib/install_profile_api-6.x-2.2.tar.gz"

projects[strongarm][type] = "module"
;projects[strongarm][version] = "2.2"
projects[strongarm][download][type] = "get"
projects[strongarm][download][url] = "http://files.aegir.cc/dev/contrib/strongarm-6.x-2.2.tar.gz"

projects[views][type] = "module"
;projects[views][version] = "2.16"
projects[views][download][type] = "get"
projects[views][download][url] = "http://files.aegir.cc/dev/contrib/views-6.x-2.16.tar.gz"

projects[nodereference_url][type] = "module"
;projects[nodereference_url][version] = "1.11"
projects[nodereference_url][download][type] = "get"
projects[nodereference_url][download][url] = "http://files.aegir.cc/dev/contrib/nodereference_url-6.x-1.11.tar.gz"

projects[fserver][type] = "module"
projects[fserver][download][type] = "git"
projects[fserver][download][url] = "git://github.com/omega8cc/FeatureServer.git"
projects[fserver][directory_name] = "fserver"
projects[fserver][destination] = "modules"

projects[tao][type] = "theme"
;projects[tao][version] = "3.3"
projects[tao][download][type] = "get"
projects[tao][download][url] = "http://files.aegir.cc/dev/contrib/tao-6.x-3.3.tar.gz"

projects[singular][type] = "theme"
projects[singular][download][type] = "git"
projects[singular][download][url] = "git://github.com/omega8cc/singular.git"
