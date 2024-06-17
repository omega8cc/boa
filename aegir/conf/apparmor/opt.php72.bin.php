# Last Modified: Mon Jun 17 08:11:09 2024
#include <tunables/global>

/opt/php72/bin/php flags=(complain) {
  #include <abstractions/base>
  #include <abstractions/bash>
  #include <abstractions/consoles>

  /bin/dash mrix,
  /bin/websh mrix,

  /etc/ImageMagick-6/log.xml r,
  /etc/ImageMagick-6/policy.xml r,

  /proc/loadavg r,

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

  /data/disk/*/.drush/** r,
  /data/disk/*/aegir/** r,
  /data/disk/*/config/** r,
  /data/disk/*/distro/** r,
  /data/disk/*/platforms/** r,
  /data/disk/*/static/** r,
  /data/disk/*/tools/le/** r,

  /data/all/** r,
  /data/conf/* r,

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
  owner /home/*/.tmp/* rw,

  owner /proc/*/mountinfo r,

}
