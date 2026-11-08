# QEMU checklist: manual Calamares install

This is a manual acceptance checklist.  No full install has been run in this
checkout.  There is no built ISO yet and the development environment does not
have QEMU, so no full install has been tested.  Do not mark the installer as
tested until every step below has a recorded result.

Use only a disposable disk image under `out/` (ignored by git).  Never point
QEMU at a host disk or a real partition.

## Preconditions

- A built ISO at `out/maria-padilha-*.iso` with the Calamares layer included.
- `qemu-system-x86_64` and `qemu-img` on the test host.
- Optional for UEFI: OVMF firmware, for example
  `/usr/share/ovmf/OVMF.fd` on Arch (`edk2-ovmf`).
- At least 4 GiB RAM and 20 GiB free in the disposable image.
- The guest must have **no network** for the offline proof: use `-nic none`.

## Create the disposable disk

```sh
mkdir -p out/qemu
qemu-img create -f qcow2 out/qemu/calamares-test.qcow2 20G
```

## Boot the ISO (BIOS)

```sh
qemu-system-x86_64 \
  -enable-kvm -m 4096 -smp 2 \
  -drive file=out/qemu/calamares-test.qcow2,if=virtio,format=qcow2 \
  -cdrom out/maria-padilha-*.iso \
  -boot d -nic none \
  -display gtk
```

## Boot the ISO (UEFI, optional)

```sh
qemu-system-x86_64 \
  -enable-kvm -m 4096 -smp 2 -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/OVMF.fd \
  -drive file=out/qemu/calamares-test.qcow2,if=virtio,format=qcow2 \
  -cdrom out/maria-padilha-*.iso \
  -boot d -nic none \
  -display gtk
```

## Manual install steps

1. Boot the live ISO.  Confirm the syslinux menu shows the Maria Padilha
   splash and palette (BIOS) or the text-only Maria Padilha systemd-boot menu
   (UEFI), then confirm the ISO boots with networking absent; the installer
   must not complain that the internet is unavailable.  See
   [qemu-branding.md](qemu-branding.md) for the dedicated boot-screen checklist.
2. Launch Calamares and confirm the Maria Padilha name, candle logo and
   red/black/cream palette on the welcome page.
3. Welcome: the requirements show storage and RAM only; no internet check.
4. Locale/timezone: pick a locale and click the map; confirm the timezone
   preview changes and matches the selected city.
5. Keyboard: type in the test field and confirm the layout preview.
6. Partition: choose only `out/qemu/calamares-test.qcow2`; use erase disk,
   ext4, no encryption.  Confirm the encryption controls are not offered.
7. Software: keep the desktop group and optionally add Development tools.
8. User: create a test user, set a user password and a separate root password.
9. Summary: confirm the target disk is the disposable image and the selected
   timezone/keyboard/user are correct.  Start the installation.
10. During the execution phase, confirm the slideshow uses local branding and
    that the log shows the `maria-padilha-offline` file:// repository, not a
    mirror.  The install must complete with the network still absent.
11. Reboot the guest without the ISO:

```sh
qemu-system-x86_64 \
  -enable-kvm -m 4096 -smp 2 \
  -drive file=out/qemu/calamares-test.qcow2,if=virtio,format=qcow2 \
  -boot c -nic none \
  -display gtk
```

12. Log in as the created user.  Confirm the Hyprland/Quickshell session,
    default wallpaper and palette appear, and the themed greetd login works
    when you log out.  See [qemu-branding.md](qemu-branding.md) for the greeter
    and installed-GRUB visual checks.
13. In the guest, confirm the live account and autologin did not survive:

```sh
test ! -e /etc/sudoers.d/10-maria-live
test ! -e /etc/sysusers.d/maria-live.conf
! grep -q '^\[initial_session\]' /etc/greetd/config.toml
```

14. Still in the guest, check the enabled units and first-login defaults:

```sh
systemctl is-enabled NetworkManager bluetooth seatd power-profiles-daemon greetd
systemctl --user is-enabled pipewire pipewire-pulse wireplumber
test -f /usr/share/wayland-sessions/maria-padilha.desktop
padilha-daylight --dry-run
ls ~/.local/state/padilha/wallpaper
```

15. In the guest, check the installed system:

```sh
findmnt -no FSTYPE /
pacman -Q maria-padilha
pacman -Q grub efibootmgr
pacman -Qc maria-padilha
```

16. Confirm the target did not install Calamares, and that the local repository
    still exists at `/var/cache/calamares/offline-repo`.
17. Reboot once more and confirm the GRUB menu contains "Maria Padilha" and
    uses the candle-red/gold theme with readable fallback text.

## Negative checks

- Repeat with the ISO booted and `-nic none`: no step may hang on a network
  request.
- Confirm `/etc/pacman.conf` in the target contains the
  `[maria-padilha-offline]` stanza and points at `file://`.
- Confirm no LUKS/encryption option appears in the partition page.
- Confirm cancelling during the execution phase is disabled.

## Record the result

Write the date, QEMU command, ISO checksum, BIOS/UEFI mode, package group
selection and any failures to `out/qemu/result.md`.  `out/` is ignored, so this
record is for the tester and the review note, not part of the commit.

Unattended QEMU acceptance was not added: it would require a built ISO,
preseeded Calamares answers and a reliable way to detect the installed system,
none of which exist in this checkout.  Do not claim a full install was tested
from the static suite alone.
