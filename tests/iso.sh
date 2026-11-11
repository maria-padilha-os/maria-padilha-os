#!/usr/bin/env bash
# Static checks for the archiso profile. These do not need root, mkarchiso or
# an Arch host; they verify the files that build.sh and mkarchiso consume.
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

for file in \
    README.md \
    build.sh \
    Makefile \
    iso/profiledef.sh \
    iso/packages.x86_64 \
    iso/pacman.conf \
    iso/package-version \
    iso/airootfs/etc/greetd/config.toml \
    iso/airootfs/etc/maria-padilha-release \
    iso/airootfs/etc/maria-padilha/boot-palette.conf \
    iso/airootfs/etc/plymouth/plymouthd.conf \
    iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf \
    iso/airootfs/etc/skel/.bashrc \
    iso/airootfs/etc/skel/.profile \
    iso/airootfs/etc/skel/.bash_logout \
    iso/airootfs/etc/skel/.config/maria-padilha/README.md \
    iso/airootfs/usr/local/bin/maria-padilha-calamares-first-boot \
    iso/airootfs/usr/local/bin/maria-padilha-greeter \
    iso/airootfs/usr/share/plymouth/themes/maria-padilha/maria-padilha.plymouth \
    iso/airootfs/boot/grub/themes/maria-padilha/theme.txt \
    iso/airootfs/usr/local/bin/maria-padilha-hardware-check \
    iso/airootfs/usr/local/bin/maria-padilha-rescue \
    iso/airootfs/usr/local/bin/maria-padilha-rollback \
    iso/airootfs/etc/systemd/system/maria-padilha-rescue.service \
    iso/efiboot/loader/entries/02-maria-padilha-rescue.conf \
    iso/syslinux/archiso_rescue.cfg \
    iso/airootfs/etc/systemd/sleep.conf.d/10-maria-padilha-no-s2idle.conf \
    iso/airootfs/etc/systemd/logind.conf.d/10-maria-padilha-no-autosuspend.conf \
    iso/efiboot/loader/entries/01-maria-padilha-linux.conf \
    iso/syslinux/syslinux.cfg \
    iso/syslinux/archiso_sys.cfg \
    iso/syslinux/splash.png \
    scripts/overlay-dotfiles.sh \
    scripts/check-hardware.sh \
    scripts/ci/build-iso.sh \
    scripts/ci/container-build.sh \
    scripts/ci/qemu-smoke-test.sh \
    .github/workflows/iso.yml \
    iso/airootfs/etc/systemd/system/maria-padilha-ci-boot-marker.service \
    tests/ci.sh \
    tests/first-boot.sh \
    tests/skel.sh \
    tests/branding.sh \
    docs/first-boot.md \
    docs/boot-branding.md \
    docs/qemu-branding.md \
    docs/ci.md \
    tests/hardware.sh \
    tests/rescue.sh \
    docs/supported-hardware.md \
    docs/rescue.md \
    docs/rollback.md; do
    require_file "$file"
done

for executable in build.sh tests/all.sh tests/iso.sh tests/first-boot.sh tests/skel.sh \
    tests/branding.sh scripts/overlay-dotfiles.sh iso/profiledef.sh \
    iso/airootfs/usr/local/bin/maria-padilha-greeter \
    tests/hardware.sh scripts/check-hardware.sh \
    scripts/ci/build-iso.sh scripts/ci/container-build.sh \
    scripts/ci/qemu-smoke-test.sh tests/ci.sh tests/rescue.sh \
    iso/airootfs/usr/local/bin/maria-padilha-hardware-check \
    iso/airootfs/usr/local/bin/maria-padilha-rescue \
    iso/airootfs/usr/local/bin/maria-padilha-rollback; do
    require_exec "$executable"
done

for script in build.sh tests/all.sh tests/iso.sh tests/first-boot.sh tests/skel.sh \
    tests/branding.sh scripts/overlay-dotfiles.sh iso/profiledef.sh \
    tests/hardware.sh scripts/check-hardware.sh \
    scripts/ci/build-iso.sh scripts/ci/container-build.sh \
    scripts/ci/qemu-smoke-test.sh tests/ci.sh tests/rescue.sh \
    iso/airootfs/usr/local/bin/maria-padilha-hardware-check \
    iso/airootfs/usr/local/bin/maria-padilha-rescue \
    iso/airootfs/usr/local/bin/maria-padilha-rollback; do
    if bash -n "$script" 2>/dev/null; then
        ok "$script syntax"
    else
        bad "$script has a bash syntax error"
    fi
