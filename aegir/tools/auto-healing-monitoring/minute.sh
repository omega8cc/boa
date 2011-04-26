#!/bin/bash

perl /var/xdrago/firewall/check/hackcheck
perl /var/xdrago/firewall/check/hackmail
perl /var/xdrago/firewall/check/hackftp
perl /var/xdrago/firewall/check/scan_nginx
perl /var/xdrago/firewall/check/sqlcheck

echo DONE!
