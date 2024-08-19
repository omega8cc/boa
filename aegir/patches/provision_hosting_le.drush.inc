<?php

/**
 * Implements hook_post_provision_verify().
 */
function drush_provision_hosting_le_post_provision_verify() {

  if (d()->type == 'site') {
    $le_root = d('@server_master')->aegir_root . "/tools/le";
    $le_cert = d('@server_master')->aegir_root . "/tools/le/certs";
    $le_acme = d('@server_master')->aegir_root . "/tools/le/.acme-challenges";
    $le_ctrl = d('@server_master')->aegir_root . "/tools/le/.ctrl";
    $le_exec = d('@server_master')->aegir_root . "/tools/le/dehydrated";
    $le_conf = d('@server_master')->aegir_root . "/tools/le/config.sh";
    $le_cnfx = d('@server_master')->aegir_root . "/tools/le/config";
    $le_acct = d('@server_master')->aegir_root . "/tools/le/accounts";
    $le_hook = d('@server_master')->aegir_root . "/tools/le/letsencrypt-sh-hooks.sh";
    $cf_hook = d('@server_master')->aegir_root . "/tools/le/hooks/cloudflare/hook.py";

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
      drush_log('[hosting_le] This sitename redirection target is ' . d()->redirection, 'info');
      $main_name = d()->redirection;
      if ($is_boa) {
        $cert_dir = $le_cert . "/" . $real_name;
      }
      else {
        $cert_dir = $le_cert . "/" . $main_name;
        drush_log('[hosting_le] LE SSL certificate will be valid only for ' . d()->redirection, 'info');
      }
    }
    else {
      $cert_dir = $le_cert . "/" . $main_name;
    }

    drush_log('[hosting_le] This cert_dir is ' . $cert_dir, 'info');

    if ($is_boa) {
      drush_log('[hosting_le] This site main SSL name is ' . $real_name, 'info');
      drush_log('[hosting_le] BOA system detected, congrats!', 'info');
    }
    else {
      drush_log('[hosting_le] This site main SSL name is ' . $main_name, 'info');
    }

    $wildcard_ctrl = d('@server_master')->aegir_root . "/static/control/wildcard-enable-" . $main_name . ".info";
    drush_log('[hosting_le] The optional wildcard flag is ' . $wildcard_ctrl, 'info');

    $legacy_tls_ctrl = d('@server_master')->aegir_root . "/static/control/tls-legacy-enable-" . $main_name . ".info";
    drush_log('[hosting_le] The optional legacy TLSv1.1 flag is ' . $legacy_tls_ctrl, 'info');

    $no_san_ctrl = d('@server_master')->aegir_root . "/static/control/ssl-no-san-" . $main_name . ".info";
    drush_log('[hosting_le] The optional no-SAN flag is ' . $no_san_ctrl, 'info');

    $yes_dev_ctrl = d('@server_master')->aegir_root . "/static/control/ssl-yes-dev-" . $main_name . ".info";
    drush_log('[hosting_le] The optional enable-DEV flag is ' . $yes_dev_ctrl, 'info');

    $immutable = $le_ctrl . "/dont-overwrite-" . $main_name . ".pid";
    drush_log('[hosting_le] The optional immutable flag is ' . $immutable, 'info');

    $demo_mode_ctrl = $le_ctrl . "/ssl-demo-mode.pid";
    drush_log('[hosting_le] The optional demo flag is ' . $demo_mode_ctrl, 'info');

    // https://community.letsencrypt.org/t/revoking-certain-certificates-on-march-4/114864
    $forced_renewal_ctrl = $le_ctrl . "/forced-renewal-02-" . $main_name . ".pid";

    $site_mode_demo_ctrl = $le_ctrl . "/demo-" . $main_name . ".pid";
    $site_mode_live_ctrl = $le_ctrl . "/live-" . $main_name . ".pid";

    $force_renew = FALSE;

    $on_remote_server = !provision_is_local_host(d()->platform->web_server->remote_host);
  }

  $is_wildcard = FALSE;
  if (provision_file()->exists($wildcard_ctrl)->status()) {
    if (provision_file()->exists($cf_hook)->status()) {
      if (provision_file()->exists($le_cnfx)->status()) {
        $is_wildcard = TRUE;
        $main_name = preg_replace('`^www\.`', '', $main_name);
        $real_name = preg_replace('`^www\.`', '', $real_name);
      }
    }
  }

  if (d()->type == 'site' &&
     !d()->ssl_enabled &&
     !provision_file()->exists($immutable)->status()) {
    if (file_exists($cert_dir)) {
      exec("/bin/bash " . $le_exec . " --cleanup", $output_b);
      $acme_result_b = implode(' ', $output_b);
      drush_log('[hosting_le] ACME Cleanup Output: ' . $acme_result_b, 'info');

      exec("symlinks -dr " . $cert_dir, $output_c);
      $acme_result_c = implode(' ', $output_c);
      drush_log('[hosting_le] ACME Cleanup Symlinks: ' . $acme_result_c, 'info');
    }
  }
  elseif (d()->type == 'site' &&
          d()->ssl_enabled) {

    provision_file()->create_dir($le_root, dt('[hosting_le] LE root'), 0711);
    provision_file()->create_dir($le_cert, dt('[hosting_le] LE certs'), 0700);
    provision_file()->create_dir($le_acme, dt('[hosting_le] LE challenges'), 0711);
    provision_file()->create_dir($le_ctrl, dt('[hosting_le] LE ctrl'), 0711);

    if (!provision_file()->exists($le_exec)->status()) {
      drush_log('[hosting_le] Please upload dehydrated to ' . $le_exec, 'warning');
      drush_log('[hosting_le] URL: https://raw.githubusercontent.com/omega8cc/dehydrated/master/dehydrated', 'warning');
      return FALSE;
    }

    if ($on_remote_server && !provision_file()->exists($le_hook)->status()) {
      drush_log('[hosting_le] Please copy letsencrypt-sh-hooks.sh to ' . $le_root, 'warning');
      return FALSE;
    }

    $enable_dev_ctrl = FALSE;
    if (provision_file()->exists($yes_dev_ctrl)->status()) {
      $enable_dev_ctrl = TRUE;
      drush_log('[hosting_le] SSL enable-DEV mode ctrl file detected for ' . $main_name, 'info');
    }

    if ($is_boa) {
      if (preg_match("/\.(?:host8|boa|aegir|o8)\.(?:biz|io|cc)$/", $main_name) ||
          preg_match("/\.(?:nodns)\./", $main_name)
         ) {
        drush_log('[hosting_le] Skipping LE setup for ' . $main_name, 'warning');
        return FALSE;
      }
      if (!$enable_dev_ctrl) {
        if (preg_match("/\.(?:temp|tmp|temporary)\./", $main_name) ||
          preg_match("/\.(?:test|testing)\./", $main_name) ||
          preg_match("/\.(?:dev|devel)\./", $main_name)
          ) {
          drush_log('[hosting_le] Skipping LE setup for ' . $main_name, 'warning');
          return FALSE;
        }
      }
    }

    if (provision_file()->exists($demo_mode_ctrl)->status()) {
      if (!provision_file()->exists($le_conf)->status()) {

        $le_conf_lines = "CA=\"https://acme-staging-v02.api.letsencrypt.org/directory\"\n";

        provision_file()->file_put_contents($le_conf, $le_conf_lines)
          ->succeed('[hosting_le] Created cnf ' . $le_conf)
          ->fail('[hosting_le] Could not create cnf ' . $le_conf);

        copy($le_conf, $le_cnfx);

        if (provision_file()->exists($le_acct)->status()) {
          drush_log('[hosting_le] Demo LE account will be created.', 'info');
          rename($le_acct, $le_acct . "-live");
        }

        drush_log('[hosting_le] New LE accounts require registration on ACMEv2.', 'info');
        drush_log('[hosting_le] Running --register --accept-terms as required by ACMEv2.', 'info');
        $le_register = " --register --accept-terms";
        exec("/bin/bash " . $le_exec . $le_register . " 2>&1", $register_output);
        $acme_register = implode(' ', $register_output);
        drush_log("[hosting_le] ACMEv2 Demo Register Output: " . $acme_register, 'info');
        $acme_register = "";
      }
      drush_log('[hosting_le] Demo LE mode active. No real LE certs will be generated.', 'info');
      $demo_mode = TRUE;
    }
    else {
      if (provision_file()->exists($le_conf)->status()) {
        unlink($le_conf);
        unlink($le_cnfx);
        if (provision_file()->exists($le_acct)->status()) {
          rename($le_acct, $le_acct . "-demo");
        }
        drush_log('[hosting_le] Live LE account will be registered.', 'info');
        drush_log('[hosting_le] New LE accounts require registration on ACMEv2.', 'info');
        drush_log('[hosting_le] Running --register --accept-terms as required by ACMEv2.', 'info');
        $le_register = " --register --accept-terms";
        exec("/bin/bash " . $le_exec . $le_register . " 2>&1", $register_output);
        $acme_register = implode(' ', $register_output);
        drush_log("[hosting_le] ACMEv2 Live Register Output: " . $acme_register, 'info');
        $acme_register = "";
      }
      drush_log('[hosting_le] Live LE mode active. Real LE certs will be generated.', 'info');
      $demo_mode = FALSE;
    }

    if ($demo_mode) {
      if (file_exists($site_mode_live_ctrl) || !file_exists($site_mode_demo_ctrl)) {
        unlink($site_mode_live_ctrl);
        $force_renew = TRUE;
        drush_log('[hosting_le] Forcing DEMO certificate renew for ' . $main_name, 'info');
      }
      if (!file_exists($site_mode_demo_ctrl)) {
        provision_file()->file_put_contents($site_mode_demo_ctrl, $main_name)
          ->succeed('[hosting_le] Created pid ' . $site_mode_demo_ctrl)
          ->fail('[hosting_le] Could not create pid ' . $site_mode_demo_ctrl);
      }
    }
    else {
      if (file_exists($site_mode_demo_ctrl) || !file_exists($site_mode_live_ctrl)) {
        @unlink($site_mode_demo_ctrl);
        $force_renew = TRUE;
        drush_log('[hosting_le] Forcing LIVE certificate renew for ' . $main_name, 'info');
      }
      if (!file_exists($site_mode_live_ctrl)) {
        provision_file()->file_put_contents($site_mode_live_ctrl, $main_name)
          ->succeed('[hosting_le] Created pid ' . $site_mode_live_ctrl)
          ->fail('[hosting_le] Could not create pid ' . $site_mode_live_ctrl);
      }
    }

    if (!file_exists($forced_renewal_ctrl)) {
      $force_renew = TRUE;
      provision_file()->file_put_contents($forced_renewal_ctrl, $main_name)
        ->succeed('[hosting_le] Created pid ' . $forced_renewal_ctrl)
        ->fail('[hosting_le] Could not create pid ' . $forced_renewal_ctrl);
    }

    // WIP: needed after certs deleted
    // $force_renew = TRUE;

    drush_log('[hosting_le] LE certificate for ' . $main_name, 'info');

    if (provision_file()->exists($no_san_ctrl)->status()) {
      $no_alt_names = TRUE;
      drush_log('[hosting_le] SSL no-SAN mode ctrl file detected for ' . $main_name, 'info');
    }
    else {
      $no_alt_names = FALSE;
      if ($is_boa) {
        if (!empty(d()->aliases)) {
          foreach (d()->aliases as $alias) {
            if ($is_wildcard) {
              if (!preg_match("/\.(?:host8|boa|aegir|o8)\.(?:biz|io|cc)$/", $alias) &&
                !preg_match("/\.(?:nodns)\./", $alias) &&
                !strpos($alias, $main_name)) {
                $alt_names .= ' --domain ' . str_replace('/', '.', $alias);
              }
            }
            else {
              if (!preg_match("/\.(?:host8|boa|aegir|o8)\.(?:biz|io|cc)$/", $alias) &&
                !preg_match("/\.(?:nodns)\./", $alias)) {
                $alt_names .= ' --domain ' . str_replace('/', '.', $alias);
              }
            }
          }
        }
      }
      else {
        if (!empty(d()->aliases)) {
          $alt_names = implode(' --domain ', str_replace('/', '.', d()->aliases));
          $alt_names = ' --domain ' . $alt_names;
        }
      }
      drush_log('[hosting_le] ALT names:' . $alt_names, 'info');
    }

    $web_server = d()->platform->web_server;
    // check if server is a pack
    if ($web_server->master_web_servers) {
      // use pack master
      $web_server = d(reset($web_server->master_web_servers));
    }
    $site_vhost = $web_server->http_vhostd_path . "/" . $real_name;

    if (provision_file()->exists($site_vhost)->status()) {
      $grep_output = '';
      $redirect_result = '';
      $http_service_type = $web_server->http_service_type;

      if ($http_service_type == 'nginx_ssl') {
        exec("/bin/grep  \"alias redirection virtual host\" " . $site_vhost, $grep_output);
      }
      elseif ($http_service_type == 'apache_ssl') {
        exec("/bin/grep  \"Redirect all aliases\" " . $site_vhost, $grep_output);
      }

      $redirect_result = implode(' ', $grep_output);
      drush_log('[hosting_le] Redirect check result for ' . $main_name . ' : ' . $redirect_result, 'info');

      if ($redirect_result && !$no_alt_names && !$is_boa) {
        drush_log("[hosting_le] Aliases redirection must be disabled if all aliases are expected to be listed as SAN names.", 'info');
        drush_log("[hosting_le] The alternative is to disable SAN mode for this site with empty ctrl file: " . $no_san_ctrl, 'info');
        drush_log('[hosting_le] Forcing no-SAN-mode for ' . $main_name, 'info');
        $no_alt_names = TRUE;
      }
    }
    else {
      drush_log("[hosting_le] The site's vhost must already exist, or the LE agent will not be able to proceed.", 'warning');
      drush_log('[hosting_le] Path to vhost: ' . $site_vhost, 'info');
      drush_log('[hosting_le] Skipping LE setup for ' . $main_name, 'warning');
      return FALSE;
    }

    if (provision_file()->exists($immutable)->status() &&
        provision_file()->exists($cert_dir)->status()) {
      $needs_update = FALSE;
      drush_log("[hosting_le] Immutable protection mode detected for this domain: " . $cert_dir, 'info');
      drush_log("[hosting_le] SSL Certificate for this domain already exists in: " . $cert_dir, 'info');
      drush_log("[hosting_le] You can replace it with any other certificate since it will be left here as-is forever.", 'info');
      drush_log("[hosting_le] To re-activate LE auto-renewals please delete this file: " . $immutable, 'info');
      drush_log("[hosting_le] NOTE: On hosted Aegir service you need to contact your host support for further assistance.", 'info');
    }
    else {
      drush_log("[hosting_le] To stop the LE Certificate auto-renewals please create an empty ctrl file.", 'info');
      drush_log("[hosting_le] Path to use for this site specific empty ctrl file: " . $immutable, 'info');
      drush_log("[hosting_le] You could then replace existing cert with any other cert since it will be left here as-is forever.", 'info');
      drush_log("[hosting_le] NOTE: On hosted Aegir service you need to contact your host support for further assistance.", 'info');
      $output = '';
      $le_options = " --cron --ipv4";
      $le_challenge = " --domain " . $real_name . " --challenge dns-01 --hook " . $cf_hook;
      if ($on_remote_server) {
        $le_options .= " --hook " . $le_hook;
      }
      if ($force_renew) {
        if ($no_alt_names || empty($alt_names)) {
          if ($is_wildcard) {
            $le_options .= " --alias " . $real_name . " --domain *." . $real_name . $le_challenge;
            exec("/bin/bash " . $le_exec . $le_options . " --force 2>&1", $output);
          }
          else {
            exec("/bin/bash " . $le_exec . $le_options . " --force --domain " . $main_name . ' 2>&1', $output);
          }
        }
        else {
          if ($is_wildcard) {
            $le_options .= " --alias " . $real_name . " --domain *." . $real_name . $alt_names . $le_challenge;
            exec("/bin/bash " . $le_exec . $le_options . " --force 2>&1", $output);
          }
          else {
            exec("/bin/bash " . $le_exec . $le_options . " --force --domain " . $real_name . $alt_names . ' 2>&1', $output);
          }
        }
      }
      else {
        if ($no_alt_names || empty($alt_names)) {
          if ($is_wildcard) {
            $le_options .= " --alias " . $real_name . " --domain *." . $real_name . $le_challenge;
            exec("/bin/bash " . $le_exec . $le_options . " 2>&1", $output);
          }
          else {
            exec("/bin/bash " . $le_exec . $le_options . " --domain " . $main_name . ' 2>&1', $output);
          }
        }
        else {
          if ($is_wildcard) {
            $le_options .= " --alias " . $real_name . " --domain *." . $real_name . $alt_names . $le_challenge;
            exec("/bin/bash " . $le_exec . $le_options . " 2>&1", $output);
          }
          else {
            exec("/bin/bash " . $le_exec . $le_options . " --domain " . $real_name . $alt_names . ' 2>&1', $output);
          }
        }
      }
      $acme_result = implode(' ', $output);
      drush_log("[hosting_le] ACME Output: " . $acme_result, 'info');
      if (!provision_file()->exists($cert_dir)->status()) {
        $needs_update = FALSE;
        drush_log("[hosting_le] Hmm.. For some reason cert_dir doesn't exist:  " . $cert_dir, 'info');
        drush_log("[hosting_le] I couldn't generate LE cert during this Verify procedure.", 'info');
        drush_log("[hosting_le] It's normal while running a series of Verify sub-tasks during Rename/Migrate.", 'info');
        drush_log("[hosting_le] But if this happens during standalone Verify, maybe permissions are incorrect.", 'info');
        drush_log("[hosting_le] Let's abort the procedure here. Bye.", 'info');
        return FALSE;
      }
      else {
        if (preg_match("/unchanged.*Skipping/i", $acme_result)) {
          $needs_update = FALSE;
          drush_log("[hosting_le] The existing LE Certificate is up to date in " . $cert_dir, 'success');
        }
        elseif (preg_match("/Forcing.*renew/i", $acme_result) &&
                preg_match("/Creating.*fullchain/i", $acme_result)) {
          $needs_update = TRUE;
          drush_log("[hosting_le] The LE Certificate has been successfully updated in " . $cert_dir, 'success');
        }
        elseif (preg_match("/Forcing.*renew/i", $acme_result) &&
               !preg_match("/Creating.*fullchain/i", $acme_result)) {
          $needs_update = FALSE;
          drush_log("[hosting_le] The LE Certificate attempted update looks incomplete in " . $cert_dir, 'warning');
          drush_log("[hosting_le] Make sure that all aliases have valid DNS names pointing to your instance IP address.", 'warning');
          if (!$is_boa) {
            drush_log("[hosting_le] Aliases redirection must be disabled, or the LE agent will not be able to proceed.", 'warning');
          }
          drush_log("[hosting_le] The alternative is to disable SAN mode for this site with empty ctrl file: " . $no_san_ctrl, 'warning');
        }
        elseif (preg_match("/Requesting.*challenge/i", $acme_result) &&
               !preg_match("/Forcing.*renew/i", $acme_result) &&
               !preg_match("/Creating.*fullchain/i", $acme_result)) {
          $needs_update = FALSE;
          drush_log("[hosting_le] The LE Certificate attempted creation failed in " . $cert_dir, 'warning');
          drush_log("[hosting_le] Make sure that all aliases have valid DNS names pointing to your instance IP address.", 'warning');
          if (!$is_boa) {
            drush_log("[hosting_le] Aliases redirection must be disabled, or the LE agent will not be able to proceed.", 'warning');
          }
          drush_log("[hosting_le] The alternative is to disable SAN mode for this site with empty ctrl file: " . $no_san_ctrl, 'warning');
        }
        else {
          $needs_update = TRUE;
          drush_log("[hosting_le] The LE Certificate has been successfully [re]generated in " . $cert_dir, 'success');
        }
      }
    }

    if ($needs_update && !provision_file()->exists($immutable)->status()) {

      exec("/bin/bash " . $le_exec . " --cleanup", $output_clean);
      $acme_result_clean = implode(' ', $output_clean);
      drush_log('[hosting_le] ACME Cleanup Output: ' . $acme_result_clean, 'info');

      $ssl_symlinks[] = d('@server_master')->ssld_path . "/" . $real_name;
      $ssl_symlinks[] = $web_server->http_ssld_path . "/" . $real_name;

      foreach ($ssl_symlinks as $symlink) {
        if (provision_file()->exists($symlink)->status()) {
          drush_log('[hosting_le] File exists: ' . $symlink, 'info');

          if (!is_link($symlink)) {
            drush_log('[hosting_le] Moving original directory out of the way: ' . $symlink, 'info');

            // This will overwrite symlink.bak if necessary, so we don't end up
            // with dozens of backups of unused certificates.
            rename($symlink, $symlink . ".bak");
          }
          else {
            drush_log('[hosting_le] SSL certificate already symlinked: ' . $symlink, 'success');
            continue;
          }
        }

        drush_log('[hosting_le] Creating symlink at ' . $symlink, 'info');

        if (symlink($cert_dir, $symlink)) {
          drush_log('[hosting_le] Symlinked cert directory to ' . $symlink, 'success');
        }
        else {
          drush_log('[hosting_le] Could not symlink cert directory to ' . $symlink, 'warning');
        }
      }

      drush_log('[hosting_le] Replacing openssl symlinks.', 'info');

      $filenames = array(
        'openssl.crt' => 'cert.pem',
        'openssl.csr' => 'cert.csr',
        'openssl.key' => 'privkey.pem',
        'openssl_chain.crt' => 'fullchain.pem',
      );

      $success = TRUE;
      foreach ($filenames as $original => $target) {
        // Remove current symlink or file (this would have been generated by
        // Aegir AFTER the original dir symlinking, meaning it's self-generated
        // and therefore unimportant.
        @unlink($cert_dir . "/" . $original);

        $success = ($success && symlink($cert_dir . "/" . $target, $cert_dir . "/" . $original));
      }

      if ($success) {
        drush_log('[hosting_le] Successfully replaced all symlinks.', 'success');
      }
      else {
        drush_log('[hosting_le] Could not replace one or more symlinks. Check ' . $certdir, 'warning');
      }

      $web_server->sync($le_cert . '/' . $real_name);
      $web_server->sync($web_server->http_ssld_path);

      $pid = $le_ctrl . "/" . $main_name . ".pid";

      if (file_exists($cert_dir) && !file_exists($pid)) {
        provision_file()->file_put_contents($pid, $main_name)
          ->succeed('[hosting_le] Created pid ' . $pid)
          ->fail('[hosting_le] Could not create pid ' . $pid);
        // We will not run the secondary Verify if pid file doesn't exist,
        // to avoid verify-inside-verify loop which could overload the system.
        if (provision_file()->exists($pid)->status()) {
          drush_log('[hosting_le] Running Verify again to reload web server once openssl_chain.crt is present in the vhost', 'info');
          $local_uri_verify = '@' . $real_name;
          provision_backend_invoke($local_uri_verify, 'provision-verify');
          // We could run it via frontend but it is not needed currently.
          //provision_backend_invoke('@hostmaster', 'hosting-task', array($local_uri_verify, 'verify'), array('force' => TRUE));
          sleep(5); // A small trick to avoid high load and race conditions.
        }
      }

      drush_log('[hosting_le] Restarting webserver', 'info');
      $web_server->restart();
    }
  }
}
