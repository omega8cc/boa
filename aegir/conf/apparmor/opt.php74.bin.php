# Last Modified: Fri Jun 21 16:24:27 2024
include <tunables/global>

/opt/php74/bin/php flags=(complain) {
  include <abstractions/base>
  include <abstractions/bash>
  include <abstractions/consoles>
  include <abstractions/mysql>
  include <abstractions/nameservice>

  /opt/php74/bin/php mrix,

  /bin/dash mrix,
  /bin/grep mrix,
  /bin/rm mrix,
  /bin/stty mrix,
  /bin/touch mrix,
  /bin/websh mrix,
  /usr/bin/id mrix,
  /usr/bin/mysql mrix,
  /usr/bin/tput mrix,
  /usr/bin/which mrix,
  /usr/bin/which.debianutils mrix,
  /usr/local/bin/curl mrix,
  /usr/local/bin/wkhtmltoimage mrix,
  /usr/local/bin/wkhtmltopdf mrix,

  /etc/ImageMagick-6/log.xml r,
  /etc/ImageMagick-6/policy.xml r,
  /etc/ld.so.cache r,
  /etc/mysql/conf.d/* r,
  /etc/mysql/my.cnf r,
  /etc/newrelic/upgrade_please.key r,
  /etc/nsswitch.conf r,

  /proc/loadavg r,
  /proc/filesystems r,

  /usr/local/ioncube/ioncube_loader_lin_*.so mr,
  /usr/local/lib/lib*so* mr,
  /usr/local/ssl/lib/lib*so* mr,
  /usr/local/ssl/openssl.cnf r,
  /usr/local/ssl3/lib64/libcrypto.so.* mr,
  /usr/local/ssl3/lib64/libssl.so.* mr,
  /usr/local/ssl3/openssl.cnf r,
  /{media,mnt,opt,srv}/** mr,

  /var/log/php/* w,

  /opt/tools/drush/** r,
  /var/aegir/drush/** r,

  /var/www/** r,

  /var/aegir/config/** r,
  /var/aegir/host_master/** r,
  /var/aegir/platforms/** r,

  /data/disk/*/.bashrc r,
  /data/disk/*/.drush/** r,
  /data/disk/*/aegir/** r,
  /data/disk/*/config/** r,
  /data/disk/*/distro/** r,
  /data/disk/*/platforms/** r,
  /data/disk/*/static/** r,
  /data/disk/*/tools/drush/** r,
  /data/disk/*/tools/le/** r,

  /data/all/** r,
  /data/conf/* r,

  owner /var/aegir/.tmp/** rw,
  owner /var/aegir/host_master/** w,
  owner /var/aegir/platforms/** w,

  owner /data/disk/*/.drush/** w,
  owner /data/disk/*/.tmp/** rw,
  owner /data/disk/*/aegir/** w,
  owner /data/disk/*/config/** w,
  owner /data/disk/*/distro/** w,
  owner /data/disk/*/platforms/** w,
  owner /data/disk/*/static/** w,
  owner /data/disk/*/tools/le/** w,
  owner /var/www/** w,

  owner /home/*/.drush/** r,
  owner /home/*/.drush/cache/** rw,
  owner /home/*/.tmp/* rw,

  owner /proc/*/mountinfo r,

}
