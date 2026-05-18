# Welcome to the Fast Lane of HTTPS: HTTP/3 and KTLS

## New BOA-5.9.1 PRO/LTS Release Notes

  Yes, we said that BOA-LTS would enter complete code freeze for 2026, but
  we think that the major new features and many security updates introduced in
  the last two months must be shared with the entire community before we enter
  a less rapid feature development cycle for the next few months.

  The future of 100% Open Source Drupal hosting is brighter than ever!

  With BOA-5.9.1 PRO/LTS, we proudly deliver full HTTP/3 and KTLS support —
  a fundamental change in the way modern browsers communicate with modern
  HTTPS web servers — along with the latest OpenSSL 3.5 LTS, which made it
  possible, a clever and very professional tool to diagnose your server hardware
  performance in the context of BOA-specific requirements and capabilities,
  and many critical security and bug fixes related to system components.

  This groundbreaking feature not only pushes the boundaries of what BOA
  can achieve but also reaffirms our commitment to staying ahead of the curve
  for modern Drupal deployments.

  We are thrilled to introduce BOA-5.9.1 PRO/LTS, our 8th release under the
  new branch structure and dual licensing model. It merges 2 months of
  intense development from the DEV branch, delivering 333 commits packed
  with powerful features, critical fixes, and enhancements.

  Thank you to everyone who supports our work by purchasing a BOA PRO license:
  https://omega8.cc/boapro.

  As always, this announcement highlights only the most impactful changes.
  For a full breakdown, explore the complete commit history.

## Key New Features Explained

 * HTTP/3 and KTLS support. If you run Drupal sites that should feel fast and
   responsive (and stay that way during spikes), this is genuinely good news.
   Why is this a big deal? What should visitors notice? [**Read the full story!**](https://github.com/omega8cc/boa/tree/5.x-pro/HTTP3.md)

 * Percona 8.4 comes to Excalibur. We no longer need vanilla MySQL 8.4 now that
   Percona has released its own build for Debian Trixie, which can be used on
   Devuan Excalibur. There is no MySQL-to-Percona upgrade option yet, though.
   Please note that we still recommend Devuan Daedalus as the most versatile
   system, which can also support Percona 8.0 and 5.7.

 * Curious if your VM is good enough to fully benefit from BOA optimisations
   and deliver a first-class Drupal hosting environment? There’s a deep
   hardware and network analysis tool available: simply type `perftest` as root.

 * From now on, all BOA installers will download their components as packaged
   batches instead of dozens of separate little modules. They will also no longer
   rely on fetching complete repositories from GitHub, instead downloading only
   the latest packaged code from our mirrors. You can revert to the old method
   by changing _DL_MODE=BATCH to _DL_MODE=GIT in /root/.barracuda.cnf

## 4 NEW, 12 UPDATED, 32 TOTAL Drupal distros/platforms available

  While most of you typically build your own codebases/platforms with Composer
  these days, we still deliver a list of 32 platforms ready to use in your Ægir.

  Since these platforms are updated only with BOA releases, they are not really
  intended for production use per se, because you typically need a faster
  lifecycle to keep your sites secure.

  However, they provide a wide range of testing playgrounds, because you can
  install only those you wish to test or use, and reinstall if needed, with
  the help of our BOA-only feature that allows you to upgrade your Ægir
  on demand with two simple control files, as described in the built-in docs
  you can always find in ~/static/control/README.txt.

## Going Local with Infrastructure

  We’ve expanded our network considerably to meet the growing expectations of
  the **Data Sovereignty** movement. This isn’t just about adding more cities
  to our hosting map — it’s also about going local with infrastructure
  wherever we can.

  We no longer rely solely on big-name vendors and hyperscalers. Instead, we’re
  gradually migrating to local providers and data centers in every country where
  we offer hosted BOA for Drupal.

  For example, in Canada you can now choose not only **Toronto**, but also
  **Montreal**, **Calgary**, and **Vancouver**. In Australia, it’s no longer
  just **Sydney** — we also offer **Adelaide**, **Brisbane**, and **Perth**.

  We’ve also added an excellent facility in **New Zealand**.

  Of course, we continue to support our original **Singapore** location and
  still offer **EU**, **UK**, and **US** options.

## Usage disk/sql limits x2 + Aero and Archive plans

  It's worth mentioning that our hosted BOA plans have received a huge upgrade:
  several new locations have been added around the world, our vendors are now
  local (instead of the previous US-only hyperscalers), and an entirely new
  Archive Tier has been added for those looking to host collections of
  low-traffic sites at low cost.

  [**Take a look if you are interested**](https://omega8.cc/hosted)

For the full scoop, check out the [changelog](https://github.com/omega8cc/boa/blob/5.x-pro/CHANGELOG.txt).

Thank you!

