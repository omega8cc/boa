#!/bin/bash

rm -f /var/log/php/*
/etc/init.d/php-fpm reload
touch /var/xdrago/log/clear.done
