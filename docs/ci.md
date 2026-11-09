# CI: ISO build and headless smoke boot

`.github/workflows/iso.yml` builds the `maria-padilha` package and the archiso
image in a privileged Arch container, records the ISO SHA256, and uploads the
image, checksum and build metadata as GitHub Actions artifacts. It deliberately
does **not** create a release, tag or published asset.

## What runs

| job | what it does | timeout |
| --- | --- | --- |
| `build` | runs `tests/all.sh`, checks out the pinned desktop source and dotfiles, builds the package and ISO with `./build.sh` inside `archlinux:latest`, verifies the checksum and uploads artifacts | 120 min |
| `smoke` | downloads the ISO artifact, verifies its checksum, boots it headlessly in QEMU with a serial console and waits for the CI boot marker and a login prompt | 45 min |

The workflow runs on pushes to `main`, pull requests targeting `main`, and
manual `workflow_dispatch`.

## Artifacts

The `build` job uploads one artifact named `maria-padilha-iso` containing:

- `maria-padilha-<version>-x86_64.iso`
- `maria-padilha-<version>-x86_64.iso.sha256` (verify from `out/` with
  `sha256sum -c ./*.sha256`)
- `build-info.txt` with the ISO name, size, SHA256, package version, pinned
  commits, container image, kernel parameters and `SOURCE_DATE_EPOCH`

When the smoke test is enabled, the `smoke` job also uploads
`qemu-smoke-serial-log` (serial console and QEMU logs) with `if: always()`, so a
failed boot leaves evidence. Artifacts expire after 14 days (ISO) or 7 days
(serial log). No release is published from CI.

## Package source and reproducibility

The desktop package is not vendored in this repository. CI checks out
`maria-padilha-os/maria-padilha-de` at the `v0.2.0` tag by default, matching
`iso/package-version`, and checks out the tracked dotfiles at
`known-good-2026-11-06e`. Override them without editing the workflow:

- repository variable `MARIA_PADILHA_DE_REF` (or the `de_ref` dispatch input)
- repository variable `MARIA_PADILHA_DOTFILES_REF`
- repository variable `ARCH_IMAGE` (for example a pinned Arch image digest)

The build wrapper passes the current commit timestamp as `SOURCE_DATE_EPOCH`
and the profile uses it for the ISO label. Arch is a rolling distribution and
the container tag is floating by default, so builds are repeatable in
procedure rather than guaranteed bit-for-bit identical. Pin `ARCH_IMAGE` and
both refs when a stable rebuild is required.

`scripts/ci/build-iso.sh` restores ownership of `out/` and `.scratch/` to the
invoking user after the privileged container exits. It never runs `sudo` on the
host.

The desktop PKGBUILD currently declares `libcava`, which is an AUR package, not
an official Arch package. Inside the container,
`scripts/ci/container-build.sh` builds that one AUR package with `makepkg`,
installs it for the `maria-padilha` build, and passes its package archive to
`build.sh` through `MARIA_PADILHA_EXTRA_REPO`. `build.sh` adds it to the
ISO-local `[maria-padilha]` repository so `mkarchiso` can resolve the dependency
inside the live root. The AUR branch is skipped automatically if `libcava`
becomes available in the official repositories. No AUR helper is installed and
the AUR source/package is not cached.

## Package download cache

The workflow caches only `/var/cache/pacman/pkg`, mounted from
`.ci/cache/pacman`. Pacman packages are signature/checksum verified by pacman,
so reusing the download cache is safe. The pacman database, build directories,
secrets and the ISO itself are never cached. The cache key includes the tracked
package lists and `iso/pacman.conf`; a cache miss simply downloads the packages
again.

## Headless QEMU smoke boot

The smoke test is **opt-in**. Run it from **Actions → ISO build and smoke boot →
Run workflow** with `smoke_test` enabled. On push and pull request runs the build
still happens, but the workflow emits an explicit notice that no smoke result is
claimed instead of silently pretending the test passed.

When enabled, the build adds these live kernel parameters:

```text
console=tty0 console=ttyS0,115200
systemd.wants=serial-getty@ttyS0.service
maria-padilha.ci=1
```

`maria-padilha.ci=1` arms a boot-marker unit that writes
`MARIA_PADILHA_BOOT_OK` to the console; it is inert on normal boots. The serial
getty provides the login prompt. `scripts/ci/qemu-smoke-test.sh` then:

1. boots the ISO with `qemu-system-x86_64 -display none -serial file:... -nic none`;
2. waits for `MARIA_PADILHA_BOOT_OK` and a line ending in `login:`;
3. fails immediately on a kernel panic, fatal boot error, unexpected QEMU exit
   or timeout (default 900 seconds in the script, 1200 in CI);
4. keeps the serial and QEMU logs for artifact upload.

The smoke test proves that the ISO reaches userspace, starts the serial getty
and can present a login prompt. It does not log in, start a graphical session,
run Calamares or replace the manual visual checklists in
[`qemu-branding.md`](qemu-branding.md) and
[`qemu-calamares.md`](qemu-calamares.md).

Run the same check locally after a smoke-enabled build:

```sh
bash scripts/ci/qemu-smoke-test.sh out/maria-padilha-*.iso
```

## Runner and artifact limits

The default GitHub-hosted `ubuntu-latest` runner has roughly 14 GB of free disk
and 16 GB of RAM. The privileged Arch container, downloaded packages, package
build output and the mkarchiso work tree can consume several GB before the ISO
is written. To keep that runner and the artifact upload practical, the build
wrapper enforces a project ceiling of **9 GiB** (`9663676416` bytes) by default
and prints a clear error instead of uploading an unexpectedly huge image. Raise
`MARIA_PADILHA_MAX_ISO_BYTES` deliberately, or use a self-hosted/larger runner
with more disk. GitHub additionally applies plan-based artifact storage quotas;
check the current GitHub Actions limits before relying on a very large upload.

QEMU is intentionally opt-in because it needs the ISO artifact plus a 3 GiB
guest, a writable disk/log area and a 20-minute boot budget. That is too much
for the default CI path to run reliably on every push. If the ISO or runner
cannot support it, the smoke job is not silently skipped: the build job records
that the test was not requested, and an enabled smoke run fails with the serial
log when the ISO cannot boot.

## Manual equivalent

The workflow wraps the same commands documented in the README. To reproduce it
on a machine with Docker or Podman:

```sh
# make the sibling sources available under .ci/ (or set MARIA_PADILHA_DE and
# MARIA_PADILHA_DOTFILES to existing checkouts)
git clone --depth 1 --branch v0.2.0 \
  https://github.com/maria-padilha-os/maria-padilha-de.git .ci/maria-padilha-de
git clone --depth 1 \
  https://github.com/maria-padilha-os/maria-padilha-dotfiles.git .ci/maria-padilha-dotfiles

# build, checksum and write out/build-info.txt; no host sudo
bash scripts/ci/build-iso.sh

# optional: build with the serial parameters, then boot it headlessly
MARIA_PADILHA_KERNEL_PARAMS='quiet splash console=tty0 console=ttyS0,115200 systemd.wants=serial-getty@ttyS0.service maria-padilha.ci=1' \
  bash scripts/ci/build-iso.sh
bash scripts/ci/qemu-smoke-test.sh out/maria-padilha-*.iso
```

The wrapper starts `docker run --privileged` (or the Podman equivalent) because
`mkarchiso` needs mount, loop devices and chroot inside the container. It does
not install anything on the host and does not publish anything.
