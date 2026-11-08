#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Copy the tracked Maria Padilha dotfiles into an /etc/skel tree.
#
# The dotfiles checkout is a separate repository and is only read.  This
# helper is used by build.sh, and can be exercised by the static tests with a
# temporary fixture.  It deliberately copies an allowlist of config
# directories, never the whole checkout, so a stray personal file cannot leak
# into a release image.
#
# Machine-local secrets are excluded:
#   - hypr/hyprland/env.local.lua and env.local.example.lua
#   - .ssh/.gnupg, key material, .env, .netrc, git credentials
#   - files whose names look like credentials, secrets, tokens or cookies
#
# The destination is normalised to root:root (when run as root), directories
# 0755 and files 0644, while keeping the executable bit on scripts.  New users
# therefore get a root-owned, world-readable skeleton that useradd can copy
# into their own home.
set -Eeuo pipefail

script_name="${0##*/}"
source_dir=""
dest_dir=""
owner=""
declare -A seen=()

log() { printf '[overlay] %s\n' "$*" >&2; }
warn() { printf '[overlay] WARNING: %s\n' "$*" >&2; }
die() { printf '[overlay] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
usage: $script_name --source DIR --dest DIR [--owner USER:GROUP]

Copy the tracked Hyprland, Quickshell, Neovim, WezTerm, micro and Midnight
Commander configs from a maria-padilha-dotfiles checkout into an /etc/skel
tree.  Secrets and machine-local files are excluded and verified absent.

options:
  --source DIR          maria-padilha-dotfiles checkout (read-only)
  --dest DIR            destination, normally <profile>/airootfs/etc/skel
  --owner USER:GROUP    owner to apply to the copied tree
  -h, --help            show this help

When --owner is omitted, the tree is chowned to 0:0 only when this script runs
as root.
EOF
}

