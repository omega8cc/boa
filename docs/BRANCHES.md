# Introducing the New BOA Branching Scheme

To streamline our development efforts and provide a clear distinction between the increasingly diverse requirements of our **LTS (free)**, **PRO (licensed)**, and **OMM (internal)** BOA branches, we are implementing a new branching scheme. This update is designed to accommodate our growing team and accelerate development while maintaining the highest quality standards. The plan includes incremental rewrites to modernize legacy components.

### Goals of the New Branching Scheme

The updated scheme aims to:
1. Support **rock-stable releases** for both LTS and PRO.
2. Enable **rapid development** and **experimental deployments** through separate branches.
3. Provide a framework for safely experimenting with upcoming features without impacting stable branches.

### Key Changes

While you will still primarily work with two main public branches—**LTS** (free, no commercial license required) and **PRO** (licensed)—the project’s workflow has changed. It's important to understand how these branches interact and how to safely test future releases.

---

### Branching Structure

Each public main branch now includes two additional sub-branches with `-base` and `-edge` suffixes to clarify their roles. Here’s how the new structure works:

#### **Development Branches**
1. **5.x-dev**
   Main development branch where the latest untested changes are committed.
2. **5.x-dev-base**
   Slower development branch, accepting only non-breaking commits from `5.x-dev`.
3. **5.x-dev-edge**
   Experimental branch for testing features from `5.x-dev`.

#### **PRO (Licensed) Branches**
1. **5.x-pro**
   Main stable PRO branch, accepting commits only from `5.x-pro-base`.
2. **5.x-pro-base**
   Testing branch for PRO, accepting commits only from `5.x-dev-base`.
3. **5.x-pro-edge**
   Experimental branch supporting testing for `5.x-pro-base`.

#### **LTS (Free) Branches**
1. **5.x-lts**
   Main stable LTS branch, accepting commits only from `5.x-lts-base`.
2. **5.x-lts-base**
   Testing branch for LTS, accepting commits only from `5.x-dev-base`.
3. **5.x-lts-edge**
   Experimental branch supporting testing for `5.x-lts-base`.

---

### Code Management Workflow

- **LTS and PRO branches:** Both the `5.x-lts` and `5.x-pro` branches rely on their respective `-base` branches for code updates. These `-base` branches receive commits from `5.x-dev-base` after thorough testing.
- **OMM branch:** Reserved for internal development and testing outside public workflows.

### Guidelines for Tagging Releases

- New **tags** should only be applied to the **5.x-pro** and **5.x-lts** branches.
- Tags trigger the BOA SKYNET auto-self-update procedures, so it is crucial to ensure only important incremental batch updates and stable releases are tagged.

### Key Points to Remember
1. Use the **main LTS** and **PRO branches** for stable deployments.
2. Experimentation and testing should be done in the respective `-base` and `-edge` branches.
3. Always tag updates and releases in **5.x-pro** or **5.x-lts** to ensure compatibility with BOA SKYNET auto-update procedures.

---

This new branching scheme ensures greater flexibility, improves stability, and allows for faster innovation across our LTS and PRO offerings. If you have any questions or require guidance on adapting to these changes, please feel free to reach out.

