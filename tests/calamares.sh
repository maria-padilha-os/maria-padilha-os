#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Static validation for the offline Calamares installer layer.
# This does not run Calamares, partition anything, mount anything or need root.
set -euo pipefail

root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail=0
ok() { printf 'ok %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

require_file() {
    if [[ -s "$1" ]]; then
        ok "$1"
    else
        bad "missing or empty: $1"
    fi
}

config_dir="iso/airootfs/etc/calamares"
brand_dir="$config_dir/branding/maria-padilha"
module_dir="$config_dir/modules"

for path in \
    "$config_dir/settings.conf" \
    "$module_dir/welcome.conf" \
    "$module_dir/locale.conf" \
    "$module_dir/keyboard.conf" \
    "$module_dir/partition.conf" \
    "$module_dir/users.conf" \
    "$module_dir/packagechooser.conf" \
    "$module_dir/packages.conf" \
    "$module_dir/bootloader.conf" \
    "$module_dir/unpackfs.conf" \
    "$module_dir/mount.conf" \
    "$module_dir/fstab.conf" \
    "$module_dir/grubcfg.conf" \
    "$module_dir/initcpiocfg.conf" \
    "$module_dir/initcpio.conf" \
    "$module_dir/machineid.conf" \
    "$module_dir/services-systemd.conf" \
    "$module_dir/shellprocess.conf" \
    "$module_dir/umount.conf" \
    "$module_dir/finished.conf" \
    "$brand_dir/branding.desc" \
    "$brand_dir/stylesheet.qss" \
    "$brand_dir/logo.svg" \
    "$brand_dir/welcome.svg" \
    "$brand_dir/show.qml" \
    "iso/airootfs/usr/local/bin/maria-padilha-calamares-offline" \
    "iso/airootfs/var/cache/calamares/offline-repo/README.md" \
    "iso/calamares/live-packages.x86_64" \
    "iso/calamares/offline-packages.x86_64" \
    "scripts/calamares-offline-repo.sh" \
    "docs/calamares.md" \
    "docs/qemu-calamares.md"
do
    require_file "$path"
done

if python3 - "$root" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
config = root / "iso/airootfs/etc/calamares"
brand = config / "branding/maria-padilha"
modules = config / "modules"
manifest_path = root / "iso/calamares/offline-packages.x86_64"
live_manifest_path = root / "iso/calamares/live-packages.x86_64"

try:
    import yaml
except ImportError:
    print("ok PyYAML not installed; YAML semantic checks skipped")
    raise SystemExit(0)


def load(path):
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise AssertionError(f"{path.relative_to(root)} is not a YAML mapping")
    return data


def manifest_names(path):
    names = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            names.append(line.lstrip("@"))
    if len(names) != len(set(names)):
        raise AssertionError(f"{path.relative_to(root)} has duplicate packages")
    return names


settings = load(config / "settings.conf")
if settings.get("branding") != "maria-padilha":
    raise AssertionError("settings.conf does not select the maria-padilha branding")
if settings.get("dont-chroot") is not False:
    raise AssertionError("settings.conf must run as a real installer (dont-chroot: false)")
if settings.get("prompt-install") is not True:
    raise AssertionError("settings.conf should prompt before executing the install")

sequence = []
for phase in settings.get("sequence") or []:
    if not isinstance(phase, dict):
        raise AssertionError("settings.conf sequence entries must be mappings")
    for key, values in phase.items():
        if key not in ("show", "exec"):
            raise AssertionError(f"unknown sequence phase: {key}")
        sequence.extend(values or [])

required_modules = {
    "welcome", "locale", "keyboard", "partition", "users",
    "packagechooser", "packages", "unpackfs", "shellprocess", "bootloader",
}
missing = required_modules - set(sequence)
if missing:
    raise AssertionError(f"settings.conf is missing modules: {sorted(missing)}")
if "netinstall" in sequence:
    raise AssertionError("netinstall is not part of an offline installer")
for before, after in (("shellprocess", "packages"), ("packages", "bootloader")):
    if sequence.index(before) >= sequence.index(after):
        raise AssertionError(f"{before} must run before {after}")

welcome = load(modules / "welcome.conf")
requirements = welcome.get("requirements") or {}
checks = requirements.get("check") or []
required_checks = requirements.get("required") or []
if "internet" in checks or "internet" in required_checks:
    raise AssertionError("welcome.conf still requires internet")
if (welcome.get("geoip") or {}).get("style") not in (None, "none"):
    raise AssertionError("welcome.conf GeoIP must be disabled")

locale = load(modules / "locale.conf")
if not locale.get("region") or not locale.get("zone"):
    raise AssertionError("locale.conf must set an initial region and zone")
if (locale.get("geoip") or {}).get("style") not in (None, "none"):
    raise AssertionError("locale.conf GeoIP must be disabled for an offline install")

keyboard = load(modules / "keyboard.conf")
if keyboard.get("guessLayout") is not True:
    raise AssertionError("keyboard.conf should guess the layout from the locale")
if not isinstance(keyboard.get("configure"), dict):
    raise AssertionError("keyboard.conf is missing the configure mapping")

partition = load(modules / "partition.conf")
if partition.get("defaultFileSystemType") != "ext4":
    raise AssertionError("partition.conf must default to ext4")
if partition.get("availableFileSystemTypes") != ["ext4"]:
    raise AssertionError("partition.conf should offer ext4 only")
if partition.get("enableLuksAutomatedPartitioning") is not False:
    raise AssertionError("LUKS must stay disabled: the image lacks the encrypted-root stack")
if (partition.get("lvm") or {}).get("enable") is not False:
    raise AssertionError("LVM must stay disabled in this image")

users = load(modules / "users.conf")
if users.get("sudoersGroup") != "wheel":
    raise AssertionError("users.conf must give sudo through the wheel group")
if users.get("setRootPassword") is not True:
    raise AssertionError("users.conf should set a root password")
if not (users.get("hostname") or {}).get("location"):
    raise AssertionError("users.conf is missing hostname settings")

packages = load(modules / "packages.conf")
if packages.get("backend") != "pacman":
    raise AssertionError("packages.conf must use the pacman backend")
for key in ("skip_if_no_internet", "update_db", "update_system"):
    if packages.get(key) is not False:
        raise AssertionError(f"packages.conf {key} must be false for offline installs")
if not (packages.get("pacman") or {}).get("needed_only"):
    raise AssertionError("packages.conf should use needed_only")
operations = packages.get("operations") or []
installed = []
for operation in operations:
    installed.extend(operation.get("install") or [])
if not {"grub", "efibootmgr"} <= set(installed):
    raise AssertionError("packages.conf must install grub and efibootmgr from the ISO")

chooser = load(modules / "packagechooser.conf")
if chooser.get("method") != "packages":
    raise AssertionError("packagechooser.conf must hand packages to the packages module")
if not chooser.get("items"):
    raise AssertionError("packagechooser.conf has no items")
chosen = []
for item in chooser["items"]:
    chosen.extend(item.get("packages") or [])
if not chosen:
    raise AssertionError("packagechooser.conf items install no packages")

manifest = manifest_names(manifest_path)
missing_manifest = (set(installed) | set(chosen)) - set(manifest)
if missing_manifest:
    raise AssertionError(
        "offline-packages.x86_64 does not cover: " + ", ".join(sorted(missing_manifest)))
live_manifest = manifest_names(live_manifest_path)
if "calamares" not in live_manifest:
    raise AssertionError("calamares is not in the live package list")

bootloader = load(modules / "bootloader.conf")
if bootloader.get("efiBootLoader") not in ("grub", "systemd-boot"):
    raise AssertionError("bootloader.conf has an unsupported EFI bootloader")
for key in ("grubInstall", "grubMkconfig", "grubCfg", "efiBootMgr"):
    if not bootloader.get(key):
        raise AssertionError(f"bootloader.conf is missing {key}")

branding = load(brand / "branding.desc")
if branding.get("componentName") != "maria-padilha":
    raise AssertionError("branding.desc componentName must match its directory")
images = branding.get("images") or {}
if not images:
    raise AssertionError("branding.desc has no images")
for key, value in images.items():
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", str(value)):
        raise AssertionError(f"branding image {key} is not a repository file: {value}")
    if not (brand / str(value)).is_file():
        raise AssertionError(f"branding image {key} is missing: {value}")

palette = {
    "#120807", "#1a0d0b", "#b12e1b", "#d8a24a", "#f3e6da", "#fff7ef",
}
style = branding.get("style") or {}
if not {"SidebarBackground", "SidebarText"} <= set(style):
    raise AssertionError("branding.desc is missing sidebar colours")
for key, value in style.items():
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(value)):
        raise AssertionError(f"branding colour {key} is not a hex colour: {value}")
    if str(value).lower() not in palette:
        raise AssertionError(f"branding colour {key} is outside the Maria Padilha palette: {value}")

