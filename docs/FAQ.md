# FAQ

**Q: Can I use BOA to host Drupal sites outside of Ægir?**

**A:** Yes, but it is an unsupported feature, so you need to figure out how to do it properly and you should be prepared that things may explode without any warning after the next BOA upgrade. All custom vhosts must reside in the master vhosts directory: `/var/aegir/config/server_master/nginx/vhost.d/` to avoid GHOST vhost detection and auto-cleanup which runs daily, but only for all Octopus instances in `/data/disk` directory tree.

---

**Q: Can I use BOA to host sites with different engines, like WordPress?**

**A:** Yes, but it is an unsupported feature, so you need to figure out how to do it properly and you should be prepared that things may explode without any warning after the next BOA upgrade. All custom vhosts must reside in the master vhosts directory: `/var/aegir/config/server_master/nginx/vhost.d/` to avoid GHOST vhost detection and auto-cleanup which runs daily.

Check also:

- [Drupal Node 1416798](https://drupal.org/node/1416798)
- [GitHub Issue 359](https://github.com/omega8cc/boa/issues/359)

---

**Q: Can I install services and apps not included in BOA?**

**A:** It depends. BOA uses very aggressive upgrade procedures and if it is not aware of extra services installed and running, it may even uninstall them if the system packages dependency autoclean triggers such action, so you need to watch closely what happens during and after barracuda upgrade. Note that you can specify extra packages in the special `_EXTRA_PACKAGES` variable in the `/root/.barracuda.cnf` file -- This should help, but you should still watch closely what happens during and after barracuda upgrade.

---

**Q: Can I call Drush from PHP scripts running via PHP-FPM (web-based requests)?**

**A:** Theoretically yes, but Drush should never be available for web requests, period. Not because we are telling you that it is bad and ugly, but because PHP-CLI and PHP-FPM are totally separate tools for many reasons, including privileges separation, security, cascades of various limits, etc. You should use a better, proper, and secure method to run PHP, and if you need to extend or interact with Drupal via web requests, you should use Drupal API, along with contrib or custom modules and never attempt to call Drush from PHP-FPM.

---

**Q: How to increase PHP-FPM `memory_limit`?**

**A:** While limits are still auto-configured, depending on available RAM and CPU cores and written in the respective PHP ini files, the only place to modify `memory_limit` manually is the line with `php_admin_value[memory_limit]` in a file shared between all PHP-FPM pools in all running PHP versions: `/opt/etc/fpm/fpm-pool-common.conf` -- of course you need to reload all running FPM versions to make the change active, for example: `service php74-fpm reload`, `service php81-fpm reload`, etc.
Check also: [Drupal Comment 8689745](https://drupal.org/comment/8689745#comment-8689745)

The same applies to some other hardcoded/enforced limits:

```php
php_admin_value[max_execution_time] = 180
php_admin_value[max_input_time] = 180
php_admin_value[default_socket_timeout] = 180
```

Note: You can modify this file, but your changes will be overwritten on every barracuda upgrade.
