# AppArmor profile for PHP-CLI
# This profile restricts PHP-CLI (php83) to essential operations only.

#include <tunables/global>

/opt/php83/bin/php flags=(complain) {

  # Include common AppArmor abstractions
  include <abstractions/base>
  include <abstractions/bash>
  include <abstractions/consoles>
  include <abstractions/mysql>
  include <abstractions/nameservice>

  # Capabilities needed by PHP-CLI
  capability setgid,
  capability setuid,
  capability dac_override,
  capability dac_read_search,

  # Allow PHP-CLI to execute its own binary
  /opt/php83/bin/php mrix,

  # Allow PHP-CLI to read its configuration files
  /home/*/.drush/ r,
  /home/*/.drush/** r,
  /data/conf/** r,
  /etc/mysql/my.cnf r,
  /etc/mysql/conf.d/ r,
  /etc/mysql/conf.d/* r,
  /etc/ImageMagick-6/log.xml r,
  /etc/ImageMagick-6/policy.xml r,
  /etc/ld.so.cache r,
  /etc/newrelic/upgrade_please.key r,
  /opt/php83/** r,

  # Allow PHP-CLI to execute some other binaries
  /usr/bin/sudo mrix,
  /bin/dash mrix,
  /bin/grep mrix,
  /bin/rm mrix,
  /bin/stty mrix,
  /bin/touch mrix,
  /bin/websh mrix,
  /usr/bin/convert mrix,
  /usr/bin/id mrix,
  /usr/bin/magick mrix,
  /usr/bin/mysql mrix,
  /usr/bin/tput mrix,
  /usr/bin/which mrix,
  /usr/bin/which.debianutils mrix,
  /usr/local/bin/composer mrix,
  /usr/local/bin/curl mrix,
  /usr/local/bin/wkhtmltoimage mrix,
  /usr/local/bin/wkhtmltopdf mrix,

  # Allow PHP-CLI to access some /dev
  /dev/urandom r,
  /dev/random r,
  /dev/null rw,
  /dev/tty rw,

  # Allow PHP-CLI to use tmp files
  /home/*/.tmp/** rw,
  /tmp/** rw,
  /var/tmp/** rw,

  # Allow read access to necessary libraries
  /lib/** mr,
  /lib64/** mr,
  /opt/php*/lib/php/** mr,
  /usr/lib/** mr,
  /usr/lib/x86_64-linux-gnu/** mr,
  /lib/x86_64-linux-gnu/** mr,
  /usr/local/include/** mr,
  /usr/local/ioncube/ioncube_loader_lin_*.so mr,
  /usr/local/lib/** mr,
  /usr/local/ssl/** mr,
  /usr/local/ssl3/** mr,

  # Allow PHP-CLI to read and write its log files
  /var/log/php/** rw,
  /var/log/newrelic/php_agent.log rw,

  # Allow PHP-CLI to access /proc and /sys for necessary information
  /proc/** r,
  /sys/** r,

  # Allow PHP-CLI to use /dev/shm for temporary storage
  /dev/shm/** rw,

  # Deny execution of binaries from these directories
  deny /home/*/.tmp/** m,
  deny /home/*/** m,
  deny /tmp/** m,
  deny /var/tmp/** m,

  # Allow PHP-CLI to access drush
  /opt/tools/drush/** mrix,
  /var/aegir/drush/** mrix,

  # Allow PHP-CLI to read and write in the custom web root directories

  /var/www/** r,

  /var/aegir/.drush/ r,
  /var/aegir/.drush/** r,
  /var/aegir/config/** r,
  /var/aegir/host_master/** r,
  /var/aegir/platforms/** r,

  /data/disk/*/.bashrc r,
  /data/disk/*/.drush/ r,
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

  owner /var/aegir/.tmp/ rw,
  owner /var/aegir/.tmp/** rw,
  owner /var/aegir/host_master/** rw,
  owner /var/aegir/platforms/** rw,

  owner /data/disk/*/.drush/ rw,
  owner /data/disk/*/.drush/** rw,
  owner /data/disk/*/.tmp/ rw,
  owner /data/disk/*/.tmp/** rw,
  owner /data/disk/*/aegir/** rw,
  owner /data/disk/*/config/** rw,
  owner /data/disk/*/distro/** rw,
  owner /data/disk/*/platforms/** rw,
  owner /data/disk/*/static/** rw,
  owner /data/disk/*/tools/le/** rw,
  owner /var/www/** rw,

  owner /home/*/.drush/cache/ rw,
  owner /home/*/.drush/cache/** rw,
  owner /home/*/.tmp/ rw,
  owner /home/*/.tmp/** rw,

  # Deny access to various sensitive directories and files
  deny /boot/** mrwklx,
  deny /root/** mrwklx,
  deny /etc/shadow* rwlx,

  # Catchall to deny everything else
  #deny /** rwklx,

  # Site-specific additions and overrides can be added below
}
