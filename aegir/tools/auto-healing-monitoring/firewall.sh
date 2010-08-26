#! /bin/bash
#
# firewall	iptables based frewall script
#
#		Written by Thomas Pircher <tehpeh@gmx.net>
#		Based on the skeleton script, written by
#		Miquel van Smoorenburg <miquels@cistron.nl> and
#		Ian Murdock <imurdock@gnu.ai.mit.edu>.
#
# Version:	@(#)firewall  1.0.1  2006-01-22  tehpeh@gmx.net
#

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON=/sbin/iptables
NAME=firewall
DESC="iptables based firewall"

test -x $DAEMON || exit 0

set -e

iptables=/sbin/iptables
int_if=eth0			# internal (local) interface, e.g. eth0
int_ip=89.145.120.127		# internal (local) IP, e.g. 192.168.1.94



function firewall_start
{
	#modprobe ip_conntrack
	#modprobe ip_conntrack_ftp
	#modprobe ip_nat_ftp

	# other network protection
	echo 1 > /proc/sys/net/ipv4/tcp_syncookies                              # enable syn cookies (prevent against the common 'syn flood attack')
	echo 0 > /proc/sys/net/ipv4/ip_forward                                  # disable Packet forwarning between interfaces
	echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts                 # ignore all ICMP ECHO and TIMESTAMP requests sent to it via broadcast/multicast
	echo 1 > /proc/sys/net/ipv4/conf/all/log_martians                       # log packets with impossible addresses to kernel log
	echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses           # disable logging of bogus responses to broadcast frames
	echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter                          # do source validation by reversed path (Recommended option for single homed hosts)
	echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects                     # don't send redirects
	echo 0 > /proc/sys/net/ipv4/conf/all/accept_source_route                # don't accept packets with SRR option
										              
	# default policy
	$iptables -P INPUT   DROP
	$iptables -P FORWARD DROP
	$iptables -P OUTPUT  DROP

	# drop broadcast (do not log)
	$iptables -A INPUT  -i $int_if -d 255.255.255.255 -j DROP
	$iptables -A INPUT  -i $int_if -d 192.168.255.255 -j DROP
	$iptables -A INPUT  -i $int_if -d 192.168.1.255   -j DROP
	$iptables -A INPUT             -d 10.0.0.0/8      -j DROP
	$iptables -A INPUT             -d 169.254.0.0/16  -j DROP

	# drop Bad Guys
	$iptables -A INPUT -m recent --rcheck --seconds 60 -m limit --limit 10/second -j LOG --log-prefix "BG "
	$iptables -A INPUT -m recent --update --seconds 60 -j DROP
	
	sh /var/xdrago/run_all

	# drop spoofed packets (i.e. packets with local source addresses coming from outside etc.), mark as Bad Guy
	$iptables -A INPUT  -i $int_if -s $int_ip -m recent --set -j DROP

	# drop silently well-known virus/port scanning attempts
	$iptables -A INPUT  -i $int_if -m multiport -p tcp --dports 53,113,135,137,139,445 -j DROP
	$iptables -A INPUT  -i $int_if -m multiport -p udp --dports 53,113,135,137,139,445 -j DROP
	$iptables -A INPUT  -i $int_if -p udp --dport 1026 -j DROP
	$iptables -A INPUT  -i $int_if -m multiport -p tcp --dports 1433,4899 -j DROP

	# accept everything from loopback
	$iptables -A INPUT  -i lo -j ACCEPT
	$iptables -A OUTPUT -o lo -j ACCEPT

	# accept ICMP packets (ping et.al.)
	$iptables -A INPUT  -p icmp -m limit --limit 10/second -j ACCEPT
	$iptables -A INPUT  -p icmp -j DROP
#	$iptables -A INPUT  -m recent --name ICMP --update --seconds 60 --hitcount 6 -j DROP
#	$iptables -A INPUT  -i $int_if -d $int_ip -p icmp -m recent --set --name ICMP -j ACCEPT

	# internet (established and out)
	$iptables -A OUTPUT -o $int_if -j ACCEPT
	$iptables -A INPUT  -i $int_if -m state --state ESTABLISHED,RELATED -j ACCEPT

	# public services
	$iptables -A INPUT -i $int_if -p tcp -d $int_ip -m multiport --dports 25,80,143,443,993,8000 -j ACCEPT

$iptables -A INPUT -p udp -m udp --dport 53 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 53 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 20000 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 10000 -j ACCEPT
$iptables -A INPUT -p udp -m udp -s 10.1.1.101 --dport 161 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 587 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 8443 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 85 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 88 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 993 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 143 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 995 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 110 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 20 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 21 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 53 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 25 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
$iptables -A INPUT -p tcp -m tcp --dport 30000:50000 -j ACCEPT

	# accept ssh connections (max 2/minute from the same IP address)
	$iptables -A INPUT -p tcp --dport 22 -m recent --rcheck --seconds 60 --hitcount 2 --name SSH -j LOG --log-prefix "SH "
	$iptables -A INPUT -p tcp --dport 22 -m recent --update --seconds 60 --hitcount 2 --name SSH -j DROP
	$iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH -j ACCEPT

	# log all the rest before dropping
	$iptables -A INPUT   -j LOG --log-prefix "IN "
	$iptables -A INPUT   -j REJECT --reject-with icmp-port-unreachable
	$iptables -A OUTPUT  -j LOG --log-prefix "OU "
	$iptables -A OUTPUT  -j REJECT --reject-with icmp-port-unreachable
	$iptables -A FORWARD -j LOG --log-prefix "FW "
	$iptables -A FORWARD -j REJECT --reject-with icmp-port-unreachable

echo "1" > /var/xdrago/backup/log/blackIP.log
$iptables --list > /var/xdrago/fire_restart.done

}

