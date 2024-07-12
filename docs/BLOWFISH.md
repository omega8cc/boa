
## SHA512

Your Devuan or Debian system uses SHA512 for password encryption by default.

This is not bad, and for sure much better than MD5 by default used in BOA for all newly created SSH/FTPS accounts (both main and extra - for Ægir Clients) in all releases up to BOA-2.0.8.

But since BOA forces all users to update their passwords every 90 days, once the user updates their password, it is automatically encrypted with SHA512, so it no longer uses the completely insecure MD5 hashing.

Note that BOA switched to SHA512 instead of MD5 by default in HEAD after BOA-2.0.8 Edition, and will use SHA512 by default starting with BOA-2.0.9.

## WARNING!

1. Make sure you have working SSH (RSA) keys for direct root access without sudo.
2. Make sure you have working SSH (RSA) keys for direct root access without sudo.
3. Make sure you have working SSH (RSA) keys for direct root access without sudo.

**REALLY. Don't even read anything below if you didn't set this up yet!**
You could lock yourself out of your server forever (almost), if your only access is password based and something will go wrong, because you didn't read and follow this how-to *precisely*. If you are interested why it is so important, read the explanation further below.

## BLOWFISH

You can easily switch your system to use much more secure Bcrypt/Blowfish, using the simple steps listed below.

```sh
$ apt-get install libpam-unix2 -y

$ cp -af /usr/share/pam-configs/unix /usr/share/pam-configs/unix2
$ sed -i "s/^Name: Unix/Name: Unix2/g"  /usr/share/pam-configs/unix2
$ sed -i "s/pam_unix.so/pam_unix2.so/g" /usr/share/pam-configs/unix2
$ sed -i "s/nullok_secure//g"           /usr/share/pam-configs/unix2
$ sed -i "s/obscure//g"                 /usr/share/pam-configs/unix2
$ sed -i "s/sha512//g"                  /usr/share/pam-configs/unix2
$ sed -i "s/rounds//g"                  /usr/share/pam-configs/unix2
$ sed -i "s/pam_unix.so/pam_unix2.so/g" /etc/pam.d/pure-ftpd
$ sed -i "s/^CRYPT=des.*/CRYPT=blowfish/g" /etc/security/pam_unix2.default
$ sed -i "s/^BLOWFISH_CRYPT_FILES=.*/BLOWFISH_CRYPT_FILES=8/g" /etc/security/pam_unix2.default

$ pam-auth-update

[*] Unix2 authentication
[*] Unix authentication
```

In the displayed dialog box, please enable "Unix2 authentication" and **DO NOT** disable "Unix authentication". Both should be enabled, or all existing SHA512 passwords, including your root password, will stop working!

You should use Arrow keys, then choose `<Ok>` with Tab and hit Enter to confirm.

## TESTING

Now update your root password and any other account password for testing with the standard `passwd` command. Even if you have disabled password-based root access, you should still keep the password working because you will still need it when accessing the system via remote console, if available.

You will notice in the `/etc/shadow` file that instead of lines similar to:

```
o1.ftp:$1$XVn3/oPw$Me6EZMC2A4/qAayQGRCh2/:15801::90:7:::
=== if $1$ then it is *insecure* MD5 ===

o1.ftp:$6$N52KMMFm$m/CB/sQtgREx1TtlHNy7aBHUxUQMx6r3q8O39FDTbt6Etzfi2ZYqR/AjUWtRWHmz3IPjZQW8xtXJjwbee9dFk0:15822::90:7:::
=== if $6$ then it is better SHA512 ===
```

Now it looks similar to:

```
o1.ftp:$2a$08$EeO3oNMsWxqtvCdWrZfeNeQhwxI0MxqJEDjvRqjZ1Cvc5Yu8XbTlK:15822::90:7:::
=== if $2a$ $08$ then it is the best Bcrypt/Blowfish with 8 work-factor ===
```

Test if the updated password for `o1.ftp` allows you to log in via SSH and FTPS.

Done!

## IMPORTANT!

Only MD5 passwords would still work after enabling "Unix2 authentication" and disabling "Unix authentication", as it is recommended in many how-tos you can find on the net. Their authors even share horrible stories where they managed to lock the access completely and were forced to boot the system from a rescue CD, etc. because they didn't fully realize what they are doing.

The problem is that both root password and any other account password, once updated after initial setup with MD5 used in BOA for non-root accounts previously, will use SHA512, which simply doesn't work when you have disabled "Unix authentication" and enabled only "Unix2 authentication".

Make sure that you have enabled both!

Note that BOA will still use SHA512 for all new or updated automatically extra accounts, but since it still forces you to update passwords every 90 days, all accounts on your system will use Bcrypt/Blowfish as soon as their passwords are updated with the standard `passwd` command, after you have added Bcrypt/Blowfish support using the how-to above.

## REFERENCES

- [Why LivingSocial's 50 Million Password Breach Is Graver Than You May Think](http://arstechnica.com/security/2013/04/why-livingsocials-50-million-password-breach-is-graver-than-you-may-think/)
- [Passwords Under Assault](http://arstechnica.com/security/2012/08/passwords-under-assault/)
- [How To Safely Store A Password](http://codahale.com/how-to-safely-store-a-password/)
- [Use Bcrypt, Fool](http://yorickpeterse.com/articles/use-bcrypt-fool/)
- [Choosing a Bcrypt Work Factor](http://wildlyinaccurate.com/bcrypt-choosing-a-work-factor)
- [Gist: Bcrypt](https://gist.github.com/jkmickelson/3660219)
- [Drupal.org: Password Hashing](https://drupal.org/node/1201444#comment-6448638)
- [Drupal.org: PHPass](https://drupal.org/project/phpass)
- [PHP.net: Crypt](http://www.php.net/manual/en/function.crypt.php)
- [PHP.net: Blowfish](http://www.php.net/security/crypt_blowfish.php)
