#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Static checks for the rescue entry and the explicit desktop rollback.
#
# Everything here is read-only: no mount, fsck, mkfs, parted, grub-install,
# pacman or QEMU command is run.  The rollback helper is exercised with a
# temporary fixture containing a fake package archive.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail=0
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

require_file() {
    if [[ -s "$1" ]]; then ok "$1"; else bad "$1 missing or empty"; fail=1; fi
}

require_exec() {
    if [[ -x "$1" ]]; then ok "$1 executable"; else bad "$1 is not executable"; fail=1; fi
}

rescue_script="iso/airootfs/usr/local/bin/maria-padilha-rescue"
rollback_script="iso/airootfs/usr/local/bin/maria-padilha-rollback"
rescue_unit="iso/airootfs/etc/systemd/system/maria-padilha-rescue.service"
rescue_link="iso/airootfs/etc/systemd/system/multi-user.target.wants/maria-padilha-rescue.service"
syslinux_entry="iso/syslinux/archiso_rescue.cfg"
uefi_entry="iso/efiboot/loader/entries/02-maria-padilha-rescue.conf"

# ---------------------------------------------------------------------------
# Files, executable bits and syntax
# ---------------------------------------------------------------------------
for file in \
    "$rescue_script" \
    "$rollback_script" \
    "$rescue_unit" \
    "$syslinux_entry" \
    "$uefi_entry" \
    "docs/rescue.md" \
    "docs/rollback.md"; do
    require_file "$file"
done

for executable in "$rescue_script" "$rollback_script"; do
    require_exec "$executable"
done

for script in "$rescue_script" "$rollback_script" tests/rescue.sh; do
    if bash -n "$script" 2>/dev/null; then
        ok "$script syntax"
    else
        bad "$script has a bash syntax error"
    fi
done

if command -v shellcheck >/dev/null 2>&1; then
    for script in "$rescue_script" "$rollback_script"; do
        if shellcheck -x "$script"; then
            ok "shellcheck: $script"
        else
            bad "shellcheck: $script"
        fi
    done
else
    ok "shellcheck not installed; skipped"
fi

# ---------------------------------------------------------------------------
# Boot menu wiring
# ---------------------------------------------------------------------------
if grep -qF -- 'INCLUDE archiso_rescue.cfg' iso/syslinux/archiso_sys.cfg; then
    ok "BIOS menu includes the rescue entry"
else
    bad "BIOS menu does not include archiso_rescue.cfg"
fi

for pattern in \
    'LABEL rescue' \
    'Maria Padilha Rescue (BIOS)' \
    'maria-padilha.rescue=1' \
    'systemd.unit=multi-user.target' \
    'systemd.mask=getty@tty1.service' \
    'vmlinuz-linux' \
    'initramfs-linux.img' \
    'archisobasedir=%INSTALL_DIR%' \
    'archisosearchuuid=%ARCHISO_UUID%'; do
    if grep -qF -- "$pattern" "$syslinux_entry"; then
        ok "syslinux rescue entry has: $pattern"
    else
        bad "syslinux rescue entry is missing: $pattern"
    fi
done

for pattern in \
    'Maria Padilha Rescue (%ARCH%, UEFI)' \
    'sort-key 02' \
    'maria-padilha.rescue=1' \
    'systemd.unit=multi-user.target' \
    'systemd.mask=getty@tty1.service' \
    'vmlinuz-linux' \
    'initramfs-linux.img' \
    'archisobasedir=%INSTALL_DIR%' \
    'archisosearchuuid=%ARCHISO_UUID%'; do
    if grep -qF -- "$pattern" "$uefi_entry"; then
        ok "UEFI rescue entry has: $pattern"
    else
        bad "UEFI rescue entry is missing: $pattern"
    fi
done

if ! grep -qF -- 'maria-padilha.rescue=1' iso/syslinux/archiso_sys-linux.cfg &&
    ! grep -qF -- 'maria-padilha.rescue=1' iso/efiboot/loader/entries/01-maria-padilha-linux.conf; then
    ok "rescue mode is opt-in, not part of the normal live entries"
