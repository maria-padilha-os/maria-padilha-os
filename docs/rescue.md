# Rescue mode

The Maria Padilha ISO has a rescue boot entry for the case where the installed
system cannot reach a usable desktop or bootloader.  It is not an automatic
repair mode: it boots the same live squashfs with a root shell on tty1, and
nothing is mounted, partitioned, formatted or repaired until you type a command.

The rescue entry is an opt-in menu item.  The default live entry still starts
the Hyprland session.  Rescue mode is implemented by the
`maria-padilha-rescue.service` unit, the `maria-padilha-rescue` helper and the
extra packages in `iso/packages.x86_64`; the static tests in
[`tests/rescue.sh`](../tests/rescue.sh) check that the pieces and links are
present.  A rescue boot has not been run in this checkout, so treat the
procedure as configured and statically verified, not as a tested recovery on
real hardware.

## Entering rescue mode

1. Boot the Maria Padilha ISO.
2. At the firmware menu, choose the rescue entry:
   - BIOS/syslinux: **Maria Padilha Rescue (BIOS)**
   - UEFI/systemd-boot: **Maria Padilha Rescue (UEFI)**
3. The entry adds these kernel parameters:
   ```text
   maria-padilha.rescue=1
   systemd.unit=multi-user.target
   systemd.mask=getty@tty1.service
   plymouth.enable=0
   ```
   It starts a root shell on tty1 and does not start greetd or the graphical
   session.  Type `exit` to leave the shell; reboot or power off from there.
4. The shell prints the same short reminder as `maria-padilha-rescue --help`.
   The full procedure is this document; keep a copy of the repository or this
   file on another machine because the ISO itself does not install the docs.

The normal live entry and the rescue entry share the same kernel, initramfs and
squashfs.  There is no separate rescue image to update.

## What the rescue shell contains

| category | commands / packages |
| --- | --- |
| shell and block devices | `bash`, `lsblk`, `blkid`, `findmnt`, `mount`, `umount`, `fdisk` |
| ext4/FAT | `e2fsck`, `dumpe2fs`, `resize2fs` from `e2fsprogs`; `fsck.fat` from `dosfstools` |
| other filesystems | `btrfs check`/`btrfs restore` (`btrfs-progs`), `xfs_repair`/`xfs_db` (`xfsprogs`), `fsck.f2fs` (`f2fs-tools`), `fsck.exfat` (`exfatprogs`), `ntfsfix`/`ntfs-3g` (`ntfs-3g`) |
| partition tables | `parted`, `sgdisk` (`gptfdisk`), `fdisk` |
| target access | `arch-chroot` from `arch-install-scripts`, `pacman`, `maria-padilha-rollback` |
| bootloader repair | `grub-install`, `grub-mkconfig`, `grub-probe`, `efibootmgr` |

The live image does not include the complete LUKS or LVM stack.  If the
installed root is encrypted or on LVM, this rescue entry cannot open it; stop
and use a full Arch ISO with the required tools instead of guessing at the
device.

## Safety rules

- Start with read-only inspection:
  ```sh
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME,MOUNTPOINTS
  blkid
  findmnt
  ```
- Never run `fsck`, `e2fsck`, `btrfs check`, `xfs_repair` or `ntfsfix` on a
  mounted filesystem.  Unmount the whole tree first, for example
  `umount -R /mnt`.
- `mkfs`, `parted`, `sgdisk`, `dd` and `blkdiscard` destroy data.  They are
  present for deliberate repair work, but the rescue helper never runs them.
- Do not assume device names.  A device may be `/dev/nvme0n1p2` on one machine
  and `/dev/sda2` on another.  Match filesystem type, label and size from
  `lsblk -f` first.
- The live ISO is ephemeral.  Mount the installed root explicitly before
  changing it, and unmount it before rebooting.

## Inspect and mount the installed root

