<?php

function __forbidden_function($name, $obj, $args, $data, &$done) {
  // for debugging only
  // print 'Calling ' . $name . ' is forbidden!<br>';
  $intercepted = TRUE;
}

fb_intercept('shell_exec', '__forbidden_function');
fb_intercept('disk_free_space', '__forbidden_function');
fb_intercept('disk_total_space', '__forbidden_function');
fb_intercept('diskfreespace', '__forbidden_function');
fb_intercept('dl', '__forbidden_function');
fb_intercept('get_cfg_var', '__forbidden_function');
fb_intercept('get_current_user', '__forbidden_function');
fb_intercept('getlastmo', '__forbidden_function');
fb_intercept('getmygid', '__forbidden_function');
fb_intercept('getmyinode', '__forbidden_function');
fb_intercept('getmypid', '__forbidden_function');
fb_intercept('getmyuid', '__forbidden_function');
fb_intercept('ini_restore', '__forbidden_function');
fb_intercept('link', '__forbidden_function');
fb_intercept('pfsockopen', '__forbidden_function');
fb_intercept('posix_getlogin', '__forbidden_function');
fb_intercept('posix_getpwnam', '__forbidden_function');
fb_intercept('posix_getpwuid', '__forbidden_function'); // for debugging only
fb_intercept('posix_getrlimit', '__forbidden_function');
fb_intercept('posix_kill', '__forbidden_function');
fb_intercept('posix_mkfifo', '__forbidden_function');
fb_intercept('posix_setpgid', '__forbidden_function');
fb_intercept('posix_setsid', '__forbidden_function');
fb_intercept('posix_setuid', '__forbidden_function');
fb_intercept('posix_ttyname', '__forbidden_function');
fb_intercept('posix_uname', '__forbidden_function');
fb_intercept('proc_nice', '__forbidden_function');
fb_intercept('proc_terminate', '__forbidden_function');
fb_intercept('show_source', '__forbidden_function');
fb_intercept('symlink', '__forbidden_function');
fb_intercept('opcache_compile_file', '__forbidden_function');
fb_intercept('opcache_get_configuration', '__forbidden_function');
fb_intercept('opcache_get_status', '__forbidden_function');
fb_intercept('opcache_reset', '__forbidden_function');
