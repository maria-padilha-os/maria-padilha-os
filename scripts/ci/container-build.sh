#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Runs inside the privileged Arch container started by build-iso.sh.
#
# The maria-padilha PKGBUILD depends on libcava, which is only in the AUR, and
# this Arch snapshot no longer packages Calamares in the official repositories.
# Build both with makepkg, install libcava for the package build, and expose
# their archives to build.sh as extra ISO-local repository packages. Either AUR
# branch is skipped when the package is available in the official repositories.
set -Eeuo pipefail

root="/work"
build_user="${MARIA_PADILHA_BUILD_USER:-builder}"
aur_dir="/tmp/ci-aur"
extra_repo=""

log() { printf '[ci-container] %s\n' "$*" >&2; }
die() { printf '[ci-container] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$root/build.sh" ]] || die "build.sh not found at $root/build.sh"

log "installing Arch build prerequisites"
pacman -Syu --needed --noconfirm archiso base-devel git curl

ensure_builder() {
    if ! id -u "$build_user" >/dev/null 2>&1; then
        log "creating unprivileged AUR builder '$build_user'"
        useradd --create-home --shell /bin/bash "$build_user"
    fi
    install -d -m 0755 -o "$build_user" -g "$build_user" "/home/$build_user"
}

build_aur_libcava() {
    local archive="$aur_dir/libcava.tar.gz" package
    local -a packages=()

    log "libcava is AUR-only; building it for the package and ISO repositories"
    ensure_builder
    rm -rf "$aur_dir"
    install -d -m 0755 "$aur_dir" "$aur_dir/out"
    chown "$build_user:$build_user" "$aur_dir" "$aur_dir/out"

    curl -fsSL \
        "https://aur.archlinux.org/cgit/aur.git/snapshot/libcava.tar.gz" \
        -o "$archive" ||
        die "could not download the AUR libcava snapshot"

    tar -xzf "$archive" -C "$aur_dir" ||
        die "could not unpack the AUR libcava snapshot"
    [[ -f "$aur_dir/libcava/PKGBUILD" ]] ||
        die "AUR snapshot did not contain libcava/PKGBUILD"

    log "installing libcava build/runtime dependencies"
    pacman -S --needed --noconfirm \
        cmake meson autoconf-archive \
        fftw ncurses alsa-lib iniparser libglvnd sdl2 portaudio sndio \
        libpulse libpipewire ||
        die "could not install libcava build dependencies"

    chown -R "$build_user:$build_user" "$aur_dir"
    runuser -u "$build_user" -- env HOME="/home/$build_user" \
        bash -lc "cd $aur_dir/libcava && PKGDEST=$aur_dir/out makepkg -f --nocheck --nodeps --noconfirm" ||
        die "makepkg failed for AUR libcava"

    mapfile -t packages < <(find "$aur_dir/out" -maxdepth 1 -type f \
        -name 'libcava-*.pkg.tar.*' ! -name '*.sig' | sort)
    ((${#packages[@]} > 0)) || die "makepkg did not produce a libcava package"

    log "installing built libcava so the package build can link against it"
    pacman -U --noconfirm "${packages[@]}" ||
        die "could not install the built libcava package"

    repo-add "$aur_dir/out/ci-aur.db.tar.gz" "${packages[@]}" >/dev/null ||
        die "could not index the local AUR repository"
    # A reused build container may still carry a [ci-aur] block from an earlier
    # run. Replace it instead of appending a duplicate and refreshing for each.
    sed -i '/^\[ci-aur\]$/,/^$/d' /etc/pacman.conf
    printf '\n[ci-aur]\nSigLevel = Optional DatabaseOptional\nServer = file://%s\n' \
        "$aur_dir/out" >>/etc/pacman.conf
    pacman -Sy --noconfirm || die "could not refresh the local AUR repository"

    extra_repo="$aur_dir/out"
    for package in "${packages[@]}"; do
        log "extra ISO repository package: $(basename -- "$package")"
    done
}

# Check only the official repositories. A previous run in a reused container
# leaves [ci-aur] in /etc/pacman.conf, and a plain `pacman -Si libcava` would
# then report the package as available and skip adding it to the ISO repo.
if ! pacman -Sl core extra 2>/dev/null | awk '$1 == "core" || $1 == "extra" { print $2 }' | grep -qx libcava; then
    build_aur_libcava
else
    log "libcava is available in the official repositories; not using the AUR"
fi

install_aur_build_deps() {
    local dir="$1" srcinfo
    local -a deps=()

    srcinfo="$(runuser -u "$build_user" -- env HOME="/home/$build_user" \
        bash -lc "cd $(printf '%q' "$dir") && makepkg --printsrcinfo -p PKGBUILD")" ||
        die "makepkg --printsrcinfo failed in $dir"
    mapfile -t deps < <(awk -F' = ' '{ sub(/^[[:space:]]+/, "", $1) } $1 == "depends" || $1 == "makedepends" { print $2 }' <<<"$srcinfo")
    ((${#deps[@]} > 0)) || die "no build dependencies found in $dir/PKGBUILD"
    log "installing AUR build dependencies: ${deps[*]}"
    pacman -S --needed --noconfirm "${deps[@]}" ||
        die "could not install AUR build dependencies from the official repositories"
}

build_aur_calamares() {
    local archive="$aur_dir/calamares.tar.gz" dir="$aur_dir/calamares" package
    local -a packages=()

    log "calamares is AUR-only; building it for the live ISO repository"
    ensure_builder
    rm -rf "$dir"
    curl -fsSL \
        "https://aur.archlinux.org/cgit/aur.git/snapshot/calamares.tar.gz" \
        -o "$archive" ||
        die "could not download the AUR calamares snapshot"
    tar -xzf "$archive" -C "$aur_dir" ||
        die "could not unpack the AUR calamares snapshot"
    [[ -f "$dir/PKGBUILD" ]] ||
        die "AUR snapshot did not contain calamares/PKGBUILD"

    # The AUR recipe skips packagechooser because not every distribution uses
    # it. Maria Padilha's Calamares settings require the packagechooser module,
    # so keep it in this build.
    sed -i '/^[[:space:]]*packagechooser[[:space:]]*$/d' "$dir/PKGBUILD"

    install_aur_build_deps "$dir"
    chown -R "$build_user:$build_user" "$dir"
    runuser -u "$build_user" -- env HOME="/home/$build_user" \
        bash -lc "cd $(printf '%q' "$dir") && PKGDEST=$(printf '%q' "$aur_dir/out") makepkg -f --nocheck --nodeps --noconfirm" ||
        die "makepkg failed for AUR calamares"

    mapfile -t packages < <(find "$aur_dir/out" -maxdepth 1 -type f \
        -name 'calamares-*.pkg.tar.*' ! -name '*.sig' | sort)
    ((${#packages[@]} > 0)) || die "makepkg did not produce a calamares package"

    repo-add "$aur_dir/out/ci-aur.db.tar.gz" "${packages[@]}" >/dev/null ||
        die "could not index the local AUR repository"
    pacman -Sy --noconfirm || die "could not refresh the local AUR repository"

    extra_repo="$aur_dir/out"
    for package in "${packages[@]}"; do
        log "extra ISO repository package: $(basename -- "$package")"
    done
}

# Calamares is not in the official repositories for this Arch snapshot. Build
# it from the AUR and expose it through the same ISO-local repository so the
# live package list can still install the installer.
if ! pacman -Sl core extra 2>/dev/null | awk '$1 == "core" || $1 == "extra" { print $2 }' | grep -qx calamares; then
    build_aur_calamares
else
    log "calamares is available in the official repositories; not using the AUR"
fi

if [[ -n "$extra_repo" ]]; then
    MARIA_PADILHA_EXTRA_REPO="$extra_repo" "$root/build.sh"
else
    "$root/build.sh"
fi
