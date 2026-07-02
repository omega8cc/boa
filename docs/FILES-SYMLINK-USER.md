# Sites Files Directories Symlinking (per-site how-to)

On BOA, each site's writable `files` and `private` directories live in your
account's **static store** and are linked back into the site with symlinks. It is
automatic and transparent — for normal use you do not need to do anything.

This is the per-site how-to. Server admins should read
[FILES-SYMLINK.md](FILES-SYMLINK.md) for the full picture and tooling.

## What you will see

Inside a site directory, `files` and `private` are symlinks rather than plain
folders:

```
files    -> /data/disk/<account>/static/files/<your-site>/files
private  -> /data/disk/<account>/static/files/<your-site>/private
```

Your uploads, image styles, generated CSS/JS, and private files all work exactly
as before — the symlink is followed automatically. Keeping the real data in the
store means your uploads **survive platform rebuilds and code redeploys**, and
your backups stay fast and consistent.

## Automatic nightly upkeep

Besides linking new sites as they are created, BOA can run a nightly job that
converts any **older** site whose files were not symlinked yet and reports stray
leftover data — keeping everything tidy without you asking.

This nightly upkeep is **on by default only on omega8.cc-hosted systems** (servers
managed for you by omega8.cc). On a **self-hosted** BOA server, or one **remotely
managed by omega8.cc**, it is **off unless your server administrator enables it** —
they turn it on per server, according to that server's available resources. Either
way, the transparent per-site symlinking described above already works everywhere;
only the automatic conversion of older sites depends on this setting.

## Cloning a site

When you clone one of your sites, the clone gets its **own separate copy** of the
files — it never shares the original's uploads. Changing files on one site does
not affect the other.

## Migrating or renaming a site

Migrating a site to another platform, or renaming it (for example promoting a
staging site to your live domain), works the same way: the moved or renamed site
keeps its own files, symlinked into its own store — you don't lose your uploads
and don't need to do anything.

## Reusing a site name

If you delete a site and later create a new one with the **same name**, the new
site starts clean with its own fresh files. Any leftover files from the previous
site of that name are set aside automatically — never mixed into the new site —
so there is nothing you need to clean up first.

## Sharing files between two of your own sites (optional)

Occasionally you may *want* a second site to use another site's files — for
example a staging copy that should read the live site's uploads. To keep such a
deliberate share instead of getting a separate copy, create a control file in
your account's `static/control` directory, named for the site whose files are
shared:

```bash
touch /data/disk/<account>/static/control/share.files.<site>.info
```

While that file exists, an intentional cross-site files link for `<site>` is left
in place. Note that **a clone always gets its own copy** regardless — a freshly
cloned site never inherits a share.

## Keeping plain directories for your account (rare)

If for some reason you need plain `files`/`private` directories instead of
symlinks for your whole account, create:

```bash
touch /data/disk/<account>/static/control/no_native_files_symlink.info
```

New sites in your account will then get plain directories. Remove the file to
return to the default symlinked behaviour. In almost all cases you should leave
this alone — the default is recommended.
