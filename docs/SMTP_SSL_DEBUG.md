# SMTP SSL Error Debugging

You may experience this in the form similar to:

>SMTP stopped working with :"SMTP Error: Could not connect to SMTP host. Connection failed. stream_socket_enable_crypto(): SSL operation failed with code 1. OpenSSL Error messages: error:0A000086:SSL routines::certificate verify failed"

That error almost always means “the TLS handshake started, but PHP/OpenSSL refused the server’s certificate.” Since both Symfony Mailer and the SMTP module fail, it’s not the Drupal module—it’s the connection or the trust store. Here’s a precise checklist to find (and fix) the culprit.

## 1) Sanity checks (the easy wins)

* **Use a hostname, not an IP** in the SMTP config. The cert’s CN/SAN must match the **hostname**.
* **Pick the right port + mode**:

  * Port **587** → “STARTTLS” (explicit TLS).
  * Port **465** → “SSL/TLS” (implicit TLS).
    Mixing these will fail.
* **System clock**: if time/date is off, cert validation fails.

  ```bash
  ntpdate pool.ntp.org
  ```

## 2) Verify the server’s certificate chain from the shell

Replace `smtp.example.com` and port as needed.

**STARTTLS on 587**

```bash
openssl s_client -starttls smtp -connect smtp.example.com:587 -servername smtp.example.com -CAfile /etc/ssl/certs/ca-certificates.crt -showcerts </dev/null | sed -n '/Server certificate/,/subject=/p; /Verify return code/p'
```

**Implicit TLS on 465**

```bash
openssl s_client -connect smtp.example.com:465 -servername smtp.example.com -CAfile /etc/ssl/certs/ca-certificates.crt -showcerts </dev/null | sed -n '/Server certificate/,/subject=/p; /Verify return code/p'
```

You want to see:

```
Verify return code: 0 (ok)
```

If you see a different code/message (expired cert, hostname mismatch, unable to get local issuer certificate, etc.), that’s your root cause.

## 3) Make sure PHP (the one your site is using) can see a valid CA bundle

Check what PHP thinks:

```bash
/opt/php83/bin/php -i | egrep -i 'openssl|default_socket|openssl\.cafile|openssl\.capath|curl\.cainfo'
```

Key items:

* `openssl.cafile` should be **empty** or point to **/etc/ssl/certs/ca-certificates.crt**.
* `openssl.capath` usually **/etc/ssl/certs**.
* If these point to a non-existent file (e.g., from an old BOA build), cert validation will fail.

Fix the CA bundle if needed:

```bash
sudo apt-get update
sudo apt-get --reinstall install ca-certificates
sudo update-ca-certificates
```

## 4) Test with a known-good SMTP client

Install **swaks** (handy for SMTP + TLS):

```bash
apt-get install swaks
swaks --server smtp.example.com --port 587 --tls --tls-verify --protocol ESMTP
# or for 465:
swaks --server smtp.example.com --port 465 --tls --tls-verify --protocol ESMTP
```

If swaks fails with the same verify error, the problem is definitely TLS/CA/hostname, not Drupal.

## 5) Check TLS versions & ciphers (OpenSSL 3 vs old servers)

Some mail servers still only offer legacy ciphers or old TLS. Your box runs OpenSSL 3, which drops a lot of legacy. See what the server offers:

```bash
openssl s_client -starttls smtp -connect smtp.example.com:587 -servername smtp.example.com -cipher 'DEFAULT:@SECLEVEL=1' </dev/null | egrep -i 'Protocol|Cipher|Verify return code'
```

* If lowering security (`@SECLEVEL=1`) makes it work, the server is **too old**. Don’t keep this as a permanent fix—ask the provider to update.
* In PHPMailer/Symfony-Mailer you can sometimes set crypto method to TLS 1.2+ explicitly. For PHPMailer (Drupal SMTP module) there’s an “Advanced” option for **SMTPOptions**—but you should fix the server or CA instead of weakening security.

## 6) Drupal SMTP module settings (PHPMailer)

In **/admin/config/system/smtp**:

* Ensure Encryption matches the port (see §1).
* **Do not** enable “allow self-signed” unless you truly use a private CA.
* If your provider uses an enterprise/private CA, import it:

  ```bash
  mkdir -p /usr/local/share/ca-certificates/custom
  cp /path/to/provider-root-or-intermediate.crt /usr/local/share/ca-certificates/custom/provider.crt
  update-ca-certificates
  ```

  Then (optionally) point “CA file” in SMTP settings to `/etc/ssl/certs/ca-certificates.crt`.

## 7) Hostname/SNI pitfalls

* If you connect by IP or override name in `/etc/hosts` **and** your mailer passes the IP as the peer name, SNI/hostname verification will fail. Always use the **public SMTP hostname** in the module config.
* With `openssl s_client`, always include `-servername smtp.example.com` to test SNI correctly.

## 8) IPv6 edge case

If DNS for the SMTP host has AAAA and your outbound prefers IPv6 but the provider’s IPv6 endpoint presents a different certificate/chain, you’ll get verify errors. Quick test:

```bash
# Force IPv4:
openssl s_client -starttls smtp -connect smtp.example.com:587 -servername smtp.example.com -4 -CAfile /etc/ssl/certs/ca-certificates.crt </dev/null
```

If IPv4 succeeds but default fails, pin IPv4 (or ask the provider to fix their IPv6 TLS chain).

## 9) If it still fails—collect the exact failure

Run and share the tail lines:

```bash
openssl s_client -starttls smtp -connect smtp.example.com:587 -servername smtp.example.com -CAfile /etc/ssl/certs/ca-certificates.crt -showcerts </dev/null | tail -n +1 | sed -n '/Certificate chain/,$p'
```

Look for:

* **“unable to get local issuer certificate”** → missing intermediate CA → fix with updated `ca-certificates`.
* **“certificate has expired”** → provider must renew.
* **“IP address mismatch” / “hostname mismatch”** → use correct hostname.
* **Non-zero verify code** with legacy cipher notes → server too old vs OpenSSL 3.

