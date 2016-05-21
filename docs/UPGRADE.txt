
###
### Important Notes - Read This First!
###

 => If you haven't run full barracuda+octopus upgrade to latest BOA Stable
    Edition yet, don't use any partial upgrade modes explained further below.
    Once new BOA Stable is released, you must run *full* upgrades with commands:

    $ cd;wget -q -U iCab http://files.aegir.cc/BOA.sh.txt;bash BOA.sh.txt
    $ barracuda up-stable
    $ barracuda up-stable system           (recommended on major upgrade)
    $ octopus up-stable all both
    $ bash /var/xdrago/manage_ltd_users.sh (recommended on major upgrade)
    $ bash /var/xdrago/daily.sh            (recommended on major upgrade)

    For silent, logged mode with email message sent once the upgrade is
    complete, but no progress is displayed in the terminal window, you can run
    alternatively, starting with screen session to avoid incomplete upgrade
    if your SSH session will be closed for any reason before the upgrade
    will complete:

    $ screen
    $ cd;wget -q -U iCab http://files.aegir.cc/BOA.sh.txt;bash BOA.sh.txt
    $ barracuda up-stable log
    $ octopus up-stable all both log

    Note that the silent, non-interactive mode will automatically say Y/Yes
    to all prompts and is thus useful to run auto-upgrades scheduled in cron.

 => Don't run any installer via sudo.
    You must be logged in as root or `sudo -i` first.

 => Please never use HEAD version on any production server. Always use Stable.
    The HEAD can be occasionally broken and should be used *only* for testing!

 => All commands will honor settings in their respective config files:

    /root/.barracuda.cnf
    /root/.o1.octopus.cnf

    However, arguments specified on command line will take precedence - see
    upgrade modes explained below.


###
### Available Standard Upgrade Modes
###

    Download and run (as root) BOA Meta Installer first:

    $ cd;wget -q -U iCab http://files.aegir.cc/BOA.sh.txt;bash BOA.sh.txt

 => To upgrade system and Aegir Master Instance to Stable use:

    $ barracuda up-stable

 => To upgrade selected Aegir Satellite Instance to Stable use:

    $ octopus up-stable o1

 => To upgrade *all* Aegir Satellite Instances to Stable use:

    $ octopus up-stable all


###
### Available Custom Upgrade Modes
###

 => You can append "log" as the last argument to every command, and it will
    write the output to the file instead of to the console, respectively:

    /var/backups/reports/up/barracuda/*
    /var/backups/reports/up/octopus/*

    Examples:

    $ barracuda up-stable log
    $ octopus up-stable all log

    Detailed backend log on barracuda upgrade is always stored in /var/backups/

 => You can append "system" as a last argument to the barracuda command, and
    it will upgrade only the system, without running Aegir Master Instance
    upgrade, plus it will write the output to the file instead of console:

    /var/backups/reports/up/barracuda/*

    Example:

    $ barracuda up-stable system

    Note that while both "log" and "system" modes are "silent", because they
    don't display anything in your console, they will send the log via email
    to your address specified in the config file: /root/.barracuda.cnf

    It is recommended that you start `screen` before running commands using
    the "silent" mode - to avoid confusion or incomplete tasks when your
    SSH connection drops for any reason.

 => It is possible to set/force the upgrade mode on the fly using optional
    arguments: {aegir|platforms|both}

    Note that none is similar to "both", however "both" will force aegir plus
    platforms upgrade, while none will honor also settings from the octopus
    instance cnf file, where currently only "aegir" mode is defined with
    _HM_ONLY=YES option.

    Examples:

    $ octopus up-stable o1 aegir
    $ octopus up-stable o1 platforms log
    $ octopus up-stable all aegir log
    $ octopus up-stable all platforms

 => To keep Legacy version instead of Stable, use the same commands, but
    replace "up-stable" with the legacy version you want to still use:
    "up-2.4", "up-2.3" or "up-2.2".

    The oldest Legacy version (up-2.2) is the last Edition in the 2.2.x series
    which still supported Drupal 5 and used Drush 4 with old Aegir version.
    Note that once you have current stable or head installed, you can't
    go back to any legacy version.

 => To use HEAD instead of Stable, use the same commands, but replace
    "up-stable" with "up-head". Please never use HEAD version on any production
    server. Always use Stable. The HEAD can be occasionally broken and should
    be used *only* for testing!

