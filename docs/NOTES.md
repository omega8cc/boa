# Barracuda _XTRAS_LIST and install mode explained

## Add-ons configurable with _XTRAS_LIST in `/root/.barracuda.cnf`

### Xtras Included with "ALL" Wildcard:

- **ADM**: Adminer DB Manager (installed by default in LOCAL mode)
- **CSF**: Firewall (installed by default in PUBLIC mode)
- **FTP**: Pure-FTPd server with forced FTPS
- **IMG**: Image Optimize binaries: `advdef`, `advpng`, `jpegoptim`, `jpegtran`, `optipng`, `pngcrush`, `pngquant`

### Xtras Which Need to be Listed Explicitly:

- **BND**: Bind9 DNS Server (deprecated)
- **BZR**: Bazaar
- **CGP**: Collectd Graph Panel
- **CSS**: Ruby Gems for Compass
- **FMG**: FFmpeg support (deprecated)
- **NPM**: NPM for Gulp/Bower (requires also /root/.allow.node.lshell.cnf)
- **SR4**: Apache Solr 4 with Jetty 9
- **SR7**: Apache Solr 7
- **SR9**: Apache Solr 9
- **WMN**: Webmin Control Panel (deprecated)

### Examples:

```
_XTRAS_LIST=""
_XTRAS_LIST="ALL"
_XTRAS_LIST="ALL SR9"
```

**NOTE**: The `_XTRAS_LIST` array is by default empty for `PUBLIC` and `LOCAL` mode, but `LOCAL` mode is automatically extended to include also `ADM` Adminer, while `PUBLIC` mode is automatically extended to include also `CSF` firewall so it doesn't matter if you have `ALL` or `CSF` keywords listed in the `_XTRAS_LIST` array in your system `/root/.barracuda.cnf` file -- CSF/LFD will be installed automatically.

**NOTE**: The only optional xtra add-on which requires special attention is `NPM` for Gulp/Bower--it requires presence of `/root/.allow.node.lshell.cnf` control file, because **Node should NOT be installed on system with not trusted/shared accounts**.

- Removing any item from this list once it is already installed, will NOT uninstall anything.

- Configuration file template: [barracuda.cnf](https://github.com/omega8cc/boa/tree/5.x-pro/docs/cnf/barracuda.cnf)

**NOTE**: Collectd will work only if `cgp.master.f-q-d-n` subdomain points to your IP (we recommend using wildcard DNS to simplify it). But don't worry, you can add proper DNS entries for those subdomains later, if you didn't enable wildcard DNS before running the Barracuda installer. Only the system hostname must have proper DNS configuration before installing Barracuda.

## Barracuda _EASY_SETUP options explained

**NOTE**: `123.45.67.89` below is a placeholder for your server's public, real IP address.

**NOTE**: `f-q-d-n` below is a placeholder for your real wildcard-enabled hostname.
Refer to our [DNS wildcard configuration example](http://bit.ly/UM2nRb) for reference.

**NOTE**: If your outgoing SMTP requires using relayhost, define `_SMTP_RELAY_HOST` first.

### Barracuda EASY_SETUP=PUBLIC

With `_EASY_SETUP=PUBLIC` option (default), Barracuda will install automatically the extra services listed below:

- Your Ægir Octopus Instance control panel will be available at `https://your-octopus-aegir-url/`
- Your Adminer Percona Manager will be available at `https://your-octopus-aegir-url/sqladmin/`
- Your Ægir Master Instance control panel will be available at `https://master.f-q-d-n`
- Your CSF/LFD Firewall will support integrated Nginx Abuse Guard.

- Your (optional) Collectd Graph Panel will be available at `https://cgp.master.f-q-d-n`
- Your (optional) MultiCore Apache Solr 4.9.1 with Jetty 9 will listen on `127.0.0.1:8099`
- Your (optional) MultiCore Apache Solr 7.7.3 will listen on `127.0.0.1:9077`
- Your (optional) MultiCore Apache Solr 9.8.1 will listen on `127.0.0.1:9099`
- Your (optional) Webmin Control Panel will be available at `https://f-q-d-n:10000` (deprecated)

### Barracuda EASY_SETUP=LOCAL

With `_EASY_SETUP=LOCAL` option (not enabled by default), Barracuda will configure your local DNS and hostname automatically. No external DNS configuration needed.

With `_EASY_SETUP=LOCAL` option (not enabled by default), Barracuda will install automatically only the services listed below:

- Your Ægir Master Instance control panel will be available at `https://aegir.local`
- Your Fast DNS Cache Server (unbound) will listen on `127.0.0.1:53`
- Your Adminer Percona Manager will be available at `https://adminer.aegir.local`

## Barracuda and Octopus Customized Install and Upgrades

While the BOA system installed per [docs/INSTALL.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/INSTALL.md) comes with many options set by default to make it as easy as possible, you may want to customize it further on upgrade by editing various settings stored in the BOA config files, respectively:

- `/root/.barracuda.cnf` - check [barracuda.cnf](https://github.com/omega8cc/boa/tree/5.x-pro/docs/cnf/barracuda.cnf) template
- `/root/.o1.octopus.cnf` - check [octopus.cnf](https://github.com/omega8cc/boa/tree/5.x-pro/docs/cnf/octopus.cnf) template
- `/root/.o2.octopus.cnf` - check [octopus.cnf](https://github.com/omega8cc/boa/tree/5.x-pro/docs/cnf/octopus.cnf) template
- etc.

Please read [docs/UPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/UPGRADE.md) for simple upgrades how-to.
