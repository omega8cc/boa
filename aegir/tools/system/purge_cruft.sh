#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

find /data/disk/*/backups/* -mtime +1 -type f -exec rm -rf {} \;
find /data/disk/*/distro/*/*/sites/*/files/backup_migrate/*/* -mtime +1 -type f -exec rm -rf {} \;
find /data/disk/*/distro/*/*/sites/*/files/tmp/* -mtime +1 -type f -exec rm -rf {} \;
find /data/disk/*/distro/*/*/sites/*/private/files/backup_migrate/*/* -mtime +1 -type f -exec rm -rf {} \;
find /data/disk/*/distro/*/*/sites/*/private/temp/* -mtime +1 -type f -exec rm -rf {} \;
find /data/disk/*/static/*/sites/*/files/backup_migrate/*/* -mtime +1 -type f -exec rm -rf {} \;
find /data/disk/*/static/*/sites/*/files/tmp/* -mtime +1 -type f -exec rm -rf {} \;
find /data/disk/*/static/*/sites/*/private/temp/* -mtime +1 -type f -exec rm -rf {} \;
rm -f /var/backups/dragon/x/xdrago*/log/VISITOR_ABUSE_ONE.log
###EOF2012###
