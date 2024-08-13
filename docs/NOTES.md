# Barracuda _XTRAS_LIST and _EASY_SETUP explained

## Add-ons configurable with _XTRAS_LIST in `/root/.barracuda.cnf`

### Xtras Included with "ALL" Wildcard:

- **ADM**: Adminer DB Manager (installed by default)
- **CSF**: Firewall (installed by default)
- **CSS**: Ruby Gems for Compass + NPM for Gulp/Bower (requires /root/.allow.node.lshell.cnf)
- **FTP**: Pure-FTPd server with forced FTPS (installed by default)
- **GIT**: Latest Git from sources (installed by default)
- **IMG**: Image Optimize binaries: `advdef`, `advpng`, `jpegoptim`, `jpegtran`, `optipng`, `pngcrush`, `pngquant` (installed by default)
- **SR7**: Apache Solr 7

### Xtras Which Need to be Listed Explicitly:

- **HVM**: HHVM Engine—once installed, use `~/static/control/hhvm.info` to enable per Octopus instance. (deprecated)
- **BDD**: SQL Buddy DB Manager (deprecated)
- **BND**: Bind9 DNS Server
- **BZR**: Bazaar
- **CGP**: Collectd Graph Panel (deprecated)
- **CHV**: Chive DB Manager (deprecated)
- **FMG**: FFmpeg support
- **SR1**: Apache Solr 1 with Jetty 7 (deprecated)
- **SR3**: Apache Solr 3 with Jetty 8 (deprecated)
- **SR4**: Apache Solr 4 with Jetty 9
- **WMN**: Webmin Control Panel (deprecated)

### Examples:

```
_XTRAS_LIST=""
_XTRAS_LIST="ALL"
_XTRAS_LIST="ALL SR4"
_XTRAS_LIST="SR4 SR7"
```

- Configuration file template: [barracuda.cnf](https://github.com/omega8cc/boa/tree/5.x-dev/docs/cnf/barracuda.cnf)

## Barracuda _EASY_SETUP options explained

**NOTE**: `123.45.67.89` below is a placeholder for your server's public, real IP address.

**NOTE**: `f-q-d-n` below is a placeholder for your real wildcard-enabled hostname.
Refer to our [DNS wildcard configuration example](http://bit.ly/UM2nRb) for reference.

**NOTE**: If your outgoing SMTP requires using relayhost, define `_SMTP_RELAY_HOST` first.

### Barracuda EASY_SETUP=PUBLIC

With `_EASY_SETUP=PUBLIC` option (default), Barracuda will install automatically only the services listed below:

- Your Ægir Master Instance control panel will be available at `https://master.f-q-d-n`
- Your Fast DNS Cache Server (unbound) will listen on `127.0.0.1:53`
- Your Adminer Percona Manager will be available at `https://adminer.master.f-q-d-n`
- Your CSF/LFD Firewall will support integrated Nginx Abuse Guard.

### Barracuda EASY_SETUP=NO

With `_EASY_SETUP=NO` option (default is PUBLIC), Barracuda will offer installation of services listed below:

- Your Ægir Master Instance control panel will be available at `https://master.f-q-d-n`
- Your Fast DNS Cache Server (unbound) will listen on `127.0.0.1:53`
- Your (optional) Adminer Percona Manager will be available at `https://adminer.master.f-q-d-n`
- Your (optional) Bind9 DNS Server will listen on `123.45.67.89:53`
- Your (optional) Chive Percona Manager will be available at `https://chive.master.f-q-d-n` (deprecated)
- Your (optional) Collectd Graph Panel will be available at `https://cgp.master.f-q-d-n`
- Your (optional) CSF/LFD Firewall will support integrated Nginx Abuse Guard.
- Your (optional) MultiCore Apache Solr 7.7.3 will listen on `127.0.0.1:9077`
- Your (optional) MultiCore Apache Solr 4.9.1 with Jetty 9 will listen on `127.0.0.1:8099`
- Your (optional) MultiCore Apache Solr 3.6.2 with Jetty 8 will listen on `127.0.0.1:8088` (deprecated)
- Your (optional) MultiCore Apache Solr 1.4.1 with Jetty 7 will listen on `127.0.0.1:8077` (deprecated)
- Your (optional) Webmin Control Panel will be available at `https://f-q-d-n:10000` (deprecated)

**NOTE**: Adminer, Chive, SQL Buddy, and Collectd will work only if `adminer.`, `chive.`, `sqlbuddy.`, and `cgp.` subdomains point to your IP (we recommend using wildcard DNS to simplify it). But don't worry, you can add proper DNS entries for those subdomains later, if you didn't enable wildcard DNS before running the Barracuda installer. Only the system hostname must have proper DNS configuration before installing Barracuda.

### Barracuda EASY_SETUP=LOCAL

With `_EASY_SETUP=LOCAL` option (not enabled by default), Barracuda will configure your local DNS and hostname automatically. No external DNS configuration needed.

With `_EASY_SETUP=LOCAL` option (not enabled by default), Barracuda will install automatically only the services listed below:

- Your Ægir Master Instance control panel will be available at `https://aegir.local`
- Your Fast DNS Cache Server (unbound) will listen on `127.0.0.1:53`
- Your Adminer Percona Manager will be available at `https://adminer.aegir.local`

## Barracuda and Octopus Customized Install and Upgrades

While the BOA system installed per [docs/INSTALL.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/INSTALL.md) comes with many options set by default to make it as easy as possible, you may want to customize it further on upgrade by editing various settings stored in the BOA config files, respectively:

- `/root/.barracuda.cnf` - check [barracuda.cnf](https://github.com/omega8cc/boa/tree/5.x-dev/docs/cnf/barracuda.cnf) template
- `/root/.o1.octopus.cnf` - check [octopus.cnf](https://github.com/omega8cc/boa/tree/5.x-dev/docs/cnf/octopus.cnf) template
- `/root/.o2.octopus.cnf` - check [octopus.cnf](https://github.com/omega8cc/boa/tree/5.x-dev/docs/cnf/octopus.cnf) template
- etc.

Please read [docs/UPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/UPGRADE.md) for simple upgrades how-to.
