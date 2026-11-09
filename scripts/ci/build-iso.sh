#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# CI/host wrapper around build.sh.
#
# build.sh must run as root inside an Arch container because mkarchiso mounts
# loop images and chroots.  This wrapper starts that throw-away container with
# Docker or Podman.  It never installs anything on the host and never publishes
# a release; the resulting ISO, checksum and build metadata stay under out/.
set -Eeuo pipefail

script_name="${0##*/}"
root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

container_image="${ARCH_IMAGE:-archlinux:latest}"
de_dir="${MARIA_PADILHA_DE:-$root/.ci/maria-padilha-de}"
dotfiles_dir="${MARIA_PADILHA_DOTFILES:-$root/.ci/maria-padilha-dotfiles}"
pacman_cache="${MARIA_PADILHA_PACMAN_CACHE:-$root/.ci/cache/pacman}"
max_iso_bytes="${MARIA_PADILHA_MAX_ISO_BYTES:-9663676416}" # 9 GiB
kernel_params="${MARIA_PADILHA_KERNEL_PARAMS:-}"
source_date_epoch="${SOURCE_DATE_EPOCH:-}"

log() { printf '[ci-build] %s\n' "$*" >&2; }
warn() { printf '[ci-build] WARNING: %s\n' "$*" >&2; }
die() { printf '[ci-build] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
usage: $script_name

Build the maria-padilha package and ISO in a privileged Arch container, then
write out/<iso>, out/<iso>.sha256 and out/build-info.txt.

Required environment:
  MARIA_PADILHA_DE          maria-padilha-de checkout (default .ci/maria-padilha-de)

Optional environment:
  MARIA_PADILHA_DOTFILES    dotfiles checkout (default .ci/maria-padilha-dotfiles)
  ARCH_IMAGE                container image (default archlinux:latest)
  CONTAINER_RUNTIME         docker or podman (default: auto-detect)
  MARIA_PADILHA_PACMAN_CACHE
                            host directory mounted at /var/cache/pacman/pkg
                            (default .ci/cache/pacman; safe package cache only)
  MARIA_PADILHA_KERNEL_PARAMS
                            override the live kernel command line, for example
                            the serial-console parameters used by the smoke test
  MARIA_PADILHA_MAX_ISO_BYTES
                            refuse to upload/keep an ISO larger than this
                            (default 9663676416, 9 GiB)
  SOURCE_DATE_EPOCH         timestamp used by the profile label

This script never asks for root privileges on the host.  It does start a
--privileged container because mkarchiso requires mount, loop devices and chroot.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    '')
        ;;
    *)
        die "unknown argument: $1 (try --help)"
        ;;
esac

[[ -f "$de_dir/packaging/PKGBUILD" ]] ||
    die "maria-padilha-de checkout not found at $de_dir (set MARIA_PADILHA_DE or check out packaging/PKGBUILD)"
[[ "$max_iso_bytes" =~ ^[0-9]+$ ]] || die "MARIA_PADILHA_MAX_ISO_BYTES must be an integer"

runtime="${CONTAINER_RUNTIME:-}"
if [[ -z "$runtime" ]]; then
    for candidate in docker podman; do
        if command -v "$candidate" >/dev/null 2>&1; then
            runtime="$candidate"
            break
        fi
    done
fi
[[ -n "$runtime" ]] || die "neither docker nor podman is installed; this wrapper only runs the build in a container"
command -v "$runtime" >/dev/null 2>&1 || die "container runtime not found: $runtime"

if [[ ! -d "$dotfiles_dir" ]]; then
    warn "dotfiles checkout not found at $dotfiles_dir; /etc/skel will use this repository's skeleton only"
fi

# Keep out/ and the cache host-owned so the non-root CI user can write the
# checksum/metadata and the cache action can archive the downloads.
if [[ -e "$root/out" && ! -w "$root/out" ]]; then
    die "$root/out is not writable by $(id -un); remove it or fix its ownership (this script never elevates host privileges)"
fi
mkdir -p "$root/out" "$root/.scratch" "$pacman_cache"

if [[ -z "$source_date_epoch" ]]; then
    source_date_epoch="$(git -C "$root" log -1 --format=%ct 2>/dev/null || date +%s)"
fi

