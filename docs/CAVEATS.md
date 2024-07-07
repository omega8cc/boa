
# CAVEATS

**Note:** BOA maintainers currently use only Devuan-based 64-bit systems/servers.
We no longer use Ubuntu, while Debian is mainly supported as a starting point before migration to its systemd-free alternative -- Devuan.

**Note:** BOA maintainers use only server (public) install mode and rarely test localhost (local) mode, which is considered highly experimental, while server (public) mode is considered stable and fully supported.

**Note:** By VMware we mean the system, not the company or its hosted service, the vCloud Air, which is known to cause serious issues for Drupal in general, which are not related to anything in BOA. The vCloud Air has a major flaw which breaks many Drupal features, including image derivatives, AdvAgg, and any other module which requires that the site can connect to itself via its public IP address.
