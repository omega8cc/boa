# Provides

**Included/Enabled by Default** (See [docs/NOTES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/NOTES.md) for details)

1. PHP-FPM versions 8.3/2/1/0, 7.4/3/2/1/0, and 5.6, configurable per site.
2. Latest release of Percona 5.7 database server with Adminer manager.
3. All libraries and tools required to install and run the Nginx-based Ægir system.
4. Magic Speed Booster cache, functioning like a Boost + AuthCache, but per user.
5. Entry-level XSS protection built into Nginx.
6. Firewall csf/lfd integrated with Nginx abuse guard.
7. Autonomous Maintenance and Auto-Healing scripts located in `/var/xdrago`.
8. Local monitoring for uptime and self-healing every 3 seconds.
9. Automated, rotated daily backups for all databases in `/data/disk/arch/sql`.
10. Letsencrypt.org SSL support (See [docs/SSL.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SSL.md) for details).
11. HTTP/2 or SPDY Nginx support.
12. Perfect Forward Secrecy (PFS) support in Nginx.
13. PHP extensions: Zend OPcache, PHPRedis, UploadProgress, MailParse, and ionCube.
14. Fast Redis Cache/Lock/Path with DB auto-failover for all Drupal core versions.
15. Limited Shell, SFTP, and FTPS accounts per Ægir Client with per-site access.
16. Drush access on the command line in all shell accounts.
17. Composer and Drush Make access on the command line for the main shell account only.
18. PHP error debugging, including WSOD, enabled on the fly on `.dev` aliases.
19. Built-in collection of useful modules available on all platforms.
20. Fast DNS Cache Server (unbound).
21. Image Optimize toolkit binaries.

**Optional Add-ons** (See [docs/NOTES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/NOTES.md) for details)

22. MultiCore Apache Solr 7 and Solr 4 (See [docs/SOLR.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SOLR.md) for details).
23. New Relic Apps Monitor with per Octopus license and per site reporting.
24. Ruby Gems and NPM (See [docs/GEM.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/GEM.md) for details).
25. FFmpeg support.
26. Bind9 DNS server.
