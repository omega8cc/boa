# Troubleshooting Common Ægir Workflow Issues

This guide addresses common issues that may arise when working with Ægir, Drush, and Composer, and outlines steps to resolve them.

### 1. **Task Failure: Error - Declaration of `Drupal\Core\Logger\LoggerChannel`**

This error typically shouldn't occur in any `site-task` if you have run `Platform Verify + Lock Drush` (or the lighter `Lock Local Drush`) before executing other tasks like `site clone`, `site migrate` or `site verify`. The `Unlock Local Drush` task is required for `site-local` Drush or Composer to work on the command line, after which the platform must be re-locked before running other Ægir tasks. Forgetting to re-lock, or other underlying issues, may cause tasks such as `site clone`, `site migrate` or `site verify` to fail with the PHP error. The `Lock Local Drush` and `Unlock Local Drush` tasks are themselves idempotent — re-running either on a platform already in that state is a harmless no-op, not an error.

**Resolution Steps:**

If a task fails due to this error, it is crucial to follow the **full recovery cycle** to bring the platform or site back into a working state. The recovery process involves the following steps:

1. **Platform Verify + Lock Drush:**
   Start by running `Verify + Lock Drush` task to ensure the codebase is ready for `site-tasks`.

2. **Unlock Local Drush:**
   Execute `Unlock Local Drush` to remove any codebase permissions locks and un-patch Drupal core.

3. **Platform Verify + Lock Drush Again:**
   After unlocking Drush, run `Platform Verify + Lock Drush` once more to finalize the recovery.

This full cycle is necessary because certain tasks in Ægir may patch or unpatch the core on the fly or adjust file permissions. When an issue like a PHP version mismatch or a codebase error occurs, the platform can go out of sync, requiring multiple steps to fully restore it.

By following this process, you ensure that the platform and site are properly aligned, allowing future Ægir tasks to succeed.

