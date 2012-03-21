#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games

touch /var/run/boa_wait.pid
sleep 180
DATABASEUSER=root
DATABASEPASS=NdKBu34erty325r6mUHxWy
BACKUPDIR=/data/disk/arch/sql
DATE=`date +%y%m%d-%H%M`
HOST=`hostname`
SAVELOCATION=$BACKUPDIR/$HOST-$DATE

truncate_cache_tables() {
TABLES="sessions cache cache_menu cache_page cache_filter cache_form cache_block cache_views_data cache_views cache_content watchdog cache_path boost_cache boost_cache_relationships"
for i in $TABLES; do
mysql --default-character-set=utf8 --password=$DATABASEPASS -h localhost --port=3306 -u $DATABASEUSER $line<<EOFMYSQL
TRUNCATE $i;
EOFMYSQL
echo $i table truncated in $line database
done
}

#Check if location to save exists, if not create it
[ ! -a $SAVELOCATION ] &&  mkdir -p $SAVELOCATION ;

#Get a list of databases to backup
mysql -u $DATABASEUSER -p$DATABASEPASS -e "show databases" -s > .databasesToBackup;

#Parse the list of databases and then backup using mysqldump
cat .databasesToBackup | while read line; do
  truncate_cache_tables
  #mysqlcheck --port=3306 -h localhost -r -u $DATABASEUSER --password=$DATABASEPASS $line &> /dev/null
  #mysqlcheck --port=3306 -h localhost -o -u $DATABASEUSER --password=$DATABASEPASS $line &> /dev/null
  mysqldump -u $DATABASEUSER -p$DATABASEPASS --default-character-set=utf8 -Q -C -e --hex-blob --add-drop-table $line | gzip  > $SAVELOCATION/$line.sql.gz
  echo backup completed for $line database
  sleep 1
done

rm .databasesToBackup

#Delete all files in the backup dir 8 days or older - note: this deletes everything!
#Only database backups should exist in $BACKUPDIR!!!
find $BACKUPDIR -mtime +8 -type d -exec rm -rf {} \;

echo COMPLETED ALL
rm -f /var/run/boa_wait.pid
touch /var/xdrago/log/last-run-backup
###EOF2012###
