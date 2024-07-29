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
  capability audit_write,
  capability chown,
  capability dac_override,
  capability dac_read_search,
  capability fowner,
  capability fsetid,
  capability mknod,
  capability setgid,
  capability setuid,
  capability sys_ptrace,
  capability sys_resource,

  # Allow PHP-CLI to execute its own binary
  /opt/php83/bin/php mrix,

  # Allow PHP-CLI to signal/ptrace other processes
  ptrace (read) peer=/opt/php*/bin/php,
  signal (send) peer=unconfined,
  signal (send) peer=/usr/sbin/nginx,
  ptrace (read) peer=/opt/php*/sbin/php-fpm,
  ptrace (read) peer=/usr/bin/mysqld_safe,
  ptrace (read) peer=/usr/bin/redis-server,
  ptrace (read) peer=/usr/local/sbin/pure-ftpd,
  ptrace (read) peer=/usr/sbin/nginx,
  ptrace (read) peer=/usr/sbin/rsyslogd,
  ptrace (read) peer=/usr/sbin/unbound,
  ptrace (read) peer=unconfined,

  # Allow PHP-CLI to read required configuration files
  /etc/wgetrc r,
  /etc/default/nginx r,
  /etc/ImageMagick-6/log.xml r,
  /etc/ImageMagick-6/policy.xml r,
  /etc/ld.so.cache r,
  /etc/ldap/ldap.conf r,
  /etc/mailname r,
  /etc/mysql/conf.d/ r,
  /etc/mysql/conf.d/* r,
  /etc/mysql/my.cnf r,
  /etc/newrelic/upgrade_please.key r,
  /etc/nginx/conf.d/ r,
  /etc/nginx/conf.d/** r,
  /etc/nginx/fastcgi_params r,
  /etc/nginx/mime.types r,
  /etc/nginx/nginx.conf r,
  /etc/postfix/dynamicmaps.cf r,
  /etc/postfix/dynamicmaps.cf.d/ r,
  /etc/postfix/main.cf r,
  /etc/ssl/private/ r,
  /etc/ssl/private/* r,
  /etc/ssl/private/nginx-wild-ssl.crt r,
  /etc/ssl/private/nginx-wild-ssl.dhp r,
  /etc/ssl/private/nginx-wild-ssl.key r,
  /home/*/.drush/ r,
  /home/*/.drush/** r,
  /usr/share/GeoIP/GeoIP.dat r,
  /opt/php83/** r,

  # Allow PHP-CLI to read required user/access files
  /etc/login.defs r,
  /etc/pam.d/* r,
  /etc/passwd r,
  /etc/security/capability.conf r,
  /etc/security/limits.conf r,
  /etc/security/limits.d/ r,
  /etc/security/limits.d/* r,
  /etc/shadow r,
  /etc/sudo.conf r,
  /etc/sudoers r,
  /etc/sudoers.d/ r,
  /etc/sudoers.d/* r,
  /run/sudo/ts/ r,
  /run/sudo/ts/* r,

  # Allow PHP-CLI to execute some other binaries
  /bin/cat mrix,
  /bin/chmod mrix,
  /bin/chown mrix,
  /bin/cp mrix,
  /bin/dash mrix,
  /bin/date mrix,
  /bin/egrep mrix,
  /bin/grep mrix,
  /bin/mkdir mrix,
  /bin/mv mrix,
  /bin/pidof mrix,
  /bin/rm mrix,
  /bin/run-parts mrix,
  /bin/sed mrix,
  /bin/stty mrix,
  /bin/tar mrix,
  /bin/touch mrix,
  /bin/websh mrix,
  /data/disk/*/**/vendor/bin/drush mrix,
  /etc/init.d/nginx mrix,
  /sbin/killall5 mrix,
  /sbin/unix_chkpwd mrix,
  /usr/bin/convert mrix,
  /usr/bin/find mrix,
  /usr/bin/id mrix,
  /usr/bin/magick mrix,
  /usr/bin/mysql mrix,
  /usr/bin/patch mrix,
  /usr/bin/sudo mrix,
  /usr/bin/tput mrix,
  /usr/bin/tr mrix,
  /usr/bin/wget mrix,
  /usr/bin/which mrix,
  /usr/bin/which.debianutils mrix,
  /usr/local/bin/composer mrix,
  /usr/local/bin/curl mrix,
  /usr/local/bin/fix-drupal-platform-ownership.sh mrix,
  /usr/local/bin/fix-drupal-platform-permissions.sh mrix,
  /usr/local/bin/fix-drupal-site-ownership.sh mrix,
  /usr/local/bin/fix-drupal-site-permissions.sh mrix,
  /usr/local/bin/lock-local-drush-permissions.sh mrix,
  /usr/local/bin/mydumper mrix,
  /usr/local/bin/myloader mrix,
  /usr/local/bin/wkhtmltoimage mrix,
  /usr/local/bin/wkhtmltopdf mrix,
  /usr/sbin/nginx mrix,
  /usr/sbin/postdrop mrix,
  /usr/sbin/sendmail mrix,

  # Allow PHP-CLI to access some /dev
  /dev/null rw,
  /dev/random r,
  /dev/tty rw,
  /dev/urandom r,

  # Allow PHP-CLI to use tmp files
  /tmp/ r,
  /tmp/** rw,
  /var/spool/postfix/maildrop/ r,
  /var/spool/postfix/maildrop/* rw,
  /var/tmp/** rw,

  # Allow read access to necessary libraries
  /lib/** mr,
  /lib/x86_64-linux-gnu/** mr,
  /lib64/** mr,
  /opt/php*/lib/php/** mr,
  /usr/lib/** mr,
  /usr/lib/x86_64-linux-gnu/** mr,
  /usr/libexec/** mr,
  /usr/local/include/** mr,
  /usr/local/ioncube/ioncube_loader_lin_*.so mr,
  /usr/local/lib/** mr,
  /usr/local/ssl/** mr,
  /usr/local/ssl3/** mr,

  # Allow PHP-CLI to read and write its log files
  /var/log/php/** rw,
  /var/log/newrelic/php_agent.log rw,

  # Allow PHP-CLI to write to some other log/pid files
  /run/nginx.pid rw,
  /var/log/nginx/access.log rw,
  /var/log/nginx/error.log rw,

  # Allow PHP-CLI to access /proc and /sys for necessary information
  /proc/ r,
  /proc/** r,
  /sys/ r,
  /sys/** r,

  # Allow PHP-CLI to use /dev/shm for temporary storage
  /dev/shm/ r,
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

  /data/all/ r,
  /data/all/* r,
  /data/all/** r,
  /data/conf/ r,
  /data/conf/* r,
  /data/conf/** r,

  /data/disk/*/static/** rw,
  /data/disk/*/distro/** rw,
  /data/disk/*/platforms/** rw,

  owner /var/aegir/.tmp/ r,
  owner /var/aegir/.tmp/** rw,
  owner /var/aegir/host_master/** rw,
  owner /var/aegir/platforms/** rw,

  owner /data/disk/*/log/ r,
  owner /data/disk/*/log/* rw,
  owner /data/disk/*/.*.pass.php r,
  owner /data/disk/*/.rnd rw,
  owner /data/disk/*/backups/ rw,
  owner /data/disk/*/backups/** rw,

  owner /data/disk/*/.drush/ r,
  owner /data/disk/*/.drush/** rw,
  owner /data/disk/*/.tmp/ r,
  owner /data/disk/*/.tmp/** rw,
  owner /data/disk/*/aegir/ rw,
  owner /data/disk/*/aegir/** rw,
  owner /data/disk/*/clients/ r,
  owner /data/disk/*/clients/** rw,
  owner /data/disk/*/config/** rw,
  owner /data/disk/*/distro/ rw,
  owner /data/disk/*/platforms/ rw,
  owner /data/disk/*/tools/le/** rw,
  owner /var/www/** rw,

  owner /home/*/.drush/sites/ r,
  owner /home/*/.drush/sites/** rw,
  owner /home/*/.drush/cache/ r,
  owner /home/*/.drush/cache/** rw,
  owner /home/*/.tmp/ r,
  owner /home/*/.tmp/** rw,
  owner /root/.tmp/ r,
  owner /root/.tmp/** rw,

  # Deny access to various sensitive directories and files
  deny /boot/** mrwklx,

  # Catchall to deny everything else
  #deny /** rwklx,

  # Site-specific additions and overrides can be added below
}
