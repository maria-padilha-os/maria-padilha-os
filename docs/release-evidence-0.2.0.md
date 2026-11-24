# Release evidence: Maria Padilha OS 0.2.0 ISO

Status: **built and checksummed, not booted in QEMU, not published, not
uploaded, and not installed.** This is release evidence, not a release.

## Artifact

| field | value |
| --- | --- |
| ISO | `out/maria-padilha-0.2.0-x86_64.iso` |
| size | `6072815616` bytes (5.7 GiB) |
| SHA-256 | `50dc182e6b8778d76293bc8ea0655564a60186b88f26124419dcb1419c103306` |
| checksum file | `out/maria-padilha-0.2.0-x86_64.iso.sha256` |
| build metadata | `out/build-info.txt` |
| package | `maria-padilha-0.2.0-1-x86_64.pkg.tar.zst` |
| package SHA-256 | `753398df135d588d0179fa181b8a33682979dc3e95c077a3800ea882ad3f9cff` |

Verification performed:

```sh
cd out
sha256sum -c maria-padilha-0.2.0-x86_64.iso.sha256   # OK
```

The ISO contains a valid squashfs live root and an El Torito catalog with both
a BIOS (`/boot/syslinux/isolinux.bin`) and a UEFI
(`/EFI/BOOT/BOOTx64.EFI`) boot image. The live root reports
`VERSION="0.2.0"` and `PACKAGE_VERSION="0.2.0"` in
`/etc/maria-padilha-release`; pacman records `maria-padilha 0.2.0-1`. The
`calamares` package is present and includes the `packagechooser` module. Both
the BIOS and UEFI entries carry `quiet splash`.

## Build inputs

| input | value |
| --- | --- |
| repository base commit | `bde1db2d6861493a9fe0089c6c9211b6fab2df00` |
| build fixes | the change set containing this file (see `git log` on this branch) |
| `maria-padilha-de` | `b09c7810f2f43222a379df12c0f7774c1d511c99` (`v0.2.0`) |
| tracked dotfiles | `f9b6a8304ce1c13a849831d5d57b2dbad1b43420` (`known-good-2026-11-06e`) |
| `iso/package-version` | `0.2.0` |
| Arch rootfs | `archlinux-bootstrap-2026.11.01-x86_64` |
| build date | `2026-11-24T10:56:40Z` (`SOURCE_DATE_EPOCH=1795517800`) |
| kernel parameters | `quiet splash` |

AUR packages built inside the throw-away rootfs and added to the ISO-local
repository:

- `calamares 3.4.2-2` (`087a85ee9cc0f42a29cc9d0b5587dd99a530fdd3b5d6559554c0a6c4ed9eecaf`)
- `libcava 1.0.0-1` (`0ab06c134b1c8a369359196858276711616668c7b2059969c80d1ce300c357e5`)

## Reproduce from a clean checkout

The documented container path is the reproducible path. Clone the image
repository, then check out the two pinned inputs under the ignored `.ci/`
directory:

```sh
git clone https://github.com/maria-padilha-os/maria-padilha-os.git
cd maria-padilha-os
git clone --depth 1 --branch v0.2.0 \
  https://github.com/maria-padilha-os/maria-padilha-de.git .ci/maria-padilha-de
git clone --depth 1 --branch known-good-2026-11-06e \
  https://github.com/maria-padilha-os/maria-padilha-dotfiles.git .ci/maria-padilha-dotfiles

MARIA_PADILHA_DE="$PWD/.ci/maria-padilha-de" \
MARIA_PADILHA_DOTFILES="$PWD/.ci/maria-padilha-dotfiles" \
  bash scripts/ci/build-iso.sh
```

`build-iso.sh` needs Docker or Podman with `--privileged` support for
`mkarchiso`. It writes the ISO, its `.sha256`, and `out/build-info.txt`; it
never installs host packages, runs host `sudo`, or publishes anything. The
same path is available as `make ci-iso`.

## Exact environment note

This host had neither Docker nor Podman. The build therefore ran the same
in-container script (`scripts/ci/container-build.sh`, which invokes
`build.sh`) inside a local `bubblewrap` Arch rootfs created from the official
2026.11.01 bootstrap. The single mapped UID in that sandbox required
environment-local adaptations for `pacstrap`/`arch-chroot` mounts and live-home
ownership; those adaptations are not part of the repository scripts. The
successful final `mkarchiso` command was:

```sh
MARIA_PADILHA_VERSION=0.2.0 SOURCE_DATE_EPOCH=1795517800 \
  mkarchiso -v \
    -w .scratch/iso-build/mkarchiso \
    -o out \
    -C .scratch/iso-build/pacman.conf \
    .scratch/iso-build/profile
```

The repository fixes required by the normal container path are in the change
set containing this file: SRCINFO dependency parsing, the missing Qt6
ShaderTools build dependency, profile mode normalisation,
`kernel_params_x86_64`, and the AUR Calamares bootstrap. A maintainer with
Docker or Podman should use the clean checkout command above rather than the
local bubblewrap adaptations.
