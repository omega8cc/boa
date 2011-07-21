#!/bin/bash

/usr/bin/memcached -u nobody -p 11211 -m 64 -I 3m -d -l 127.0.0.1
/usr/bin/memcached -u nobody -p 11212 -m 64 -I 3m -d -l 127.0.0.1
/usr/bin/memcached -u nobody -p 11213 -m 64 -I 3m -d -l 127.0.0.1
/usr/bin/memcached -u nobody -p 11214 -m 64 -I 3m -d -l 127.0.0.1
/usr/bin/memcached -u nobody -p 11215 -m 64 -I 3m -d -l 127.0.0.1
/usr/bin/memcached -u nobody -p 11216 -m 64 -I 3m -d -l 127.0.0.1
/usr/bin/memcached -u nobody -p 11217 -m 64 -I 3m -d -l 127.0.0.1
/usr/bin/memcached -u nobody -p 11218 -m 64 -I 3m -d -l 127.0.0.1
