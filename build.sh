#!/usr/bin/env bash
# Build the Maria Padilha package and then the archiso live/installer image.
#
# The package recipe lives in the sibling maria-padilha-de checkout:
#   ../maria-padilha-de/packaging/PKGBUILD
# Override it with --de or MARIA_PADILHA_DE, or point at an already built
# package with --package. The package is always copied into this checkout's
# scratch directory; the source repository is only read.
#
# This script refuses to run outside an Arch container. It also needs root
# inside that container because mkarchiso/pacstrap mount and chroot.
set -Eeuo pipefail

script_name="${0##*/}"
root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
profile_src="$root/iso"
out_dir="$root/out"
work_root="$root/.scratch/iso-build"
de_dir="${MARIA_PADILHA_DE:-$root/../maria-padilha-de}"
dotfiles_dir="${MARIA_PADILHA_DOTFILES:-$root/../maria-padilha-dotfiles}"
build_user="${MARIA_PADILHA_BUILD_USER:-builder}"
pkgbuild_path=""
package_path=""
source_path=""
package_only=0
profile_work=""
result_pkgfile=""

log() { printf '[build] %s\n' "$*" >&2; }
warn() { printf '[build] WARNING: %s\n' "$*" >&2; }
die() { printf '[build] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
usage: $script_name [options]

Build the maria-padilha package from a PKGBUILD, add it to a local repository,
then build the archiso profile in iso/.

Run this as root inside an Arch Linux container. It refuses to run on a
non-Arch host and outside a container.

options:
  --de PATH          maria-padilha-de checkout (default: ../maria-padilha-de)
                     uses PATH/packaging/PKGBUILD
  --pkgbuild PATH    use this PKGBUILD instead of the --de default
  --package PATH     use an already built maria-padilha package; skips makepkg
  --source PATH      source tarball for --pkgbuild (default: found next to it,
                     or exported from the maria-padilha-de git HEAD)
  --package-only     build just the package and stop (no mkarchiso needed)
  --keep-work        keep .scratch/iso-build after a successful build
  -h, --help         show this help

Environment:
  MARIA_PADILHA_DE          same as --de
  MARIA_PADILHA_DOTFILES    dotfiles checkout to overlay on /etc/skel
  MARIA_PADILHA_BUILD_USER  unprivileged makepkg user (default: builder)

Example inside archlinux:latest (with /work and the two sibling checkouts
mounted read-only):
  pacman -Syu --needed --noconfirm archiso base-devel git
  MARIA_PADILHA_DE=/pkg/maria-padilha-de ./build.sh

The ISO is written to out/maria-padilha-<pkgver>-x86_64.iso.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --de)
                (($# >= 2)) || die "--de needs a path"
                de_dir="$2"
                shift 2
                ;;
            --pkgbuild)
                (($# >= 2)) || die "--pkgbuild needs a path"
                pkgbuild_path="$2"
                shift 2
                ;;
            --package)
                (($# >= 2)) || die "--package needs a path"
                package_path="$2"
                shift 2
                ;;
            --source)
                (($# >= 2)) || die "--source needs a path"
                source_path="$2"
                shift 2
                ;;
            --package-only)
                package_only=1
                shift
                ;;
            --keep-work)
                keep_work=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                die "unknown argument: $1 (try --help)"
                ;;
        esac
    done
    (($# == 0)) || die "unexpected argument: $1"
}

require_arch_container() {
    local os_id="" os_like=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
        # shellcheck disable=SC1091
        os_like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    fi

    if [[ "$os_id" != "arch" ]]; then
        die "refusing to build outside an Arch container (detected ID='${os_id:-unknown}', ID_LIKE='${os_like:-unknown}'); use docker/podman with archlinux:latest"
    fi
    [[ -e /etc/arch-release ]] || die "refusing to build: /etc/arch-release is missing; use an Arch container"

    local in_container=0 virt=""
    [[ -e /.dockerenv ]] && in_container=1
    [[ -e /run/.containerenv ]] && in_container=1
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt="$(systemd-detect-virt --container 2>/dev/null || true)"
        if [[ -n "$virt" && "$virt" != "none" ]]; then
            in_container=1
        fi
    fi
    ((in_container == 1)) || die "refusing to build outside an Arch container: no container marker found (/.dockerenv, /run/.containerenv or systemd-detect-virt)"
}

require_root() {
    if ((EUID != 0)); then
        die "run as root inside the Arch container (mkarchiso/pacstrap need mount and chroot): sudo ./$script_name"
    fi
}

check_commands() {
    local -a missing=()
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if ((${#missing[@]})); then
        die "missing prerequisites: ${missing[*]}; inside the Arch container run: pacman -Syu --needed --noconfirm archiso base-devel git"
    fi
}

ensure_builder() {
    [[ "$build_user" != "root" ]] || die "MARIA_PADILHA_BUILD_USER must not be root"
    if ! id -u "$build_user" >/dev/null 2>&1; then
        log "creating unprivileged package builder '$build_user'"
        useradd --create-home --shell /bin/bash "$build_user" ||
            die "cannot create package builder '$build_user'"
    fi
    if [[ ! -d "/home/$build_user" ]]; then
        install -d -m 0755 -o "$build_user" -g "$build_user" "/home/$build_user"
    fi
}

as_builder() {
    local command="$1"
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$build_user" -- env HOME="/home/$build_user" bash -lc "$command"
    else
        su -s /bin/bash "$build_user" -c "$command"
    fi
}

read_field() {
    local file="$1" field="$2" value
    value="$(sed -nE "s/^${field}=([^[:space:]#]+).*/\\1/p" "$file" | head -n1)"
    [[ -n "$value" ]] || die "cannot read ${field} from $file"
    printf '%s' "$value"
}

package_version() {
    local pkgfile="$1" info full
    info="$(pacman -Qp --color never "$pkgfile" 2>/dev/null)" ||
        die "cannot read package metadata from $pkgfile"
    full="${info##* }"
    full="${full#*:}" # drop an epoch if present
    printf '%s\n' "${full%-*}"
}

stage_package() {
    local pkgfile="$1" info name
    [[ -f "$pkgfile" ]] || die "package not found: $pkgfile"
    pkgfile="$(realpath -- "$pkgfile")"
    info="$(pacman -Qp --color never "$pkgfile" 2>/dev/null)" ||
        die "not a readable pacman package: $pkgfile"
    name="${info%% *}"
    [[ "$name" == "maria-padilha" ]] ||
        die "$pkgfile is package '$name', expected 'maria-padilha'"
    printf '%s\n' "$pkgfile"
}

build_package() {
    local pkgbuild="$1" pkgdir pkgver pkgrel tarball srcinfo pkgbase pkgfile
    local -a deps=()
    [[ -f "$pkgbuild" ]] || die "PKGBUILD not found: $pkgbuild"
    pkgbuild="$(realpath -- "$pkgbuild")"
    pkgdir="$(dirname -- "$pkgbuild")"
    pkgver="$(read_field "$pkgbuild" pkgver)"
    pkgrel="$(read_field "$pkgbuild" pkgrel)"

    log "building maria-padilha $pkgver-$pkgrel from $pkgbuild"
    ensure_builder

    local pkgwork="$work_root/package"
    rm -rf "$pkgwork"
    install -d -m 0755 "$pkgwork" "$pkgwork/out" "$pkgwork/build" "$pkgwork/src"
    cp -f "$pkgbuild" "$pkgwork/PKGBUILD"

    tarball="maria-padilha-$pkgver.tar.gz"
    if [[ -n "$source_path" ]]; then
        [[ -f "$source_path" ]] || die "source tarball not found: $source_path"
        cp -f "$source_path" "$pkgwork/$tarball"
    elif [[ -f "$pkgdir/$tarball" ]]; then
        cp -f "$pkgdir/$tarball" "$pkgwork/$tarball"
    elif [[ -d "$de_dir/.git" ]]; then
        log "exporting package source from $de_dir HEAD"
        git -c safe.directory="$de_dir" -C "$de_dir" archive \
            --format=tar.gz --prefix="maria-padilha-$pkgver/" \
            -o "$pkgwork/$tarball" HEAD -- . ':(exclude)packaging' ||
            die "git archive failed in $de_dir"
    else
        die "missing $pkgdir/$tarball; run tools/release.sh --export in maria-padilha-de or pass --source"
    fi

    chown -R "$build_user:$build_user" "$pkgwork"
    srcinfo="$(as_builder "cd $(printf '%q' "$pkgwork") && BUILDDIR=$(printf '%q' "$pkgwork/build") SRCDEST=$(printf '%q' "$pkgwork/src") makepkg --printsrcinfo -p PKGBUILD")" ||
        die "makepkg --printsrcinfo failed"
    pkgbase="$(awk -F' = ' '$1 == "pkgbase" { print $2; exit }' <<<"$srcinfo")"
    [[ "$pkgbase" == "maria-padilha" ]] ||
        die "PKGBUILD is for '$pkgbase', expected maria-padilha"

    mapfile -t deps < <(awk -F' = ' '$1 == "depends" || $1 == "makedepends" { print $2 }' <<<"$srcinfo")
    log "installing build dependencies in the container (not in the ISO root)"
    pacman -S --needed --noconfirm --asdeps base-devel "${deps[@]}" ||
        die "could not install package build dependencies"

    as_builder "cd $(printf '%q' "$pkgwork") && BUILDDIR=$(printf '%q' "$pkgwork/build") SRCDEST=$(printf '%q' "$pkgwork/src") PKGDEST=$(printf '%q' "$pkgwork/out") makepkg -f --nocheck --nodeps" ||
        die "makepkg failed"
    pkgfile="$(find "$pkgwork/out" -maxdepth 1 -type f \
        -name 'maria-padilha-*.pkg.tar.*' ! -name '*.sig' | sort | tail -n1)"
    [[ -n "$pkgfile" ]] || die "makepkg did not produce a maria-padilha package"
    result_pkgfile="$pkgfile"
}

prepare_repo() {
    local pkgfile="$1" repo_dir="$out_dir/repo"
    rm -rf "$repo_dir"
    install -d -m 0755 "$repo_dir"
    cp -f "$pkgfile" "$repo_dir/"
    repo-add "$repo_dir/maria-padilha.db.tar.gz" "$repo_dir/$(basename -- "$pkgfile")" >/dev/null ||
        die "repo-add failed"
    log "local package repository: $repo_dir"
}

overlay_dotfiles() {
    local profile="$1" skel entry
    local dotdir="$dotfiles_dir"
    if [[ -n "${MARIA_PADILHA_DOTFILES:-}" && ! -d "$dotdir" ]]; then
        die "MARIA_PADILHA_DOTFILES is not a directory: $dotdir"
    fi
    if [[ ! -d "$dotdir" ]]; then
        warn "dotfiles checkout not found at $dotdir; /etc/skel keeps only this repository's skeleton"
        return 0
    fi
    log "overlaying dotfiles from $dotdir"
    skel="$profile/airootfs/etc/skel/.config"
    install -d -m 0755 "$skel"
    for entry in hypr nvim wezterm micro; do
        [[ -d "$dotdir/$entry" ]] || continue
        install -d -m 0755 "$skel/$entry"
        tar -C "$dotdir/$entry" \
            --exclude='.git' --exclude='*.bak' --exclude='*.log' \
            --exclude='env.local.lua' --exclude='Session.vim' \
            -cf - . | tar -C "$skel/$entry" -xf -
    done
}

prepare_profile() {
    local pkgver="$1"
    profile_work="$work_root/profile"
    rm -rf "$profile_work"
    cp -a "$profile_src" "$profile_work"
    printf '%s\n' "$pkgver" >"$profile_work/package-version"
    cat >"$profile_work/airootfs/etc/maria-padilha-release" <<EOF
NAME="Maria Padilha OS"
ID=maria-padilha
PRETTY_NAME="Maria Padilha OS"
VERSION="$pkgver"
PACKAGE="maria-padilha"
PACKAGE_VERSION="$pkgver"
EOF
    overlay_dotfiles "$profile_work"
}

build_iso() {
    local pkgver="$1" pacman_conf="$work_root/pacman.conf" repo_url mkwork iso_file
    install -d -m 0755 "$work_root" "$out_dir"
    cp -f "$profile_src/pacman.conf" "$pacman_conf"
    repo_url="$(printf '%s' "$out_dir/repo" | sed 's/ /%20/g')"
    cat >>"$pacman_conf" <<EOF

[maria-padilha]
SigLevel = Optional DatabaseOptional
Server = file://$repo_url
EOF

    mkwork="$work_root/mkarchiso"
    rm -rf "$mkwork"
    install -d -m 0755 "$mkwork"

    log "building ISO with mkarchiso (working directory: $mkwork)"
    MARIA_PADILHA_VERSION="$pkgver" mkarchiso -v \
        -w "$mkwork" \
        -o "$out_dir" \
        -C "$pacman_conf" \
        "$profile_work"

    iso_file="$out_dir/maria-padilha-$pkgver-x86_64.iso"
    [[ -f "$iso_file" ]] || die "mkarchiso finished but $iso_file is missing"
    log "ISO ready: $iso_file"
    du -h "$iso_file" | awk '{ print "[build] size: " $1 }'
}

main() {
    parse_args "$@"
    require_arch_container
    require_root

    if [[ -n "$package_path" && -n "$pkgbuild_path" ]]; then
        die "--package and --pkgbuild are mutually exclusive"
    fi
    if [[ -n "$package_path" && -n "$source_path" ]]; then
        die "--package and --source are mutually exclusive"
    fi

    check_commands pacman makepkg repo-add git bsdtar useradd
    if ! command -v runuser >/dev/null 2>&1 && ! command -v su >/dev/null 2>&1; then
        die "missing prerequisites: runuser or su is required to drop from root for makepkg"
    fi
    if ((package_only == 0)); then
        check_commands mkarchiso pacstrap arch-chroot xorriso mksquashfs mkfs.fat mmd mcopy
    fi

    install -d -m 0755 "$work_root"

    local pkgfile pkgver profile_version
    if [[ -n "$package_path" ]]; then
        pkgfile="$(stage_package "$package_path")"
    else
        build_package "${pkgbuild_path:-$de_dir/packaging/PKGBUILD}"
        pkgfile="$result_pkgfile"
    fi
    pkgver="$(package_version "$pkgfile")"
    profile_version="$(tr -d '[:space:]' <"$profile_src/package-version")"
    if [[ "$pkgver" != "$profile_version" ]]; then
        warn "package is $pkgver but iso/package-version pins $profile_version; the ISO will use $pkgver"
    fi

    if ((package_only == 1)); then
        log "package ready: $pkgfile"
        log "package version: $pkgver"
        exit 0
    fi

    prepare_repo "$pkgfile"
    prepare_profile "$pkgver"
    build_iso "$pkgver"

    if ((keep_work == 0)); then
        rm -rf "$work_root"
    else
        log "keeping working directory: $work_root"
    fi
}

main "$@"