done

# Read the profile exactly as mkarchiso does, but with the version override
# unset so the checked-in pin is what the test sees.
profile_dump="$(bash --noprofile --norc -c '
    set -e
    unset MARIA_PADILHA_VERSION
    source "$1"
    printf "%s\n" "$iso_name" "$iso_label" "$iso_version" "$install_dir" "$pacman_conf" "${bootmodes[*]}"
' _ "$root/iso/profiledef.sh")"
mapfile -t profile < <(printf '%s\n' "$profile_dump")
iso_name="${profile[0]:-}"
iso_label="${profile[1]:-}"
iso_version="${profile[2]:-}"
install_dir="${profile[3]:-}"
pacman_conf="${profile[4]:-}"
bootmodes="${profile[5]:-}"

if [[ "$iso_name" == "maria-padilha" ]]; then ok "iso_name is maria-padilha"; else bad "iso_name is '${iso_name}'"; fi
if [[ "$iso_label" =~ ^[A-Z0-9_]{1,32}$ ]]; then ok "iso_label is valid"; else bad "iso_label is invalid or too long: '${iso_label}'"; fi
if [[ "$install_dir" =~ ^[a-z0-9]+$ ]]; then ok "install_dir is valid"; else bad "install_dir must be lowercase alphanumeric: '${install_dir}'"; fi
if [[ "$pacman_conf" == "pacman.conf" && -s "iso/$pacman_conf" ]]; then ok "pacman_conf points at iso/pacman.conf"; else bad "pacman_conf does not point at iso/pacman.conf"; fi
if [[ "$bootmodes" == *bios.syslinux* ]]; then ok "BIOS syslinux boot mode"; else bad "bios.syslinux boot mode missing"; fi
if [[ "$bootmodes" == *uefi.systemd-boot* ]]; then ok "UEFI systemd-boot boot mode"; else bad "uefi.systemd-boot boot mode missing"; fi

version="$(tr -d '[:space:]' < iso/package-version)"
if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9]+)*$ ]]; then
    ok "package version pin $version"
else
    bad "iso/package-version is not a version: '$version'"
fi
if [[ "$iso_version" == "$version" ]]; then ok "iso_version follows package version"; else bad "iso_version '$iso_version' != package version '$version'"; fi

for file in iso/profiledef.sh iso/airootfs/etc/maria-padilha-release; do
    if grep -qF -- "$version" "$file"; then
        ok "$file references package version $version"
    else
        bad "$file does not reference package version $version"
    fi
done
if grep -qF -- 'package-version' build.sh && grep -qF -- 'pkgver' build.sh; then
    ok "build.sh derives the package version"
else
    bad "build.sh does not derive the package version"
fi

# When the sibling package checkout is available, the pin must match its
# PKGBUILD. In an isolated image checkout this check is skipped.
de_dir="${MARIA_PADILHA_DE:-$root/../maria-padilha-de}"
if [[ -f "$de_dir/packaging/PKGBUILD" ]]; then
    pkgver="$(sed -nE 's/^pkgver=([^[:space:]#]+).*/\1/p' "$de_dir/packaging/PKGBUILD" | head -n1)"
    if [[ "$pkgver" == "$version" ]]; then
        ok "iso/package-version matches PKGBUILD ($pkgver)"
    else
        bad "iso/package-version is $version but PKGBUILD is ${pkgver:-unreadable}"
    fi
else
    ok "sibling PKGBUILD not present; package version pin is unchanged"
fi

# Package selection.
mapfile -t packages < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' iso/packages.x86_64 | grep -v '^$')
has_pkg() {
    local wanted="$1" candidate
    for candidate in "${packages[@]}"; do
        [[ "$candidate" == "$wanted" ]] && return 0
    done
    return 1
}

