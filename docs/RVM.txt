
  @=> How to use RVM to install Compass Tools or NPM to install Gulp/Bower

  Since BOA no longer install Compass Tools nor any related gems by default,
  you need to initialize your account first to auto-install Ruby Version Manager
  (RVM) and then use rvm to install Compass, Bundler and any other gems
  required by your theme.

  Similarly, you need to initialize your account first to auto-install a user-
  level NPM package directory and then use NPM to install Gulp and/or Bower.

  NOTE! On self-hosted BOA you must add the non-default CSS symbol to the
  _XTRAS_LIST variable in your /root/.barracuda.cnf file and then run the
  'barracuda up-stable system' command before initializing RVM or NPM in your
  limited shell account. This step is automated on BOA managed by Omega8.cc

  Note that Bundler allows you to manage different gems versions per theme,
  so it is a good idea to use it for gems installation and management, but
  of course you need to install Bundler first.

  When you log in your SSH account, you are presented with helpful intro:

      ======== Welcome to the Aegir, Drush and Compass Shell ========
         Type '?' or 'help' to get the list of allowed commands
             Note that not all Drush commands are available
       Use RVM and Bundler to manage all your Compass gems! Example:
             `rvm all do gem install --conservative compass`
              Use NPM to manage all your packages! Example:
                        `npm install -g gulp`
    To install RVM and NPM use control file and re-login after 15 minutes
                 `touch ~/static/control/compass.info`

  To initialize your account properly, follow these steps:

  1. Create an empty control file: 'touch ~/static/control/compass.info'
  2. Log out and wait 15 minutes
  3. Log in and install Compass: 'rvm all do gem install --conservative compass'
  4. Install Bundler: 'rvm all do gem install --conservative bundler'
  5. Now either 'cd' to your theme and run 'bundle install' or..
  6. Continue with installing gems manually, for example:

  $ rvm all do gem install foo_bar
  $ rvm all do gem install --conservative toolkit
  $ rvm all do gem install --conservative --version 3.0.3 compass_radix

  7. Install Gulp: 'npm install -g gulp'
  8. Install Bower: 'npm install -g bower'
  9. Continue with installing packages manually, for example:

  $ npm install -g foo_bar

  The special, single control file ~/static/control/compass.info will enable
  RVM and NPM also in all extra SSH accounts on your instance. If you delete
  this file, the system will remove RVM with all gems and npm packages from
  all SSH accounts on your Aegir Octopus Instance.

  Some gems may require ability to build their native binaries during the
  install, which is not possible in the limited shell. When you initialize your
  account to support Ruby Version Manager (RVM), a few known problematic gems
  will be installed automatically, to limit these problems.

  If you will get error when attempting to install gems via RVM or Bundler,
  please let us know and we will try to add it to the automatically installed
  gems exceptions.

  You can easily check the list of gems you have access to with special
  'gem-list' command. Note that if you didn’t initialize your account yet,
  this command may display a legacy list of gems previously installed,
  but system-wide. You need to initialize your account to stop confusion and
  see only locally installed Ruby, RVM and gems versions.

  Please note that it is not possible to use Guard in a limited shell via Drush
  with commands like 'drush omega-guard theme', because it is trying to open
  a sub-shell, which is not going to work with limited shell we provide in BOA.
  You need to use Guard and Compass tools directly, with commands like
  'compass watch' or 'guard start'. Of course you have to install Compass and
  Guard gems first – they are not installed by default.

  Note that initial RVM install may take 15 minutes or longer, so remember to
  wait until it is complete and then re-login. Once the initial install is
  complete, you will be able to run 'rvm --version' command, but if it is still
  not available, you just need to wait a bit longer. It may take even longer
  if you have extra SSH sub-accounts, because the system needs to install
  separate RVM along with some problematic gems in every sub-account,
  so the effective wait time will be multiplied.

  If the 'bundle install' complains that it can’t build native extension
  for gem foobar, but that gem is already installed for you and listed when
  you type 'gem-list', the first step is to compare this gem versions.
  For example, when RVM has been initialized on your account, it installed
  some problematic gems which can’t be installed in limited shell: bluecloth,
  eventmachine, ffi, hitimes, http_parser.rb, oily_png and yajl-ruby.

  However, the version installed may be newer or older than version defined
  in your theme Gemfile.lock file. To fix the problem, you need to update gem
  version in that lock file and then run 'bundle install' again, or, if you
  really need a newer version of the problematic gem, you need to re-initialize
  RVM on your account: delete the control file, wait until .gem and .rvm
  subdirectories disappear, add the control file again, and proceed with
  further steps as usual.

  Source: https://omega8.cc/how-to-use-rvm-to-install-compass-tools-329
