# QEMU checklist: boot and greeter branding

This is a **manual visual acceptance checklist**.  It has not been run in this
checkout: there is no built ISO here and QEMU is not part of the static test
environment.  Do not mark the branding as tested until each step has a recorded
result.  The automated suite (`tests/branding.sh`) checks paths, PNG sizes,
palette fallback and wiring only; it never boots QEMU and never performs a
graphical login.

Use a disposable image under `out/` (ignored by git).  Never point QEMU at a
host disk or a real partition.

## What the test proves

| layer | expected result |
| --- | --- |
| syslinux (BIOS live) | dark candle splash behind a legible cream/red/gold menu |
| systemd-boot (UEFI live) | text-only menu, Maria Padilha entries, no missing glyphs |
| Plymouth | dark background, candle mark, cream title, red/gold progress |
| greetd + tuigreet | themed red/gold/white prompt, Maria Padilha greeting, readable |
| GRUB (installed) | themed background, Maria Padilha title, red/gold selection |
| missing palette | Plymouth and the greeter still show the checked-in fallback |

## Preconditions

- A built ISO at `out/maria-padilha-*.iso`.  The ISO must have been built after
  the `plymouth` package and `plymouth` mkinitcpio hook were added to the
  profile; `tests/branding.sh` verifies that in the source tree.
- `qemu-system-x86_64` and `qemu-img` on the test host.
- Optional UEFI: OVMF firmware, for example `/usr/share/ovmf/OVMF.fd` on Arch
  (`edk2-ovmf`).
- At least 4 GiB RAM and 20 GiB free in the disposable image.
- For the live checks, no network is needed.  Use `-nic none` so the run also
  exercises the offline path.

## Create the disposable disk

```sh
mkdir -p out/qemu/branding
qemu-img create -f qcow2 out/qemu/branding/disk.qcow2 20G
```

## Boot the live ISO (BIOS + syslinux)

```sh
qemu-system-x86_64 \
  -enable-kvm -m 4096 -smp 2 \
  -drive file=out/qemu/branding/disk.qcow2,if=virtio,format=qcow2 \
  -cdrom out/maria-padilha-*.iso \
  -boot d -nic none \
  -display gtk
```

1. Capture the syslinux menu before the timeout expires.  In the QEMU window
   press `Ctrl-Alt-2` for the monitor and run
   `screendump out/qemu/branding/01-syslinux.ppm`, then `Ctrl-Alt-1` to return.
   Record: the `splash.png` candle image is visible, "Maria Padilha" is the
   title, the menu text is cream on near-black, and the selected entry uses the
   candle-red bar.  There must be no cyan or white-on-white text.
2. Select the live entry and capture the Plymouth splash with
   `screendump out/qemu/branding/02-plymouth.ppm` as soon as it appears.
   Record: candle mark and "MARIA PADILHA / STARTING THE CANDLE" are readable;
   progress is red with a gold highlight; no black-on-black or missing-image
   placeholder.
3. If the splash is too fast to capture, add `plymouth.ignore-serial-consoles`
   to the kernel command line at the syslinux prompt (press `Tab`) and append
   `rd.debug`; do not use `quiet` for the capture boot if the screen is blank.
   Remove these temporary parameters before recording the final result.

## Boot the live ISO (UEFI + systemd-boot)

```sh
qemu-system-x86_64 \
  -enable-kvm -m 4096 -smp 2 -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/OVMF.fd \
  -drive file=out/qemu/branding/disk.qcow2,if=virtio,format=qcow2 \
  -cdrom out/maria-padilha-*.iso \
  -boot d -nic none \
  -display gtk
```

4. Capture the systemd-boot menu.  Record: the Maria Padilha entry is selected,
   the text is legible at the highest console resolution, and the editor is
   disabled.  systemd-boot has no pixmap/theme support; the expected treatment
   is text-only, not a recoloured menu.  Do not file a missing-splash bug for
   this layer; the Plymouth splash is the graphical boot treatment.

## Greeter

5. Let the live session start, then log out.  The live image has an
   `[initial_session]` autologin, so this is the first point the greeter is
   visible.  Capture `03-greeter.ppm`.
   Record: the greeting says "Maria Padilha", the prompt/border uses candle
   red, the title/time uses gold, and regular text is white/cream.  The
   username, password and session controls must all be readable.
6. Type a wrong password once.  Record: the error remains readable against the
   dark container; no text disappears into the background.
7. Select a session with `F3` and the power menu with `F12`.  Record: those
   overlays use the same container/border palette and do not show a default
   blue/white theme.

## Installed GRUB and first boot

8. Run the Calamares install from the live desktop, reboot without the ISO,
   and capture the GRUB menu as `04-grub.ppm`.
   Record: the candle background is visible, the title says "Maria Padilha OS",
   the selected entry is cream on candle red, and the timeout bar is red/gold.
   If the firmware cannot initialise gfxterm, GRUB's console fallback must
   still show readable entries (the theme is optional; bootability is not).
9. Log in with the created user, then log out.  Capture `05-installed-greeter.ppm`.
   Record: the same themed greeter appears, with no live autologin and no live
   account.  Do not treat this checklist as a live-login automation test; it is
   a human visual pass.

## Missing-palette fallback

The greeter and Plymouth must still be readable if
`/etc/maria-padilha/boot-palette.conf` is missing or has no
`MARIA_PADILHA_GREETER_THEME` value.

10. In a disposable installed guest, move the palette file aside and restart
    greetd from a root console:

    ```sh
    sudo mv /etc/maria-padilha/boot-palette.conf /root/boot-palette.conf.saved
    sudo systemctl restart greetd
    ```

    Capture `06-greeter-no-palette.ppm`.  Record: the greeter still shows the
    red/gold/white fallback; it must not fail to start or render black text.
    Restore the file afterwards.

11. For the Plymouth fallback, build one throw-away variant with
    `iso/airootfs/etc/maria-padilha/boot-palette.conf` removed before
    `mkarchiso`.  Boot it and repeat step 2.  The splash uses its baked
    `#120807`, `#1a0d0b`, `#b12e1b`, `#d8a24a`, `#f3e6da` and `#fff7ef`
    constants, so it must look identical.  This is the scenario that matters:
    Plymouth runs from the initramfs before the shell can generate anything.

## Negative checks

- Boot the live ISO with `-nic none`: no branding screen may wait for a network
  palette or a downloaded font/image.
- Remove `splash.png` from a throw-away syslinux tree: the menu colors must
  remain legible even without the background image.
- Do not remove the Plymouth PNGs from a production tree; the theme requires
  `logo.png`, `title.png`, `background.png` and the progress images.  The
  palette fallback is the tested failure mode, not a missing asset bundle.
- Confirm no theme file, SVG or script references an `http(s)://` artwork URL.
  The `xmlns` namespace on an SVG is not an artwork fetch; `tests/branding.sh`
  checks `href` attributes rather than the namespace.
- Confirm `tests/branding.sh` passes without root, greetd, Plymouth installed
  or a graphical session.

## Record the result

Write the date, QEMU command, ISO checksum, BIOS/UEFI mode, screenshot names and
any failures to `out/qemu/branding/result.md`.  `out/` is ignored, so this is a
tester record for the review note, not part of the commit.

Until this checklist has been run, describe the branding as statically verified
and visually unverified.  Do not claim a live graphical login was tested from
the static suite.
