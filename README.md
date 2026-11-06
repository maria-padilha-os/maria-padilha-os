# Maria Padilha OS

The bootable Arch-based Maria Padilha image: Hyprland, Quickshell, the
`maria-padilha` package, and the tracked dotfiles.

This repository is the image/installer layer. The desktop itself lives in
[`maria-padilha-de`](https://github.com/maria-padilha-os/maria-padilha-de), and
the tracked configs live in
[`maria-padilha-dotfiles`](https://github.com/maria-padilha-os/maria-padilha-dotfiles).

## Status

**Scaffold.** There is no bootable ISO yet. The archiso profile, Calamares
installer, package selection, branding, hardware enablement, QEMU smoke test,
and release pipeline are queued work. Do not install this on a host.

## Intended stack

- Arch Linux base with a minimal desktop footprint
- Hyprland + Quickshell shell and session
- the `maria-padilha` package from `maria-padilha-de`
- the tracked dotfiles as `/etc/skel` defaults
- offline Calamares install with optional package groups
- signed ISO builds and a QEMU smoke test

## Relationship to the other repositories

| repository | role |
| --- | --- |
| `maria-padilha-de` | shell, session, theme engine, package, docs |
| `maria-padilha-dotfiles` | Hyprland, Neovim, WezTerm, Firefox, MC, micro |
| `maria-padilha-mobile` | touch-first mobile OS (Maria Padilha de Bolso) |
| `maria-padilha-de-castela` | authorized-lab cybersecurity desktop |
| `maria-padilha-de-castela-mobile` | GrapheneOS-based Castela mobile |

## Development

The image build is not wired yet. The first tasks add the archiso profile and
tests under `tests/`. Until then, `tests/all.sh` only checks the scaffold for
basic hygiene.
