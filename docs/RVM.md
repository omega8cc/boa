
# How to Use RVM to Install Compass Tools or NPM to Install Grunt/Gulp/Bower

Since BOA doesn't install Compass Tools or any related gems by default, you need to initialize your account to auto-install Ruby Version Manager (RVM) and then use RVM to install Compass, Bundler, and any other gems required by your theme.

Similarly, you need to initialize your account to auto-install a user-level NPM package directory and then use NPM to install Grunt, Gulp, and/or Bower.

## Important

If you want to use NPM to install Grunt, Gulp, and/or Bower, but you have already enabled RVM before NPM support was added in BOA-3.1.2, you need to reinitialize RVM/NPM on your account: delete the control file, wait until `.gem` and `.rvm` subdirectories disappear, add the control file again, and proceed with the further steps as usual.

**NOTE:** On self-hosted BOA, you must add the non-default CSS symbol to the `_XTRAS_LIST` variable in your `/root/.barracuda.cnf` file, and then run the `barracuda up-lts system` command before initializing RVM or NPM in your limited shell account. This step is automated on BOA managed by Omega8.cc.

Bundler allows you to manage different gem versions per theme, so it is a good idea to use it for gem installation and management. However, you need to install Bundler first.

When you log into your SSH account, you are presented with a helpful intro:

```

      ======== Welcome to the Aegir, Drush and Compass Shell ========

         Type '?' or 'help' to get the list of allowed commands
             Note that not all Drush commands are available

       Use RVM and Bundler to manage all your Compass gems! Example:
                   `gem install --conservative compass`

              Use NPM to manage all your packages! Example:
                        `npm install -g gulp`

       To install RVM use control file and re-login after 15 minutes
                 `touch ~/static/control/compass.info`

```

To initialize your account properly, follow these steps:

1. Create an empty control file: `touch ~/static/control/compass.info`
2. Log out and wait at least 15 minutes.
3. Log in and install Compass: `gem install --conservative compass`
4. Install Bundler: `gem install --conservative bundler`
5. Either `cd` to your theme and run `bundle install` or continue with installing gems manually, for example:
   ```sh
   $ gem install foo_bar
   $ gem install --conservative toolkit
   $ gem install --conservative --version 3.0.3 compass_radix
   ```
6. Install Grunt: `npm install -g grunt`
7. Install Gulp: `npm install -g gulp`
8. Install Bower: `npm install -g bower`

The special, single control file `~/static/control/compass.info` will enable RVM and NPM in all extra SSH accounts on your instance. If you delete this file, the system will remove RVM with all gems and npm packages from all SSH accounts on your Ægir Octopus Instance.

Some gems may require the ability to build their native binaries during installation, which is not possible in the limited shell. When you initialize your account to support Ruby Version Manager (RVM), a few known problematic gems will be pre-installed automatically to limit these problems.

If you encounter an error when attempting to install gems via RVM or Bundler, please let us know, and we will try to add it to the list of automatically pre-installed gems.

You can easily check the list of gems you have access to with the special `gem-list` command. Note that if you haven’t initialized your account yet, this command may display a legacy list of gems previously installed system-wide. You need to initialize your account to stop confusion and see only locally installed Ruby, RVM, and gem versions.

Please note that it is not possible to use Guard in a limited shell via Drush with commands like `drush omega-guard theme`, because it tries to open a sub-shell, which does not work with the limited shell we provide in BOA.

You need to use Guard and Compass tools directly, with commands like `compass watch` or `guard start`. Of course, you have to install Compass and Guard gems first – they are not installed by default.

Note that the initial RVM install may take 15 minutes or longer, so remember to wait until it is complete and then re-login. Once the initial installation is complete, you will be able to run the `rvm --version` command. If it is still not available, you just need to wait a bit longer. It may take even longer if you have extra SSH sub-accounts because the system needs to install separate RVMs along with some problematic gems in every sub-account, so the effective wait time will be multiplied.

If the `bundle install` complains that it can’t build a native extension for the gem `foobar`, but that gem is already installed for you and listed when you type `gem-list`, the first step is to compare these gem versions.

For example, when RVM has been initialized on your account, it installed some problematic gems which can’t be installed in a limited shell: `bluecloth`, `eventmachine`, `ffi`, `hitimes`, `http_parser.rb`, `oily_png`, and `yajl-ruby`.

However, the version installed may be newer or older than the version defined in your theme's `Gemfile.lock` file. To fix the problem, you need to update the gem version in that lock file and then run `bundle install` again, or if you really need a newer version of the problematic gem, you need to reinitialize RVM on your account: delete the control file, wait until `.gem` and `.rvm` subdirectories disappear, add the control file again, and proceed with further steps as usual.

Source: [Omega8.cc](https://omega8.cc/how-to-use-rvm-to-install-compass-tools-329)
