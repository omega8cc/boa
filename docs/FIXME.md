# Troubleshooting Common Aegir Workflow Issues

This guide addresses common issues that may arise when working with Aegir, Drush, and Composer, and outlines steps to resolve them.

### 1. **Task Failure: Error - Declaration of `Drupal\Core\Logger\LoggerChannel`**

This error typically shouldn't occur if you have run `platform verify` before executing Drush or Composer commands (required for Drupal 10+). However, forgetting this step or other underlying issues may cause tasks such as clone, migrate, or verify to fail.

**Resolution Steps:**

If a task fails due to this error, it is crucial to follow the **full recovery cycle** to bring the platform or site back into a working state. The recovery process involves the following steps:

1. **Run Platform Verify:**
   Start by running `platform verify` to ensure the core and platform files are intact.

2. **Unlock Drush:**
   Execute `platform Drush unlock` to remove any task locks that could prevent Drush or Composer commands from running.

3. **Run Platform Verify Again:**
   After unlocking Drush, run `platform verify` once more to finalize the recovery and bring the platform back into sync.

This full cycle is necessary because certain tasks in Aegir may patch or unpatch the core on the fly or adjust file permissions. When an issue like a PHP version mismatch or a codebase error occurs, the platform can go out of sync, requiring multiple steps to fully restore it.

By following this process, you ensure that the platform and site are properly aligned, allowing future Aegir tasks to succeed.

