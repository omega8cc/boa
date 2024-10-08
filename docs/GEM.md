# How To: Enable Ruby Gems and Node/NPM

To enable Ruby Gems support you need to initialize your account and then use the `gem` command to install Compass and any other necessary gems for your theme. It takes only 5 minutes max and is now 3x faster than before.

Similarly, to enable Node/NPM support, you need to initialize your account to auto-install a user-level NPM packages directory. Afterward, you can use NPM to install Grunt, Gulp, and/or Bower.

## Security Considerations for Node/NPM

Since `node` can be used to bypass Limited Shell and create a significant security risk within the BOA system, it should not be enabled on any BOA system with multiple `lshell` users. Consequently, Node/NPM support is not enabled in BOA by default. To enable it, you must create an empty control file `/root/.allow.node.lshell.cnf`. Node/NPM support on hosted BOA is available only on dedicated systems like Phantom and Cluster.

Please note that Node/NPM support, if allowed with `/root/.allow.node.lshell.cnf` file, will be enabled only on the main Ægir Octopus `lshell` account. The `client` level sub-accounts will receive their own Ruby Gems access only.

## How It Works

If you want to use Ruby Gems or Node/NPM to install Grunt, Gulp, or Bower, and you previously enabled Ruby Gems support, you will need to reinitialize Ruby/NPM on your account due to security and deployment improvements made in BOA-5.4.0.

1. Delete the control file `~/static/control/compass.info`.
2. Wait until you can no longer issue the `compass --version` command (5 minutes max)
3. Add the control file `~/static/control/compass.info` again and wait (5 minutes max)
4. Proceed with the further steps as usual.

**NOTE:** On self-hosted BOA, you must add the non-default CSS symbol to the `_XTRAS_LIST` variable in your `/root/.barracuda.cnf` file and then run the `barracuda up-lts system` command before initializing Ruby Gems or NPM support in your limited shell account. This step is automated on BOA managed by Omega8.cc.

Bundler allows you to manage different gem versions per theme, making it a valuable tool for gem installation and management. It's installed for you by default.

When you log into your SSH account, you will be presented with a helpful intro:

```

      ======== Welcome to the Aegir, Drush and Compass Shell ========

         Type '?' or 'help' to get the list of allowed commands
             Note that not all Drush commands are available

       Use Gem and Bundler to manage all your Compass gems! Example:
                   `gem install --conservative compass`

              Use NPM to manage all your packages! Example:
                        `npm install -g gulp`

      To initialize Ruby use control file and re-login after 5 minutes
                 `touch ~/static/control/compass.info`

```

To initialize your account for Ruby Gems and Node/NPM support, follow these steps:

1. Create an empty control file: `touch ~/static/control/compass.info`
2. Log out and wait 5 minutes.
3. Log in and install Compass: `gem install --conservative compass`
4. Navigate to your theme directory and run `bundle install`, or manually install gems as needed:
   ```sh
   gem install foo_bar
   gem install --conservative toolkit
   gem install --conservative --version 3.0.3 compass_radix
   ```
5. Install Grunt: `npm install -g grunt`
6. Install Gulp: `npm install -g gulp`
7. Install Bower: `npm install -g bower`

The special control file `~/static/control/compass.info` enables Ruby Gems support for the main Ægir Octopus SSH account and for all `client` level SSH sub-accounts on your instance. Deleting this file will remove all Ruby Gems from all SSH accounts on your Ægir Octopus Instance and will remove Node/NPM support from the main account.

The non-default Node/NPM support, if allowed with `/root/.allow.node.lshell.cnf` file, is initialized using the same `~/static/control/compass.info` file, but will be enabled only on the main Octopus `lshell` account. The `client` level sub-accounts will receive their own Ruby Gems access only.

Some gems may require the ability to build their native binaries during installation, which is not possible in the limited shell. When you initialize your account to support Ruby Gems, a few known problematic gems will be pre-installed automatically to mitigate these issues.

If you encounter errors when attempting to install gems via Gem or Bundler, please let us know, and we will try to add them to the list of automatically pre-installed gems.

You can easily check the list of gems you have access to with the `gem-list` command. Note that if you haven’t initialized your account yet, this command may display a legacy list of gems previously installed system-wide. Initializing your account will ensure that only locally installed Ruby and gem versions are shown.

Please note that it is not possible to use Guard in a limited shell via Drush with commands like `drush omega-guard theme`, because it attempts to open a sub-shell, which does not work with the limited shell provided by BOA.

You need to use Guard and Compass tools directly, with commands like `compass watch` or `guard start`. Ensure that Compass and Guard gems are installed first, as they are not installed by default.

The initial Ruby Gems installation may take 5 minutes. Remember to wait until it is complete before re-logging in. Once the installation is finished, you will be able to run the `gem --version` command. If it is still unavailable, please wait a bit longer. The process may take a little longer time if you have extra SSH sub-accounts, as the system installs separate Ruby Gems and some problematic gems in every sub-account.

If `bundle install` complains that it can’t build a native extension for the gem `foobar`, but the gem is already installed and listed when you type `gem-list`, first compare the gem versions.

For example, when Ruby Gems support is initialized on your account, it installs some problematic gems that can’t be installed in a limited shell: `bluecloth`, `eventmachine`, `ffi`, `hitimes`, `http_parser.rb`, `oily_png`, and `yajl-ruby`.

The installed version may differ from the version defined in your theme's `Gemfile.lock` file. To resolve this issue, update the gem version in the lock file and run `bundle install` again. If you require a different version of the problematic gem, reinitialize Ruby Gems support on your account by deleting the control file, waiting until you can no longer issue the `compass --version` command, and proceeding with the further steps as usual.
