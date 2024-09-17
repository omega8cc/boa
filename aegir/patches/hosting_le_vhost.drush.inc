<?php

/**
 * Register our directory as a place to find provision classes.
 */
function hosting_le_vhost_register_autoload() {
  static $loaded = FALSE;
  if (!$loaded) {
    $loaded = TRUE;
    $list = drush_commandfile_list();
    $provision_dir = dirname($list['provision']);
    if (is_readable($provision_dir . '/provision.inc')) {
      include_once($provision_dir . '/provision.inc');
      include_once($provision_dir . '/provision.service.inc');
      if (function_exists('provision_autoload_register_prefix')) {
        provision_autoload_register_prefix('Provision_', dirname(__FILE__));
      }
    }
  }
}

/**
 * Implements hook_drush_init().
 */
function hosting_le_vhost_drush_init() {
  hosting_le_vhost_register_autoload();
}

/**
 *  Implements hook_provision_services().
 */
function hosting_le_vhost_provision_services() {
  hosting_le_vhost_register_autoload();
  return array('Le' => NULL);
}

/*
 * Implementation of hook_provision_nginx_vhost_config()
 */
function hosting_le_vhost_provision_nginx_vhost_config($uri, $data) {

  if (d()->type == 'site') {

    $aegir_root = d('@server_master')->aegir_root;
    $le_cert = d('@server_master')->aegir_root . "/tools/le/certs";
    $is_boa = FALSE;
    $is_boa_ctrl = "/data/conf/global.inc";

    if (provision_file()->exists($is_boa_ctrl)->status()) {
      $is_boa = TRUE;
    }

    $main_name = $real_name = substr(d()->name, 1);
    if ($real_name == 'hostmaster') {
      $real_name = $main_name = d()->uri;
    }

    if (d()->redirection) {
      $main_name = d()->redirection;
      if ($is_boa) {
        $cert_dir = $le_cert . "/" . $real_name;
      }
      else {
        $cert_dir = $le_cert . "/" . $main_name;
      }
    }
    else {
      $cert_dir = $le_cert . "/" . $main_name;
    }

    $chain_pem = $cert_dir . "/chain.pem";

    $lines = array();

    $lines[] = "";
    if (d()->ssl_enabled) {
      if (provision_file()->exists($chain_pem)->status()) {
        $lines[] = "  ssl_trusted_certificate    $chain_pem;";
        $lines[] = "";
      }
    }
    $lines[] = "  ###";
    $lines[] = "  ### Allow access to letsencrypt.org ACME challenges directory.";
    $lines[] = "  ###";
    $lines[] = "  location ^~ /.well-known/acme-challenge {";
    $lines[] = "    allow all;";
    $lines[] = "    alias $aegir_root/tools/le/.acme-challenges;";
    $lines[] = "    try_files \$uri 404;";
    $lines[] = "  }";
    $lines[] = "\n";

    $lines[] = "  ###";
    $lines[] = "  ### Allow access to SQL Adminer.";
    $lines[] = "  ###";
    $lines[] = "  location ^~ /sqladmin/ {";
    $lines[] = "    if (\$is_crawler) {";
    $lines[] = "      return 403;";
    $lines[] = "    }";
    $lines[] = "    include /var/aegir/config/includes/ip_access/sqladmin.*;";
    $lines[] = "    alias /var/www/adminer;";
    $lines[] = "    index index.php index.html;";
    $lines[] = "    try_files \$uri 404;";
    $lines[] = "  }";
    $lines[] = "\n";

    return implode("\n", $lines);
  }

  return '';
}

/*
 * Implementation of hook_provision_apache_vhost_config()
 */
function hosting_le_vhost_provision_apache_vhost_config($uri, $data) {

  $aegir_root = d('@server_master')->aegir_root;

  if (d()->type == 'site') {

    $lines = array();

    $lines[] = "";
    $lines[] = "  Alias /.well-known/acme-challenge $aegir_root/tools/le/.acme-challenges";
    $lines[] = "";
    $lines[] = "  # Allow access to letsencrypt.org ACME challenges directory.";
    $lines[] = "  <Directory \"$aegir_root/tools/le/.acme-challenges\">";
    $lines[] = "    Order allow,deny";
    $lines[] = "    Allow from all";
    $lines[] = "    Require all granted";
    $lines[] = "    Satisfy Any";
    $lines[] = "  </Directory>";
    $lines[] = "\n";

    return implode("\n", $lines);
  }

  return '';
}
