# First boot and session defaults

A freshly installed Maria Padilha system should reach a usable Hyprland +
Quickshell session on the first graphical login without a manual setup pass.
This document describes the two halves of that promise:

- the image/installer enables the services and seeds `/etc/skel` (this
  repository);
- the package, dotfiles and session commands paint the wallpaper and palette
  when the user logs in (the sibling repositories).

No full install has been run in this checkout. The static checks below verify
the configuration; they are not a substitute for the QEMU checklist in
[qemu-calamares.md](qemu-calamares.md).

## System services

The live root carries the unit files; symlinks in `iso/airootfs` enable them
for the live image, and the Calamares `services-systemd` module enables the same
units in the installed target.

| unit | target | why |
| --- | --- | --- |
| `NetworkManager.service` | `multi-user.target` | networking and the Quickshell network popout |
| `bluetooth.service` | `multi-user.target` | BlueZ adapter management; no adapter is required for boot |
| `seatd.service` | `multi-user.target` | seat/device access for a non-logind session |
| `power-profiles-daemon.service` | `multi-user.target` | power profiles where the hardware supports them |
| `greetd.service` | `graphical.target` | the Maria Padilha greeter (tuigreet) |
| `display-manager.service` | alias to `greetd.service` | the standard display-manager target |

The repo deliberately uses **greetd + tuigreet**, not SDDM. `iso/packages.x86_64`
therefore carries `seatd`, `power-profiles-daemon`, `greetd` and
`greetd-tuigreet`; `iso/airootfs/etc/calamares/modules/services-systemd.conf`
enables them in the target. The greeter command is
`/usr/local/bin/maria-padilha-greeter`, which applies the Maria Padilha tuigreet
theme from `/etc/maria-padilha/boot-palette.conf` and falls back to the same
red/gold/white spec when that file is missing. `power-profiles-daemon` is
enabled where the package is present and the service is available, but it must
not conflict with another power manager: this image does not install TLP,
auto-cpufreq or similar.

## PipeWire user services

PipeWire is a user-session service stack, not a system service. Global user
enablement lives in the image, so it applies to every account created from
`/etc/skel`:

| unit | enabled through |
| --- | --- |
| `pipewire.service` | `/etc/systemd/user/default.target.wants/` |
| `pipewire-pulse.service` | `/etc/systemd/user/default.target.wants/` |
| `wireplumber.service` | `/etc/systemd/user/default.target.wants/` |
| `pipewire.socket` | `/etc/systemd/user/sockets.target.wants/` |
| `pipewire-pulse.socket` | `/etc/systemd/user/sockets.target.wants/` |

These units start when the user's systemd manager starts at login. They cannot
start during boot or in a chroot: there is no user manager or session bus yet.
PulseAudio is not installed, so `pipewire-pulse` is the compatibility server
for applications that still speak the PulseAudio protocol.

## Installer cleanup before the first user

The target root is unpacked from the live squashfs, so it starts with the
live-only pieces as well as the desktop. Calamares therefore runs
`/usr/local/bin/maria-padilha-calamares-first-boot` in its target chroot before
the `users` module:

- removes the live-only `maria` account, its home and the
  `/etc/sudoers.d/10-maria-live` rule (the live account has no password and may
  use sudo);
- removes `/etc/sysusers.d/maria-live.conf`, so the account is not recreated on
  the next boot;
- rewrites `/etc/greetd/config.toml` without the live `[initial_session]`
  autologin, leaving the themed `maria-padilha-greeter` as the installed
  greeter;
- normalises `/etc/skel` and recreates the global PipeWire user links.

Removing the live account before `users` also frees UID/GID 1000, so the
default `maria` target account can be created cleanly. The shellprocess job is
ordered before `users` and `packages` in
`iso/airootfs/etc/calamares/settings.conf` for exactly that reason.

## `/etc/skel`

`/etc/skel` stays root-owned and free of machine-local state. It contains:

- `.bashrc`, `.profile` and `.bash_logout`: a small interactive Bash setup that
  adds `~/.local/bin` to `PATH`, sets sensible history and editor defaults, and
  does not assume a theme or a network connection;
- `.config/maria-padilha/README.md`: the user-facing note on the session and
  the secret policy;
- when the build runs with `MARIA_PADILHA_DOTFILES` or finds a sibling
  `maria-padilha-dotfiles` checkout: the tracked Hyprland configs under
  `.config/hypr`, Quickshell configs under `.config/quickshell`, and the
  Neovim, WezTerm, micro and Midnight Commander files described by the dotfiles
  README.

The overlay is implemented by `scripts/overlay-dotfiles.sh`, called from
`build.sh`. It copies an allowlist, not the whole checkout:

| source | destination |
| --- | --- |
| `hypr/` | `~/.config/hypr/` |
| `quickshell/` | `~/.config/quickshell/` |
| `nvim/` | `~/.config/nvim/` |
| `wezterm/` | `~/.config/wezterm/` |
| `micro/` | `~/.config/micro/` |
| `mc/{ini,mc.keymap,mc.ext.ini}` | `~/.config/mc/` |

Machine-local files are never copied: `hypr/hyprland/env.local.lua`,
`env.local.example.lua`, `~/.ssh`, `~/.gnupg`, `.env`/`*.env`, `.netrc`,
`.git-credentials`, key material (`*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.kdbx`,
SSH keys), and files whose names look like credentials, secrets, tokens or
cookies. The helper then scans the copied tree for key-shaped values and
rejects the build rather than publishing one. Local Hyprland secrets belong in
the user's own `~/.config/hypr/hyprland/env.local.lua`, created after the first
login; they are not part of any image or skel tree.

