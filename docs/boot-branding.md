# Boot and greeter branding

Maria Padilha carries one candle-red palette from the firmware menu through
Plymouth to the greetd login screen.  The desktop theme engine generates its
own wallpaper palette at login, but the boot path runs before that: every layer
therefore has a checked-in fallback derived from the same seed.

The palette is documented in
`iso/airootfs/etc/maria-padilha/boot-palette.conf`:

| role | value |
| --- | --- |
| background | `#120807` |
| surface | `#1a0d0b` |
| raised surface | `#2a1310` |
| primary / candle red | `#b12e1b` |
| gold | `#d8a24a` |
| text cream | `#f3e6da` |
| bright cream | `#fff7ef` |
| muted brown | `#8d7567` |

The seed is the same `#b12e1b` used by `maria-padilha-de`'s daylight defaults
and by the Calamares branding, so the installer, boot splash, menu and greeter
do not drift away from the desktop.

## Layers

| layer | files | behaviour |
| --- | --- | --- |
| Plymouth | `iso/airootfs/usr/share/plymouth/themes/maria-padilha/`, `/etc/plymouth/plymouthd.conf`, `plymouth` hook in `/etc/mkinitcpio.conf.d/archiso.conf` | graphical candle splash, local PNG assets, baked fallback colours |
| systemd-boot (UEFI live) | `iso/efiboot/loader/loader.conf`, entry files | text-only menu; no pixmap support, highest console mode, editor disabled |
| syslinux (BIOS live) | `iso/syslinux/archiso_head.cfg`, `splash.png` | dark candle background plus cream/red/gold menu colours |
| GRUB (installed target) | `iso/airootfs/boot/grub/themes/maria-padilha/`, Calamares `grubcfg.conf` | themed gfxterm menu, with GRUB's console fallback if gfxterm fails |
| greeter (greetd + tuigreet) | `/usr/local/bin/maria-padilha-greeter`, `/etc/greetd/config.toml` | derives a tuigreet `--theme` spec from the palette, with a compiled-in fallback |

Plymouth starts from the initramfs, before `/etc/maria-padilha/boot-palette.conf`
can be used by the theme and long before the user session writes a generated
palette.  Its `.script` therefore contains the final float colours as constants.
`tests/branding.sh` converts the palette file's hex values and checks those
constants, so a palette edit that forgets the splash fails the suite.

The greeter is different: it runs after the root filesystem is mounted and can
read `/etc/maria-padilha/boot-palette.conf`.  `maria-padilha-greeter` extracts
only `MARIA_PADILHA_GREETER_THEME` from that data file (it does not source or
execute it).  If the file is missing, unreadable or malformed, the wrapper uses
the same red/gold/white spec that is compiled into the script.  This is the
normal state on a fresh image and on the pre-shell boot path, so the login
screen is never blank or unstyled.

tuigreet renders on the Linux virtual console and accepts ANSI colour names,
not hex values.  The palette file therefore carries both the six hex colours
(for the graphical layers and documentation) and the derived
`MARIA_PADILHA_GREETER_THEME` string.  A generated system palette can replace
the file; keep the derived spec in the same file when it is written.

## Kernel command line

`iso/profiledef.sh` sets `kernel_params="quiet splash"`; the efiboot and
syslinux entries pass `%KERNEL_PARAMS%`, and Calamares writes `quiet splash`
for the installed GRUB/systemd-boot entries.  Without `splash`, the `plymouth`
hook is loaded but the graphical splash is not selected.

The live ISO uses syslinux on BIOS and systemd-boot on UEFI.  Calamares always
installs GRUB into the target, so the installed system sees the GRUB theme; the
systemd-boot live files are not copied into the target.

## Artwork and licensing

All assets are original vector/text treatments created in this repository:

- `iso/airootfs/usr/share/plymouth/themes/maria-padilha/*.svg` rendered to PNG;
- `iso/syslinux/splash.svg` rendered to `splash.png`;
- `iso/airootfs/boot/grub/themes/maria-padilha/background.svg` and
  `logo.svg` rendered to PNG.

No external wallpaper, icon pack, photograph, downloaded font or remote URL is
referenced.  The SVG source files are checked into the repository, and
`tests/branding.sh` rejects external `href`/embedded bitmap references.  The
theme README records the render commands and file sizes.

## Verification

```sh
bash tests/branding.sh       # paths, PNG sizes, palette/fallback, wiring
bash tests/all.sh            # repository suite
```

`tests/branding.sh` does **not** start Plymouth, greetd, QEMU or a graphical
login.  It runs the greeter wrapper with `--print-theme` against missing,
valid and malformed palette fixtures, then checks the static boot files.

The manual visual pass is [qemu-branding.md](qemu-branding.md).  It has not been
run in this checkout; do not call the branding visually tested until it is.
