
# Notes Regarding Drupal Development on BOA

## Drupal 8

**Note:** All commands/paths are relative to the site folder, not the platform.

### Disable Redis

Redis is automatically disabled if you use a dev domain and the following file exists:
```sh
touch files/development.services.yml
```

### Theme Debug Mode (Twig)

To enable theme debugging for your Drupal 8 site you need to use a dev domain (*.dev.*) and add the following in `files/development.services.yml`:

```yaml
services:
  cache.backend.null:
    class: Drupal\Core\Cache\NullBackendFactory

parameters:
  twig.config:
    debug: true
    auto_reload: true
    cache: false
```

## Drupal 7

**Note:** All commands/paths are relative to the site folder, not the platform.

### Disable Redis

Edit `modules/boa_site_control.ini`.

### Theme Debug Mode

As of Drupal 7.33, you can enable theme debug mode via the variable: `theme_debug`. You can configure it using one of the methods below.

#### Drush

```sh
drush variable-set theme_debug 1
```

#### Configuration (local.settings.php)

```php
$conf['theme_debug'] = TRUE;
```