The build normalises the copied tree to `root:root`, directories `0755` and
files `0644`, preserving executable bits on helper scripts. `useradd` copies
that root-owned skeleton into the new account and makes the copy user-owned.

Firefox is intentionally not copied into skel: its user.js and `chrome/` files
only make sense after Firefox has created a profile. That is a documented
post-first-launch step in the dotfiles repository, not a boot requirement.

## Session entry, wallpaper and palette

The `maria-padilha` package installs:

- `/usr/share/wayland-sessions/maria-padilha.desktop`, the entry greetd/tuigreet
  lists as **Maria Padilha**;
- the Quickshell tree under `/etc/xdg/quickshell/caelestia`;
- `padilha-session`, `padilha-config`, `padilha-theme`, `padilha-daylight` and
  the other desktop commands under `/usr/bin`;
- the default day and night wallpapers under
  `/usr/lib/maria-padilha/share/wallpapers/`.

`iso/airootfs/etc/greetd/config.toml` points the themed wrapper at
`/usr/share/wayland-sessions`, and the live image enters Hyprland directly with
`initial_session`. The installed system has no autologin; the user chooses the
Maria Padilha entry. The wrapper never requires the session-generated palette:
it uses its built-in fallback before the first login and switches to
`/etc/maria-padilha/boot-palette.conf` when that file exists. See
[boot-branding.md](boot-branding.md) for the palette paths and the manual
[QEMU visual checklist](qemu-branding.md).

On login, the tracked Hyprland config starts `padilha-session`. That command:

1. creates `~/.config/padilha/init.lua` on a fresh home if it is missing;
2. compiles the shell settings;
3. runs `padilha-daylight --once`, which resolves the default day/night
   wallpaper, writes the wallpaper state under `~/.local/state/padilha`,
   generates the palette from the candle-red seed and applies it;
4. starts Quickshell.

The Hyprland `execs.lua` also starts the long-running `padilha-daylight`
daemon, so the wallpaper and palette switch at the configured day/night
boundary. The tracked dotfiles ship both `scheme/default.lua` and
`scheme/current.lua`; the first login needs `current.lua` to exist for the
initial palette, and the first-boot test checks that pair when the Hyprland
config is present.

## What must wait for the first graphical login

These steps cannot be completed during the image build, Calamares install or a
chroot test:

- **PipeWire, WirePlumber and the user systemd manager.** They need the user
  session, a session bus and `$XDG_RUNTIME_DIR`; the global links only take
  effect once the user logs in.
- **Wallpaper and palette generation.** `padilha-daylight` writes under the
  user's `~/.local/state/padilha` and needs a real `$HOME`, a running session
  for `apply`, and ImageMagick (`magick`) to build the thumbnail. The
  `--once` first paint and the daemon both happen after login.
- **The Quickshell process.** `qs -c caelestia` needs a Wayland compositor and
  the user's config. It is started by `padilha-session`, not by a system unit.
- **Keyring, polkit and portals.** `gnome-keyring-daemon`, the polkit
  authentication agent and `xdg-desktop-portal-hyprland` are session processes.
- **Bluetooth adapter state and power profiles.** The services start at boot,
  but the adapter/power hardware is only usable once the user session and
  policy agent are available.
- **Firefox theming.** `user.js` and `chrome/*.css` are applied after Firefox
  creates its first profile, as documented by the dotfiles checkout.

## Verification

From the repository, the profile-only checks run without root:

```sh
bash tests/first-boot.sh --profile
bash tests/skel.sh
bash tests/all.sh
```

Against an installed root (after Calamares, from the build host):

```sh
make first-boot ROOT=/mnt
```

Inside a chroot or systemd-nspawn, copy the read-only verifier into the target
and run it there:

```sh
install -m 0755 tests/first-boot.sh /mnt/root/first-boot-test.sh
arch-chroot /mnt /root/first-boot-test.sh
# or
systemd-nspawn -D /mnt /root/first-boot-test.sh
```

The verifier reports `ok`, `FAIL` or `SKIP` and exits non-zero on any `FAIL`.
It checks:

- `/etc/skel` ownership (`root:root`), file modes and absence of
  credential-looking files or key-shaped values;
- human home directories when `/etc/passwd` has entries with UID 1000 or above;
- system and user service enablement symlinks and, when the unit tree is
  present, the unit targets;
- the Maria Padilha wayland session entry;
- the absence of the live sudoers/sysusers files and the live greetd
  `[initial_session]` block in an installed target;
- `padilha-daylight`, the day/night wallpapers and the Hyprland palette pair;
- `/etc/passwd`, `/etc/group` and the shadow files' ownership/modes.

It does **not** start a graphical session, run `systemctl`, change ownership or
prove that a GPU, Bluetooth adapter or compositor works. Use the QEMU checklist
for that. Pass `--run-daylight` only when inspecting the running system; the
default chroot check does not execute a GUI command.

## Known limits

- The ISO and the installed system have not been built or booted in this
  checkout. The QEMU checklist is still required before calling first boot
  tested.
- The dotfiles repository is optional at build time for development. A release
  image should be built with `MARIA_PADILHA_DOTFILES` (or the sibling checkout
  mounted) so the tracked Hyprland/Quickshell configs are present; without it,
  `/etc/skel` still has the shell setup but not the full desktop config.
- `power-profiles-daemon` is enabled as the single power manager. Do not add a
  conflicting daemon without adjusting the service policy and tests.
