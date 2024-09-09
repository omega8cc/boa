## CAVEATS

1. **Devuan-Based Systems Only**

BOA maintainers currently use only 64-bit systems based on Devuan. While Debian may be used as an initial setup, it is mainly supported as a transition step before migrating to Devuan, which is free of systemd. We no longer support or use Ubuntu systems.

2. **Amazon EC2 No Longer Supported**

Amazon EC2 is no longer considered a BOA-friendly environment. With its strict reliance on systemd, it has caused unexpected crashes on BOA instances that previously ran smoothly on legacy Debian Stretch. Additionally, it now prevents upgrading to Devuan, which is systemd-free.

3. **Server (Public) Install Mode Preferred**

BOA maintainers primarily use the server (public) installation mode, which is considered stable and fully supported. The localhost (local) installation mode is rarely tested and remains highly experimental.

4. **VMware Clarification**

When we refer to VMware in this context, we are talking about the virtualization technology, not the company or its vCloud Air service. The vCloud Air service is known to cause issues with Drupal, including problems with CSS/JS aggregation, the AdvAgg module, and other features that require the site to connect to itself via its public IP. These issues are unrelated to BOA itself.
