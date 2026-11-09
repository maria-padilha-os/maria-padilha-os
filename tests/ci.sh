#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Static checks for the CI image build and the opt-in QEMU smoke boot.  These
# checks never start Docker, mkarchiso or QEMU and never need root.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail=0
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

require_file() {
    if [[ -s "$1" ]]; then ok "$1"; else bad "$1 missing or empty"; fi
}

require_exec() {
    if [[ -x "$1" ]]; then ok "$1 executable"; else bad "$1 is not executable"; fi
}

workflow=".github/workflows/iso.yml"
build_script="scripts/ci/build-iso.sh"
container_script="scripts/ci/container-build.sh"
smoke_script="scripts/ci/qemu-smoke-test.sh"
marker_unit="iso/airootfs/etc/systemd/system/maria-padilha-ci-boot-marker.service"
marker_link="iso/airootfs/etc/systemd/system/multi-user.target.wants/maria-padilha-ci-boot-marker.service"

for file in "$workflow" "$build_script" "$container_script" "$smoke_script" "$marker_unit" "docs/ci.md"; do
    require_file "$file"
done
for executable in "$build_script" "$container_script" "$smoke_script"; do
    require_exec "$executable"
done
for script in "$build_script" "$container_script" "$smoke_script"; do
    if bash -n "$script" 2>/dev/null; then
        ok "$script syntax"
    else
        bad "$script has a bash syntax error"
    fi
done

# Workflow shape: an Arch container build, checksum, artifacts and an explicit
# opt-in QEMU job.  It must not publish a release.
if grep -q '^  workflow_dispatch:' "$workflow" &&
    grep -q '^      smoke_test:' "$workflow" &&
    grep -q 'default: false' "$workflow"; then
    ok "workflow_dispatch exposes smoke_test with an opt-in default"
else
    bad "workflow is missing the opt-in smoke_test input"
fi
if grep -qF 'archlinux' "$workflow" &&
    grep -qF 'build-iso.sh' "$workflow" &&
    grep -qF 'mkarchiso' "$build_script" &&
    grep -qF 'mkarchiso' "$root/build.sh"; then
    ok "workflow builds the image through the Arch-container wrapper"
else
    bad "workflow/wrapper does not show the Arch-container mkarchiso path"
fi
if grep -qF 'container-build.sh' "$build_script" &&
    grep -qF 'MARIA_PADILHA_EXTRA_REPO' "$root/build.sh" &&
    grep -qF 'libcava' "$container_script"; then
    ok "container bootstrap provides the AUR-only libcava dependency to the ISO repo"
else
    bad "AUR-only package bootstrap is missing from the CI build path"
fi
if grep -qF 'sha256sum' "$workflow" &&
    grep -qF 'sha256sum' "$build_script" &&
    grep -qF 'out/*.sha256' "$workflow"; then
    ok "workflow records and verifies the SHA256 checksum"
else
    bad "workflow is missing SHA256 checksum handling"
fi
if grep -qF 'actions/upload-artifact' "$workflow" &&
    grep -qF 'out/*.iso' "$workflow" &&
    grep -qF 'out/*.sha256' "$workflow"; then
    ok "workflow uploads the ISO and checksum as artifacts"
else
    bad "workflow does not upload the ISO and checksum"
fi
if grep -qF 'actions/cache@' "$workflow" &&
    grep -qF 'PACMAN_CACHE: .ci/cache/pacman' "$workflow"; then
    ok "workflow caches only pacman package downloads"
else
    bad "workflow is missing the safe pacman package cache"
fi
if grep -qF 'timeout-minutes: 120' "$workflow" &&
    grep -qF 'timeout-minutes: 45' "$workflow"; then
    ok "workflow build/smoke jobs have finite timeouts"
else
    bad "workflow is missing reasonable job timeouts"
fi
if grep -qF 'needs.build.outputs.smoke_test' "$workflow" &&
    grep -qF "smoke_test == 'true'" "$workflow" &&
    grep -qiF 'not requested' "$workflow"; then
    ok "smoke job is explicitly opt-in and not silently treated as passing"
else
    bad "smoke job is not clearly opt-in/explicit about not running"
fi
if grep -Eqi 'action-gh-release|gh release|softprops|create-release|upload-release' "$workflow"; then
    bad "workflow appears to publish a release"
else
    ok "workflow does not publish a release"
fi

# Smoke implementation: QEMU, serial, marker, login prompt and panic handling.
if grep -qF 'qemu-system-x86_64' "$smoke_script" &&
    grep -qF -- '-serial' "$smoke_script" &&
    grep -qF -- '-display none' "$smoke_script" &&
    grep -qF -- '-nic none' "$smoke_script"; then
    ok "smoke script boots QEMU headlessly with a serial console"
else
    bad "smoke script is missing the headless serial QEMU invocation"
fi
if grep -qF 'MARIA_PADILHA_BOOT_OK' "$smoke_script" &&
    grep -qF 'MARIA_PADILHA_BOOT_OK' "$marker_unit" &&
    grep -qF 'ConditionKernelCommandLine=maria-padilha.ci=1' "$marker_unit"; then
    ok "boot marker is emitted only for the CI kernel parameter"
else
    bad "boot marker unit/script are not wired together"
fi
if [[ -L "$marker_link" ]] &&
    [[ "$(readlink -- "$marker_link")" == *maria-padilha-ci-boot-marker.service ]]; then
    ok "CI boot marker unit is enabled"
else
    bad "CI boot marker unit is not enabled"
fi
if grep -qF 'login:' "$smoke_script" &&
    grep -qF 'panic' "$smoke_script" &&
    grep -qF 'timed out' "$smoke_script"; then
    ok "smoke script fails on missing login prompt, panic or timeout"
else
    bad "smoke script does not enforce login prompt/panic/timeout"
fi
if grep -qF 'MARIA_PADILHA_KERNEL_PARAMS' "$root/iso/profiledef.sh" &&
    grep -qE '^kernel_params=.*splash' "$root/iso/profiledef.sh" &&
    grep -qF 'systemd.wants=serial-getty@ttyS0.service' "$workflow"; then
    ok "CI serial kernel parameters are opt-in and leave the normal default intact"
else
    bad "kernel parameter override is missing or changed the normal default"
fi

# Size/ownership guard and documentation of the runner/artifact limit.
if grep -qF 'MARIA_PADILHA_MAX_ISO_BYTES' "$build_script" &&
    grep -qF '9663676416' "$build_script" &&
    grep -qF '9 GiB' "docs/ci.md" &&
    grep -qiF 'opt-in' "docs/ci.md"; then
    ok "ISO size limit and opt-in smoke policy are documented and enforced"
else
    bad "ISO size/runner limit is not documented and enforced"
fi

# The repository suite must run this file.
if grep -qF 'tests/ci.sh' tests/all.sh; then
    ok "tests/all.sh runs tests/ci.sh"
else
    bad "tests/all.sh does not run tests/ci.sh"
fi

if ((fail)); then
    printf '\nCI validation failed\n' >&2
    exit 1
fi
printf '\nCI validation passed\n'
