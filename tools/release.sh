#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Stage a Maria Padilha OS ISO release locally.
#
# This script builds the ISO through scripts/ci/build-iso.sh (a throw-away
# privileged Arch container started with Docker or Podman), copies it into a
# release directory, writes SHA256SUMS and optionally signs the checksum file
# with a maintainer GPG key.
#
# It never runs sudo/pkexec on the host, never tags, uploads, publishes a
# GitHub release or deploys Pages. Publication is a separate, explicit human
# action documented in docs/release-checklist.md.
set -Eeuo pipefail

script_name="${0##*/}"
root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version_file="$root/iso/package-version"
build_script="$root/scripts/ci/build-iso.sh"
release_template="$root/.github/RELEASE_TEMPLATE.md"

version=""
version_explicit=0
out_arg=""
iso_arg=""
from_out=0
build_requested=0
sign_key="${MARIA_PADILHA_GPG_KEY:-}"
sign_explicit=0
no_sign=0
force=0
allow_version_mismatch=0
stage_dir=""

log() { printf '[release] %s\n' "$*" >&2; }
warn() { printf '[release] WARNING: %s\n' "$*" >&2; }
die() { printf '[release] ERROR: %s\n' "$*" >&2; exit 1; }
usage_error() {
    printf '[release] ERROR: %s\n' "$*" >&2
    printf 'try %s --help\n' "$script_name" >&2
    exit 2
}

usage() {
    cat <<EOF
usage: $script_name [options]

Build or stage the Maria Padilha OS ISO, write SHA256SUMS, and optionally sign
the checksum file with a maintainer GPG key. Nothing is uploaded, tagged or
published; follow docs/release-checklist.md for the manual release gate.

options:
  --iso PATH                 stage an already built ISO instead of building
  --from-out, --no-build     stage the newest out/maria-padilha-*.iso
  --build                    build first (default when --iso/--from-out is absent)
  --out DIR                  release output directory
                             (default: out/release/<version>)
  --version VERSION          release version (default: iso/package-version)
  --sign-key KEYID           sign SHA256SUMS with this GPG secret key
                             (also: MARIA_PADILHA_GPG_KEY)
  --sign                     sign with MARIA_PADILHA_GPG_KEY
  --no-sign                  never sign, even if MARIA_PADILHA_GPG_KEY is set
  --force                    replace release files in a non-empty --out
  --allow-version-mismatch   allow --version to differ from iso/package-version
  -h, --help                 show this help

environment:
  MARIA_PADILHA_GPG_KEY      default maintainer GPG key for signing
  MARIA_PADILHA_DE           passed through to scripts/ci/build-iso.sh
  MARIA_PADILHA_DOTFILES     passed through to scripts/ci/build-iso.sh
  ARCH_IMAGE                 container image for the build (default archlinux:latest)
  CONTAINER_RUNTIME          docker or podman (default: auto-detect)

Examples:
  # build, checksum and sign a release
  MARIA_PADILHA_GPG_KEY=0123456789ABCDEF tools/release.sh --version 0.2.0

  # checksum a prebuilt ISO without signing
  tools/release.sh --iso /path/to/maria-padilha-0.2.0-x86_64.iso \\
      --out out/release/0.2.0 --no-sign

The output directory contains the ISO, SHA256SUMS, an optional
SHA256SUMS.asc signature, build-info.txt (when available) and a draft
release-notes.md rendered from .github/RELEASE_TEMPLATE.md. Keep previous
version directories: they are the rollback material.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --iso)
                (($# >= 2)) || usage_error "--iso needs a path"
                iso_arg="$2"
                shift 2
                ;;
            --from-out|--no-build)
                from_out=1
                shift
                ;;
            --build)
                build_requested=1
                shift
                ;;
            --out)
                (($# >= 2)) || usage_error "--out needs a directory"
                out_arg="$2"
                shift 2
                ;;
            --version)
                (($# >= 2)) || usage_error "--version needs a version"
                version="$2"
                version_explicit=1
                shift 2
                ;;
            --sign-key)
                (($# >= 2)) || usage_error "--sign-key needs a key id"
                sign_key="$2"
                sign_explicit=1
                shift 2
                ;;
            --sign)
                sign_explicit=1
                shift
                ;;
            --no-sign)
                no_sign=1
                shift
                ;;
            --force)
                force=1
                shift
                ;;
            --allow-version-mismatch)
                allow_version_mismatch=1
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
            -*)
                usage_error "unknown argument: $1"
                ;;
            *)
                usage_error "unexpected argument: $1"
                ;;
        esac
    done
    (($# == 0)) || usage_error "unexpected argument: $1"

    if [[ -n "$iso_arg" && "$from_out" -eq 1 ]]; then
        usage_error "--iso and --from-out are mutually exclusive"
    fi
    if ((build_requested)) && [[ -n "$iso_arg" || "$from_out" -eq 1 ]]; then
        usage_error "--build cannot be combined with --iso or --from-out"
    fi
    if ((no_sign)) && ((sign_explicit)); then
        usage_error "--sign/--sign-key cannot be combined with --no-sign"
    fi
    if ((no_sign)); then
        sign_key=""
    fi
    if [[ -n "$sign_key" ]] && [[ "$sign_key" == -* ]]; then
        usage_error "invalid GPG key id: $sign_key"
    fi
    if ((sign_explicit)) && [[ -z "$sign_key" ]]; then
        usage_error "--sign needs MARIA_PADILHA_GPG_KEY or --sign-key"
    fi
}

validate_version() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9][A-Za-z0-9._+-]*)?$ ]] ||
        usage_error "invalid version '$value' (expected something like 0.2.0)"
}

