# AppArmor profile for PHP-CLI
# This profile restricts PHP-CLI (php82) to essential operations only.

# Include the tunables/global definitions
include <tunables/global>

/opt/php82/bin/php flags=(complain) {

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
  /opt/php82/bin/php rix,

  # Allow PHP-CLI to read its configuration files
  /home/*/.drush/** r,
  /data/conf/** r,
  /etc/ImageMagick-6/log.xml r,
  /etc/ImageMagick-6/policy.xml r,
  /etc/ld.so.cache r,
  /etc/newrelic/upgrade_please.key r,
  /opt/php82/** r,

  # Allow PHP-CLI to execute some other binaries
  /bin/dash rix,
  /bin/grep rix,
  /bin/rm rix,
  /bin/stty rix,
  /bin/touch rix,
  /bin/websh rix,
  /usr/bin/convert rix,
  /usr/bin/id rix,
  /usr/bin/magick rix,
  /usr/bin/mysql rix,
  /usr/bin/tput rix,
  /usr/bin/which rix,
  /usr/bin/which.debianutils rix,
  /usr/local/bin/composer rix,
  /usr/local/bin/curl rix,
  /usr/local/bin/wkhtmltoimage rix,
  /usr/local/bin/wkhtmltopdf rix,

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
  /lib/** r,
  /lib64/** r,
  /usr/lib/** r,
  /usr/local/lib/** r,
  /usr/local/ssl/lib/** r,
  /usr/local/ssl3/lib64/** r,
  /opt/php*/lib/php/** mr,
  /usr/local/ioncube/ioncube_loader_lin_*.so mr,

  # Allow PHP-CLI to read and write its log files
  /var/log/php/** rw,
  /var/log/newrelic/php_agent.log rw,

  # Allow PHP-CLI to access /proc and /sys for necessary information
  /proc/** r,
  /sys/** r,

  # Allow PHP-CLI to use /dev/shm for temporary storage
  /dev/shm/** rw,

  # Deny execution of binaries from /tmp and /var/tmp and HOME
  deny /home/*/.tmp/** m,
  deny /home/*/** m,
  deny /tmp/** m,
  deny /var/tmp/** m,

  # Allow PHP-CLI to access drush
  /opt/tools/drush/** rix,
  /var/aegir/drush/** rix,
  /usr/bin/drush rix,

  # Allow PHP-CLI to read and write in the custom web root directories

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
  owner /var/aegir/host_master/** rw,
  owner /var/aegir/platforms/** rw,

  owner /data/disk/*/.drush/** rw,
  owner /data/disk/*/.tmp/** rw,
  owner /data/disk/*/aegir/** rw,
  owner /data/disk/*/config/** rw,
  owner /data/disk/*/distro/** rw,
  owner /data/disk/*/platforms/** rw,
  owner /data/disk/*/static/** rw,
  owner /data/disk/*/tools/le/** rw,
  owner /var/www/** rw,

  owner /home/*/.drush/** r,
  owner /home/*/.drush/cache/** rw,
  owner /home/*/.tmp/* rw,

  # Deny access to various sensitive directories and files
  deny /boot/** mrwklx,
  deny /dev/** mrwklx,
  deny /media/** mrwklx,
  deny /mnt/** mrwklx,
  deny /root/** mrwklx,
  deny /srv/** mrwklx,
  deny /usr/local/** mrwklx,
  deny /var/** mrwklx,

  deny /etc/shadow* rw,
  deny /etc/passwd* rw,
  deny /root/** rwklx,

  # Catchall to deny everything else
  deny /** rwklx,

  # Site-specific additions and overrides can be added below
}