container_name="maria-padilha-iso-$$"
run_args=(
    run
    --rm
    --name "$container_name"
    --privileged
    --workdir /work
    --env "MARIA_PADILHA_DE=/pkg/maria-padilha-de"
    --env "MARIA_PADILHA_DOTFILES=/pkg/maria-padilha-dotfiles"
    --env "SOURCE_DATE_EPOCH=$source_date_epoch"
    --volume "$root:/work"
    --volume "$de_dir:/pkg/maria-padilha-de:ro"
    --volume "$pacman_cache:/var/cache/pacman/pkg"
)
if [[ -d "$dotfiles_dir" ]]; then
    run_args+=(--volume "$dotfiles_dir:/pkg/maria-padilha-dotfiles:ro")
fi
if [[ -n "$kernel_params" ]]; then
    run_args+=(--env "MARIA_PADILHA_KERNEL_PARAMS=$kernel_params")
fi
run_args+=(
    "$container_image"
    bash -lc 'set -Eeuo pipefail; ./scripts/ci/container-build.sh'
)

log "container image: $container_image"
log "package source: $de_dir"
log "pacman cache: $pacman_cache"
log "building package and ISO (this needs a privileged Arch container)"
log "AUR-only runtime dependencies are bootstrapped inside the container"
log "no release will be published; outputs stay in $root/out"

rc=0
"$runtime" "${run_args[@]}" || rc=$?

# The build container runs as root.  Give the outputs back to the invoking
# user so checksum verification, artifact upload and local cleanup work.
if [[ -e "$root/out" ]]; then
    "$runtime" run --rm --user 0 \
        --volume "$root/out:/out" \
        --volume "$root/.scratch:/scratch" \
        "$container_image" \
        chown -R "$(id -u):$(id -g)" /out /scratch >/dev/null 2>&1 ||
        warn "could not restore output ownership; artifact files may be root-owned"
fi

((rc == 0)) || die "the ISO build container exited with status $rc"

shopt -s nullglob
isos=("$root"/out/maria-padilha-*.iso)
((${#isos[@]})) || die "the build finished but no maria-padilha-*.iso was produced in $root/out"
if ((${#isos[@]} > 1)); then
    iso="$(for candidate in "${isos[@]}"; do
        printf '%s\t%s\n' "$(stat -c '%Y' -- "$candidate")" "$candidate"
    done | sort -rn -k1,1 | head -n1 | cut -f2-)"
else
    iso="${isos[0]}"
fi

base="$(basename -- "$iso")"
size="$(stat -c '%s' -- "$iso")"
if ((size > max_iso_bytes)); then
    die "$base is $size bytes, above the configured limit of $max_iso_bytes bytes; use a larger/self-hosted runner or raise MARIA_PADILHA_MAX_ISO_BYTES deliberately"
fi

hash="$(sha256sum -- "$iso" | awk '{print $1}')"
printf '%s  %s\n' "$hash" "$base" >"$root/out/$base.sha256"

de_commit="$(git -C "$de_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
if [[ -d "$dotfiles_dir/.git" ]]; then
    dotfiles_commit="$(git -C "$dotfiles_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
else
    dotfiles_commit="not-mounted"
fi
package_version="$(tr -d '[:space:]' <"$root/iso/package-version")"
iso_size_human="$(du -h -- "$iso" | awk '{print $1}')"

{
    printf 'ISO=%s\n' "$base"
    printf 'ISO_PATH=%s\n' "$iso"
    printf 'ISO_SIZE_BYTES=%s\n' "$size"
    printf 'ISO_SIZE=%s\n' "$iso_size_human"
    printf 'ISO_SHA256=%s\n' "$hash"
    printf 'PACKAGE_VERSION=%s\n' "$package_version"
    printf 'ARCH_IMAGE=%s\n' "$container_image"
    printf 'SOURCE_DATE_EPOCH=%s\n' "$source_date_epoch"
    printf 'KERNEL_PARAMS=%s\n' "${kernel_params:-profile default (quiet splash)}"
    printf 'REPO_COMMIT=%s\n' "$(git -C "$root" rev-parse HEAD 2>/dev/null || printf 'unknown')"
    printf 'DE_COMMIT=%s\n' "$de_commit"
    printf 'DOTFILES_COMMIT=%s\n' "$dotfiles_commit"
} >"$root/out/build-info.txt"

log "ISO: $iso"
log "size: $iso_size_human ($size bytes)"
log "SHA256: $hash"
log "checksum: $root/out/$base.sha256"
