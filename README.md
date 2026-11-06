# Maria Padilha OS

The bootable Arch-based Maria Padilha image: Hyprland, Quickshell, the
`maria-padilha` package, and the tracked dotfiles.

This repository is the image/installer layer. The desktop itself lives in
[`maria-padilha-de`](https://github.com/maria-padilha-os/maria-padilha-de), and
the tracked configs live in
[`maria-padilha-dotfiles`](https://github.com/maria-padilha-os/maria-padilha-dotfiles).

## Status

**Archiso scaffold.** The profile, package selection, live user, greetd/tuigreet
setup and build wrapper are in place. There is no Calamares installer, signed
release pipeline or QEMU smoke test yet. Do not install this on a host, and do
not treat an untested local build as a release.

The static tests run anywhere. The ISO itself is only built inside an Arch
container; `build.sh` refuses to run on a non-Arch host and outside a container.

## What the profile contains

| path | role |
| --- | --- |
| `iso/profiledef.sh` | archiso profile, boot modes and file permissions |
| `iso/packages.x86_64` | live-root package list |
| `iso/pacman.conf` | official repositories; `build.sh` appends the local package repository |
| `iso/airootfs/` | live user, greetd config, enabled units, `/etc/skel`, mkinitcpio config |
| `iso/efiboot/` | UEFI systemd-boot entries |
| `iso/syslinux/` | BIOS syslinux entries |
| `build.sh` | builds `maria-padilha`, publishes it to `out/repo`, then runs `mkarchiso` |
| `tests/iso.sh` | static profile, package, permission, version and secret checks |

The installed root deliberately does **not** include `base-devel` or a compiler
toolchain. `build.sh` installs package build dependencies in the throw-away Arch
container, then builds the desktop package there. The ISO only gets runtime
packages.

## Greeter choice

**greetd + tuigreet**, not SDDM. The live image starts greetd on VT 1 and uses
`initial_session` to enter the `maria` live account directly. Logging out drops
back to `tuigreet`, which lists the Maria Padilha session installed by the
`maria-padilha` package at
`/usr/share/wayland-sessions/maria-padilha.desktop`.

The live account has no password and may use `sudo`; root is locked. The ISO is
ephemeral. `iso/airootfs/etc/greetd/config.toml`,
`iso/packages.x86_64` and the enabled `greetd.service` unit must stay in sync.

## Build

Run this on a machine with Docker or Podman. The container needs
`--privileged` because `mkarchiso` creates and mounts loop images and chroots
into the new root. The sibling checkouts are mounted read-only; the build copies
what it needs into `.scratch/`.

```sh
# from the maria-padilha-os checkout
docker run --rm -it --privileged \
  -v "$PWD:/work" \
  -v "$(cd ../maria-padilha-de && pwd):/pkg/maria-padilha-de:ro" \
  -v "$(cd ../maria-padilha-dotfiles && pwd):/pkg/maria-padilha-dotfiles:ro" \
  -w /work archlinux:latest
```

Inside the container:

```sh
pacman -Syu --needed --noconfirm archiso base-devel git
MARIA_PADILHA_DE=/pkg/maria-padilha-de \
MARIA_PADILHA_DOTFILES=/pkg/maria-padilha-dotfiles \
./build.sh
```

The result is `out/maria-padilha-<pkgver>-x86_64.iso`. `make iso` is the same
thing and must run in the same container.

If the dotfiles checkout is absent, the build still succeeds but `/etc/skel`
only carries this repository's placeholder. If the package source tarball is
missing from `maria-padilha-de/packaging/`, `build.sh` exports the current git
HEAD into the scratch directory with `git archive`, matching
`tools/release.sh --export`.

Use an already built package instead of running `makepkg`:

```sh
./build.sh --package /path/to/maria-padilha-0.2.0-1-x86_64.pkg.tar.zst
```

Other useful options: `--de PATH`, `--pkgbuild PATH`, `--source PATH`,
`--package-only`, `--keep-work`, `--help`.

## Package version

`maria-padilha-de/packaging/PKGBUILD` is the source of truth. This repository
pins the matching fallback in `iso/package-version` (currently `0.2.0`) and
references it from the profile and `/etc/maria-padilha-release`. `build.sh`
reads the package version from the PKGBUILD, updates the working copy of the
profile, and warns if the package no longer matches the pin. When the sibling
checkout is present, `tests/iso.sh` fails if the pin and PKGBUILD disagree.

## Tests

```sh
bash tests/all.sh     # hygiene + tests/iso.sh
make test             # same
```

`tests/iso.sh` checks the profile files and version, required and forbidden
package names, executable bits, greetd enablement, boot entries, the mkinitcpio
archiso hook, no `.env`, and obvious API/private-key patterns. It does not
require root or `mkarchiso`.

## Host prerequisites

The full build needs an Arch container with `archiso`, `base-devel` and `git`;
`archiso` pulls `dosfstools`, `e2fsprogs`, `erofs-utils`, `libarchive`,
`libisoburn` (`xorriso`), `mtools` and `squashfs-tools`. Package build
dependencies from the `maria-padilha` PKGBUILD are installed inside that same
container. Nothing is installed on the host and the live `/usr` is not touched.

On a non-Arch host without `mkarchiso`/`pacstrap` (for example the Manjaro
development laptop), only the static tests can run. Start the container to do a
real build.

## Relationship to the other repositories

| repository | role |
| --- | --- |
| `maria-padilha-de` | shell, session, theme engine, package, docs |
| `maria-padilha-dotfiles` | Hyprland, Neovim, WezTerm, Firefox, MC, micro |
| `maria-padilha-mobile` | touch-first mobile OS (Maria Padilha de Bolso) |
| `maria-padilha-de-castela` | authorized-lab cybersecurity desktop |
| `maria-padilha-de-castela-mobile` | GrapheneOS-based Castela mobile |

## Known gaps

- Calamares/offline installation is not wired yet.
- No signed ISO, checksum publication or QEMU smoke test.
- The live session is intentionally ephemeral and has an empty live-user
  password; do not reuse this configuration for an installed system.
