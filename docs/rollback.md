# Desktop update rollback

The supported rollback is **explicit and package-scoped**.  Before a desktop
update you save the package archive for the currently installed
`maria-padilha` version; if the update breaks the session, you boot the rescue
entry and install that saved archive with `pacman -U`.  There is no hidden snapshot,
no automatic rollback hook and no claim that a broken system heals itself.

This mechanism is deliberately simple enough to inspect with ordinary file and
pacman commands.  It does **not** snapshot the whole root filesystem, the
kernel, firmware or the graphics stack.  Those are separate, bigger changes
and need their own saved packages if you want to reverse them.

## What is saved

`maria-padilha-rollback save` copies the package archive for the installed
`maria-padilha` version into:

```text
/var/cache/maria-padilha/rollback/
```

It also writes two plain files beside the archive:

| file | contents |
| --- | --- |
| `SHA256SUMS` | `sha256sum` lines for each saved archive; `verify` checks them |
| `manifest.txt` | date, archive name and the package metadata read with `pacman -Qp` |

The archive is found in the normal pacman cache or the retained offline
installer repository (`/var/cache/pacman/pkg` and
`/var/cache/calamares/offline-repo` by default).  `save` only copies one
already-present package; it does not download or rebuild the old version.  If
the archive is not cached, the command fails and tells you to supply it instead
of pretending a rollback point exists.

The directory is not a snapshot of `/`, `/etc` or `/home`.  It stores packages,
not user data.  Keep normal backups for documents, keys and configuration.

## Before updating

Run these commands on the installed system **before** the update:

```sh
sudo maria-padilha-rollback save
maria-padilha-rollback list
maria-padilha-rollback verify
```

`save` and `apply` need root because they write the system cache or run pacman.
`list` and `verify` are read-only.  If `save` cannot find the current archive,
copy the matching `maria-padilha-<version>-x86_64.pkg.tar.*` file into
`/var/cache/pacman/pkg` and run `save` again, or point at another cache:

```sh
sudo maria-padilha-rollback --cache-dir /path/to/archives save
```

Then perform the update the normal way and reboot:

```sh
sudo pacman -Syu
```

`save` is an explicit step, not a pacman hook.  If you forget it before the
update, the old package may still be in `/var/cache/pacman/pkg` or the
offline repository, but do not assume it is there.

## When the desktop update fails

The desktop failing to start is different from a broken bootloader.  If the
machine still boots and reaches the greeter, you may be able to switch to a TTY
and repair from there.  If it does not boot far enough, use the rescue entry
described in [rescue.md](rescue.md).

From rescue mode:

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME,MOUNTPOINTS
mount /dev/nvme0n1p2 /mnt
arch-chroot /mnt
maria-padilha-rollback list
maria-padilha-rollback verify
maria-padilha-rollback apply 0.2.0
exit
umount -R /mnt
reboot
```

Replace the device and version with the values you identified.  `apply`
verifies `SHA256SUMS` first, shows the package metadata, asks you to type the
version, and then runs the equivalent of:

```sh
pacman -U /var/cache/maria-padilha/rollback/maria-padilha-0.2.0-1-x86_64.pkg.tar.zst
```

Use `--dry-run` to see the command without changing the system, and `--yes` to
skip the confirmation prompt in a deliberate non-interactive run.  Be aware
that `--yes` passes `--noconfirm` to pacman.

After the rollback, reboot and test the session before updating again.  If the
desktop package installs but the session still fails, inspect the session logs
and the package dependencies; do not keep downgrading unrelated packages
blindly.

## Dependency and kernel limits

This helper rolls back only the `maria-padilha` package archive.  If the failed
update also changed its dependencies, pacman may report a dependency problem
or the old package may not run against the newer libraries.  Read that output
and decide which packages need explicit attention; do not force the transaction
with `--assume-installed`, `--nodeps` or a blanket downgrade.

A kernel, firmware or graphics-stack regression is not fixed by this package
rollback.  If one of those is the cause, identify the specific package and use
its own cached archive deliberately, for example:

```sh
ls /var/cache/pacman/pkg/linux-*
# inspect the old version, then downgrade only the package you identified
sudo pacman -U /var/cache/pacman/pkg/linux-<old-version>-x86_64.pkg.tar.zst
```

That is a separate decision with its own compatibility risks; it is not
automated here.

## If no rollback point exists

If the archive is missing, the installed target may still have the offline
installer repository at `/var/cache/calamares/offline-repo`.  Inspect it before
using it:

```sh
ls -l /var/cache/calamares/offline-repo/
pacman -Qp /var/cache/calamares/offline-repo/maria-padilha-*.pkg.tar.*
```

Do not reinstall over the running desktop just to recover a session.  From the
rescue environment, identify the version and install it explicitly with
`pacman -U`, or make the desktop usable first and save a proper rollback point
for the next update.

## Inspecting a saved point

Everything is a normal file:

```sh
sudo maria-padilha-rollback list
sudo cat /var/cache/maria-padilha/rollback/manifest.txt
sudo sha256sum -c /var/cache/maria-padilha/rollback/SHA256SUMS
```

`verify` runs the same checksum check.  To remove old saved packages, remove
the specific archive and refresh the metadata by running `save` again when the
current version is still installed.  The helper never cleans the directory
automatically.

The static tests in [`tests/rescue.sh`](../tests/rescue.sh) exercise the
read-only listing and checksum verification with a temporary fixture.  They do
not install packages, run pacman, mount a filesystem or touch the host's
partition table.
