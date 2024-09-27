# Dual License and BOA Branches Explained

**BOA** remains a **Free/Libre Open Source Project**. While all of **BOA** code is **Free/Libre Open Source**, only the **BOA LTS** branch and **Ægir** are available without any cost or restrictions.

- **LTS**: This public branch remains completely free to use without any commercial license, as it has been from the beginning (previously named HEAD or STABLE). This branch should be considered the **BOA Long Term Support** variant, with slow updates focused on security and bug fixes, and limited new features.

- **DEV**: This public branch requires a commercial license for both installation and upgrades. It includes the latest features, security updates, bug fixes, and updated service versions. This branch should not be used in production without extensive testing.

- **PRO**: This public branch requires a commercial license and is available only as an upgrade from either LTS or DEV (or previous HEAD/STABLE). It offers new releases once ready, closely following the tested DEV branch.

- **OMM**: This private branch is managed separately, with some unused components removed and others added. It is generally simplified for easier maintenance and adheres to modern coding standards.

You can install only **BOA LTS** and then upgrade to **PRO** with a license from [Omega8.cc](https://omega8.cc/licenses).

## Practical Differences Between **LTS** and **PRO**

Over time, **PRO** will be ahead of **LTS** as its name suggests.

The `BOA-5.4.0` release is the last parallel release including all features developed for **PRO**, so both **PRO** and **LTS** users will enjoy the same improvements, bug fixes, and new features.

In the future, new features will be regularly added to **PRO**, while **LTS** will receive only security updates and critical fixes. There may be exceptions, and some new features may find their way to **LTS**, but only as exceptions.

The **PRO** will be available in three main variants, and while all **BOA PRO** licenses will grant access to the same **BOA PRO** branch and features, they will differ in terms of available support levels.

### **PRO** with **Basic Support**

This license is designed for **BOA** users familiar with managing and monitoring their own systems who don't need extended support, monitoring, or assistance in managing their **BOA** installation and updates. Our support is limited to the Issue Queue on GitHub without any kind of SLA or Best Effort guarantee.

Ideal for: Small businesses or developers who need basic support and can handle issues independently or with community help.

### **PRO** with **Advanced Support**

This license is designed for **BOA** users who are familiar with managing their own server but need assistance in handling their custom needs or fixing individual problems privately via our helpdesk at [Ægir Helpdesk](https://aegir.happyfox.com), without posting details on GitHub. There is no SLA guarantee, only a Best Effort guarantee. System local and remote uptime monitoring with Site24x7 is included.

Ideal for: Medium to large businesses needing reliable support during business hours with quick response times for critical issues.

### **PRO** with **Hands-Off Experience**

This license is for **BOA** users who prefer to delegate all the work needed to maintain their **BOA** server, including regular upgrades (both **BOA** and major OS upgrades), active monitoring, and responding to DoS incidents. It comes with a fully managed **BOA PRO** installation you can use without worrying about anything else, with our general SLA guarantee applied: [Omega8.cc SLA](https://omega8.cc/sla). System local and remote uptime monitoring with Site24x7 is included.

Ideal for: Enterprises requiring comprehensive, around-the-clock support with quick response times for all issues.

You can obtain a **BOA PRO** license from [Omega8.cc](https://omega8.cc/licenses).

## Upcoming **PRO-Only** Features

Certain planned features are likely to be exclusive to **BOA PRO**. If these features are added to other **BOA** versions, it will be with a significant delay. However, some key features, such as Backdrop CMS and Grav CMS support, will also be added to **BOA LTS**.

Check out the details in [ROADMAP](https://github.com/omega8cc/boa/tree/5.x-dev/ROADMAP.md)
