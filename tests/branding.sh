#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Static/file-level checks for the Maria Padilha boot and greeter branding.
# This never starts a graphical login, QEMU, Plymouth or greetd.  It checks the
# files that the ISO, initramfs, GRUB and greeter consume, the PNG dimensions,
# the palette fallback and the no-palette path used before the shell has run.
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

theme_dir="iso/airootfs/usr/share/plymouth/themes/maria-padilha"
grub_dir="iso/airootfs/boot/grub/themes/maria-padilha"
greeter="iso/airootfs/usr/local/bin/maria-padilha-greeter"
palette="iso/airootfs/etc/maria-padilha/boot-palette.conf"

# ---------------------------------------------------------------------------
# Paths and required files
# ---------------------------------------------------------------------------
for file in \
    "$palette" \
    "iso/airootfs/etc/plymouth/plymouthd.conf" \
    "$theme_dir/maria-padilha.plymouth" \
    "$theme_dir/maria-padilha.script" \
    "$theme_dir/logo.svg" \
    "$theme_dir/logo.png" \
    "$theme_dir/background.svg" \
    "$theme_dir/background.png" \
    "$theme_dir/title.svg" \
    "$theme_dir/title.png" \
    "$theme_dir/progress-bg.svg" \
    "$theme_dir/progress-bg.png" \
    "$theme_dir/progress-fill.svg" \
    "$theme_dir/progress-fill.png" \
    "$theme_dir/README.md" \
    "$grub_dir/theme.txt" \
    "$grub_dir/background.svg" \
    "$grub_dir/background.png" \
    "$grub_dir/logo.png" \
    "$grub_dir/README.md" \
    "iso/syslinux/splash.svg" \
    "iso/syslinux/splash.png" \
    "iso/efiboot/loader/loader.conf" \
    "iso/efiboot/loader/entries/01-maria-padilha-linux.conf" \
    "iso/syslinux/archiso_head.cfg" \
    "iso/syslinux/archiso_sys-linux.cfg" \
    "$greeter" \
    "docs/qemu-branding.md"; do
    require_file "$file"
done

require_exec "$greeter"

if sh -n "$greeter" 2>/dev/null; then
    ok "$greeter syntax"
else
    bad "$greeter has a shell syntax error"
fi

if grep -qF -- 'qemu-system-x86_64' docs/qemu-branding.md &&
    grep -qF -- 'qemu-img' docs/qemu-branding.md &&
    grep -qi 'not been run\|visually unverified\|not been tested' docs/qemu-branding.md; then
    ok "QEMU visual checklist is present and does not claim a tested boot"
else
    bad "QEMU visual checklist is incomplete or claims a tested boot"
fi

# ---------------------------------------------------------------------------
# Palette file and no-palette fallback
# ---------------------------------------------------------------------------
if python3 - "$palette" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
expected = {
    "MARIA_PADILHA_SEED": "#b12e1b",
    "MARIA_PADILHA_BG": "#120807",
    "MARIA_PADILHA_SURFACE": "#1a0d0b",
    "MARIA_PADILHA_SURFACE_HIGH": "#2a1310",
    "MARIA_PADILHA_PRIMARY": "#b12e1b",
    "MARIA_PADILHA_GOLD": "#d8a24a",
    "MARIA_PADILHA_TEXT": "#f3e6da",
    "MARIA_PADILHA_TEXT_BRIGHT": "#fff7ef",
    "MARIA_PADILHA_MUTED": "#8d7567",
}
values = dict(re.findall(r'^([A-Z0-9_]+)="([^"]*)"$', text, re.MULTILINE))
for key, value in expected.items():
    if values.get(key) != value:
        raise SystemExit(f"{path} {key} is {values.get(key)!r}, expected {value!r}")
theme = values.get("MARIA_PADILHA_GREETER_THEME", "")
for component in ("container", "border", "title", "text", "prompt", "action", "button"):
    if f"{component}=" not in theme:
        raise SystemExit(f"greeter theme is missing {component}=: {theme!r}")
if ";\n" in theme or "\n" in theme:
    raise SystemExit("greeter theme must stay one line")