resolve_version() {
    local pin
    [[ -r "$version_file" ]] || die "version pin not found: $version_file"
    pin="$(tr -d '[:space:]' <"$version_file")"
    [[ -n "$pin" ]] || die "version pin is empty: $version_file"
    validate_version "$pin"

    if ((version_explicit)); then
        validate_version "$version"
        if [[ "$version" != "$pin" ]] && ((allow_version_mismatch == 0)); then
            usage_error "release version '$version' does not match iso/package-version '$pin'; bump the pin or pass --allow-version-mismatch"
        fi
    else
        version="$pin"
    fi
}

preflight_signing() {
    [[ -n "$sign_key" ]] || return 0
    command -v gpg >/dev/null 2>&1 ||
        die "gpg is required to sign but was not found; install gnupg or pass --no-sign"
    if ! gpg --batch --list-secret-keys "$sign_key" >/dev/null 2>&1; then
        die "no GPG secret key matches '$sign_key'; import the maintainer key, fix --sign-key or pass --no-sign"
    fi
}

newest_out_iso() {
    local candidate newest=""
    shopt -s nullglob
    for candidate in "$root"/out/maria-padilha-*.iso; do
        [[ -f "$candidate" ]] || continue
        if [[ -z "$newest" || "$candidate" -nt "$newest" ]]; then
            newest="$candidate"
        fi
    done
    shopt -u nullglob
    printf '%s\n' "$newest"
}

built_iso_from_metadata() {
    local metadata="$root/out/build-info.txt" name
    [[ -f "$metadata" ]] || return 0
    name="$(sed -nE 's/^ISO=//p' "$metadata" | head -n1)"
    if [[ -n "$name" && -f "$root/out/$name" ]]; then
        printf '%s\n' "$root/out/$name"
    fi
}

stage_iso() {
    local source="$1" target="$2"
    [[ -f "$source" ]] || die "ISO not found: $source"
    cp -f -- "$source" "$target" || die "could not copy ISO to $target"
}

