#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# First-boot verification for an installed Maria Padilha root.
#
# Run it inside the target (chroot or systemd-nspawn):
#   arch-chroot /mnt /root/first-boot-test.sh
#   systemd-nspawn -D /mnt /root/first-boot-test.sh
#
# It can also inspect another root tree without chrooting:
#   tests/first-boot.sh --root /mnt
#
# The profile tree can be checked without root or a built ISO:
#   tests/first-boot.sh --profile
#
# This is a read-only verifier.  It does not enable units, change ownership,
# run a graphical session, or call a privileged command.
set -Eeuo pipefail

script_name="${0##*/}"
repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target_root=""
profile_mode=0
allow_missing_session=0
run_daylight=0
requested_user=""

usage() {
    cat <<EOF
usage: $script_name [--root DIR | --profile] [options]

Check an installed root for first-login readiness: service enablement, skel
ownership, the Maria Padilha session/defaults, and the absence of secrets.

options:
  --root DIR             root to inspect (default: /, or iso/airootfs with --profile)
  --profile              inspect this repository's iso/airootfs statically
  --user NAME            also check the home directory of NAME
  --allow-missing-session
                         do not fail when the wayland-sessions entry is absent
                         (for a checkout that has not installed the package)
  --run-daylight         run 'padilha-daylight --dry-run' when it is present
                         and the inspected root is the running root
  -h, --help             show this help

Exit status is 0 only when every check passes.  Checks that need an installed
package or a graphical session are reported as SKIP instead of failing when the
package is genuinely absent from the inspected tree.
EOF
}

