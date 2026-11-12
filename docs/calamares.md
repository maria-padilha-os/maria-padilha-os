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
  module runs.  `grubcfg.conf` points `/etc/default/grub` at the repository's
  `/boot/grub/themes/maria-padilha/theme.txt`, sets the candle-red GRUB
  colours and writes `quiet splash`; GRUB's console fallback keeps the menu
  usable if gfxterm cannot start.  See [boot-branding.md](boot-branding.md).
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

## Software groups

The **Software** page is an offline `packagechooser` list.  The base group is
mandatory: `packagechooser.conf` preselects it, and the fixed operations in
`packages.conf` install the same package list, so clearing every selection in
the list-view cannot remove the desktop, session, shell or hardware support.
There are no `remove` or `try_remove` operations in `packages.conf`; optional
groups are strictly additive.

| group | id | contents |
| --- | --- | --- |
| Base system (required) | `base` | Maria Padilha desktop, Hyprland/Quickshell session, Bash, greetd, PipeWire audio, NetworkManager/Bluetooth, microcode, firmware, graphics and laptop hardware packages |
| Development tools | `development` | `base-devel`, git, Neovim, Python, Node.js, Rust, Go, compiler and debugger tooling |
| Media | `media` | VLC, mpv, FFmpeg/GStreamer, GIMP, ImageMagick, OBS Studio, yt-dlp |
| Games | `games` | 0 A.D., SuperTuxKart, Luanti, Lutris, Wine, GameMode, MangoHud, Vulkan tools |
| Office and Mail | `office-mail` | LibreOffice, **Thunderbird** and English spelling tools |
| AI Tools | `ai-tools` | The local assistant runtime: **Ollama** and llama.cpp |

Selecting a group installs software only.  It does **not** configure mail
accounts, calendars, address books, game-store or streaming accounts, online
services, AI provider accounts, API keys or any other credential.  Thunderbird
starts with no configured mail account, and the AI group contains no key,
token or provider secret.  Models, accounts and any online service setup remain
explicit user decisions after installation.

Every group is resolved from the ISO-local repository.  No online package
source is offered; there is no opt-in network path, `netinstall` module or
mirror fallback.  The `packages` module keeps `update_db` and `update_system`
false, so an install that is offline from start to finish cannot make a
network request.

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
never synchronizes with a mirror.  `packagechooser.conf` offers the mandatory
base group and the optional Development, Media, Games, Office/Mail and AI Tools
groups; every group is resolved from the same local repository.  The manifest
covers every package named by the chooser and by the fixed operations, so a
selection cannot pull from a mirror.  `build.sh` runs the helper into the
build's working profile after `prepare_repo`, immediately before `mkarchiso`:

```sh
scripts/calamares-offline-repo.sh \
    --package-dir out/repo \
    --output .scratch/iso-build/profile/airootfs/var/cache/calamares/offline-repo
```

Keep the manifest, the fixed `packages.conf` operations and the
`packagechooser.conf` groups aligned when changing package selection.

Laptop hardware support is part of the mandatory base group.  Microcode,
firmware, audio and power/thermal packages are listed in both `base` and
`iso/packages.x86_64`, so they arrive in the target through the live squashfs
and are also resolvable from the offline repository.  See
[supported-hardware.md](supported-hardware.md).

The repository is deliberately retained in the target so `pacman` can install
from it later without a network.  Add or remove packages by rebuilding the ISO,
not by deleting the directory at install time.

## Branding

The palette follows the desktop's candle-red seed `#b12e1b`, near-black
surfaces `#120807` / `#1a0d0b`, candle gold `#d8a24a` and cream `#f3e6da` /
`#fff7ef`.  `logo.svg`, `welcome.svg`, `stylesheet.qss` and `show.qml` are all
files in this repository; no remote image, font or stylesheet is referenced by
the branding component.

The same palette continues outside Calamares: the Plymouth theme, syslinux
menu, installed GRUB theme and greetd wrapper all use it, with a checked-in
fallback for the pre-session boot path.  See [boot-branding.md](boot-branding.md)
for the paths, fallback behaviour and the manual
[QEMU visual checklist](qemu-branding.md).

## Testing

```sh
bash tests/calamares.sh   # static config, branding and offline checks
bash tests/all.sh         # repository suite
```

`tests/calamares.sh` parses every YAML config when PyYAML is available, checks
the module sequence, the ext4/no-LUKS partition policy, the no-network package
settings, the group ids and required packages, Thunderbird in Office/Mail, the
local assistant runtime in AI Tools, the absence of secret-like keys, the
base-group guarantee in `packages.conf`, the enabled system units, the branding
files and palette, the offline helper manifest, and the shell scripts.  It is a
configuration test, not an installation test.  First-boot ownership and service
checks live in `tests/first-boot.sh` and are documented in
[first-boot.md](first-boot.md).

## Manual QEMU checklist

See [qemu-calamares.md](qemu-calamares.md).  No full install has been run in
this checkout: there is no built ISO and QEMU is not installed in the
development environment.  The checklist is the acceptance procedure to run
before calling the installer tested.
