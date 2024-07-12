# Contributing to BOA

Guidelines for contributing code and reporting bugs and problems with BOA.

## Bug, Feature, and Patch Submission

- **Active issue queue:** [GitHub Issues](https://github.com/omega8cc/boa/issues)

Reporting bugs is a great way to contribute to BOA. Mis-reporting bugs or duplicating reports, however, can be a distraction to the development team and waste precious resources. So, help out by following these guidelines.

**Important:**
- Every bug report must include a Gist link to the output of the `boa info` command.
- Any bug report failing to follow the guidelines will be ignored and closed.

Before reporting a bug, always search for a similar bug report before submitting your own, and include as much information about your context as possible, including your server/VPS parent system name (like Xen) and/or hosting provider name and URL.

Please always attach the output of the `boa info` command, or for a more detailed system configuration and history report, use the `boa info more` command.

**Do not post your server or error logs directly in the issue.** Instead, use services like [Gist](http://gist.github.com) and post the link in your submission.

**Hint:** Please enable debugging with `_DEBUG_MODE=YES` in the `/root/.barracuda.cnf` file before running an upgrade, so it will display more helpful details. You can find more verbose logs in the `/var/backups/` directory.

It is also a good idea to search our deprecated issue queues for Barracuda and Octopus projects on drupal.org:

- **Legacy issue queue for Barracuda:** [Drupal.org Barracuda Issues](https://drupal.org/project/issues/barracuda)
- **Legacy issue queue for Octopus:** [Drupal.org Octopus Issues](https://drupal.org/project/issues/octopus)

## Help Options

- **Documentation and How-to:** [Omega8.cc Library](https://omega8.cc/library/development)
- **Gitter chat:** [Gitter Chat](https://gitter.im/omega8cc/boa)
- **Commercial support:** [Omega8.cc](https://omega8.cc)
