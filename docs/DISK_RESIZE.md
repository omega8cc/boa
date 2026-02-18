# Live Disk Resize How-To

This covers the common “plan upgraded, disk grew, but system still sees old sizes / fstab out of sync” situations on Debian/Devuan-like systems (GPT, ext4 root, EFI partition).

---

### Dependencies

Install only if missing:

```bash
apt-get update
apt-get install -y gdisk cloud-guest-utils parted
```

Provides:

* `sgdisk` (from `gdisk`) — GPT fixes/backup
* `growpart` (from `cloud-guest-utils`) — extend partition safely
* `partprobe` (from `parted`) — ask kernel to re-read partition table (optional)

Filesystem grow for ext4:

* `resize2fs` (usually already installed via `e2fsprogs`)

---

### Situation A: Partition already uses full disk, filesystem is smaller

**Symptoms**

* `lsblk` shows `/dev/sda1` already near disk size
* `df -h /` shows smaller size than `lsblk`
* `resize2fs` hasn’t been run yet

**Steps**

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT /dev/sda
df -h /
resize2fs -p /dev/sda1
df -h /
```

Done.

---

### Situation B: Disk grew, but GPT warnings + root partition still old size

**Symptoms**

* `fdisk -l /dev/sda` shows e.g. 100G disk but `sda1` still ~50G
* Warnings like:

  * `GPT PMBR size mismatch (...) will be corrected by write.`
  * `The backup GPT table is not on the end of the device.`

**Goal**
Fix GPT metadata, extend partition in-place, then grow ext4 — **no rebuild**.

#### 1) Backup GPT (recommended)

```bash
sgdisk --backup=/root/sda.gpt.backup /dev/sda
```

#### 2) Fix GPT headers to match new disk end

```bash
sgdisk -e /dev/sda
```

#### 3) Extend root partition to fill disk

```bash
growpart /dev/sda 1
```

#### 4) Ask kernel to re-read partition table (optional)

If `partprobe` exists:

```bash
partprobe /dev/sda
```

If not installed, you can skip if `lsblk` already shows the new size.

#### 5) Verify partition grew

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT /dev/sda
```

#### 6) Grow ext4 filesystem online

```bash
resize2fs -p /dev/sda1
df -h /
```

Done.

---

### Situation C: `/etc/fstab` out of sync (remount fails)

**Symptoms**

* System is running, but:

  * `mount -o remount /` fails with “can’t find PARTUUID=…”
  * `/etc/fstab` references a stale `PARTUUID`/`UUID`

**Steps**

1. Identify the *actual* root device:

```bash
findmnt -n -o SOURCE /
```

2. Get correct identifiers:

```bash
blkid /dev/sda1
```

3. Update `/etc/fstab` (recommend using filesystem UUID for `/`)
   Example root line:

```text
UUID=<UUID-from-blkid> / ext4 rw,errors=remount-ro,noatime 0 1
```

4. Test:

```bash
mount -o remount /
mount -a
```

---

### Situation D: GRUB `root=` still points to old PARTUUID/UUID (reboot risk)

**Symptoms**

* `/proc/cmdline` shows `root=PARTUUID=<old>`
* You fixed partitions/fstab but fear next boot will fail

**Steps**

1. Check current boot cmdline:

```bash
cat /proc/cmdline
```

2. Regenerate bootloader config:

```bash
update-grub
update-initramfs -u
```

3. Verify new GRUB entries contain the correct root id:

```bash
grep -R "linux.*root=" -n /boot/grub/grub.cfg | head
```

---

### Quick verification block (use anytime)

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT /dev/sda
fdisk -l /dev/sda | sed -n '1,40p'
findmnt -n -o SOURCE,FSTYPE,OPTIONS /
df -h /
blkid /dev/sda1
```

---

### Notes

* “Partition table entries are not in disk order.” is normal on GPT cloud images (BIOS boot + EFI at the front).
* If `partprobe` is missing but `lsblk` already shows the updated partition size, you’re fine.
* For ext4 root on `/dev/sda1`, `resize2fs` works online while mounted (as you saw).
