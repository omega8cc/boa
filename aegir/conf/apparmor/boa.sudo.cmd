# AppArmor profile for the commands BOA's backend runs through sudo
# Only boa_sudo reaches this profile, for a command a sudoers line names, as root: the
# nginx init script, boa-dbctl and the fix-drupal and lock-local-drush wrappers, with
# the autosymlink tool behind them. They check their own arguments and work on every
# account's files, so this profile does not try to narrow them. What it keeps out of
# PHP-CLI's profile is the access they need, which a tenant's own process must not
# have, and nginx itself still runs under its own profile.

#include <tunables/global>

profile boa_sudo_cmd flags=(complain) {

  include <abstractions/base>

  capability,
  network,
  signal,
  ptrace,
  unix,

  /** rwlkm,
  /** ix,

  # Started or tested from here, nginx is confined by its own profile as ever
  /usr/sbin/nginx Px,
}
