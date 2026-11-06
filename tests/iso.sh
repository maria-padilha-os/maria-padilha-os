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
    iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf \
    iso/efiboot/loader/entries/01-maria-padilha-linux.conf \
    iso/syslinux/syslinux.cfg \
    iso/syslinux/archiso_sys.cfg; do
    require_file "$file"
done

for executable in build.sh tests/all.sh tests/iso.sh iso/profiledef.sh; do
    require_exec "$executable"
done

for script in build.sh tests/all.sh tests/iso.sh iso/profiledef.sh; do
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
    linux-firmware
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

# Greeter choice is greetd + tuigreet and the config must say so.
if grep -qF -- '[initial_session]' iso/airootfs/etc/greetd/config.toml &&
    grep -qF -- 'tuigreet' iso/airootfs/etc/greetd/config.toml &&
    grep -qF -- 'Maria Padilha' iso/airootfs/etc/greetd/config.toml; then
    ok "greetd + tuigreet is the configured greeter"
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

# Secret and credential scan over the working tree (tracked and untracked).
secret_pattern='(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY-----)'
secret_hits="$(mktemp)"
if grep -RInE --exclude-dir=.git --exclude-dir=out --exclude-dir=.scratch -- "$secret_pattern" . >"$secret_hits" 2>/dev/null; then
    bad "possible tracked secret"
    cat "$secret_hits"
else
    ok "no obvious API key or private key"
fi
rm -f "$secret_hits"

if find . -path ./.git -prune -o -path ./out -prune -o -path ./.scratch -prune -o -type f -name '.env' -print | grep -q .; then
    bad "a .env file is present in the tree"
else
    ok "no .env file"
fi

exit "$fail"
