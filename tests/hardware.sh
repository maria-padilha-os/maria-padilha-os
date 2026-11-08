#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Static and fixture checks for laptop hardware enablement.  This does not
# touch real hardware, load modules, change services, or exercise suspend and
# hibernation.
set -Eeuo pipefail

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

for file in \
    docs/supported-hardware.md \
    scripts/check-hardware.sh \
    iso/airootfs/usr/local/bin/maria-padilha-hardware-check \
    iso/airootfs/etc/systemd/sleep.conf.d/10-maria-padilha-no-s2idle.conf \
    iso/airootfs/etc/systemd/logind.conf.d/10-maria-padilha-no-autosuspend.conf; do
    require_file "$file"
done

for executable in scripts/check-hardware.sh \
    iso/airootfs/usr/local/bin/maria-padilha-hardware-check; do
    require_exec "$executable"
done

for script in scripts/check-hardware.sh \
    iso/airootfs/usr/local/bin/maria-padilha-hardware-check; do
    if bash -n "$script" 2>/dev/null; then
        ok "$script syntax"
    else
        bad "$script has a bash syntax error"
    fi
done

# Package coverage.  The list is parsed exactly like tests/iso.sh so comments
# and whitespace cannot hide a package.
mapfile -t packages < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' iso/packages.x86_64 | grep -v '^$')
has_pkg() {
    local wanted="$1" candidate
    for candidate in "${packages[@]}"; do
        [[ "$candidate" == "$wanted" ]] && return 0
    done
    return 1
}

required_packages=(
    amd-ucode
    linux-firmware
    linux-firmware-amd
    linux-firmware-amdgpu
    linux-firmware-atheros
    linux-firmware-broadcom
    linux-firmware-intel
    linux-firmware-mediatek
    linux-firmware-realtek
    mesa
    vulkan-radeon
    libva
    sof-firmware
    alsa-ucm-conf
    power-profiles-daemon
    upower
    lm_sensors
    acpi
    bluez
    bluez-utils
    iw
    wireless-regdb
    pciutils
    usbutils
)
for package in "${required_packages[@]}"; do
    if has_pkg "$package"; then
        ok "package $package"
    else
        bad "required hardware package $package is missing"
    fi
done

for package in tlp auto-cpufreq thermald; do
    if has_pkg "$package"; then
        bad "conflicting power/thermal package $package must not be installed"
    else
        ok "package $package excluded"
    fi
done

sleep_conf="iso/airootfs/etc/systemd/sleep.conf.d/10-maria-padilha-no-s2idle.conf"
logind_conf="iso/airootfs/etc/systemd/logind.conf.d/10-maria-padilha-no-autosuspend.conf"

for setting in AllowSuspend AllowHibernation AllowHybridSleep AllowSuspendThenHibernate; do
    if grep -qE "^[[:space:]]*${setting}[[:space:]]*=[[:space:]]*no([[:space:]]|$)" "$sleep_conf"; then
        ok "sleep.conf disables $setting"
    else
        bad "sleep.conf does not disable $setting"
    fi
done

for setting in HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked HandleSuspendKey HandleHibernateKey; do
    if grep -qE "^[[:space:]]*${setting}[[:space:]]*=[[:space:]]*ignore([[:space:]]|$)" "$logind_conf"; then
        ok "logind.conf sets $setting=ignore"
    else
        bad "logind.conf does not set $setting=ignore"
    fi
done
if grep -qE '^[[:space:]]*IdleAction[[:space:]]*=[[:space:]]*ignore([[:space:]]|$)' "$logind_conf"; then
    ok "logind.conf sets IdleAction=ignore"
else
    bad "logind.conf does not set IdleAction=ignore"
fi
if grep -RInE '^[[:space:]]*Handle(LidSwitch|SuspendKey|HibernateKey)[[:space:]]*=[[:space:]]*(suspend|hibernate)' \
    iso/airootfs/etc/systemd/logind.conf.d >/dev/null 2>&1; then
    bad "a logind drop-in still auto-suspends"
else
    ok "no logind drop-in auto-suspends"
fi

# Documentation contract.
if grep -qx '## Tested' docs/supported-hardware.md &&
    grep -qx '## Best-effort' docs/supported-hardware.md &&
    grep -qx '## Explicitly unsupported' docs/supported-hardware.md; then
    ok "supported-hardware document has tested/best-effort/unsupported sections"
else
    bad "supported-hardware document is missing a required status section"
fi
for term in s2idle suspend hibernate 'maria-padilha-hardware-check'; do
    if grep -qiF -- "$term" docs/supported-hardware.md; then
        ok "supported-hardware document mentions $term"
    else
        bad "supported-hardware document does not mention $term"
    fi
done

# The check script must be read-only and must never exercise sleep.  It also
# must not name the privilege/manager commands the repository forbids in
# scripts.
check_script="iso/airootfs/usr/local/bin/maria-padilha-hardware-check"
for literal in amd-ucode linux-firmware-amdgpu sof-firmware power-profiles-daemon; do
    if grep -qF -- "$literal" "$check_script"; then
        ok "hardware check covers $literal"
    else
        bad "hardware check does not cover $literal"
    fi