function fallback_start
{
	# flush rules
	$iptables -F
	$iptables -F -t mangle
	$iptables -X -t mangle
	$iptables -F -t nat
	$iptables -X -t nat
	$iptables -X

	# default policy
	$iptables -P INPUT   DROP
	$iptables -P FORWARD DROP
	$iptables -P OUTPUT  DROP

	# accept everything from loopback
	$iptables -A INPUT  -i lo -j ACCEPT
	$iptables -A OUTPUT -o lo -j ACCEPT

	# accept ICMP packets (ping et.al.)
	$iptables -A INPUT  -i $int_if -d $int_ip -p icmp -j ACCEPT

	# internet (established and out)
	$iptables -A OUTPUT -o $int_if -j ACCEPT
	$iptables -A INPUT  -i $int_if -m state --state ESTABLISHED,RELATED -j ACCEPT

	# public services
	$iptables -A INPUT -i $int_if -p tcp -d $int_ip -m multiport --dports 22,25,80,143,443,993 -j ACCEPT

	# log all the rest before dropping
	$iptables -A INPUT   -j LOG --log-prefix "IN "
	$iptables -A OUTPUT  -j LOG --log-prefix "OU "
	$iptables -A FORWARD -j LOG --log-prefix "FW "
}

function firewall_stop
{
	# flush rules
	$iptables -F
	$iptables -F -t mangle
	$iptables -X -t mangle
	$iptables -F -t nat
	$iptables -X -t nat
	$iptables -X

	# default policy
	$iptables -P INPUT   ACCEPT
	$iptables -P FORWARD ACCEPT
	$iptables -P OUTPUT  ACCEPT
}

case "$1" in
  start)
	echo -n "Starting $DESC: "
	firewall_start || fallback_start
	echo "OK."
	;;
  stop)
	echo -n "Stopping $DESC: "
	firewall_stop
	echo "OK."
	;;
#  reload|force-reload)
#	#
#	#	If the daemon can reload its config files on the fly
#	#	for example by sending it SIGHUP, do it here.
#	#
#	#	If the daemon responds to changes in its config file
#	#	directly anyway, make this a do-nothing entry.
#	echo -n "Reloading $DESC: $NAME"
#	echo "OK."
#  ;;
  restart|reload|force-reload)
	#
	#	If the "reload" option is implemented, move the "force-reload"
	#	option to the "reload" entry above. If not, "force-reload" is
	#	just the same as "restart".
	#
	echo -n "Restarting $DESC: "
	firewall_stop
	sleep 1
	firewall_start || fallback_start
	echo "OK."
	;;
  *)
	N=/etc/init.d/$NAME
	echo "Usage: $N {start|stop|restart|reload|force-reload}" >&2
	# echo "Usage: $N {start|stop|restart|force-reload}" >&2
	exit 1
	;;
esac

exit 0
