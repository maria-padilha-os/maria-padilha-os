# Changelog

All notable changes to Maria Padilha OS are recorded here. The release
checklist in [docs/release-checklist.md](docs/release-checklist.md) explains
how an `Unreleased` section becomes a versioned release.

## [Unreleased]

### Added

- Local release staging with `tools/release.sh`: build or reuse an ISO, write
  and verify `SHA256SUMS`, and optionally sign the checksum file with a
  maintainer GPG key.
- Manual GitHub draft-release template and a release/rollback checklist. No
  workflow tags, uploads or publishes a release automatically.
- The first built Maria Padilha OS 0.2.0 ISO, with checksum and build evidence
  in `docs/release-evidence-0.2.0.md`.

### Fixed

- `build.sh` now parses the tab-indented `depends`/`makedepends` keys from
  `makepkg --printsrcinfo`, installs the Qt6 ShaderTools headers used by the
  pinned desktop CMake project, and normalises staged profile modes.
- The profile now sets `kernel_params_x86_64`, the variable current mkarchiso
  reads, so `quiet splash` reaches the boot entries.
- The container build bootstraps AUR Calamares (with its `packagechooser`
  module enabled) because the current Arch repositories no longer ship it, and
  detects an existing reusable `[ci-aur]` repository without skipping it.

## [0.2.0] - 2026-11-10

### Added

- Archiso live/installer image with the offline Calamares installer.
- Maria Padilha boot, Plymouth, GRUB, syslinux and greeter branding.
- First-boot provisioning and desktop/session defaults.
- Laptop hardware enablement and read-only hardware checks.
- CI ISO build with checksum artifacts and an opt-in headless QEMU smoke boot.
