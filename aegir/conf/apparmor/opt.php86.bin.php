# AppArmor profile for PHP-CLI
# This profile restricts PHP-CLI (php86) to essential operations only.

#include <tunables/global>

/opt/php86/bin/php flags=(complain) {

  # Include common AppArmor abstractions
  include <abstractions/base>
  include <abstractions/bash>
  include <abstractions/consoles>
  include <abstractions/mysql>
  include <abstractions/nameservice>

  # Capabilities needed by PHP-CLI
  capability chown,
  capability dac_override,
  capability dac_read_search,
  capability fowner,
  capability fsetid,
  capability sys_resource,

  # Allow PHP-CLI to execute its own binary
  /opt/php86/bin/php mrix,

  # Allow PHP-CLI to signal/ptrace other processes
  ptrace (read) peer=/opt/php*/bin/php,
  signal (send) peer=unconfined,
  signal (send) peer=/usr/sbin/nginx,
  ptrace (read) peer=/opt/php*/sbin/php-fpm,
  ptrace (read) peer=/usr/bin/mysqld_safe,
  ptrace (read) peer=/usr/local/sbin/pure-ftpd,
  ptrace (read) peer=/usr/bin/valkey-server,
  ptrace (read) peer=/usr/sbin/mysqld,
  ptrace (read) peer=/usr/sbin/nginx,
  ptrace (read) peer=/usr/sbin/rsyslogd,
  ptrace (read) peer=/usr/sbin/unbound,
  ptrace (read) peer=unconfined,

  # Allow PHP-CLI to read required configuration files
  /data/disk/*/.subversion/ r,
  /data/disk/*/.subversion/* r,
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
  /etc/subversion/ r,
  /etc/subversion/* r,
  /etc/wgetrc r,
  /home/*/.drush/ r,
  /home/*/.drush/** r,
  /usr/local/share/git-core/templates/ r,
  /usr/local/share/git-core/templates/* r,
  /usr/local/share/git-core/templates/** r,
  /usr/share/GeoIP/GeoIP.dat r,
  /usr/share/GeoIP/GeoIPv6.dat r,
  /usr/share/GeoIP/GeoLite2-ASN.mmdb r,
  /usr/share/GeoIP/GeoLite2-City.mmdb r,
  /usr/share/GeoIP/GeoLite2-Country.mmdb r,
  /opt/php86/** r,

  # Allow PHP-CLI to read what the backend tools it starts ask for
  / r,
  /data/disk/*/.drush/ r,
  /data/disk/*/.drush/usr/ r,
  /data/disk/*/.drush/usr/** r,
  /data/disk/*/log/*.txt r,
  /etc/ImageMagick-*/ r,
  /etc/ImageMagick-*/** r,
  /etc/mydumper.cnf r,
  /etc/boa/mydumper-extra.cnf r,
  /usr/share/ImageMagick-*/ r,
  /usr/share/ImageMagick-*/** r,

  # Allow PHP-CLI to read required user/access files
  /etc/passwd r,

  # Allow PHP-CLI to execute some other binaries
  /usr/bin/symlinks mrix,
  /{,usr/}bin/cat mrix,
  /{,usr/}bin/chmod mrix,
  /{,usr/}bin/chown mrix,
  /{,usr/}bin/cp mrix,
  /{,usr/}bin/dash mrix,
  /{,usr/}bin/perl mrix,
  /{,usr/}bin/date mrix,
  /{,usr/}bin/egrep mrix,
  /{,usr/}bin/grep mrix,
  /{,usr/}bin/kmod mrix,
  /{,usr/}bin/mkdir mrix,
  /{,usr/}bin/mv mrix,
  /{,usr/}bin/pidof mrix,
  /{,usr/}bin/rm mrix,
  /{,usr/}bin/run-parts mrix,
  /{,usr/}bin/sed mrix,
  /{,usr/}bin/stty mrix,
  /{,usr/}bin/tar mrix,
  /{,usr/}bin/touch mrix,
  /opt/local/bin/autosymlink mrix,
  /opt/local/bin/websh mrix,
  /{,usr/}sbin/killall5 mrix,
  /usr/bin/chromium mrix,
  /usr/bin/convert mrix,
  /usr/bin/find mrix,
  /usr/bin/id mrix,
  /usr/bin/magick mrix,
  /usr/bin/mysql mrix,
  /usr/bin/patch mrix,
  /usr/bin/sudo Px -> boa_sudo,
  /usr/bin/svn mrix,
  /usr/bin/tput mrix,
  /usr/bin/tr mrix,
  /usr/bin/unzip mrix,
  /usr/bin/wget mrix,
  /usr/bin/which mrix,
  /usr/bin/which.debianutils mrix,
  /usr/local/bin/composer mrix,
  /usr/local/bin/curl mrix,
  /usr/local/bin/git mrix,
  /usr/local/bin/mydumper mrix,
  /usr/local/bin/myloader mrix,
  /usr/local/bin/wkhtmltoimage mrix,
  /usr/local/bin/wkhtmltopdf mrix,
  /usr/local/libexec/git-core/* mrix,
  /usr/local/libexec/git-core/** mrix,
  /usr/sbin/nginx mrix,
  /usr/sbin/postdrop mrix,
  /usr/sbin/sendmail mrix,
  /{,usr/}bin/basename mrix,
  /{,usr/}bin/cut mrix,
  /{,usr/}bin/dd mrix,
  /{,usr/}bin/df mrix,
  /{,usr/}bin/dirname mrix,
  /{,usr/}bin/du mrix,
  /{,usr/}bin/env mrix,
  /{,usr/}bin/getent mrix,
  /{,usr/}bin/gzip mrix,
  /{,usr/}bin/head mrix,
  /{,usr/}bin/mawk mrix,
  /{,usr/}bin/readlink mrix,
  /{,usr/}bin/realpath mrix,
  /{,usr/}bin/sort mrix,
  /{,usr/}bin/stat mrix,
  /{,usr/}bin/tee mrix,
  /{,usr/}bin/timeout mrix,
  /{,usr/}bin/whoami mrix,
  /usr/bin/mydumper mrix,
  /usr/bin/myloader mrix,
  /usr/bin/mysqldump mrix,
  /opt/php*/bin/php mrix,

  # hosting_le runs its Let's Encrypt client under bash from a site's Verify, and
  # Provision's self-signed path calls openssl
  /{,usr/}bin/bash mrix,
  /{,usr/}bin/ln mrix,
  /{,usr/}bin/mktemp mrix,
  /{,usr/}bin/sleep mrix,
  /{,usr/}bin/tail mrix,
  /{,usr/}bin/uname mrix,
  /usr/bin/diff mrix,
  /usr/bin/hexdump mrix,
  /usr/bin/openssl mrix,
  /usr/local/ssl3/bin/openssl mrix,

  # What a backup, a deploy, the Sync task, a certificate hook and a tenant's Composer
  # scripts and Drush commands start. Named one by one: a glob over /usr/bin would take in
  # sudo and every setuid program.
  /{,usr/}bin/base64 mrix,
  /{,usr/}bin/bzip2 mrix,
  /{,usr/}bin/chgrp mrix,
  /{,usr/}bin/expr mrix,
  /{,usr/}bin/false mrix,
  /{,usr/}bin/gawk mrix,
  /{,usr/}bin/gunzip mrix,
  /{,usr/}bin/hostname mrix,
  /{,usr/}bin/ls mrix,
  /{,usr/}bin/md5sum mrix,
  /{,usr/}bin/nproc mrix,
  /{,usr/}bin/rev mrix,
  /{,usr/}bin/rmdir mrix,
  /{,usr/}bin/seq mrix,
  /{,usr/}bin/sha1sum mrix,
  /{,usr/}bin/sha256sum mrix,
  /{,usr/}bin/true mrix,
  /{,usr/}bin/uniq mrix,
  /{,usr/}bin/wc mrix,
  /{,usr/}bin/xargs mrix,
  /{,usr/}bin/xz mrix,
  /{,usr/}bin/zcat mrix,
  /usr/bin/drill mrix,
  /usr/bin/file mrix,
  /usr/bin/jq mrix,
  /usr/bin/lz4 mrix,
  /usr/bin/python3* mrix,
  /usr/bin/rsync mrix,
  /usr/bin/zstd mrix,
  /usr/local/ssl/bin/openssl mrix,

  # The tools BOA's own list opens to the backend, by the file each really is: convert and
  # magick are links to a versioned program, and the kernel judges the file
  /usr/bin/advdef mrix,
  /usr/bin/advpng mrix,
  /usr/bin/clamdscan mrix,
  /usr/bin/clamscan mrix,
  /usr/bin/compare{,-im[67].q16*} mrix,
  /usr/bin/composite{,-im[67].q16*} mrix,
  /usr/bin/convert-im[67].q16* mrix,
  /usr/bin/ffmpeg mrix,
  /usr/bin/ffprobe mrix,
  /usr/bin/gpg mrix,
  /usr/bin/gs mrix,
  /usr/bin/identify{,-im[67].q16*} mrix,
  /usr/bin/jpegoptim mrix,
  /usr/bin/jpegtran mrix,
  /usr/bin/logger mrix,
  /usr/bin/magick-im[67].q16* mrix,
  /usr/bin/mogrify{,-im[67].q16*} mrix,
  /usr/bin/montage{,-im[67].q16*} mrix,
  /usr/bin/node mrix,
  /usr/bin/optipng mrix,
  /usr/bin/pngcrush mrix,
  /usr/bin/pngquant mrix,
  /usr/bin/rrdtool mrix,
  /usr/lib/chromium/** mrix,
  /opt/jdk/ r,
  /opt/jdk/** mr,
  /opt/jdk/*/bin/java mrix,
  /opt/jdk/*/lib/jspawnhelper mrix,
  /usr/lib/jvm/*/bin/java mrix,
  /usr/lib/jvm/*/lib/jspawnhelper mrix,
  /usr/lib/node_modules/npm/bin/** mrix,
  /usr/local/bin/compass mrix,
  /usr/local/bin/gem mrix,
  /usr/local/bin/ruby mrix,
  /usr/local/bin/sass mrix,
  /usr/local/bin/scss mrix,
  /usr/local/bin/wkhtmltoimage-0.12.4 mrix,
  /usr/local/bin/wkhtmltopdf-0.12.4 mrix,
  /opt/tools/bee/ r,
  /opt/tools/bee/** mr,

  # An ssh client reads the account's own keys, which this profile keeps from tenant code,
  # so it runs under a profile of its own, where no shell can start
  /usr/bin/ssh Px -> boa_remote_client,
  /usr/local/bin/ssh Px -> boa_remote_client,
  signal (send) peer=boa_remote_client,

  # The certificate client's DNS hooks are root's clones: the nightly moves away a tree with
  # anything else in it, and what the task's own user wrote there does not run
  /data/disk/*/tools/le/hooks/ r,
  /data/disk/*/tools/le/hooks/** mrix,
  deny owner /data/disk/*/tools/le/hooks/** mx,

  # Fonts, for the page and image tools
  /etc/fonts/ r,
  /etc/fonts/** r,
  /usr/local/share/fonts/ r,
  /usr/local/share/fonts/** r,
  /usr/share/fonts/ r,
  /usr/share/fonts/** r,
  /var/cache/fontconfig/ r,
  /var/cache/fontconfig/** r,

  # Root's composer asks for an optional file and goes on without it
  deny /root/.config/composer/update-channel r,

  # The data those tools read: fontconfig's own, colour profiles, PDF character maps, time zones
  /etc/magic r,
  /etc/python3*/ r,
  /etc/python3*/** r,
  /usr/bin/npm r,
  /etc/paperspecs r,
  /etc/ssl/openssl.cnf r,
  /etc/vulkan/ r,
  /etc/vulkan/** r,
  /etc/papersize r,
  /etc/udev/udev.conf r,
  /usr/share/color/ r,
  /usr/share/color/** r,
  /usr/share/file/ r,
  /usr/share/file/** r,
  /usr/share/fontconfig/ r,
  /usr/share/fontconfig/** r,
  /usr/share/glib-2.0/schemas/ r,
  /usr/share/glib-2.0/schemas/** r,
  /usr/share/javascript/mathjax/ r,
  /usr/share/javascript/mathjax/** r,
  /usr/share/poppler/ r,
  /usr/share/poppler/** r,
  /usr/share/publicsuffix/ r,
  /usr/share/publicsuffix/** r,
  /usr/share/zoneinfo/ r,
  /usr/share/zoneinfo/** r,

  # A browser asks these of its own processes
  /dev/dri/ r,
  /var/tmp/ r,
  deny /usr/lib/chromium/extensions/ w,
  owner /proc/*/clear_refs w,
  owner /proc/*/coredump_filter rw,
  owner /proc/*/oom_score_adj rw,

  /{,usr/}bin/echo mrix,
  /usr/bin/findmnt mrix,

  # What a browser, svn and Composer keep in the home they run under
  owner /data/disk/*/.local/ rw,
  owner /data/disk/*/.local/** rwk,
  owner /data/disk/*/.subversion/ rw,
  owner /data/disk/*/.subversion/** rw,
  owner /home/*/.cache/ rw,
  owner /home/*/.cache/** rwk,
  owner /home/*/.composer/ rw,
  owner /home/*/.composer/** rwk,
  owner /home/*/.config/ rw,
  owner /home/*/.config/** rwk,
  owner /home/*/.subversion/ rw,
  owner /home/*/.subversion/** rw,

  # Wrappers a tenant's command line may name, and the real files behind a link
  /{,usr/}bin/ionice mrix,
  /{,usr/}bin/nice mrix,
  /{,usr/}bin/nohup mrix,
  /{,usr/}bin/setsid mrix,
  /{,usr/}bin/stdbuf mrix,
  /opt/local/bin/bee mrix,
  /opt/local/bin/grav mrix,
  /usr/bin/curl mrix,
  /usr/bin/pdf* mrix,
  /usr/bin/time mrix,
  /usr/bin/wkhtmltoimage{,-0.12.4} mrix,
  /usr/bin/wkhtmltopdf{,-0.12.4} mrix,

  # What those tools read
  /etc/chromium.d/ r,
  /etc/chromium.d/* r,
  /etc/chromium/ r,
  /etc/chromium/** r,
  /etc/clamav/ r,
  /etc/clamav/** r,
  /etc/ghostscript/ r,
  /etc/ghostscript/** r,
  /etc/java-*/ r,
  /etc/java-*/** r,
  /opt/jetty9/lib/ r,
  /opt/jetty9/lib/** r,
  /opt/tika*/ r,
  /opt/tika*/** r,
  /usr/share/chromium/ r,
  /usr/share/chromium/** r,
  /usr/share/ghostscript/ r,
  /usr/share/ghostscript/** r,
  /usr/share/java/ r,
  /usr/share/java/** r,
  /usr/share/pdftk/ r,
  /usr/share/pdftk/** r,
  /var/lib/clamav/ r,
  /var/lib/clamav/** r,
  /var/lib/ghostscript/ r,
  /var/lib/ghostscript/** r,

  # Each PHP reads its own settings, whichever PHP started it
  /opt/php*/lib/php.ini r,

  # The shared core and a files store moved to attached storage: the kernel judges the file
  # a link resolves to, so neither matches the account's own paths
  /data/disk/all/ r,
  /data/disk/all/** r,
  /mnt/**/files/*/static/files/ rw,
  /mnt/**/files/*/static/files/** rwk,
  owner /mnt/**/files/*/static/files/.backups/ rwl,
  owner /mnt/**/files/*/static/files/.backups/** rwl,
  owner /mnt/**/files/*/static/files/.backup-exports/ rwl,
  owner /mnt/**/files/*/static/files/.backup-exports/** rwl,

  # The master instance's tasks, as an account's
  owner /var/aegir/backups/ rwl,
  owner /var/aegir/backups/* rwl,
  owner /var/aegir/backups/** rwl,
  owner /var/aegir/backup-exports/ rwl,
  owner /var/aegir/backup-exports/* rwl,
  owner /var/aegir/backup-exports/** rwl,
  owner /var/aegir/clients/ rw,
  owner /var/aegir/clients/* rw,
  owner /var/aegir/clients/** rwk,

  # renameaegirhost and perftest run a PHP script as root from a private folder, and read
  # renameaegirhost's answer from its log there
  /var/backups/renameaegirhost.*/ r,
  /var/backups/renameaegirhost.*/*.php r,
  /var/backups/renameaegirhost.*/*.log w,
  /root/.perftest-run.*/ r,
  /root/.perftest-run.*/*.php r,

  # A folder listing of the account's own home
  owner /data/disk/*/ r,

  # Allow PHP-CLI to access some /dev
  /dev/null rw,
  /dev/random r,
  /dev/tty rw,
  /dev/urandom r,

  # Allow PHP-CLI to use tmp files
  /tmp/ r,
  /tmp/** rwk,
  /var/spool/postfix/maildrop/ r,
  /var/spool/postfix/maildrop/* rw,
  /var/tmp/** rwk,

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
  /dev/shm/** rwk,

  # Deny execution of binaries from these directories
  deny /home/*/.tmp/** m,
  deny /home/*/** m,
  deny /tmp/** m,
  deny /var/tmp/** m,

  # Allow PHP-CLI to access drush
  /data/disk/*/tools/drush/ r,
  /data/disk/*/tools/drush/* mrix,
  /data/disk/*/tools/drush/** r,
  /opt/tools/drush/** mrix,
  /usr/local/bin/cv.phar mrix,
  /var/aegir/drush/ r,
  /var/aegir/drush/* mrix,
  /var/aegir/drush/** r,

  # Allow PHP-CLI to access System Default Web Root

  /var/www/** r,
  owner /var/www/** rwk,

  # Allow PHP-CLI to read/write in the Ægir Backend on Master Instance

  owner /var/aegir/hostmaster-*/ r,
  owner /var/aegir/hostmaster-*/** r,
  owner /var/aegir/.drush/ r,
  owner /var/aegir/.drush/* rw,
  owner /var/aegir/.drush/** rwk,
  owner /var/aegir/.tmp/ r,
  owner /var/aegir/.tmp/* rw,
  owner /var/aegir/.tmp/** rwk,
  owner /var/aegir/config/ r,
  owner /var/aegir/config/* rw,
  owner /var/aegir/config/** rwk,
  owner /var/aegir/host_master-*/ r,
  owner /var/aegir/host_master-*/* rw,
  owner /var/aegir/host_master-*/** rwk,
  owner /var/aegir/host_master/ r,
  owner /var/aegir/host_master/* rw,
  owner /var/aegir/host_master/** rwk,
  owner /var/aegir/platforms/ r,
  owner /var/aegir/platforms/* rw,
  owner /var/aegir/platforms/** rwk,

  # Allow PHP-CLI to read/write in the Ægir Backend on Octopus Instances

  /data/all/ r,
  /data/all/* r,
  /data/all/** r,

  /data/conf/ r,
  /data/conf/* r,
  /data/conf/** r,

  # The account worker runs Drush's core:init as the account and as its login, once
  # each on a new account: what it writes in those homes
  owner /data/disk/*/.bashrc rw,
  owner /home/*/.bashrc rw,
  owner /home/*/.drush/ rw,
  owner /home/*/.drush/drush.bashrc rw,
  owner /home/*/.drush/drush.complete.sh rw,
  owner /home/*/.drush/drush.prompt.sh rw,
  owner /home/*/.drush/drush.yml rw,

  owner /data/disk/*/.cache/**/pack-* l,
  owner /data/disk/*/static/**/pack-* l,

  owner /data/disk/*/log/ r,
  owner /data/disk/*/log/* rw,
  owner /data/disk/*/.*.pass.php r,
  owner /data/disk/*/.rnd rw,

  owner /data/disk/*/backups/ rwl,
  owner /data/disk/*/backups/* rwl,
  owner /data/disk/*/backups/** rwlk,

  owner /data/disk/*/backup-exports/ rwl,
  owner /data/disk/*/backup-exports/* rwl,
  owner /data/disk/*/backup-exports/** rwlk,

  owner /data/disk/*/.config/ rwl,
  owner /data/disk/*/.config/* rwl,
  owner /data/disk/*/.config/** rwlk,

  owner /data/disk/*/.cache/ rwl,
  owner /data/disk/*/.cache/* rwl,
  owner /data/disk/*/.cache/** rwlk,

  owner /data/disk/*/.drush/ rwl,
  owner /data/disk/*/.drush/* rwl,
  owner /data/disk/*/.drush/** rwlk,

  owner /data/disk/*/.tmp/ rwl,
  owner /data/disk/*/.tmp/* rwl,
  owner /data/disk/*/.tmp/** rwlk,

  owner /data/disk/*/clients/ rw,
  owner /data/disk/*/clients/* rw,
  owner /data/disk/*/clients/** rwk,

  owner /data/disk/*/config/ rw,
  owner /data/disk/*/config/* rw,
  owner /data/disk/*/config/** rwk,

  owner /data/disk/*/tools/le/ rw,
  owner /data/disk/*/tools/le/* rw,
  owner /data/disk/*/tools/le/** rwk,

  # Allow PHP-CLI to read/write in the Ægir Frontend on Octopus Instances

  owner /data/disk/*/aegir/ rw,
  owner /data/disk/*/aegir/* rw,
  owner /data/disk/*/aegir/** rwk,

  # Allow PHP-CLI to read/write in the limited shell user home for Drush support

  owner /home/*/.drush/sites/ rw,
  owner /home/*/.drush/sites/* rw,
  owner /home/*/.drush/sites/** rwk,

  owner /home/*/.drush/cache/ rw,
  owner /home/*/.drush/cache/* rw,
  owner /home/*/.drush/cache/** rwk,

  owner /home/*/.tmp/ rw,
  owner /home/*/.tmp/* rw,
  owner /home/*/.tmp/** rwk,

  # Allow PHP-CLI to read/write in the custom web root directories

  /data/disk/*/static/ rw,
  /data/disk/*/static/* rw,
  /data/disk/*/static/** rwk,

  /data/disk/*/distro/ rw,
  /data/disk/*/distro/* rw,
  /data/disk/*/distro/** rwk,

  /data/disk/*/platforms/ rw,
  /data/disk/*/platforms/* rw,
  /data/disk/*/platforms/** rwk,

  # Allow PHP-CLI to read and write in the root tmp

  owner /root/.tmp/ rw,
  owner /root/.tmp/* rw,
  owner /root/.tmp/** rwk,

  # Deny access to various sensitive directories and files
  deny /boot/** mrwklx,

  # Catchall to deny everything else
  #deny /** rwklx,

  # Site-specific additions and overrides can be added below
}
