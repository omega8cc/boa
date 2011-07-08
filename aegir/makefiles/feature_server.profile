<?php

/**
 * Return a description of the profile for the initial installation screen.
 *
 * @return
 *   An array with keys 'name' and 'description' describing this profile.
 */
function feature_server_profile_details() {
  return array(
    'name' => 'Feature Server',
    'description' => 'Select this profile to deploy a feature server.'
  );
}

/**
 * Return an array of the modules to be enabled when this profile is installed.
 *
 * @return
 *  An array of modules to be enabled.
 */
function feature_server_profile_modules() {
  return array(
    /* optional core */
    'color', 'comment', 'dblog', 'help', 'menu', 'taxonomy',
    /* other contrib */ 
    'content', 'context', 'ctools', 'features', 'filefield', 'fserver', 'install_profile_api', 'nodereference', 'nodereference_url', 'number', 'optionwidgets', 'strongarm', 'text', 'views',
  );
}

/**
* Implementation of hook_profile_tasks().
*/
function feature_server_profile_tasks() {

  // Install the core required modules and our extra modules
  $core_required = array('block', 'filter', 'node', 'system', 'user');
  install_include(array_merge(feature_server_profile_modules(), $core_required));

  // Make a 'maintainer' role
  install_add_role('maintainer');
  $rid = install_get_rid('maintainer');
  // Set some permissions for the role
  $perms = array(
    'access content', 
    'create fserver_project content', 
    'create fserver_release content',
    'edit own fserver_project content',    
    'edit own fserver_release content',
    'delete own fserver_project content',    
    'delete own fserver_release content',
    'access comments', 
    'post comments without approval',
  );

  install_add_permissions($rid, $perms);

  // Change anonymous user's permissions - since anonymous user is always rid 1 we don't need to retrieve it
  $perms = array(
    'access content', 
    'access comments', 
    'post comments',
  );

  install_add_permissions(1, $perms);

  // Enable the Tao subtheme
  install_enable_theme("tao");

  // Enable default theme
  install_default_theme("singular");

  // Put the navigation block in the sidebar because the sidebar looks awesome.
  install_init_blocks();
  // Recent comments
  install_set_block('user', 1, 'singular', 'right');

  // call rebuild - this makes the cck fields 'associate' to their node types properly
  features_rebuild();
 
  // Set the front page to be fserver
  variable_set('site_frontpage', 'fserver');

}