while (($#)); do
    case "$1" in
        --source)
            (($# >= 2)) || die "--source needs a path"
            source_dir="$2"
            shift 2
            ;;
        --dest)
            (($# >= 2)) || die "--dest needs a path"
            dest_dir="$2"
            shift 2
            ;;
        --owner)
            (($# >= 2)) || die "--owner needs USER:GROUP"
            owner="$2"
            shift 2
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

[[ -n "$source_dir" ]] || die "--source is required"
[[ -n "$dest_dir" ]] || die "--dest is required"
[[ -d "$source_dir" ]] || die "source is not a directory: $source_dir"

source_dir="$(realpath -- "$source_dir")"
dest_dir="$(realpath -m -- "$dest_dir")"
[[ "$source_dir" != "$dest_dir" ]] || die "--source and --dest must differ"
[[ "$dest_dir" != "/" ]] || die "--dest must not be /"

[[ -d "$dest_dir" ]] || install -d -m 0755 "$dest_dir"

# Keep this list and the exclude list in sync with docs/first-boot.md.  The
# old lilith spelling is accepted during the rename, but is not used to copy
# two copies of the same tree.
copy_config_dir() {
    local src_name="$1" dest_name="$2"
    local src="$source_dir/$src_name" dest="$dest_dir/$dest_name"

    if [[ ! -d "$src" ]]; then
        log "no $src_name/ in the dotfiles checkout; leaving the skeleton entry alone"
        return 0
    fi
    if [[ -n "${seen[$dest_name]:-}" ]]; then
        return 0
    fi
    seen["$dest_name"]=1

    log "copying $src_name -> $dest_name"
    rm -rf -- "$dest"
    install -d -m 0755 "$dest"
    tar -C "$src" \
        --exclude='.git' --exclude='.git/*' \
        --exclude='.ssh' --exclude='.ssh/*' \
        --exclude='.gnupg' --exclude='.gnupg/*' \
        --exclude='env.local.lua' \
        --exclude='env.local.example.lua' \
        --exclude='.env' --exclude='*.env' \
        --exclude='.netrc' --exclude='.git-credentials' \
        --exclude='*credential*' --exclude='*credentials*' \
        --exclude='*secret*' --exclude='*secrets*' \
        --exclude='*token*' --exclude='*cookie*' \
        --exclude='*.pem' --exclude='*.key' --exclude='*.p12' \
        --exclude='*.pfx' --exclude='*.kdbx' \
        --exclude='id_rsa*' --exclude='id_ed25519*' --exclude='id_ecdsa*' \
        --exclude='*.bak' --exclude='*.log' \
        --exclude='Session.vim' \
        --exclude='__pycache__' --exclude='.venv' \
        -cf - . | tar -C "$dest" -xf -
}

# Midnight Commander is not linked as a whole directory: its hotlist, panel
# layout and history are per-machine.  Only the three tracked static files are
# copied, matching maria-padilha-dotfiles/README.md.
copy_mc_files() {
    local dest="$dest_dir/.config/mc" name
    local -a files=(ini mc.keymap mc.ext.ini)
    [[ -d "$source_dir/mc" ]] || return 0
    install -d -m 0755 "$dest"
    for name in "${files[@]}"; do
        [[ -f "$source_dir/mc/$name" ]] || continue
        cp -f -- "$source_dir/mc/$name" "$dest/$name"
    done
    log "copying mc/{ini,mc.keymap,mc.ext.ini} -> .config/mc"
}

copy_config_dir hypr .config/hypr
copy_config_dir quickshell .config/quickshell
copy_config_dir nvim .config/nvim
copy_config_dir wezterm .config/wezterm
copy_config_dir micro .config/micro
copy_mc_files

# The Firefox config only applies after the browser has created a profile, so
# it is a documented first-run step rather than something skel can place.
if [[ -d "$source_dir/firefox" ]]; then
    log "firefox/ is documented as a post-first-launch step; not copied into skel"
fi

# Permissions and ownership.  useradd copies /etc/skel into the new home and
# makes it user-owned; the skeleton itself stays root-owned so a compromised
# user cannot change defaults for the next account.
find "$dest_dir" -type d -exec chmod 0755 {} +
find "$dest_dir" -type f -perm /111 -exec chmod 0755 {} +
find "$dest_dir" -type f ! -perm /111 -exec chmod 0644 {} +

if [[ -n "$owner" ]]; then
    chown -R -- "$owner" "$dest_dir"
elif ((EUID == 0)); then
    chown -R -- 0:0 "$dest_dir"
fi

# Defence in depth: even a future change to the allowlist must not publish a
# credential.  Remove named files, then grep text files for key-shaped data.
forbidden=()
while IFS= read -r -d '' path; do
    forbidden+=("$path")
    rm -f -- "$path"
done < <(find "$dest_dir" -type f \( \
    -name '.env' -o -name '*.env' \
    -o -name 'env.local.lua' -o -name 'env.local.example.lua' \
    -o -name '.netrc' -o -name '.git-credentials' \
    -o -iname '*credential*' -o -iname '*secret*' \
    -o -name 'id_rsa*' -o -name 'id_ed25519*' -o -name 'id_ecdsa*' \
    -o -name '*.pem' -o -name '*.key' -o -name '*.p12' \
    -o -name '*.pfx' -o -name '*.kdbx' \
    \) -print0 2>/dev/null)

secret_pattern='(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY-----|https?://[^/[:space:]]+:[^/@[:space:]]+@)'
secret_hits="$(mktemp)"
if grep -RInE --exclude-dir=.git -- "$secret_pattern" "$dest_dir" >"$secret_hits" 2>/dev/null; then
    cat "$secret_hits" >&2
    rm -f -- "$secret_hits"
    die "possible credential copied into $dest_dir"
fi
rm -f -- "$secret_hits"

# A symlink can smuggle a secret past a filename check; reject links whose
# target is a known machine-local name.
while IFS= read -r -d '' link; do
    target="$(readlink -- "$link")"
    case "$target" in
        *env.local*|*.env|*credential*|*secret*|*id_rsa*|*id_ed25519*|*id_ecdsa*|*.pem|*.key|*.kdbx)
            die "refusing symlink to a possible credential: ${link#"$dest_dir"/} -> $target"
            ;;
    esac
done < <(find "$dest_dir" -type l -print0 2>/dev/null)

if ((${#forbidden[@]})); then
    printf '[overlay] ERROR: removed forbidden files from %s:\n' "$dest_dir" >&2
    printf '  %s\n' "${forbidden[@]}" >&2
    exit 1
fi

log "ok: skeleton configs are root-owned defaults with no obvious secrets"