done
if grep -qE '(^|[;&|[:space:]])(sudo|pkexec|systemctl|pacman|mount)([[:space:]]|$)' "$check_script"; then
    bad "hardware check uses a privileged or forbidden command"
else
    ok "hardware check uses no privileged or forbidden command"
fi
if grep -qE '(^|[;&|[:space:]])(systemctl[[:space:]]+(suspend|hibernate|hybrid-sleep|suspend-then-hibernate)|rtcwake|pm-suspend|pm-hibernate)([[:space:]]|$)' \
    "$check_script"; then
    bad "hardware check invokes a suspend/hibernate command"
else
    ok "hardware check does not invoke suspend or hibernate"
fi
if bash "$check_script" --help >/dev/null 2>&1; then
    ok "hardware check --help"
else
    bad "hardware check --help failed"
fi

# Fixture root: exercise the check without root, real firmware or a package
# manager.  The fixture mimics a minimal installed image.
tmp_base="$root/.scratch"
install -d -m 0755 "$tmp_base"
tmp="$(mktemp -d "$tmp_base/hardware-test.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

fixture="$tmp/root"
mkdir -p "$fixture/var/lib/pacman/local"
fixture_packages=(
    linux amd-ucode linux-firmware linux-firmware-amd linux-firmware-amdgpu
    linux-firmware-mediatek linux-firmware-realtek linux-firmware-atheros
    linux-firmware-broadcom linux-firmware-intel sof-firmware alsa-ucm-conf
    power-profiles-daemon upower lm_sensors acpi networkmanager bluez
    bluez-utils iw wireless-regdb mesa vulkan-radeon libva
    pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils
)
for package in "${fixture_packages[@]}"; do
    mkdir -p "$fixture/var/lib/pacman/local/$package-1.0-1"
done

mkdir -p \
    "$fixture/usr/lib/firmware/amdgpu" \
    "$fixture/usr/lib/firmware/mediatek" \
    "$fixture/usr/lib/firmware/intel/sof" \
    "$fixture/usr/share/alsa/ucm2" \
    "$fixture/usr/bin" \
    "$fixture/etc/systemd/system/multi-user.target.wants"
: >"$fixture/usr/lib/firmware/amdgpu/gpu.bin"
: >"$fixture/usr/lib/firmware/mediatek/wifi.bin"
: >"$fixture/usr/lib/firmware/intel/sof/sof.ri"
for command in pipewire wireplumber wpctl powerprofilesctl sensors; do
    : >"$fixture/usr/bin/$command"
    chmod 0755 "$fixture/usr/bin/$command"
done
for unit in power-profiles-daemon NetworkManager bluetooth; do
    ln -s "/usr/lib/systemd/system/$unit.service" \
        "$fixture/etc/systemd/system/multi-user.target.wants/$unit.service"
done
install -d -m 0755 "$fixture/etc/systemd/sleep.conf.d" "$fixture/etc/systemd/logind.conf.d"
cp "$sleep_conf" "$fixture/etc/systemd/sleep.conf.d/"
cp "$logind_conf" "$fixture/etc/systemd/logind.conf.d/"

if output="$(bash "$check_script" --root "$fixture" 2>&1)"; then
    ok "hardware check accepts a complete fixture"
else
    bad "hardware check rejected a complete fixture"
    printf '%s\n' "$output" | sed 's/^/  /'
fi

# Missing AMD GPU firmware must be a hard failure even when the package names
# still look plausible.
rm -rf "$fixture/usr/lib/firmware/amdgpu"
if output="$(bash "$check_script" --root "$fixture" 2>&1)"; then
    bad "hardware check accepted a root without AMD GPU firmware"
else
    if grep -qF 'AMD GPU firmware tree is missing' <<<"$output"; then
        ok "hardware check reports missing AMD GPU firmware"
    else
        bad "hardware check failed without naming the missing AMD GPU firmware"
        printf '%s\n' "$output" | sed 's/^/  /'
    fi
fi

# A missing required package must also fail clearly.
mkdir -p "$fixture/usr/lib/firmware/amdgpu"
: >"$fixture/usr/lib/firmware/amdgpu/gpu.bin"
rm -rf "$fixture/var/lib/pacman/local/sof-firmware-1.0-1"
if output="$(bash "$check_script" --root "$fixture" 2>&1)"; then
    bad "hardware check accepted a root without sof-firmware"
else
    if grep -qF 'package sof-firmware is not installed' <<<"$output"; then
        ok "hardware check reports a missing audio firmware package"
    else
        bad "hardware check failed without naming the missing audio package"
        printf '%s\n' "$output" | sed 's/^/  /'
    fi
fi

if ((fail)); then
    printf '\nHardware enablement test FAILED\n' >&2
    exit 1
fi
printf '\nHardware enablement test passed\n'
