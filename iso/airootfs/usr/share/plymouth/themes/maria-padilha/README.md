# Maria Padilha boot branding assets

All artwork in this directory is original, simple vector/text work for this
repository.  There is no downloaded wallpaper, icon set, photograph or other
third-party artwork here.  The SVG files are the editable sources; the PNG
files are deterministic renders used by Plymouth, which does not load SVG from
the initramfs.

| file | role | size |
| --- | --- | --- |
| `logo.svg`, `logo.png` | candle mark | 256 x 256 |
| `background.svg`, `background.png` | dark candle-lit background | 1920 x 1080 |
| `title.svg`, `title.png` | Maria Padilha title card | 760 x 160 |
| `progress-bg.svg`, `progress-bg.png` | progress track | 600 x 8 |
| `progress-fill.svg`, `progress-fill.png` | progress fill | 600 x 8 |

The palette is the same candle-red seed used by the desktop and the Calamares
branding: background `#120807`, surface `#1a0d0b`, primary `#b12e1b`, gold
`#d8a24a`, cream `#f3e6da` and bright cream `#fff7ef`.

To re-render after editing an SVG (the maintainer command, not part of the
image build):

```sh
for size in "logo 256 256" "background 1920 1080" "title 760 160" \
            "progress-bg 600 8" "progress-fill 600 8"; do
    set -- $size
    rsvg-convert -w "$2" -h "$3" "$1.svg" -o "$1.png"
done
```

The systemd-boot live menu cannot use these images; it is text-only and uses
the same dark console palette through its normal terminal rendering.  The
syslinux and GRUB assets live under `iso/syslinux/` and
`iso/airootfs/boot/grub/themes/maria-padilha/`.
