#!/usr/bin/env bash
# Static test for scripts/overlay-dotfiles.sh.
#
# The real dotfiles checkout is a separate repository and is not present in
# every build/test environment.  This fixture proves that the allowlist,
# exclusions, permissions and secret scan behave the way build.sh relies on.
set -Eeuo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail=0
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

overlay="$root/scripts/overlay-dotfiles.sh"
[[ -x "$overlay" ]] || { printf 'FAIL %s is not executable\n' "$overlay"; exit 1; }

tmp_base="$root/.scratch"
install -d -m 0755 "$tmp_base"
tmp="$(mktemp -d "$tmp_base/skel-test.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

dot="$tmp/dotfiles"
skel="$tmp/skel"
mkdir -p "$dot"/hypr/hyprland "$dot"/hypr/scheme "$dot"/hypr/utils \
    "$dot"/quickshell "$dot"/nvim "$dot"/wezterm "$dot"/micro "$dot"/mc

cat >"$dot/hypr/hyprland.lua" <<'EOF'
-- fixture main config
EOF
cat >"$dot/hypr/hyprland/env.lua" <<'EOF'
hl.env("FIXTURE", "1")
EOF
cat >"$dot/hypr/hyprland/env.local.lua" <<'EOF'
return { API_KEY = "must-not-be-copied" }
EOF
cat >"$dot/hypr/hyprland/env.local.example.lua" <<'EOF'
return { API_KEY = "" }
EOF
cat >"$dot/hypr/hyprland/credentials.json" <<'EOF'
{"password": "must-not-be-copied"}
EOF
cat >"$dot/hypr/hyprland/secret-notes.lua" <<'EOF'
return {}
EOF
cat >"$dot/hypr/scheme/default.lua" <<'EOF'
return { primary = "b12e1b" }
EOF
cat >"$dot/hypr/scheme/current.lua" <<'EOF'
return { primary = "b12e1b" }
EOF
cat >"$dot/hypr/utils/helper.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$dot/hypr/utils/helper.sh"

cat >"$dot/quickshell/shell.qml" <<'EOF'
// fixture shell config
EOF
cat >"$dot/nvim/init.lua" <<'EOF'
-- fixture nvim config
EOF
cat >"$dot/wezterm/wezterm.lua" <<'EOF'
return {}
EOF
cat >"$dot/micro/settings.json" <<'EOF'
{}
EOF
cat >"$dot/mc/ini" <<'EOF'
[Layout]
EOF
cat >"$dot/mc/mc.keymap" <<'EOF'
[default]
EOF
cat >"$dot/mc/mc.ext.ini" <<'EOF'
[Default]
EOF
cat >"$dot/mc/panels.ini" <<'EOF'
[Panel]
EOF

if "$overlay" --source "$dot" --dest "$skel" >/dev/null 2>&1; then
    ok "overlay runs against a fixture checkout"
else
    bad "overlay failed against a fixture checkout"
fi

for rel in \
    .config/hypr/hyprland.lua \
    .config/hypr/hyprland/env.lua \
    .config/hypr/scheme/default.lua \
    .config/hypr/scheme/current.lua \
    .config/hypr/utils/helper.sh \
    .config/quickshell/shell.qml \
    .config/nvim/init.lua \
    .config/wezterm/wezterm.lua \
    .config/micro/settings.json \
    .config/mc/ini \
    .config/mc/mc.keymap \
    .config/mc/mc.ext.ini; do
    if [[ -f "$skel/$rel" ]]; then
        ok "copied $rel"
    else
        bad "missing $rel"
    fi
done

for rel in \
    .config/hypr/hyprland/env.local.lua \
    .config/hypr/hyprland/env.local.example.lua \
    .config/hypr/hyprland/credentials.json \
    .config/hypr/hyprland/secret-notes.lua \
    .config/mc/panels.ini; do
    if [[ -e "$skel/$rel" ]]; then
        bad "leaked $rel into skel"
    else
        ok "excluded $rel"
    fi
done

if [[ "$(stat -c '%a' "$skel/.config/hypr/utils/helper.sh")" == "755" ]]; then
    ok "executable bit preserved on helper.sh"
else
    bad "helper.sh lost its executable bit"
fi
if [[ "$(stat -c '%a' "$skel/.config/hypr/hyprland.lua")" == "644" ]]; then
    ok "regular config mode is 644"
else
    bad "regular config mode is not 644"
fi
if [[ "$(stat -c '%a' "$skel/.config/hypr")" == "755" ]]; then
    ok "config directory mode is 755"
else
    bad "config directory mode is not 755"
fi

# A key-shaped value must make the helper fail rather than publish the file.
fake_token="ghp_$(printf 'A%.0s' {1..24})"
printf 'token = "%s"\n' "$fake_token" >"$dot/quickshell/leak.qml"
if "$overlay" --source "$dot" --dest "$skel" >/dev/null 2>&1; then
    bad "overlay accepted a key-shaped secret"
else
    ok "overlay rejects a key-shaped secret"
fi

# The build must use the helper, not a second copy of the exclusion rules.
if grep -qF -- 'overlay-dotfiles.sh' build.sh; then
    ok "build.sh uses scripts/overlay-dotfiles.sh"
else
    bad "build.sh does not call the overlay helper"
fi

if ((fail)); then
    printf '\nSkel overlay test FAILED\n' >&2
    exit 1
fi
printf '\nSkel overlay test passed\n'
