# Maria Padilha OS

The bootable Arch-based Maria Padilha image: Hyprland, Quickshell, the
`maria-padilha` package, and the tracked dotfiles.

This repository is the image/installer layer. The desktop itself lives in
[`maria-padilha-de`](https://github.com/maria-padilha-os/maria-padilha-de), and
the tracked configs live in
[`maria-padilha-dotfiles`](https://github.com/maria-padilha-os/maria-padilha-dotfiles).

## Status

**Scaffold + Calamares configuration.** There is no bootable ISO yet and the
archiso profile is not part of this branch. The offline installer layer is in
`iso/airootfs/etc/calamares/`: Calamares config modules, Maria Padilha branding,
an ISO-local package repository and a manual QEMU checklist. No ISO has been
built and **no full install has been run**. Do not install this on a host.

## Calamares installer

The installer is designed to work without a network: the target root comes from
the ISO squashfs and extra packages come from the ISO-local pacman repository.
See [docs/calamares.md](docs/calamares.md) for the design and
[docs/qemu-calamares.md](docs/qemu-calamares.md) for the manual acceptance
checklist.

| path | role |
| --- | --- |
| `iso/airootfs/etc/calamares/settings.conf` | module sequence and branding choice |
| `iso/airootfs/etc/calamares/modules/` | welcome, locale/timezone, keyboard, partition, user, packages and bootloader configs |
| `iso/airootfs/etc/calamares/branding/maria-padilha/` | palette, local SVG art, stylesheet and slideshow |
| `iso/airootfs/var/cache/calamares/offline-repo/` | build-time local package repository copied into the ISO |
| `iso/calamares/` | live/offline package manifests and integration notes |
| `scripts/calamares-offline-repo.sh` | stages and indexes the offline repository |
| `tests/calamares.sh` | static config, branding and offline checks |

Partitioning defaults to ext4. Encryption is disabled because this image does
not carry the complete LUKS/GRUB/initramfs stack; enable it only after the image
supports and tests encrypted root. The installer still needs to be built into
an archiso profile and exercised with the QEMU checklist before it can be called
tested.

## Intended stack

- Arch Linux base with a minimal desktop footprint
- Hyprland + Quickshell shell and session
- the `maria-padilha` package from `maria-padilha-de`
- the tracked dotfiles as `/etc/skel` defaults
- offline Calamares install with optional package groups
- signed ISO builds and a QEMU smoke test

## Relationship to the other repositories

| repository | role |
| --- | --- |
| `maria-padilha-de` | shell, session, theme engine, package, docs |
| `maria-padilha-dotfiles` | Hyprland, Neovim, WezTerm, Firefox, MC, micro |
| `maria-padilha-mobile` | touch-first mobile OS (Maria Padilha de Bolso) |
| `maria-padilha-de-castela` | authorized-lab cybersecurity desktop |
| `maria-padilha-de-castela-mobile` | GrapheneOS-based Castela mobile |

## Development

The image build is not wired yet. Until the archiso profile lands, the static
tests are the development gate:

```sh
bash tests/calamares.sh
bash tests/all.sh
```

`tests/all.sh` also runs the scaffold hygiene check and the Calamares suite.
The QEMU checklist is manual and must be run against a real ISO before claiming
an install works.
