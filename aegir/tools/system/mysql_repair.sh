#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

touch /var/run/boa_wait.pid
sleep 8
dir=/var/xdrago/log/mysql_optimize
mkdir -p $dir
/usr/bin/mysqlcheck -Aa >> $dir/all.a.`date +%y%m%d-%H%M%S`
/usr/bin/mysqlcheck -Ar >> $dir/all.r.`date +%y%m%d-%H%M%S`
/usr/bin/mysqlcheck -Ao >> $dir/all.o.`date +%y%m%d-%H%M%S`
rm -f /var/run/boa_wait.pid
###EOF2012###