write_checksums() {
    local dir="$1" basename="$2" tmp
    tmp="$(mktemp "$dir/.SHA256SUMS.XXXXXX")" || die "could not create a temporary checksum file"
    if ! (cd "$dir" && LC_ALL=C sha256sum -- "$basename" >"$tmp"); then
        rm -f -- "$tmp"
        die "could not generate SHA256SUMS"
    fi
    chmod 0644 "$tmp"
    mv -f -- "$tmp" "$dir/SHA256SUMS"
    if ! (cd "$dir" && sha256sum --check --strict SHA256SUMS >/dev/null); then
        die "generated SHA256SUMS does not verify"
    fi
    log "SHA256SUMS written and verified"
}

sign_checksums() {
    local dir="$1" key="$2" fingerprint=""
    fingerprint="$(gpg --batch --with-colons --list-secret-keys "$key" 2>/dev/null |
        awk -F: '$1 == "fpr" { print $10; exit }')" || true
    log "signing SHA256SUMS with GPG key ${fingerprint:-$key}"
    gpg --batch --yes --armor --detach-sign --local-user "$key" \
        --output "$dir/SHA256SUMS.asc" "$dir/SHA256SUMS" ||
        die "gpg could not sign SHA256SUMS"
    gpg --batch --verify "$dir/SHA256SUMS.asc" "$dir/SHA256SUMS" >/dev/null 2>&1 ||
        die "the new SHA256SUMS.asc signature does not verify"
    log "SHA256SUMS.asc written and verified"
}

render_release_notes() {
    local dir="$1" iso_basename="$2" hash="$3" signature_note="$4" release_date
    [[ -f "$release_template" ]] || {
        warn "release template not found at $release_template; skipping release-notes.md"
        return 0
    }
    release_date="$(date -u +%Y-%m-%d)"
    sed \
        -e "s|{{VERSION}}|$version|g" \
        -e "s|{{DATE}}|$release_date|g" \
        -e "s|{{ISO}}|$iso_basename|g" \
        -e "s|{{SHA256}}|$hash|g" \
        -e "s|{{SIGNATURE}}|$signature_note|g" \
        "$release_template" >"$dir/release-notes.md" ||
        die "could not render release-notes.md"
    chmod 0644 "$dir/release-notes.md"
}

copy_matching_build_info() {
    local dir="$1" iso_basename="$2" metadata="$root/out/build-info.txt" name
    [[ -f "$metadata" ]] || return 0
    name="$(sed -nE 's/^ISO=//p' "$metadata" | head -n1)"
    [[ "$name" == "$iso_basename" ]] || return 0
    cp -f -- "$metadata" "$dir/build-info.txt"
}

cleanup() {
    if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
        rm -rf -- "$stage_dir" || true
    fi
}
trap cleanup EXIT