if branding.get("slideshow") != "show.qml":
    raise AssertionError("branding.desc should use the repository slideshow")
if not (brand / "show.qml").is_file():
    raise AssertionError("show.qml is missing")

print("ok YAML configs and branding semantics")
PY
then
    ok "calamares YAML semantics"
else
    bad "calamares YAML semantics"
fi

# The module configs must not contain active network endpoints.  Branding may
# carry the project's repository/support URLs; these checks are about modules.
if grep -RInE 'https?://|ftp://' "$module_dir" --include='*.conf' >/dev/null 2>&1; then
    bad "a Calamares module config contains a network endpoint"
    grep -RInE 'https?://|ftp://' "$module_dir" --include='*.conf' || true
else
    ok "module configs contain no network endpoints"
fi

# The target helper must only wire file:// and must not call privileged tools.
helper="iso/airootfs/usr/local/bin/maria-padilha-calamares-offline"
if grep -q 'file:///var/cache/calamares/offline-repo' "$helper"; then
    ok "target pacman uses the ISO-local file:// repository"
else
    bad "target helper does not point at the ISO-local repository"
fi

if grep -RInE '(^|[;&|[:space:]])(sudo|pkexec|systemctl|mount)([[:space:]]|$)' \
    scripts "$helper" >/dev/null 2>&1
