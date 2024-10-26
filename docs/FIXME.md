# Troubleshooting Common Aegir Workflow Issues

This guide addresses common issues that may arise when working with Aegir, Drush, and Composer, and outlines steps to resolve them.

### 1. **Task Failure: Error - Declaration of `Drupal\Core\Logger\LoggerChannel`**

This error typically shouldn't occur in any `site-task` if you have run `Platform Verify + Lock Drush` before executing other tasks like `site clone`, `site migrate` or `site verify`, but may appear for example if you are trying to run `Unlock Local Drush` after it was already unlocked. The `Unlock Local Drush` task is required for `site-local` Drush or Composer to work on command line. However, forgetting this step or other underlying issues may cause tasks such as `site clone`, `site migrate` or `site verify` to fail with the PHP error.

**Resolution Steps:**

If a task fails due to this error, it is crucial to follow the **full recovery cycle** to bring the platform or site back into a working state. The recovery process involves the following steps:

1. **Platform Verify + Lock Drush:**
   Start by running `Verify + Lock Drush` task to ensure the codebase is ready for `site-tasks`.

2. **Unlock Local Drush:**
   Execute `Unlock Local Drush` to remove any codebase permissions locks and un-patch Drupal core.

3. **Platform Verify + Lock Drush Again:**
   After unlocking Drush, run `Platform Verify + Lock Drush` once more to finalize the recovery.

This full cycle is necessary because certain tasks in Aegir may patch or unpatch the core on the fly or adjust file permissions. When an issue like a PHP version mismatch or a codebase error occurs, the platform can go out of sync, requiring multiple steps to fully restore it.

By following this process, you ensure that the platform and site are properly aligned, allowing future Aegir tasks to succeed.

