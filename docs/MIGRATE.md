# How To: Migrate All Sites Between Remote BOA

While [docs/REMOTE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/REMOTE.md) provides a how-to for per-site migration between remote Octopus instances, it depends on some assumptions, namely:

1. Remote Octopus instance must already exist
2. Remote Octopus instance must use the same system username
3. You need to either add proxy manually or hurry to update DNS
4. There is no batch mode

New BOA tool (xboa), which is expected to mature into a more sophisticated Swiss Army Knife for BOA, resolves all those problems very easily.

The only requirement is that the remote BOA server should be installed with the same release/version. No Octopus instance is needed on the target system prior to migration.

It's a very safe and reliable (used in production) method when you need to:

1. Upgrade to a newer major OS version without the fear that things will totally explode when running the system upgrade 'in place', like in this example:
   [https://github.com/omega8cc/boa/issues/627](https://github.com/omega8cc/boa/issues/627)

2. Move to a different provider without any visible interruption to your hosted sites visitors, especially when you have so many sites, so manual procedure is not an option.

3. Just change the machine powering your BOA, magically, on the fly.

## Steps to Follow

The 'source-host' is a placeholder for the source system FQDN hostname.
The 'target-host' is a placeholder for the target system FQDN hostname.
The 'source-ip' is a placeholder for the source system IP address.
The 'target-ip' is a placeholder for the target system IP address.

While it is really easy when you have some experience with the procedure, we don't recommend using it on any live system without prior practicing a bit on test VPS instances.

Still scared? We can help! Let us know via: [https://omega8.cc/sales](https://omega8.cc/sales)

## Before You Begin

For Drupal 6 based sites which are configured to block IPs, you may need to whitelist source-ip at `/admin/user/rules` first, by adding the Allow rule for Host rule type. Otherwise, the site may block its old IP address, and you will be forced to remove it via Chive from the `{access}` table.

## On the Target Host

```sh
echo "source-ip # Legacy Proxy" >> /etc/csf/csf.allow
echo "source-ip # Legacy Proxy" >> /etc/csf/csf.ignore
csf -q
```

## On the Source Host

```sh
xboa pre-mig source-host
```

## On the Target Host

```sh
xboa pre-mig source-host
```

## On the Source Host

### Test connection to target

```sh
ssh root@target-ip
exit
```

### Enable site_readonly globally

```sh
cp -af /data/conf/global.inc /data/conf/global.inc.bak
echo >> /data/conf/global.inc
echo "\$conf['site_readonly'] = 1;" >> /data/conf/global.inc
echo >> /data/conf/global.inc
grep site_readonly /data/conf/global.inc
```

## On the Source Host

```sh
rm -f /data/disk/o1/src/*.sql
rm -f /data/disk/o1/log/*.pid
xboa create o1 target-ip
```

## On the Target Host

```sh
service cron stop
chmod 644 /data/all/cpuinfo
(then wait 5 minutes)
```

## On the Source Host

```sh
xboa export o1 target-ip
xboa transfer shared target-ip
xboa transfer o1 target-ip
```

## On the Target Host

```sh
ln -sfn /bin/websh /bin/sh
ln -sfn /bin/websh /usr/bin/sh
ls -la /bin/sh
xboa import o1 target-ip
service nginx reload
xboa post-mig
service cron start
```

## On the Source Host

```sh
xboa proxy o1 target-ip
service nginx reload
xboa post-mig
```
