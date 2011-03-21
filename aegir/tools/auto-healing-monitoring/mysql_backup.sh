#!/bin/bash

touch /var/xdrago/log/optimize_mysql_ao.pid
sleep 120
DATABASEUSER=root
DATABASEPASS=NdKBu34erty325r6mUHxWy
BACKUPDIR=/data/disk/arch/sql
DATE=`date +%y%m%d-%H%M`
HOST=`hostname`
SAVELOCATION=$BACKUPDIR/$HOST-$DATE

#Check if location to save exists, if not create it
[ ! -a $SAVELOCATION ] &&  mkdir -p $SAVELOCATION ;

#Get a list of datbases to backup
mysql -u $DATABASEUSER -p$DATABASEPASS -e "show databases" -s > .databasesToBackup;

#Parese list of databases and then backup using mysqldump
cat .databasesToBackup | while read line; do
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE sessions;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_menu;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_page;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_filter;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_form;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_block;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_views_data;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_views;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_content;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE watchdog;
EOFMYSQL
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE cache_path;
EOFMYSQL
# mysqlcheck --port=3306 -h localhost -r -u $DATABASEUSER --password=$DATABASEPASS $line &> /dev/null
# mysqlcheck --port=3306 -h localhost -o -u $DATABASEUSER --password=$DATABASEPASS $line &> /dev/null
mysqldump -u $DATABASEUSER -p$DATABASEPASS --default-character-set=utf8 -Q -C -e --hex-blob --add-drop-table $line | gzip  > $SAVELOCATION/$line.sql.gz
sleep 8
done

rm .databasesToBackup

#Delete all files in the backup dir 8 days or older - note this deletes everything!
#only database backups should exist in $BACKUPDIR!!!
find $BACKUPDIR -mtime +8 -type d -exec rm -rf {} \;

echo COMPLETED ALL
rm -f /var/xdrago/log/optimize_mysql_ao.pid
touch /var/xdrago/log/last-run-backup
