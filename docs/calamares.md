# Calamares installer

The Maria Padilha ISO uses [Calamares](https://calamares.io/) as its graphical
installer.  The profile is deliberately offline: the target root comes from the
ISO's squashfs and every additional package comes from a repository stored on
the same ISO.  No mirror, GeoIP service or network probe is required for the
base install.

The archiso profile itself is a separate piece of work; this document describes
the Calamares layer that lands in the profile's `airootfs`.

## Layout

| path | purpose |
| --- | --- |
| `iso/airootfs/etc/calamares/settings.conf` | module sequence and branding selection |
| `iso/airootfs/etc/calamares/modules/` | welcome, locale/timezone, keyboard, partition, users, packagechooser, packages, bootloader and support jobs |
| `iso/airootfs/etc/calamares/branding/maria-padilha/` | palette, local SVG logo and welcome art, stylesheet, slideshow |
| `iso/airootfs/usr/local/bin/maria-padilha-calamares-offline` | wires the target's pacman to the local repository |
| `iso/airootfs/var/cache/calamares/offline-repo/` | build artifact: target package archives and pacman database |
| `iso/calamares/live-packages.x86_64` | package to append to the live root list (`calamares`) |
| `iso/calamares/offline-packages.x86_64` | packages staged into the ISO-local repository |
| `scripts/calamares-offline-repo.sh` | build-host helper that stages and indexes the repository |

## Install sequence

The user-visible pages are **welcome → locale/timezone → keyboard → partition →
software → user → summary**.  The execution phase partitions, mounts, unpacks
the squashfs, writes locale/keyboard/fstab/initramfs, removes the live-only
account/autologin, creates the user, prepares the offline pacman repository,
installs the selected packages and the bootloader, then unmounts.

- **Locale and timezone.**  Calamares has no standalone timezone module; the
  `locale` module owns both.  `locale.conf` pins the initial map to
  `America/Sao_Paulo` and leaves GeoIP disabled.
- **Partitioning.**  ext4 is the only offered filesystem and the default.
  LUKS is explicitly disabled because this image does not ship the complete
  encrypted-root stack (cryptsetup, LUKS-aware GRUB/initramfs support).
- **Bootloader.**  GRUB is installed for UEFI and BIOS.  `grub` and
  `efibootmgr` are installed from the local repository before the bootloader
  module runs.
- **User.**  One user with `wheel` sudo rights, a separate root password, no
  autologin.  The preceding `shellprocess` job removes the passwordless live
  `maria` account, its sudo rule and the live greetd autologin before this
  module runs; see
  `iso/airootfs/usr/local/bin/maria-padilha-calamares-first-boot`.  greetd,
  NetworkManager, Bluetooth, seatd and power-profiles-daemon are enabled for the
  target; the PipeWire user stack is enabled globally through
  `/etc/systemd/user`.  `/etc/skel` comes from the image and carries the tracked
  desktop configs without secrets.  See [first-boot.md](first-boot.md) for what
  finishes at the first graphical login.

## Offline package repository

The build host may use the network.  The installed system does not:

```sh
# inside the Arch build container, from the repository root
scripts/calamares-offline-repo.sh --package-dir out/repo
```

The helper copies locally built archives (notably `maria-padilha`), downloads
the official packages and dependencies named in
`iso/calamares/offline-packages.x86_64`, and writes the repository database to
`iso/airootfs/var/cache/calamares/offline-repo/`.  The directory is then part
of `airootfs.sfs`.  `scripts/calamares-offline-repo.sh --check` validates the
manifest and paths without writing anything or using the network.

At install time the `shellprocess` job links the database into
`/var/lib/pacman/sync` and appends this stanza to the target's `pacman.conf`:

```ini
[maria-padilha-offline]
SigLevel = Optional DatabaseOptional
Server = file:///var/cache/calamares/offline-repo
```

`modules/packages.conf` keeps `update_db` and `update_system` false, so pacman
never synchronizes with a mirror.  `packagechooser.conf` offers the desktop and
an optional development group; both are resolved from the same local
repository.  Keep the manifest, the fixed `packages.conf` operations and the
packagechooser groups aligned when changing package selection.

The repository is deliberately retained in the target so `pacman` can install
from it later without a network.  Add or remove packages by rebuilding the ISO,
not by deleting the directory at install time.

## Branding

The palette follows the desktop's candle-red seed `#b12e1b`, near-black
surfaces `#120807` / `#1a0d0b`, candle gold `#d8a24a` and cream `#f3e6da` /
`#fff7ef`.  `logo.svg`, `welcome.svg`, `stylesheet.qss` and `show.qml` are all
files in this repository; no remote image, font or stylesheet is referenced by
the branding component.

## Testing

```sh
bash tests/calamares.sh   # static config, branding and offline checks
bash tests/all.sh         # repository suite
```

`tests/calamares.sh` parses every YAML config when PyYAML is available, checks
the module sequence, the ext4/no-LUKS partition policy, the no-network package
settings, the enabled system units, the branding files and palette, the offline
helper manifest, and the shell scripts.  It is a configuration test, not an
installation test.  First-boot ownership and service checks live in
`tests/first-boot.sh` and are documented in [first-boot.md](first-boot.md).

## Manual QEMU checklist

See [qemu-calamares.md](qemu-calamares.md).  No full install has been run in
this checkout: there is no built ISO and QEMU is not installed in the
development environment.  The checklist is the acceptance procedure to run
before calling the installer tested.