while (($#)); do
    case "$1" in
        --root)
            (($# >= 2)) || { printf 'error: --root needs a path\n' >&2; exit 2; }
            target_root="$2"
            shift 2
            ;;
        --profile)
            profile_mode=1
            shift
            ;;
        --user)
            (($# >= 2)) || { printf 'error: --user needs a name\n' >&2; exit 2; }
            requested_user="$2"
            shift 2
            ;;
        --allow-missing-session)
            allow_missing_session=1
            shift
            ;;
        --run-daylight)
            run_daylight=1
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
            printf 'error: unknown argument: %s (try --help)\n' "$1" >&2
            exit 2
            ;;
    esac
done
(($# == 0)) || { printf 'error: unexpected argument: %s\n' "$1" >&2; exit 2; }

if ((profile_mode)); then
    [[ -z "$target_root" ]] || { printf 'error: --root and --profile are mutually exclusive\n' >&2; exit 2; }
    target_root="$repo_root/iso/airootfs"
elif [[ -z "$target_root" ]]; then
    target_root="/"
fi

[[ -d "$target_root" ]] || { printf 'error: root is not a directory: %s\n' "$target_root" >&2; exit 2; }
target_root="$(realpath -- "$target_root")"
root_prefix="${target_root%/}"

fail=0
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }
skip() { printf 'SKIP %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }

# Absolute path inside the inspected root.  target_root="/" becomes "/etc/...".
r() { printf '%s%s' "$root_prefix" "$1"; }

require_file() {
    local rel="$1" label="${2:-$1}"
    if [[ -s "$(r "$rel")" ]]; then
        ok "$label"
    else
        bad "$label missing or empty at $rel"
    fi
}

require_dir() {
    local rel="$1" label="${2:-$1}"
    if [[ -d "$(r "$rel")" ]]; then
        ok "$label"
    else
        bad "$label missing at $rel"
    fi
}

# Accept an absolute or relative unit link target, but require the basename.
check_enabled_link() {
    local rel="$1"
    local expected="$2"
    local label="${3:-$rel}"
    local path actual
    path="$(r "$rel")"
    if [[ ! -L "$path" ]]; then
        bad "$label is not an enabled symlink"
        return
    fi
    actual="$(readlink -- "$path")"
    if [[ "${actual##*/}" == "$expected" ]]; then
        ok "$label -> $actual"
    else
        bad "$label points at '$actual', expected '$expected'"
    fi
}

# The unit itself is package-owned and may live outside a profile tree.
check_unit_target() {
    local expected="$1" scope="$2" found=0 candidate
    for candidate in \
        "$(r "/usr/lib/systemd/$scope/$expected")" \
        "$(r "/lib/systemd/$scope/$expected")"; do
        [[ -e "$candidate" ]] && found=1
    done
    if ((found)); then
        ok "unit exists: $scope/$expected"
    elif [[ -d "$(r "/usr/lib/systemd/$scope")" || -d "$(r "/lib/systemd/$scope")" ]]; then
        bad "enabled unit $scope/$expected is missing from the tree"
    else
        skip "unit tree $scope/$expected not present in this root (package not installed)"
    fi
}

check_owner() {
    local rel="$1" expected="$2" label="${3:-$1}"
    local path actual
    path="$(r "$rel")"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        bad "$label missing at $rel"
        return
    fi
    actual="$(stat -c '%u:%g' -- "$path")"
    if [[ "$actual" == "$expected" ]]; then
        ok "$label owned by $expected"
    else
        bad "$label owned by $actual, expected $expected"
    fi
}

check_not_writable() {
    local rel="$1" label="${2:-$1}"
    local path
    path="$(r "$rel")"
    [[ -e "$path" ]] || return 0
    if find "$path" -xdev -perm /022 -print -quit 2>/dev/null | grep -q .; then
        bad "$label is group- or world-writable"
        find "$path" -xdev -perm /022 -printf '  %m %p\n' 2>/dev/null || true
    else
        ok "$label is not group- or world-writable"
    fi
}

# ---------------------------------------------------------------------------
# File ownership and skel contents
# ---------------------------------------------------------------------------
printf '\n== ownership and skeleton ==\n'
require_dir /etc/skel
require_file /etc/skel/.bashrc
require_file /etc/skel/.profile
require_file /etc/skel/.bash_logout

if ((profile_mode)); then
    # The checkout is owned by the build user, not root.  What matters here is
    # that no skel entry is writable by another account.
    check_not_writable /etc/skel "/etc/skel"
    for rel in /etc/skel/.bashrc /etc/skel/.profile /etc/skel/.bash_logout; do
        mode="$(stat -c '%a' -- "$(r "$rel")")"
        if [[ "$mode" == "644" || "$mode" == "755" ]]; then
            ok "$rel mode $mode"
        else
            bad "$rel mode $mode, expected 644"
        fi
    done
else
    check_owner /etc/skel 0:0
    check_not_writable /etc/skel
    while IFS= read -r -d '' path; do
        rel="${path#"$root_prefix"}"
        actual="$(stat -c '%u:%g' -- "$path")"
        if [[ "$actual" != "0:0" ]]; then
            bad "$rel owned by $actual, expected 0:0"
        fi
    done < <(find "$(r /etc/skel)" -xdev -print0 2>/dev/null)
    ok "/etc/skel tree ownership checked"

    for rel in /etc/passwd /etc/group; do
        [[ -e "$(r "$rel")" ]] && check_owner "$rel" 0:0
    done
    for rel in /etc/shadow /etc/gshadow; do
        path="$(r "$rel")"
        [[ -e "$path" ]] || continue
        check_owner "$rel" 0:0
        mode="$(stat -c '%a' -- "$path")"
        # Numeric octal: reject any group/other read or write bit.
        if (( (8#$mode & 8#044) == 0 )); then
            ok "$rel mode $mode keeps password hashes private"
        else
            bad "$rel mode $mode is readable by group or other"
        fi
    done
fi

# A user created by Calamares gets a copy of skel.  Check existing human homes
# so a build that ran useradd before the overlay is caught.
check_home() {
    local name="$1" uid="$2" gid="$3" home="$4"
    local path
    path="$(r "$home")"
    if [[ ! -d "$path" ]]; then
        bad "home for $name is missing at $home"
        return
    fi
    actual="$(stat -c '%u:%g' -- "$path")"
    if [[ "$actual" == "$uid:$gid" ]]; then
        ok "$home owned by $uid:$gid"
    else
        bad "$home owned by $actual, expected $uid:$gid"
    fi
    check_not_writable "$home" "$home"
}

if ((profile_mode == 0)) && [[ -e "$(r /etc/passwd)" ]]; then
    while IFS=: read -r name _ uid gid _ home _; do
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        ((uid >= 1000 && uid < 60000)) || continue
        [[ "$home" == /home/* ]] || continue
        if [[ -n "$requested_user" && "$name" != "$requested_user" ]]; then
            continue
        fi
        check_home "$name" "$uid" "$gid" "$home"
    done < "$(r /etc/passwd)"
fi

if [[ -n "$requested_user" ]]; then
    if ! grep -qE "^${requested_user}:" "$(r /etc/passwd)" 2>/dev/null; then
        bad "requested user '$requested_user' is not in /etc/passwd"
    fi
fi

# ---------------------------------------------------------------------------
# Service enablement
# ---------------------------------------------------------------------------
printf '\n== service enablement ==\n'
while IFS= read -r unit; do
    check_enabled_link "/etc/systemd/system/multi-user.target.wants/$unit" "$unit"
    check_unit_target "$unit" system
done <<'EOF'
NetworkManager.service
bluetooth.service
seatd.service
power-profiles-daemon.service
EOF

check_enabled_link /etc/systemd/system/graphical.target.wants/greetd.service greetd.service
check_unit_target greetd.service system
check_enabled_link /etc/systemd/system/display-manager.service greetd.service

while IFS= read -r unit; do
    check_enabled_link "/etc/systemd/user/default.target.wants/$unit" "$unit"
    check_unit_target "$unit" user
done <<'EOF'
pipewire.service
pipewire-pulse.service
wireplumber.service
EOF

while IFS= read -r unit; do
    check_enabled_link "/etc/systemd/user/sockets.target.wants/$unit" "$unit"
    check_unit_target "$unit" user
done <<'EOF'
pipewire.socket
pipewire-pulse.socket
EOF

# ---------------------------------------------------------------------------
# Session entry, wallpaper, palette and padilha-daylight
# ---------------------------------------------------------------------------
printf '\n== Maria Padilha session and defaults ==\n'
if ((profile_mode)); then
    if grep -qF -- '--sessions /usr/share/wayland-sessions' "$(r /etc/greetd/config.toml)" 2>/dev/null; then
        ok "greetd searches /usr/share/wayland-sessions"
    else
        bad "greetd does not search /usr/share/wayland-sessions"
    fi
    if grep -qxF -- 'maria-padilha' "$repo_root/iso/packages.x86_64"; then
        ok "maria-padilha is in the package list"
    else
        bad "maria-padilha is missing from iso/packages.x86_64"
    fi
    skip "session .desktop, wallpaper and palette are installed by the maria-padilha package; build-time check only"
else
    for rel in /etc/sudoers.d/10-maria-live /etc/sysusers.d/maria-live.conf; do
        if [[ -e "$(r "$rel")" ]]; then
            bad "live-only file remains in the installed target: $rel"
        else
            ok "live-only file removed: $rel"
        fi
    done
    greetd_config="$(r /etc/greetd/config.toml)"
    if [[ -s "$greetd_config" ]] && grep -qE '^\[initial_session\]' "$greetd_config"; then
        bad "installed greetd still contains a live [initial_session] autologin"
    else
        ok "installed greetd has no initial_session autologin"
    fi
    if [[ -s "$greetd_config" ]] && grep -qE '^\[default_session\]' "$greetd_config"; then
        ok "installed greetd has a default tuigreet session"
    else
        bad "installed greetd is missing [default_session]"
    fi

    session_file="$(r /usr/share/wayland-sessions/maria-padilha.desktop)"
    if [[ -s "$session_file" ]]; then
        if grep -qF -- 'Name=Maria Padilha' "$session_file" &&
            grep -qE '^Exec=.+' "$session_file" &&
            grep -qF -- 'Type=Application' "$session_file"; then
            ok "Maria Padilha wayland session entry is valid"
        else
            bad "Maria Padilha wayland session entry is incomplete"
        fi
    elif ((allow_missing_session)); then
        skip "Maria Padilha wayland session entry is not installed (allowed)"
    else
        bad "Maria Padilha wayland session entry is missing"
    fi

    if [[ -x "$(r /usr/bin/padilha-daylight)" || -d "$(r /usr/lib/maria-padilha)" ]]; then
        if [[ -x "$(r /usr/bin/padilha-daylight)" ]]; then
            ok "padilha-daylight is executable"
        else
            bad "padilha-daylight is missing from an installed Maria Padilha tree"
        fi
        for wallpaper in day.jpg night.jpg; do
            if [[ -s "$(r "/usr/lib/maria-padilha/share/wallpapers/$wallpaper")" ]]; then
                ok "default wallpaper $wallpaper"
            else
                bad "default wallpaper $wallpaper is missing"
            fi
        done
    else
        skip "Maria Padilha package is not installed in this root"
    fi
fi

# current.lua is the palette the Hyprland config reads.  The tracked dotfiles
# ship both files; a copied skel without current.lua would show an unstyled
# first session.
if [[ -s "$(r /etc/skel/.config/hypr/scheme/default.lua)" ]]; then
    if [[ -s "$(r /etc/skel/.config/hypr/scheme/current.lua)" ]]; then
        ok "skel carries the default palette (scheme/current.lua)"
    else
        bad "skel has scheme/default.lua but no scheme/current.lua"
    fi
fi

if ((run_daylight)) && [[ "$target_root" == "/" ]] && [[ -x /usr/bin/padilha-daylight ]]; then
    daylight_home="$(mktemp -d)"
    if HOME="$daylight_home" XDG_CONFIG_HOME="$daylight_home/.config" \
        XDG_STATE_HOME="$daylight_home/.local/state" \
        /usr/bin/padilha-daylight --dry-run >/dev/null 2>&1; then
        ok "padilha-daylight --dry-run"
    else
        bad "padilha-daylight --dry-run failed"
    fi
    rm -rf -- "$daylight_home"
fi

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------
printf '\n== secrets ==\n'
secret_pattern='(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY-----|https?://[^/[:space:]]+:[^/@[:space:]]+@)'

scan_secrets() {
    local base="$1" label="$2" strict="${3:-0}" hits
    local -a names=(
        -name '.env' -o -name '*.env'
        -o -name 'env.local.lua' -o -name 'env.local.example.lua'
        -o -name '.netrc' -o -name '.git-credentials'
        -o -iname '*credential*' -o -iname '*secret*'
    )
    if ((strict)); then
        names+=(
            -o -name 'id_rsa*' -o -name 'id_ed25519*' -o -name 'id_ecdsa*'
            -o -name '*.pem' -o -name '*.key' -o -name '*.p12'
            -o -name '*.pfx' -o -name '*.kdbx'
        )
    fi
    [[ -d "$base" ]] || return 0
    hits="$(find "$base" -xdev -type f \( "${names[@]}" \) -print 2>/dev/null || true)"
    if [[ -n "$hits" ]]; then
        bad "$label contains credential-looking files"
        printf '%s\n' "$hits" | sed 's/^/  /'
    else
        ok "$label has no credential-looking filenames"
    fi

    if ((strict == 0)); then
        # A user's own key material and project .env files are legitimate.
        # Only the skeleton is required to be free of both.
        ok "$label key content not scanned (user-owned tree)"
        return 0
    fi
    if grep -RInE --exclude-dir=.git -- "$secret_pattern" "$base" >/dev/null 2>&1; then
        bad "$label contains a key-shaped secret"
        grep -RInE --exclude-dir=.git -- "$secret_pattern" "$base" 2>/dev/null | sed 's/^/  /' || true
    else
        ok "$label has no key-shaped secret"
    fi
}

scan_secrets "$(r /etc/skel)" "/etc/skel" 1

if ((profile_mode == 0)) && [[ -e "$(r /etc/passwd)" ]]; then
    while IFS=: read -r name _ uid _ _ home _; do
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        ((uid >= 1000 && uid < 60000)) || continue
        [[ "$home" == /home/* ]] || continue
        if [[ -n "$requested_user" && "$name" != "$requested_user" ]]; then
            continue
        fi
        # A user's own ~/.ssh is legitimate; only look for files that should
        # never have come from skel or an installer.
        scan_secrets "$(r "$home")" "$home" 0
    done < "$(r /etc/passwd)"
fi

if ((fail)); then
    printf '\nFirst-boot verification FAILED\n' >&2
    exit 1
fi
printf '\nFirst-boot verification passed\n'