required_packages=(
    base
    linux
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
    upower
    lm_sensors
    acpi
    pciutils
    usbutils
    mkinitcpio-archiso
    squashfs-tools
    syslinux
    networkmanager
    wpa_supplicant
    wireless-regdb
    pipewire
    pipewire-pulse
    pipewire-alsa
    wireplumber
    bluez
    bluez-utils
    hyprland
    quickshell
    qt6-base
    qt6-declarative
    qt6-wayland
    hyprlock
    hypridle
    hyprsunset
    xdg-desktop-portal-hyprland
    polkit
    polkit-gnome
    gnome-keyring
    ttf-jetbrains-mono-nerd
    noto-fonts
    noto-fonts-emoji
    greetd
    greetd-tuigreet
    plymouth
    seatd
    power-profiles-daemon
    maria-padilha
)
for package in "${required_packages[@]}"; do
    if has_pkg "$package"; then
        ok "package $package"
    else
        bad "required package $package is missing"
    fi
done

for package in sddm base-devel gcc make cmake ninja; do
    if has_pkg "$package"; then
        bad "package $package must not be installed in the live root"
    else
        ok "package $package excluded"
    fi
done

# Greeter choice is greetd + tuigreet through the themed wrapper, and the
# config must still carry the live autologin and the Maria Padilha session.
if grep -qF -- '[initial_session]' iso/airootfs/etc/greetd/config.toml &&
    grep -qF -- 'maria-padilha-greeter' iso/airootfs/etc/greetd/config.toml &&
    grep -qF -- 'Maria Padilha' iso/airootfs/etc/greetd/config.toml; then
    ok "greetd + themed tuigreet wrapper is the configured greeter"
else
    bad "greetd config is not the documented greetd + tuigreet setup"
fi
if [[ -L iso/airootfs/etc/systemd/system/graphical.target.wants/greetd.service ]] &&
    [[ "$(readlink iso/airootfs/etc/systemd/system/graphical.target.wants/greetd.service)" == *greetd.service ]]; then
    ok "greetd.service is enabled"
else
    bad "greetd.service is not enabled in graphical.target.wants"
fi
if [[ -L iso/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service ]]; then
    ok "NetworkManager.service is enabled"
else
    bad "NetworkManager.service is not enabled"
fi
if [[ -L iso/airootfs/etc/systemd/system/multi-user.target.wants/bluetooth.service ]]; then
    ok "bluetooth.service is enabled"
else
    bad "bluetooth.service is not enabled"
fi

require_symlink() {
    local path="$1" target="$2"
    if [[ -L "$path" && "$(readlink -- "$path")" == "$target" ]]; then
        ok "${path#iso/airootfs/} -> $target"
    else
        bad "${path#iso/airootfs/} is not linked to $target"
    fi
}

for unit in seatd power-profiles-daemon; do
    require_symlink         "iso/airootfs/etc/systemd/system/multi-user.target.wants/$unit.service"         "/usr/lib/systemd/system/$unit.service"
done
for unit in pipewire pipewire-pulse wireplumber; do
    require_symlink         "iso/airootfs/etc/systemd/user/default.target.wants/$unit.service"         "/usr/lib/systemd/user/$unit.service"
done
for unit in pipewire pipewire-pulse; do
    require_symlink         "iso/airootfs/etc/systemd/user/sockets.target.wants/$unit.socket"         "/usr/lib/systemd/user/$unit.socket"
done

# Profile metadata and boot files.
if grep -q '^\[core\]' iso/pacman.conf && grep -q '^\[extra\]' iso/pacman.conf &&
    grep -q '^Architecture' iso/pacman.conf; then
    ok "pacman.conf has core, extra and Architecture"
else
    bad "pacman.conf is missing core/extra/Architecture"
fi
if grep -qF -- '%INSTALL_DIR%' iso/efiboot/loader/entries/01-maria-padilha-linux.conf &&
    grep -qF -- 'archisosearchuuid=%ARCHISO_UUID%' iso/efiboot/loader/entries/01-maria-padilha-linux.conf; then
    ok "UEFI boot entry uses archiso paths"
else
    bad "UEFI boot entry is missing archiso placeholders"