main() {
    parse_args "$@"
    resolve_version
    preflight_signing

    if [[ -z "$out_arg" ]]; then
        out_arg="$root/out/release/$version"
    fi
    local out_dir parent
    out_dir="$(realpath -m -- "$out_arg")" ||
        die "cannot resolve output directory: $out_arg"
    if [[ "$out_dir" == "/" || "$out_dir" == "$root" || "$out_dir" == "$root/.git" ]]; then
        die "refusing to use '$out_dir' as the release output directory"
    fi
    parent="$(dirname -- "$out_dir")"
    mkdir -p -- "$parent" "$out_dir" || die "could not create release directory: $out_dir"

    if [[ -n "$(find "$out_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        if ((force == 0)); then
            die "release directory is not empty: $out_dir (pass --force to replace release files, or use a versioned --out)"
        fi
        if [[ -n "$(find "$out_dir" -mindepth 1 -maxdepth 1 \
            ! -name '*.iso' \
            ! -name 'SHA256SUMS' \
            ! -name 'SHA256SUMS.asc' \
            ! -name 'build-info.txt' \
            ! -name 'release-notes.md' \
            -print -quit)" ]]; then
            die "release directory contains files that are not release artifacts: $out_dir"
        fi
    fi

    local iso_source="" selection=""
    if [[ -n "$iso_arg" ]]; then
        iso_source="$(realpath -- "$iso_arg" 2>/dev/null || true)"
        [[ -n "$iso_source" ]] || die "ISO not found: $iso_arg"
        selection="prebuilt ISO"
    elif ((from_out)); then
        iso_source="$(newest_out_iso)"
        [[ -n "$iso_source" ]] || die "no out/maria-padilha-*.iso found; run scripts/ci/build-iso.sh first"
        selection="newest out/ ISO"
    else
        [[ -x "$build_script" ]] || die "build wrapper not found or not executable: $build_script"
        log "building the ISO through scripts/ci/build-iso.sh (Docker/Podman; no host sudo)"
        bash "$build_script" || die "ISO build failed; nothing was staged"
        iso_source="$(built_iso_from_metadata)"
        if [[ -z "$iso_source" ]]; then
            iso_source="$(newest_out_iso)"
        fi
        [[ -n "$iso_source" ]] || die "the build finished but no maria-padilha-*.iso was found under out/"
        selection="freshly built ISO"
    fi

    iso_source="$(realpath -- "$iso_source")" || die "cannot resolve ISO path: $iso_source"
    [[ -f "$iso_source" ]] || die "ISO not found: $iso_source"
    local iso_basename
    iso_basename="$(basename -- "$iso_source")"
    [[ "$iso_basename" == *.iso ]] || die "not an .iso file: $iso_source"

    local expected_name="maria-padilha-$version-x86_64.iso"
    if [[ "$iso_basename" != "$expected_name" ]]; then
        warn "ISO name '$iso_basename' does not match the expected release name '$expected_name'"
    fi

    # Stage into a sibling directory and move the finished set into place only
    # after checksums (and an optional signature) verify. This also means a
    # failed signing run cannot leave a half-written release behind.
    stage_dir="$(mktemp -d "$parent/.release-stage.XXXXXX")" ||
        die "could not create a staging directory under $parent"
    stage_iso "$iso_source" "$stage_dir/$iso_basename"

    write_checksums "$stage_dir" "$iso_basename"
    local hash signature_note="Not signed (no maintainer key configured)."
    hash="$(awk 'NR == 1 { print $1 }' "$stage_dir/SHA256SUMS")"

    if [[ -n "$sign_key" ]]; then
        sign_checksums "$stage_dir" "$sign_key"
        signature_note="Signed: \`SHA256SUMS.asc\` (maintainer GPG key \`$sign_key\`)."
    fi

    copy_matching_build_info "$stage_dir" "$iso_basename"
    render_release_notes "$stage_dir" "$iso_basename" "$hash" "$signature_note"

    # Only replace the old release after the complete new set has been built,
    # checksummed and (when configured) signed. A failed signing run therefore
    # leaves the previous release directory untouched.
    if [[ -n "$(find "$out_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        rm -f -- "$out_dir"/*.iso "$out_dir/SHA256SUMS" "$out_dir/SHA256SUMS.asc" \
            "$out_dir/build-info.txt" "$out_dir/release-notes.md"
        log "replacing previous release files in $out_dir (--force)"
    fi

    shopt -s nullglob
    local staged
    for staged in "$stage_dir"/*; do
        mv -f -- "$staged" "$out_dir/"
    done
    shopt -u nullglob
    rmdir -- "$stage_dir" || true
    stage_dir=""

    log "$selection staged under $out_dir"
    log "ISO: $iso_basename"
    log "SHA256: $hash"
    if [[ -n "$sign_key" ]]; then
        log "signature: $out_dir/SHA256SUMS.asc"
    else
        log "signature: none (set MARIA_PADILHA_GPG_KEY or pass --sign-key)"
    fi
    log "NOT published. Review release-notes.md, verify the checksums and follow docs/release-checklist.md."
}

main "$@"