then
    bad "a Calamares script invokes a privileged command"
    grep -RInE '(^|[;&|[:space:]])(sudo|pkexec|systemctl|mount)([[:space:]]|$)' \
        scripts "$helper" || true
else
    ok "Calamares scripts contain no privileged command"
fi

if grep -RInE 'https?://|ftp://' scripts "$helper" >/dev/null 2>&1; then
    bad "a Calamares script references a network endpoint"
else
    ok "Calamares scripts contain no network endpoint"
fi

for svg in "$brand_dir/logo.svg" "$brand_dir/welcome.svg"; do
    if python3 - "$svg" <<'PY'
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.argv[1])
for element in tree.iter():
    for key, value in element.attrib.items():
        if key.endswith("href") and "://" in value:
            raise SystemExit(f"external reference in {sys.argv[1]}: {value}")
PY
    then
        ok "valid local SVG: $svg"
    else
        bad "invalid or remote SVG: $svg"
    fi
done

if grep -q 'logo.svg' "$brand_dir/show.qml" &&
    ! grep -qE 'https?://|ftp://' "$brand_dir/show.qml"
then
    ok "slideshow uses local branding only"
else
    bad "slideshow references a remote asset or is missing logo.svg"
fi

if bash -n scripts/calamares-offline-repo.sh; then
    ok "bash syntax: scripts/calamares-offline-repo.sh"
else
    bad "bash syntax: scripts/calamares-offline-repo.sh"
fi
if sh -n "$helper"; then
    ok "POSIX sh syntax: $helper"
else
    bad "POSIX sh syntax: $helper"
fi

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x scripts/calamares-offline-repo.sh; then
        ok "shellcheck: scripts/calamares-offline-repo.sh"
    else
        bad "shellcheck: scripts/calamares-offline-repo.sh"
    fi
    if shellcheck -s sh "$helper"; then
        ok "shellcheck: $helper"
    else
        bad "shellcheck: $helper"
    fi
else
    ok "shellcheck not installed; skipped"
fi

if bash scripts/calamares-offline-repo.sh --check >/dev/null; then
    ok "offline repository manifest check"
else
    bad "offline repository manifest check"
fi

for doc in docs/calamares.md docs/qemu-calamares.md; do
    if grep -qi 'qemu' "$doc"; then
        ok "QEMU checklist referenced from $doc"
    else
        bad "QEMU checklist missing from $doc"
    fi
done

if grep -q 'qemu-system-x86_64' docs/qemu-calamares.md &&
    grep -q 'qemu-img' docs/qemu-calamares.md
then
    ok "QEMU commands documented in docs/qemu-calamares.md"
else
    bad "QEMU commands missing from docs/qemu-calamares.md"
fi

if grep -qi 'not been executed\|not been tested\|no full install has been run' docs/qemu-calamares.md; then
    ok "QEMU checklist states that no full install was tested"
else
    bad "QEMU checklist must not claim a tested install"
fi

if ((fail)); then
    printf '\nCalamares validation failed\n' >&2
    exit 1
fi
printf '\nCalamares validation passed\n'