print("ok palette keys and greeter theme")
PY
then
    ok "fallback palette data"
else
    bad "fallback palette data is invalid"
fi

fallback_theme="$(MARIA_PADILHA_PALETTE=/nonexistent/maria-padilha-palette.conf \
    sh "$greeter" --print-theme 2>/dev/null || true)"
if [[ "$fallback_theme" == 'container=black;border=red;title=yellow;text=white;'* ]]; then
    ok "greeter uses a readable fallback when the palette file is missing"
else
    bad "greeter did not fall back to the compiled-in theme: '${fallback_theme}'"
fi
if [[ "$fallback_theme" != *'container='* || "$fallback_theme" != *'text=white'* ]]; then
    bad "greeter fallback theme is not readable (container/text missing)"
fi

tmp_palette="$(mktemp)"
trap 'rm -f "$tmp_palette"' EXIT
printf '%s\n' 'MARIA_PADILHA_GREETER_THEME="container=blue;border=cyan;text=black"' >"$tmp_palette"
custom_theme="$(MARIA_PADILHA_PALETTE="$tmp_palette" sh "$greeter" --print-theme 2>/dev/null || true)"
if [[ "$custom_theme" == 'container=blue;border=cyan;text=black' ]]; then
    ok "greeter consumes a generated/system palette theme"
else
    bad "greeter ignored the palette file: '${custom_theme}'"
fi

printf '%s\n' 'MARIA_PADILHA_GREETER_THEME="unterminated' >"$tmp_palette"
malformed_theme="$(MARIA_PADILHA_PALETTE="$tmp_palette" sh "$greeter" --print-theme 2>/dev/null || true)"
if [[ "$malformed_theme" == "$fallback_theme" ]]; then
    ok "malformed palette falls back without breaking the greeter"
else
    bad "malformed palette changed the greeter theme: '${malformed_theme}'"
fi

# The wrapper must not invoke privileged tools on its real (non-comment) lines.
if sed 's/#.*//' "$greeter" | grep -Eq '(^|[;&|[:space:]])(sudo|pkexec|systemctl|mount)([[:space:]]|$)'; then
    bad "greeter wrapper invokes a privileged command"
else
    ok "greeter wrapper has no privileged command"
fi

# ---------------------------------------------------------------------------
# Palette consistency with the baked Plymouth fallback
# ---------------------------------------------------------------------------
if python3 - "$palette" "$theme_dir/maria-padilha.script" <<'PY'
import re
import sys
from pathlib import Path

palette = Path(sys.argv[1]).read_text(encoding="utf-8")
script = Path(sys.argv[2]).read_text(encoding="utf-8")
values = dict(re.findall(r'^([A-Z0-9_]+)="([^"]*)"$', palette, re.MULTILINE))
checks = {
    "MARIA_PADILHA_BG": (0.071, 0.031, 0.027),
    "MARIA_PADILHA_SURFACE": (0.102, 0.051, 0.043),
    "MARIA_PADILHA_PRIMARY": (0.694, 0.180, 0.106),
    "MARIA_PADILHA_GOLD": (0.847, 0.635, 0.290),
    "MARIA_PADILHA_TEXT": (0.953, 0.902, 0.855),
    "MARIA_PADILHA_TEXT_BRIGHT": (1.000, 0.969, 0.937),
    "MARIA_PADILHA_MUTED": (0.553, 0.459, 0.404),
}
for key, triple in checks.items():
    if key not in values:
        raise SystemExit(f"palette is missing {key}")
    hex_value = values[key].lower()
    if hex_value not in script.lower():
        raise SystemExit(f"Plymouth script does not document {key} {hex_value}")
    literal = f"({triple[0]:.3f}, {triple[1]:.3f}, {triple[2]:.3f})"
    if literal not in script:
        raise SystemExit(f"Plymouth script is missing fallback literal {literal} for {key}")
