# Maria Padilha OS

The bootable Arch-based Maria Padilha image: Hyprland, Quickshell, the
`maria-padilha` package, and the tracked dotfiles.

This repository is the image/installer layer. The desktop itself lives in
[`maria-padilha-de`](https://github.com/maria-padilha-os/maria-padilha-de), and
the tracked configs live in
[`maria-padilha-dotfiles`](https://github.com/maria-padilha-os/maria-padilha-dotfiles).

## Status

**Boot/greeter branding and laptop hardware enablement.** The profile, package selection, live user, greetd/tuigreet setup, build wrapper, Plymouth theme, GRUB/syslinux menus and first-boot provisioning are in place. Laptop enablement adds AMD microcode and GPU firmware, common Wi-Fi/Bluetooth firmware, SOF/UCM audio and power/thermal tooling with automatic suspend disabled. First boot enables NetworkManager, Bluetooth, seatd, greetd and power-profiles-daemon, enables the PipeWire user stack, and populates `/etc/skel` from the tracked dotfiles without copying secrets. The offline installer layer is under
`iso/airootfs/etc/calamares/`: Calamares modules, Maria Padilha branding, an
ISO-local package repository and a manual QEMU checklist. No bootable ISO has
been built and **no full install has been run**. Do not install this on a host,
and do not treat an untested local build as a release.

See [docs/first-boot.md](docs/first-boot.md) for the service/skel design,
[docs/boot-branding.md](docs/boot-branding.md) for the boot/greeter palette and
fallback design, and [docs/qemu-branding.md](docs/qemu-branding.md) for the
manual visual checklist. The branding checks are static; they do not perform a
graphical login.

## Laptop hardware enablement

The image targets the hardware classes used by the reference AMD laptop, not a
single board. `iso/packages.x86_64` carries `amd-ucode`, the `linux-firmware`
meta package and the AMD GPU, Wi-Fi/Bluetooth vendor splits, `mesa`/`vulkan-radeon`
with VA-API, `sof-firmware` and `alsa-ucm-conf`, plus `power-profiles-daemon`,
`upower`, `lm_sensors`, `acpi`, `pciutils` and `usbutils`. TLP, auto-cpufreq and
thermald are deliberately absent so `power-profiles-daemon` remains the only
power/thermal manager.

s2idle suspend is known broken on the reference machine. Both suspend and
hibernation are disabled in
`iso/airootfs/etc/systemd/sleep.conf.d/10-maria-padilha-no-s2idle.conf`;
`iso/airootfs/etc/systemd/logind.conf.d/10-maria-padilha-no-autosuspend.conf`
ignores the lid switch, suspend/hibernate keys and idle action. The image does
not enable automatic suspend.

See [docs/supported-hardware.md](docs/supported-hardware.md) for the tested,
best-effort and explicitly unsupported classes. The read-only check runs on a
running image without root and never tests suspend or hibernation:

```sh
maria-padilha-hardware-check
make hardware-check                 # from this checkout, against /
make hardware-check ROOT=/mnt       # or a mounted target
```

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

The static tests run anywhere. The ISO itself is only built inside an Arch
container; `build.sh` refuses to run on a non-Arch host and outside a container.

## Boot and greeter branding

The firmware menu, Plymouth splash, installed GRUB menu and greetd login screen
share one candle-red palette: `#120807` background, `#1a0d0b` surface,
`#b12e1b` primary, `#d8a24a` gold, `#f3e6da` cream and `#fff7ef` bright cream.
The static fallback lives in
`iso/airootfs/etc/maria-padilha/boot-palette.conf`; the same values are baked
into the Plymouth script because the splash runs before the root filesystem's
palette can be read. The greeter wrapper reads the palette when present and
falls back to the same readable red/gold/white theme when it is missing or
malformed. No live graphical login is needed for the tests.

| path | role |
| --- | --- |
| `iso/airootfs/usr/share/plymouth/themes/maria-padilha/` | local SVG/PNG candle splash, title, progress and theme script |
| `iso/airootfs/etc/plymouth/plymouthd.conf` | selects the Maria Padilha theme |
| `iso/airootfs/boot/grub/themes/maria-padilha/` | installed-target GRUB background and theme |
| `iso/syslinux/archiso_head.cfg`, `iso/syslinux/splash.png` | BIOS live menu colours and background |
| `iso/efiboot/loader/loader.conf` | text-only UEFI systemd-boot menu settings |
| `iso/airootfs/usr/local/bin/maria-padilha-greeter` | tuigreet `--theme` wrapper with a no-palette fallback |
| `iso/airootfs/etc/maria-padilha/boot-palette.conf` | palette data and derived tuigreet theme |
| `tests/branding.sh` | static paths, PNG sizes, palette/fallback and wiring checks |
| `docs/boot-branding.md` | design and fallback behaviour |
| `docs/qemu-branding.md` | manual QEMU visual checklist |

Plymouth is selected through the `plymouth` mkinitcpio hook, and both live and
installed kernel command lines carry `splash`. The theme assets are original
vector/text treatments rendered to PNG in this repository; no external artwork
is downloaded or embedded.

## What the profile contains

| path | role |
| --- | --- |
| `iso/profiledef.sh` | archiso profile, boot modes and file permissions |
| `iso/packages.x86_64` | live-root package list |
| `iso/pacman.conf` | official repositories; `build.sh` appends the local package repository |
| `iso/airootfs/` | live user, greetd config, enabled system/user units, `/etc/skel`, mkinitcpio config, Plymouth theme and boot palette |
| `scripts/overlay-dotfiles.sh` | copies the tracked dotfiles into `/etc/skel`, excluding secrets |
| `tests/first-boot.sh` | chroot/nspawn verifier for ownership, service enablement and secrets |
| `tests/branding.sh` | static boot/greeter branding, PNG-size and palette-fallback checks |
| `docs/first-boot.md` | first-login provisioning, limits and verification steps |
| `docs/boot-branding.md` | boot/greeter palette design, fallback and kernel parameters |
| `docs/qemu-branding.md` | manual QEMU visual checklist for boot and login |
| `iso/airootfs/usr/local/bin/maria-padilha-hardware-check` | read-only package/firmware check for a running image |
| `scripts/check-hardware.sh` | checkout alias for the installed hardware check |
| `docs/supported-hardware.md` | tested, best-effort and unsupported hardware classes |
| `tests/hardware.sh` | hardware package/policy checks and a synthetic-root fixture |
| `iso/efiboot/` | UEFI systemd-boot entries and menu settings |
| `iso/syslinux/` | BIOS syslinux entries, menu palette and splash |
| `build.sh` | builds `maria-padilha`, publishes it to `out/repo`, then runs `mkarchiso` |
| `tests/iso.sh` | static profile, package, permission, version and secret checks |
| `tests/skel.sh` | dotfiles-overlay fixture: allowlist, modes and secret rejection |

The installed root deliberately does **not** include `base-devel` or a compiler
toolchain. `build.sh` installs package build dependencies in the throw-away Arch
container, then builds the desktop package there. The ISO only gets runtime
packages.

## Greeter choice

**greetd + tuigreet**, not SDDM. The live image starts greetd on VT 1 and uses
`initial_session` to enter the `maria` live account directly. Logging out drops
back to `/usr/local/bin/maria-padilha-greeter`, which starts tuigreet with the
Maria Padilha `--theme` spec and lists the session installed by the
`maria-padilha` package at
`/usr/share/wayland-sessions/maria-padilha.desktop`.

The live account has no password and may use `sudo`; root is locked. The ISO is
ephemeral. `iso/airootfs/etc/greetd/config.toml`,
`iso/airootfs/usr/local/bin/maria-padilha-greeter`, `iso/packages.x86_64` and
the enabled `greetd.service` unit must stay in sync. The wrapper extracts the
`--theme` value from `boot-palette.conf` with `sed` (it never executes the
palette file) and uses a compiled-in red/gold/white fallback when the file is
missing, unreadable or malformed.

The same profile enables `seatd.service` and `power-profiles-daemon.service`
for systems that use them, and links `NetworkManager`, `bluetooth`, `greetd`
and `display-manager.service`. PipeWire is enabled globally for user sessions
through `/etc/systemd/user/{default,sockets}.target.wants`; it starts with the
user manager at login, not during boot. Calamares enables the system units in
the installed target through `modules/services-systemd.conf`.

Calamares also runs
`iso/airootfs/usr/local/bin/maria-padilha-calamares-first-boot` before creating
the target user. It removes the live-only passwordless `maria` account, its
sudoers/sysusers entries and the live greetd `[initial_session]` autologin, so
the installed system does not inherit the live configuration. See
[docs/first-boot.md](docs/first-boot.md).

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
only carries this repository's shell setup and placeholder; a release image
should be built with the dotfiles mounted. When present, `build.sh` calls
`scripts/overlay-dotfiles.sh`, which copies Hyprland, Quickshell, Neovim,
WezTerm, micro and the three static Midnight Commander files. It never copies
`hypr/hyprland/env.local.lua`, key material, `.env`, git credentials or other
credential-looking files, then scans the result and fails the build if it finds
a key-shaped value. If the package source tarball is missing from
`maria-padilha-de/packaging/`, `build.sh` exports the current git HEAD into the
scratch directory with `git archive`, matching `tools/release.sh --export`.

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
bash tests/all.sh                     # full static suite
make test                             # same
bash tests/branding.sh                # boot/greeter paths, sizes and fallback
bash tests/first-boot.sh --profile    # first-login checks against iso/airootfs
make first-boot ROOT=/mnt             # inspect an installed root (read-only)
bash tests/hardware.sh                # hardware package/policy checks
make hardware-check ROOT=/mnt         # inspect a mounted target (read-only)
```

`tests/iso.sh` checks the profile files and version, required and forbidden
package names, executable bits, system and user service enablement, the skel
shell setup, greetd/session discovery, boot entries, the mkinitcpio archiso
hook, no `.env`, and obvious API/private-key patterns. `tests/branding.sh`
checks the Plymouth theme wiring, PNG dimensions, syslinux/GRUB styling,
`plymouth` package and hook, kernel `splash` parameters, the greeter wrapper,
and the no-palette/malformed-palette fallback without starting a graphical
session. `tests/skel.sh` exercises the dotfiles overlay with a temporary
fixture and proves that `env.local.lua`, credentials and key-shaped values
never reach skel. `tests/first-boot.sh` can run inside a
chroot/systemd-nspawn (or inspect a root with `--root`) and checks ownership,
enabled units, the session/wallpaper defaults and secrets without changing
anything. `tests/hardware.sh` checks the laptop package/policy list and
exercises the read-only hardware check against a synthetic root. None of these
tests require root, `mkarchiso`, a network or a graphical session;
`make first-boot` and `make hardware-check` only read the target they are
pointed at.

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

- A bootable ISO has not been built yet.
- Calamares/offline installation is configured, but the QEMU acceptance
  checklist has not been run, so first boot is not yet proven end to end.
- The boot/greeter branding is statically verified only. The QEMU visual
  checklist in [docs/qemu-branding.md](docs/qemu-branding.md) has not been run,
  so the syslinux, Plymouth, GRUB and greeter screens are not yet visually
  confirmed.
- No signed ISO, checksum publication or QEMU smoke test.
- The live session is intentionally ephemeral and has an empty live-user
  password; do not reuse this configuration for an installed system.
- PipeWire, wallpaper/palette generation, the Quickshell process, keyring/polkit
  and Firefox theming finish only after the first graphical login; see
  [docs/first-boot.md](docs/first-boot.md).
- The boot and greeter palette is a checked-in fallback derived from the same
  candle-red seed; it is not rewritten automatically by the session palette
  generator. Replace `/etc/maria-padilha/boot-palette.conf` when a generated
  system palette is available.
- A development build without the sibling dotfiles checkout has the shell
  setup but not the full tracked Hyprland/Quickshell configuration.
- Laptop enablement is tested at the package/configuration level only. No
  physical reference laptop has been booted in this checkout; s2idle suspend
  and hibernation are explicitly unsupported and disabled until resume is fixed
  and tested.

`tests/all.sh` runs the archiso, Calamares, branding, skel and first-boot static
suites. The QEMU checklists are manual and must be run against a real ISO before
claiming an install or a boot/login screen works.