else
    bad "rescue mode leaked into the normal live boot entries"
fi

# ---------------------------------------------------------------------------
# Rescue service and helper
# ---------------------------------------------------------------------------
for pattern in \
    'ConditionKernelCommandLine=maria-padilha.rescue=1' \
    'ExecStart=/usr/local/bin/maria-padilha-rescue' \
    'TTYPath=/dev/tty1' \
    'WantedBy=multi-user.target'; do
    if grep -qF -- "$pattern" "$rescue_unit"; then
        ok "rescue unit has: $pattern"
    else
        bad "rescue unit is missing: $pattern"
    fi
done

if [[ -L "$rescue_link" ]] &&
    [[ "$(readlink -- "$rescue_link")" == "/etc/systemd/system/maria-padilha-rescue.service" ]]; then
    ok "rescue unit is enabled in multi-user.target.wants"
else
    bad "rescue unit is not enabled in multi-user.target.wants"
fi

if "$rescue_script" --help >/tmp/maria-rescue-help.$$ 2>&1 &&
    grep -qF -- 'lsblk' /tmp/maria-rescue-help.$$ &&
    grep -qF -- 'e2fsck' /tmp/maria-rescue-help.$$ &&
    grep -qF -- 'arch-chroot' /tmp/maria-rescue-help.$$ &&
    grep -qF -- 'grub-install' /tmp/maria-rescue-help.$$ &&
    grep -qF -- 'efibootmgr' /tmp/maria-rescue-help.$$ &&
    grep -qiF -- 'never run fsck' /tmp/maria-rescue-help.$$; then
    ok "rescue helper documents the shell, filesystem and bootloader tools"
else
    bad "rescue helper is missing tool or safety guidance"
fi
rm -f /tmp/maria-rescue-help.$$

# ---------------------------------------------------------------------------
# Package list
# ---------------------------------------------------------------------------
mapfile -t packages < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' iso/packages.x86_64 | grep -v '^$')
has_pkg() {
    local wanted="$1" candidate
    for candidate in "${packages[@]}"; do
        [[ "$candidate" == "$wanted" ]] && return 0
    done
    return 1
}

required_packages=(
    e2fsprogs
    dosfstools
    parted
    gptfdisk
    btrfs-progs
    xfsprogs
    f2fs-tools
    exfatprogs
    ntfs-3g
    grub
    efibootmgr
    arch-install-scripts
)
for package in "${required_packages[@]}"; do
    if has_pkg "$package"; then
        ok "rescue package $package"
    else
        bad "rescue package $package is missing from iso/packages.x86_64"
    fi
done

# ---------------------------------------------------------------------------
# Documentation and local links
# ---------------------------------------------------------------------------
if grep -qF -- 'Maria Padilha Rescue (BIOS)' docs/rescue.md &&
    grep -qF -- 'Maria Padilha Rescue (UEFI)' docs/rescue.md &&
    grep -qF -- 'maria-padilha.rescue=1' docs/rescue.md &&
    grep -qF -- 'arch-chroot' docs/rescue.md &&
    grep -qF -- 'grub-install' docs/rescue.md &&
    grep -qF -- 'grub-mkconfig' docs/rescue.md &&
    grep -qF -- 'efibootmgr' docs/rescue.md &&
    grep -qiF -- 'not an automatic' docs/rescue.md; then
    ok "docs/rescue.md documents entering rescue mode and the repair tools"
else
    bad "docs/rescue.md is missing entry or repair instructions"
fi

if grep -qF -- 'maria-padilha-rollback save' docs/rollback.md &&
    grep -qF -- 'maria-padilha-rollback apply' docs/rollback.md &&
    grep -qF -- 'SHA256SUMS' docs/rollback.md &&
    grep -qF -- 'pacman -U' docs/rollback.md &&
    grep -qiF -- 'package-scoped' docs/rollback.md &&
    grep -qiF -- 'hidden snapshot' docs/rollback.md; then
    ok "docs/rollback.md documents the explicit package rollback"
