#!/bin/bash

/etc/init.d/php-fpm reload
sleep 5
echo rotate > /var/log/php/php-fpm-slow.log
echo rotate > /var/log/php/php-fpm-error.log
echo rotate > /var/log/php/error_log
touch /var/xdrago/log/clear.done
