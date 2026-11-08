# Maria Padilha user configuration

This directory is the installed system's `/etc/skel`.  `useradd` copies it into
a new account's home, so the files here must stay root-owned, readable, and
free of machine-local secrets.

The build overlays the tracked `maria-padilha-dotfiles` configs into
`.config/hypr`, `.config/quickshell`, `.config/nvim`, `.config/wezterm`,
`.config/micro` and the three static `.config/mc` files.  The overlay excludes
`hypr/hyprland/env.local.lua`, key material, `.env`, git credentials and every
other file that looks like a credential.  Put machine-local secrets in your
own home after the first login; never add them to `/etc/skel`.

## First login

The Maria Padilha package installs the session entry at
`/usr/share/wayland-sessions/maria-padilha.desktop`, the wallpapers under
`/usr/lib/maria-padilha/share/wallpapers/`, and the `padilha-daylight` command.
The Hyprland configuration starts `padilha-session`, which compiles the shell
settings, runs `padilha-daylight --once` to paint the default wallpaper and
palette, and then starts Quickshell.

File ownership, service enablement and the absence of secrets can be checked
from a chroot or systemd-nspawn with the repository's `tests/first-boot.sh`.