else
    bad "docs/rollback.md is missing the rollback procedure or limits"
fi

if grep -qF -- 'docs/rescue.md' README.md &&
    grep -qF -- 'docs/rollback.md' README.md; then
    ok "README links the rescue and rollback documentation"
else
    bad "README does not link both recovery documents"
fi

if python3 - "$root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
files = [root / "README.md", *sorted((root / "docs").glob("*.md"))]
missing = []
for path in files:
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", text):
        target = match.group(1).strip("<>")
        if target.startswith(("http://", "https://", "mailto:", "tel:", "#")):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        resolved = (root / target.lstrip("/")) if target.startswith("/") else (path.parent / target)
        if not resolved.exists():
            missing.append(f"{path.relative_to(root)} -> {target}")
if missing:
    for item in missing:
        print(f"FAIL unresolved local Markdown link: {item}")
    raise SystemExit(1)
print(f"ok local Markdown links resolve in {len(files)} files")
PY
then
    ok "documentation links"
else
    bad "a local Markdown link does not resolve"
fi

# ---------------------------------------------------------------------------
# Rollback helper: read-only fixture, no pacman and no root
# ---------------------------------------------------------------------------
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
fake_pkg="$fixture/maria-padilha-0.2.0-1-x86_64.pkg.tar.zst"
printf 'not a real package archive\n' >"$fake_pkg"
(
    cd "$fixture"
    sha256sum "${fake_pkg##*/}" >SHA256SUMS
)

if "$rollback_script" --state-dir "$fixture" list >/tmp/maria-rollback-list.$$ 2>&1 &&
    grep -qF -- 'maria-padilha-0.2.0-1-x86_64.pkg.tar.zst' /tmp/maria-rollback-list.$$; then
    ok "rollback list shows a saved package archive"
else
    bad "rollback list did not show the fixture archive"
fi
rm -f /tmp/maria-rollback-list.$$

if "$rollback_script" --state-dir "$fixture" verify >/dev/null 2>&1; then
    ok "rollback verify accepts an intact fixture"
else
    bad "rollback verify rejected an intact fixture"
fi

printf 'tampered\n' >>"$fake_pkg"
if "$rollback_script" --state-dir "$fixture" verify >/dev/null 2>&1; then
    bad "rollback verify accepted a tampered archive"
else
    ok "rollback verify rejects a tampered archive"
fi

if "$rollback_script" --help >/tmp/maria-rollback-help.$$ 2>&1 &&
    grep -qF -- 'save' /tmp/maria-rollback-help.$$ &&
    grep -qF -- 'apply VERSION' /tmp/maria-rollback-help.$$ &&
    grep -qF -- 'SHA256SUMS' /tmp/maria-rollback-help.$$ &&
    grep -qF -- 'pacman -U' /tmp/maria-rollback-help.$$; then
    ok "rollback helper documents save/list/verify/apply and its checksum"
else
    bad "rollback helper help is missing a command or checksum detail"
fi
rm -f /tmp/maria-rollback-help.$$

if grep -qF -- 'tests/rescue.sh' tests/all.sh; then
    ok "tests/all.sh runs tests/rescue.sh"
else
    bad "tests/all.sh does not run tests/rescue.sh"
fi

# The rescue/rollback tests must not become destructive.  Reject commands that
# would mount, partition, format or repair the host from this test file.
if sed -e 's/#.*//' tests/rescue.sh |
    grep -Eq '(^|[;&|[:space:]])(mount|umount|fsck|e2fsck|mkfs|parted|sgdisk|grub-install|pacman)[[:space:]]'; then
    bad "tests/rescue.sh contains a destructive or privileged command"
else
    ok "tests/rescue.sh is read-only"
fi

if ((fail)); then
    printf '\nRescue/rollback validation failed\n' >&2
    exit 1
fi
printf '\nRescue/rollback validation passed\n'