fi
if grep -qF -- 'archiso_sys.cfg' iso/syslinux/syslinux.cfg &&
    grep -qF -- 'archisosearchuuid=%ARCHISO_UUID%' iso/syslinux/archiso_sys-linux.cfg; then
    ok "BIOS syslinux entry uses archiso paths"
else
    bad "BIOS syslinux entry is incomplete"
fi
if grep -q '^HOOKS=.*archiso' iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf; then
    ok "mkinitcpio archiso hook enabled"
else
    bad "mkinitcpio archiso hook missing"
fi
if grep -Eq '^iso:' Makefile && grep -qF -- './build.sh' Makefile; then
    ok "Makefile has an iso target"
else
    bad "Makefile iso target missing"
fi
if grep -qF -- 'mkarchiso' build.sh &&
    grep -qF -- 'refusing to build outside an Arch container' build.sh; then
    ok "build.sh checks mkarchiso and the Arch container guard"
else
    bad "build.sh is missing the mkarchiso/container guard"
fi
if grep -qF -- 'overlay-dotfiles.sh' build.sh; then
    ok "build.sh uses the dotfiles overlay helper"
else
    bad "build.sh does not use scripts/overlay-dotfiles.sh"
fi
for pattern in 'env.local.lua' 'env.local.example.lua' 'copy_config_dir hypr'     'copy_config_dir quickshell' 'credentials' 'secret'; do
    if grep -qF -- "$pattern" scripts/overlay-dotfiles.sh; then
        ok "overlay helper handles $pattern"
    else
        bad "overlay helper does not handle $pattern"
    fi
done
if find iso/airootfs/etc/skel -type f \( -name 'env.local*.lua' -o -name '.env' \
    -o -iname '*credential*' -o -iname '*secret*' \) -print | grep -q .; then
    bad "/etc/skel contains a credential-looking file"
else
    ok "/etc/skel has no credential-looking files"
fi
if grep -qF -- '--sessions /usr/share/wayland-sessions' iso/airootfs/etc/greetd/config.toml; then
    ok "greetd lists the installed Maria Padilha session"
else
    bad "greetd does not list /usr/share/wayland-sessions"
fi
if grep -qF -- '/etc/skel' iso/profiledef.sh; then
    ok "profiledef declares skeleton permissions"
else
    bad "profiledef does not declare /etc/skel permissions"
fi
if grep -qF -- 'tests/first-boot.sh' tests/all.sh &&
    grep -qF -- 'tests/skel.sh' tests/all.sh &&
    grep -qF -- 'tests/branding.sh' tests/all.sh; then
    ok "repository suite runs the branding, skel and first-boot tests"
else
    bad "repository suite is missing a branding, skel or first-boot test"
fi
if grep -qF -- 'docs/qemu-branding.md' README.md &&
    grep -qF -- 'docs/boot-branding.md' README.md &&
    grep -qF -- 'docs/rescue.md' README.md &&
    grep -qF -- 'docs/rollback.md' README.md; then
    ok "README links the boot-branding, rescue and rollback docs"
else
    bad "README does not link the boot-branding, rescue and rollback docs"
fi
if grep -qF -- 'tests/hardware.sh' tests/all.sh &&
    grep -qF -- 'tests/rescue.sh' tests/all.sh; then
    ok "repository suite runs the hardware and rescue/rollback tests"
else
    bad "repository suite is missing the hardware or rescue/rollback test"
fi
if grep -qE '^first-boot:' Makefile; then
    ok "Makefile has a first-boot target"
else
    bad "Makefile first-boot target missing"
fi

# Secret and credential scan over the working tree (tracked and untracked).
secret_pattern='(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY-----)'
secret_hits="$(mktemp)"
if grep -RInE --exclude-dir=.git --exclude-dir=out --exclude-dir=.scratch --exclude-dir=.ci -- "$secret_pattern" . >"$secret_hits" 2>/dev/null; then
    bad "possible tracked secret"
    cat "$secret_hits"
else
    ok "no obvious API key or private key"
fi
rm -f "$secret_hits"

if find . -path ./.git -prune -o -path ./out -prune -o -path ./.scratch -prune -o -path ./.ci -prune -o -type f -name '.env' -print | grep -q .; then
    bad "a .env file is present in the tree"
else
    ok "no .env file"
fi

exit "$fail"