for required in (
    "Window.SetBackgroundTopColor",
    "Window.SetBackgroundBottomColor",
    "progress_fill_sprite",
    "Plymouth.SetBootProgressFunction",
    "Plymouth.SetMessageFunction",
    "Plymouth.SetDisplayPasswordFunction",
):
    if required not in script:
        raise SystemExit(f"Plymouth script is missing {required}")
print("ok Plymouth fallback palette and callbacks")
PY
then
    ok "Plymouth fallback colours match the palette"
else
    bad "Plymouth fallback colours do not match the palette"
fi

# ---------------------------------------------------------------------------
# Plymouth theme wiring, initramfs and kernel command line
# ---------------------------------------------------------------------------
if grep -q '^\[Plymouth Theme\]' "$theme_dir/maria-padilha.plymouth" &&
    grep -q '^Name=Maria Padilha$' "$theme_dir/maria-padilha.plymouth" &&
    grep -q '^ModuleName=script$' "$theme_dir/maria-padilha.plymouth" &&
    grep -qF -- "ScriptFile=/usr/share/plymouth/themes/maria-padilha/maria-padilha.script" "$theme_dir/maria-padilha.plymouth"; then
    ok "Plymouth theme descriptor"
else
    bad "Plymouth theme descriptor is incomplete"
fi
if grep -q '^Theme=maria-padilha$' iso/airootfs/etc/plymouth/plymouthd.conf; then
    ok "Plymouth selects the Maria Padilha theme"
else
    bad "Plymouth does not select maria-padilha"
fi
if grep -q '^HOOKS=.*plymouth' iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf; then
    ok "mkinitcpio plymouth hook enabled"
else
    bad "mkinitcpio plymouth hook missing"
fi
if grep -q '^kernel_params=.*splash' iso/profiledef.sh; then
    ok "live kernel command line carries splash"
else
    bad "live kernel command line is missing splash"
fi
for file in \
    iso/efiboot/loader/entries/01-maria-padilha-linux.conf \
    iso/syslinux/archiso_sys-linux.cfg; do
    if grep -qF -- '%KERNEL_PARAMS%' "$file"; then
        ok "$file passes the splash kernel parameter"
    else
        bad "$file does not pass %KERNEL_PARAMS%"
    fi
done
if grep -q '^timeout 5$' iso/efiboot/loader/loader.conf &&
    grep -q '^console-mode max$' iso/efiboot/loader/loader.conf &&
    grep -q '^editor no$' iso/efiboot/loader/loader.conf; then
    ok "systemd-boot menu is legible and locked down"
else
    bad "systemd-boot loader.conf is missing timeout/console-mode/editor settings"
fi

# ---------------------------------------------------------------------------
# Syslinux and GRUB styling
# ---------------------------------------------------------------------------
if grep -qF -- 'MENU BACKGROUND splash.png' iso/syslinux/archiso_head.cfg &&
    grep -qF -- 'MENU COLOR sel' iso/syslinux/archiso_head.cfg &&
    grep -qF -- '#c0f3e6da' iso/syslinux/archiso_head.cfg; then
    ok "syslinux menu uses the splash and candle palette"
else
    bad "syslinux menu styling is incomplete"
fi
if grep -qF -- 'desktop-image: "background.png"' "$grub_dir/theme.txt" &&
    grep -qF -- 'title-color: "#f3e6da"' "$grub_dir/theme.txt" &&
    grep -qF -- 'fg_color = "#b12e1b"' "$grub_dir/theme.txt"; then
    ok "GRUB theme uses the repository background and palette"
else
    bad "GRUB theme styling is incomplete"
fi
if grep -qF -- 'GRUB_THEME: "/boot/grub/themes/maria-padilha/theme.txt"' iso/airootfs/etc/calamares/modules/grubcfg.conf &&
    grep -qF -- 'GRUB_BACKGROUND: "/boot/grub/themes/maria-padilha/background.png"' iso/airootfs/etc/calamares/modules/grubcfg.conf &&
    ! grep -qF -- 'GRUB_TERMINAL_OUTPUT: "console"' iso/airootfs/etc/calamares/modules/grubcfg.conf; then
    ok "installed GRUB points at the Maria Padilha theme"
