# Maria Padilha GRUB theme

This theme is installed into the target root and selected by Calamares
`grubcfg.conf` through `/etc/default/grub`:

```ini
GRUB_THEME="/boot/grub/themes/maria-padilha/theme.txt"
GRUB_BACKGROUND="/boot/grub/themes/maria-padilha/background.png"
```

`background.svg` and `logo.svg` are original vector art for this repository.
The PNG files are rendered from them; `background.png` is 1920x1080 and
`logo.png` is 256x256.  The theme deliberately omits font-file references so
GRUB's built-in unicode font is used.  If gfxterm cannot initialise, GRUB's
console fallback still shows readable entries; bootability does not depend on
the theme.

The palette matches Plymouth and the greeter: `#120807` background, `#1a0d0b`
surface, `#b12e1b` primary red, `#d8a24a` gold and `#f3e6da`/`#fff7ef` cream.
