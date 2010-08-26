#!/bin/bash

touch /var/xdrago/log/optimize_mysql_ao.pid
dir=/var/xdrago/log/mysql_optimize
mkdir -p $dir
/usr/bin/mysqlcheck --port=3306 -h localhost -Aa -u root --password=NdKBu34erty325r6mUHxWy >> $dir/all.a.`date +%y%m%d-%H%M%S`
/usr/bin/mysqlcheck --port=3306 -h localhost -Ar -u root --password=NdKBu34erty325r6mUHxWy >> $dir/all.r.`date +%y%m%d-%H%M%S`
/usr/bin/mysqlcheck --port=3306 -h localhost -Ao -u root --password=NdKBu34erty325r6mUHxWy >> $dir/all.o.`date +%y%m%d-%H%M%S`
rm -f /var/xdrago/log/optimize_mysql_ao.pid
