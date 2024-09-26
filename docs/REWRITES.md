# How To: Customize Rewrites and Locations in Nginx

You can include your custom rewrites/locations configuration to modify or add some custom settings taking precedence over other rules in the main Nginx configuration.

Note that some locations will require using parent literal location to stop searching for / using other regex based locations.

Your custom include file should have filename: `nginx_vhost_include.conf` for standard overrides and/or `nginx_force_include.conf` for high level overrides. The difference between both options is only the point where the extra config file is included, thus `nginx_force_include.conf` can override more than `nginx_vhost_include.conf` file.

Nginx will look for both files in the include directory specified below:

For Satellite Instances: `/data/disk/EDIT_USER/config/server_master/nginx/post.d/`

For Master Instance: `/var/aegir/config/includes/`

These files will be included if exist and will never be modified or touched by Ægir Provision backend system.

Note: your custom rewrite rules will apply to *all* sites on the same Ægir Satellite Instance, unless you will use site/domain specific `if{}` embedded locations, as shown in the examples below.

## Custom rewrites to map legacy content to the Drupal multisite.

```nginx
location ~* ^.+\.(?:jpe?g|gif|png|ico|swf|pdf|ttf|html?)$ {
  access_log off;
  log_not_found off;
  expires 30d;
  rewrite ^/files/(.*)$     /sites/$server_name/files/$1 last;
  rewrite ^/images/(.*)$    /sites/$server_name/files/images/$1 last;
  rewrite ^/downloads/(.*)$ /sites/$server_name/files/downloads/$1 last;
  rewrite ^/download/(.*)$  /sites/$server_name/files/download/$1 last;
  rewrite ^/docs/(.*)$      /sites/$server_name/files/docs/$1 last;
  rewrite ^/documents/(.*)$ /sites/$server_name/files/documents/$1 last;
  rewrite ^/legacy/(.*)$    /sites/$server_name/files/legacy/$1 last;
  try_files $uri =404;
}
```

## Site specific 301 redirect with parent literal location to stop searching for (and using) other regex based locations.

```nginx
location ^~ /some-ltsral-path/no-regex-here {
  location ~* ^/some-path/or-regex-here {
    if ($host ~* ^(www\.)?(domain\.com)$) {
      return 301 $scheme://$host/destination/url;
    }
    try_files $uri @cache;
  }
}
```

## 301 redirect for various legacy .php URIs with parent literal locations to stop searching for (and using) other regex based locations.

```nginx
location ^~ /services {
  location ~* ^/services {
    rewrite ^/services/accounting\.php$ $scheme://$host/node/18 permanent;
    rewrite ^/services/assurance\.php$  $scheme://$host/node/11 permanent;
    rewrite ^/services/audit\.php$      $scheme://$host/node/11 permanent;
    rewrite ^/services/taxation\.php$   $scheme://$host/node/92 permanent;
    rewrite ^/services/wealth\.php$     $scheme://$host/node/15 permanent;
    rewrite ^/services\.php$            $scheme://$host/node/17 permanent;
    try_files $uri @cache;
  }
  try_files $uri @cache;
}
location ^~ /our_team {
  location ~* ^/our_team {
    rewrite ^/our_team\.php$ $scheme://$host/node/10 permanent;
    rewrite ^/our_team$      $scheme://$host/node/10 permanent;
    try_files $uri @cache;
  }
  try_files $uri @cache;
}
```

## Domain specific 301 redirect for legacy .php URIs with literal location to stop searching for (and using) other regex based locations.

```nginx
location = /about_us.php {
  if ($host ~* ^(www\.)?(foo\.com)$) {
    return 301 $scheme://$host/node/19;
  }
  return 403;
}
```

## Helper locations to avoid 404 on legacy images paths

```nginx
if ($main_site_name = '') {
  set $main_site_name "$server_name";
}

location ^~ /sites/default/files {
  location ~* ^/sites/default/files/imagecache {
    access_log off;
    log_not_found off;
    expires 30d;
    set $nocache_details "Skip";
    rewrite ^/sites/default/files/imagecache/(.*)$ /sites/$main_site_name/files/imagecache/$1 last;
    try_files $uri @drupal;
  }
  location ~* ^/sites/default/files/styles {
    access_log off;
    log_not_found off;
    expires 30d;
    set $nocache_details "Skip";
    rewrite ^/sites/default/files/styles/(.*)$ /sites/$main_site_name/files/styles/$1 last;
    try_files $uri @drupal;
  }
  location ~* ^/sites/default/files {
    access_log off;
    log_not_found off;
    expires 30d;
    rewrite ^/sites/default/files/(.*)$ /sites/$main_site_name/files/$1 last;
    try_files $uri =404;
  }
}
```