First look at the disks without changing them:

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME,MOUNTPOINTS
blkid
```

Example names below are placeholders.  A read-only inspection mount is the
safest first step:

```sh
mount -o ro /dev/nvme0n1p2 /mnt
findmnt /mnt
cat /mnt/etc/fstab
umount /mnt
```

Use `cat /mnt/etc/fstab` to learn where the EFI system partition (ESP) is
mounted on the installed system: commonly `/boot`, `/efi` or `/boot/efi`.
For a repair that needs write access, mount the same root without `-o ro` and
mount the ESP at the matching directory:

```sh
mount /dev/nvme0n1p2 /mnt
mount /dev/nvme0n1p1 /mnt/boot    # only if the installed fstab uses /boot
# mount /dev/nvme0n1p1 /mnt/efi   # use the path from /mnt/etc/fstab instead
```

If `/boot` is a separate filesystem, it must be mounted before regenerating
GRUB.  If the root uses Btrfs subvolumes or another non-default layout, add
the same options shown in the installed `/etc/fstab`; do not guess.

## Filesystem checks and repair

Unmount everything under `/mnt` before checking a filesystem:

```sh
umount -R /mnt
```

Then choose the checker that matches the filesystem.  These are inspection
commands with explicit repair flags; read the tool output before confirming a
repair.

```sh
# ext4 example
e2fsck -f /dev/nvme0n1p2

# FAT ESP example (normally mounted at /boot)
fsck.fat -a /dev/nvme0n1p1

# Btrfs: read-only check first
btrfs check --readonly /dev/nvme0n1p2

# XFS: no-repair mode first
xfs_repair -n /dev/nvme0n1p2

# F2FS and exFAT
fsck.f2fs /dev/nvme0n1p2
fsck.exfat /dev/nvme0n1p1
```

`ntfsfix` is not a full NTFS repair; it clears common dirty flags and is only
useful for an NTFS volume that is already unmounted.  Stop if the checker asks
about a device you did not identify or reports a filesystem you do not expect.

After a successful check, mount the root again before repairing the bootloader.

## Repairing the bootloader

Bootloader repair needs the installed root and, for UEFI, the ESP mounted at
the same path the installed system uses.  Enter the target with `arch-chroot`:

```sh
mount /dev/nvme0n1p2 /mnt
mount /dev/nvme0n1p1 /mnt/boot    # adjust to /mnt/efi if that is the fstab path
arch-chroot /mnt
```

### UEFI

The installed target uses GRUB with the `maria-padilha` bootloader id:

```sh
grub-install --target=x86_64-efi \
    --efi-directory=/boot \
    --bootloader-id=maria-padilha
grub-mkconfig -o /boot/grub/grub.cfg
```

If the ESP is mounted at `/efi` on the installed system, use
`--efi-directory=/efi` instead.  If the firmware has no usable boot entry or
you need the removable fallback path, add `--removable` deliberately; do not
use it as a substitute for understanding why the normal entry disappeared.

Inspect the firmware entries before changing them:

```sh
efibootmgr -v
```

Do not delete or reorder NVRAM entries blindly.  The GRUB repair above is
usually enough; `efibootmgr` is for inspecting and, when necessary, correcting
the firmware-side entry.

### BIOS

```sh
grub-install --target=i386-pc /dev/nvme0n1
grub-mkconfig -o /boot/grub/grub.cfg
```

Use the whole disk (`/dev/nvme0n1`, `/dev/sda`), not a partition, for the BIOS
installation target.  Confirm the disk from `lsblk` before running it.

### After either repair

Exit the chroot, unmount the target and reboot:

```sh
exit
umount -R /mnt
sync
reboot
```

If GRUB reports that the Maria Padilha theme is missing, the menu still has
the console fallback described in [boot-branding.md](boot-branding.md).  Repair
the boot path first; restore the theme files later.

## If a desktop update is the problem

Bootloader and filesystem repair are separate from a bad desktop update.  If
the system boots but the Maria Padilha session fails, use the explicit package
rollback procedure in [rollback.md](rollback.md) instead of reinstalling or
reformatting the root.

## Limits

- The rescue entry is configured and statically checked; it has not been
  booted in this checkout.
- The shell does not detect or mount the installed root for you.  That is
  deliberate: automatic mounting and automatic repair are too easy to run
  against the wrong device.
- Encrypted and LVM roots are outside what this live image can open.
- The rescue entry does not replace backups.  A damaged partition table, a
  failed disk or overwritten data may be unrecoverable.
