service cron stop

### Check /root/.my.cnf
server:~# cat /root/.my.cnf
[client]
user=root
password=FOOO
server:~#

### If /root/.my.pass.txt does not exist or does not match /root/.my.cnf
server:~# echo FOOO > /root/.my.pass.txt

### If /etc/mysql_pre exists and /etc/mysql does not
server:~# mv -f /etc/mysql_pre /etc/mysql

### Wait 60 sec.

### Run:
service mysql stop
ps axf | grep mysql

### For Percona 8.0 and 8.4
/usr/sbin/mysqld \
  --defaults-file=/etc/mysql/my.cnf \
  --user=mysql \
  --skip-grant-tables \
  --skip-networking \
  --log-error-verbosity=3 \
  --daemonize=OFF

### For Percona 5.7
/usr/sbin/mysqld \
  --defaults-file=/etc/mysql/my.cnf \
  --user=mysql \
  --skip-grant-tables \
  --skip-networking \
  --log-warnings=2

server:~# mysql
FLUSH PRIVILEGES;
ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'FOOO';
ALTER USER 'root'@'::1' IDENTIFIED WITH mysql_native_password BY 'FOOO';
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'FOOO';
FLUSH PRIVILEGES;
mysql> exit

server:~# service mysql restart

server:~# mysql
mysql> exit

server:~# service cron start