else
    bad "installed GRUB is not wired to the Maria Padilha theme"
fi
if grep -qF -- 'splash' iso/airootfs/etc/calamares/modules/grubcfg.conf &&
    grep -qF -- 'splash' iso/airootfs/etc/calamares/modules/bootloader.conf; then
    ok "installed GRUB/systemd-boot entries carry splash"
else
    bad "installed boot entries are missing splash"
fi

# ---------------------------------------------------------------------------
# Greeter wiring and package selection
# ---------------------------------------------------------------------------
if grep -qF -- 'maria-padilha-greeter' iso/airootfs/etc/greetd/config.toml &&
    grep -qF -- '--sessions /usr/share/wayland-sessions' iso/airootfs/etc/greetd/config.toml &&
    grep -qF -- 'Maria Padilha' iso/airootfs/etc/greetd/config.toml; then
    ok "greetd runs the themed wrapper with the Maria Padilha session"
else
    bad "greetd is not wired to the themed greeter"
fi
if grep -qF -- 'maria-padilha-greeter' iso/airootfs/usr/local/bin/maria-padilha-calamares-first-boot &&
    grep -qF -- '--sessions /usr/share/wayland-sessions' iso/airootfs/usr/local/bin/maria-padilha-calamares-first-boot; then
    ok "Calamares installs the same themed greeter without autologin"
else
    bad "Calamares first-boot greeter config is stale"
fi
if grep -qx 'plymouth' iso/packages.x86_64; then
    ok "plymouth is in the live package list"
else
    bad "plymouth is missing from iso/packages.x86_64"
fi
if grep -qx 'plymouth' iso/calamares/offline-packages.x86_64; then
    ok "plymouth is staged for the installed target"
else
    bad "plymouth is missing from the offline package manifest"
fi

# ---------------------------------------------------------------------------
# PNG sizes and local-only vector sources
# ---------------------------------------------------------------------------
if python3 - "$root" <<'PY'
import struct
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected = {
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/logo.png": (256, 256),
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/background.png": (1920, 1080),
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/title.png": (760, 160),
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/progress-bg.png": (600, 8),
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/progress-fill.png": (600, 8),
    "iso/syslinux/splash.png": (1024, 768),
    "iso/airootfs/boot/grub/themes/maria-padilha/background.png": (1920, 1080),
    "iso/airootfs/boot/grub/themes/maria-padilha/logo.png": (256, 256),
}
for rel, (want_w, want_h) in expected.items():
    path = root / rel
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{rel} is not a PNG")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (want_w, want_h):
        raise SystemExit(f"{rel} is {width}x{height}, expected {want_w}x{want_h}")
    if len(data) < 200:
        raise SystemExit(f"{rel} is too small to be a real image")
print("ok PNG dimensions and signatures")
PY
then
    ok "branding PNG sizes"
else
    bad "branding PNG sizes are wrong"
fi

if python3 - "$root" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(sys.argv[1])
svgs = [
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/logo.svg",
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/background.svg",
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/title.svg",
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/progress-bg.svg",
    "iso/airootfs/usr/share/plymouth/themes/maria-padilha/progress-fill.svg",
    "iso/airootfs/boot/grub/themes/maria-padilha/background.svg",
    "iso/airootfs/boot/grub/themes/maria-padilha/logo.svg",
    "iso/syslinux/splash.svg",
]
for rel in svgs:
    path = root / rel
    tree = ET.parse(path)
    for element in tree.iter():
        for key, value in element.attrib.items():
            if key.endswith("href") and "://" in value:
                raise SystemExit(f"{rel} has an external reference: {value}")
    text = path.read_text(encoding="utf-8")
    for marker in ("<image", "data:image", "url(http"):
        if marker in text:
            raise SystemExit(f"{rel} embeds external/bitmap artwork: {marker}")
print("ok local-only SVG artwork")
PY
then
    ok "SVG sources are local vector art"
else
    bad "SVG sources reference external artwork"
fi

if ((fail)); then
    printf '\nBranding validation failed\n' >&2
    exit 1
fi
printf '\nBranding validation passed\n'
