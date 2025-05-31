service cron stop

Check /root/.my.cnf
server:~# cat /root/.my.cnf
[client]
user=root
password=FOOO
server:~#

Wait 60 sec.

Run:
service mysql stop
ps axf | grep mysql

mysqld_safe --skip-grant-tables --skip-networking &

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


