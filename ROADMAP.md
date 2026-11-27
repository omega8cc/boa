# BOA Roadmap

BOA and Ægir are developed continuously, these days with AI assisted engineering under human review, and work that once filled a season now ships within days. A hand-kept list of finished features cannot keep up with that pace, so this page no longer carries one. It says where the project is heading, and where the complete and current record of what has shipped lives.

All features ship to both **LTS** and **PRO** — the branches are kept **1:1**. The only exception is the **extended backup sub-system** (see RELEASED IN BOA PRO only), the sole feature requiring a **BOA PRO** license subscription — designed as something extra for those who decided to support BOA.

Please also note that the LTS branch is **kept up to date alongside PRO**: frequent security updates and serious new-feature work are ongoing — and the free branch receives them.

## WHERE WE ARE HEADING

- **Ægir Admin Interface**: A new control-panel interface over the proven Ægir engine, which stays in place behind it; Backdrop CMS remains an option for the engine itself, decided later
- **The Site Lifecycle from the Control Panel**: The Upgrade task family for Drupal 10 and newer sites — [Upgrade and Go back](https://docs.boa.io/using/deploying-code/upgrading-a-site), Upgrade all sites, [Build newer version](https://docs.boa.io/using/deploying-code/building-a-newer-version) and the [Upgrade that builds a newer platform first](https://docs.boa.io/using/deploying-code/upgrading-with-a-build) — is the first of the panel's work to be shaped this way: one task that checks, builds, moves and keeps a way back. The same tasks do not take a site to Drupal 12 yet; that step follows once BOA's own Drupal 12 platform is in the built set

## RELEASED IN BOA PRO only

- **Amazon S3 Alternatives**: Integrate support for AWS S3 eight (8) alternatives in `multiback` and `mybackup`

## WHAT HAS SHIPPED

Everything BOA has released is recorded where it stays current without a second list to maintain:

- [**Release notes**](https://docs.boa.io/releases): every BOA release, with what it brought
- [**CHANGELOG.txt**](https://github.com/omega8cc/boa/blob/5.x-dev/CHANGELOG.txt): every change, release by release
- [**Documentation changelog**](https://docs.boa.io/changelog): what changed on docs.boa.io, by date
- [**Blog**](https://omega8.cc/blog) and [**news**](https://omega8.cc/news): the stories behind the features, and the release announcements
