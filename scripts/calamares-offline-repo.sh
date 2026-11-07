#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Stage the ISO-local pacman repository used by the offline Calamares install.
# Run this on the Arch build host before mkarchiso.  It only writes inside this
# checkout: package archives land in
# iso/airootfs/var/cache/calamares/offline-repo and downloads (when enabled)
# go to .scratch/.  It does not install packages or touch the host.
set -Eeuo pipefail

script_name="${0##*/}"
root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/iso/calamares/offline-packages.x86_64"
output="$root/iso/airootfs/var/cache/calamares/offline-repo"
mode="stage"
download=1
declare -a package_dirs=()
declare -a packages=()

log() { printf '[offline-repo] %s\n' "$*" >&2; }
warn() { printf '[offline-repo] WARNING: %s\n' "$*" >&2; }
die() { printf '[offline-repo] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
usage: $script_name [options]

Stage the package archives and pacman database that the ISO's Calamares
installer reads from /var/cache/calamares/offline-repo.

options:
  --check                 validate the manifest and paths, write nothing
  --manifest PATH         package list (default: iso/calamares/offline-packages.x86_64)
  --output PATH           repository directory; must be inside this checkout
  --package-dir PATH      copy *.pkg.tar.* from PATH (may be repeated)
  --no-download           do not call pacman; stage --package-dir archives only
  -h, --help              show this help

Manifest format:
  one package name per line; blank lines and # comments are ignored.
  Prefix a name with @ to name a pacman group (for example @base-devel).
  The archive for every named package must end up in the repository; groups
  are expanded by pacman when --download is used.

Examples:
  $script_name --check
  $script_name --package-dir out/repo
  $script_name --package-dir /path/to/cache --no-download
EOF
}

while (($#)); do
    case "$1" in
        --check)
            mode="check"
            shift
            ;;
        --manifest)
            (($# >= 2)) || die "--manifest needs a path"
            manifest="$2"
            shift 2
            ;;
        --output)
            (($# >= 2)) || die "--output needs a path"
            output="$2"
            shift 2
            ;;
        --package-dir)
            (($# >= 2)) || die "--package-dir needs a path"
            package_dirs+=("$2")
            shift 2
            ;;
        --no-download)
            download=0
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

[[ -f "$manifest" ]] || die "manifest not found: $manifest"

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -n "$line" ]] || continue
    [[ "$line" =~ ^@?[A-Za-z0-9][A-Za-z0-9@._+:-]*$ ]] ||
        die "invalid package name in $manifest: $line"
    packages+=("$line")
done <"$manifest"

((${#packages[@]} > 0)) || die "manifest has no packages: $manifest"

declare -A seen=()
for pkg in "${packages[@]}"; do
    [[ -z "${seen[$pkg]:-}" ]] || die "duplicate package in $manifest: $pkg"
    seen[$pkg]=1
done

for dir in "${package_dirs[@]}"; do
    [[ -d "$dir" ]] || die "package directory not found: $dir"
done

output="$(realpath -m -- "$output")"
[[ "$output" != "$root" ]] || die "--output must not be the repository root"
case "$output/" in
    "$root"/*) ;;
    *) die "--output must be inside $root (got $output)" ;;
esac

if [[ "$mode" == "check" ]]; then
    log "ok: ${#packages[@]} manifest entries, output inside checkout: $output"
    exit 0
fi

command -v repo-add >/dev/null 2>&1 ||
    die "repo-add is missing; run this inside the Arch build container"

install -d -m 0755 "$output"

copy_archives_from() {
    local dir="$1" file
    local -a archives=()
    shopt -s nullglob
    archives=("$dir"/*.pkg.tar.*)
    shopt -u nullglob
    for file in "${archives[@]}"; do
        case "$file" in
            *.sig) continue ;;
        esac
        [[ -f "$file" ]] || continue
        cp -f -- "$file" "$output/"
    done
}

for dir in "${package_dirs[@]}"; do
    log "staging archives from $dir"
    copy_archives_from "$dir"
done

if ((download == 1)); then
    command -v pacman >/dev/null 2>&1 ||
        die "pacman is missing; rerun with --no-download and --package-dir"

    cache="$root/.scratch/calamares-offline-cache"
    rm -rf -- "$cache"
    install -d -m 0755 "$cache"

    for pkg in "${packages[@]}"; do
        name="${pkg#@}"
        if compgen -G "$output/${name}-*.pkg.tar.*" >/dev/null; then
            log "already staged: $name"
            continue
        fi
        log "downloading $name and dependencies (build host only)"
        pacman -Sw --noconfirm --cachedir "$cache" "$name" ||
            die "could not download $name; provide it with --package-dir or fix the build host repositories"
    done

    copy_archives_from "$cache"
fi

shopt -s nullglob
archives=("$output"/*.pkg.tar.*)
shopt -u nullglob
((${#archives[@]} > 0)) ||
    die "no package archives in $output; pass --package-dir or allow downloads"

# repo-add refreshes the database in place.  Remove old metadata first so a
# stale package can never linger in the repository index.
rm -f -- "$output"/maria-padilha-offline.db* \
    "$output"/maria-padilha-offline.files*
repo-add --quiet "$output/maria-padilha-offline.db.tar.gz" "${archives[@]}" ||
    die "repo-add failed"

if command -v pacman >/dev/null 2>&1; then
    declare -A staged=()
    for file in "${archives[@]}"; do
        info="$(pacman -Qp --color never "$file" 2>/dev/null)" || continue
        staged["${info%% *}"]=1
    done
    missing=()
    for pkg in "${packages[@]}"; do
        [[ "$pkg" == @* ]] && continue
        [[ -n "${staged[$pkg]:-}" ]] || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        warn "manifest entries without a staged archive: ${missing[*]}"
        warn "the installer would fail if those packages are selected"
    fi
fi

log "ok: ${#archives[@]} archives, database at $output/maria-padilha-offline.db.tar.gz"
