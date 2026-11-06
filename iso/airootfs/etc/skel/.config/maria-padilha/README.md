# Maria Padilha user configuration

The live ISO copies this skeleton into `/home/maria` on first boot. When the
build runs with `MARIA_PADILHA_DOTFILES` (or finds a sibling
`maria-padilha-dotfiles` checkout), `build.sh` overlays the Hyprland, Neovim,
WezTerm and micro configs here so the reference desktop is available without a
network fetch.

The desktop itself (Quickshell shell, session commands and theme engine) comes
from the `maria-padilha` package.
