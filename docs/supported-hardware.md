# Supported hardware

Maria Padilha targets the hardware classes used by the reference AMD laptop,
not one DMI string or one board revision.  The image installs the generic
firmware, microcode, audio and power/thermal pieces for those classes, and the
repository checks that they stay in the package list.  Board-specific workarounds
do not belong in the image unless they are needed by a whole class and can be
tested on more than one machine.

## Status

No physical reference laptop has been booted in this checkout.  The image
profile, package selection, unit enablement, no-suspend policy and hardware
check script are covered by the static repository suite
(`tests/hardware.sh`), but that is configuration evidence, not a hardware
qualification.  Record a real boot result before calling a class tested on
metal.  Suspend and hibernation are deliberately never exercised by the test
suite or by the check script.

## Reference platform

The reference machine is an AMD laptop with:

- an AMD Ryzen-class CPU (microcode loaded from the initramfs);
- an AMD Radeon integrated GPU, with the usual AMD laptop display and video
  decode paths;
- an integrated Wi-Fi/Bluetooth module from one of the common vendors
  (MediaTek, Realtek, Qualcomm Atheros or Intel);
- AMD/HDMI audio plus the platform Sound Open Firmware (SOF) and ALSA UCM
  profiles;
- a battery, lid switch, thermal zones and an ACPI platform profile.

These are hardware classes.  The image does not match PCI IDs, DMI product
names or board revisions.

## Tested

In this document, **tested** means the image contract is exercised by the
repository suite.  It does not mean the physical component has been qualified
on the reference laptop; the project status above is explicit about that gap.

| class | image pieces | what is tested |
| --- | --- | --- |
| AMD CPU microcode | `amd-ucode`, the archiso `microcode` initramfs hook from `mkinitcpio-archiso` | package is selected; the generated initramfs includes the microcode hook |
| AMD GPU firmware | `linux-firmware-amdgpu` plus the `linux-firmware` meta package | package is selected; `/usr/lib/firmware/amdgpu` is non-empty on a running image |
| AMD platform firmware | `linux-firmware-amd` | package is selected and the AMD firmware tree is reported |
| Wi-Fi/Bluetooth firmware | `linux-firmware-mediatek`, `linux-firmware-realtek`, `linux-firmware-atheros`, `linux-firmware-broadcom`, `linux-firmware-intel` | at least one vendor firmware package and tree is present; Bluetooth userspace is installed and `bluetooth.service` is enabled |
| AMD graphics userspace | `mesa` (which provides the VA-API driver), `vulkan-radeon`, `libva`, `libva-utils` | packages are selected; the check script confirms the audio/GPU userspace pieces it can see |
| Audio | `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber`, `alsa-utils`, `alsa-ucm-conf`, `sof-firmware` | packages are selected; the user units are enabled globally; the check script verifies the UCM tree and a SOF firmware tree |
| Power and thermal | `power-profiles-daemon`, `upower`, `lm_sensors`, `acpi` | `power-profiles-daemon.service` is enabled; the check script verifies the tools, thermal zones and the no-auto-suspend policy |
| Common laptop pieces | `bluez`, `bluez-utils`, `iw`, `wireless-regdb`, `brightnessctl`, `pciutils`, `usbutils` | packages are selected; the check script verifies the ones it uses |

The exact package list lives in `iso/packages.x86_64`.  Keeping the firmware
vendor splits listed next to the meta package makes the intended coverage
reviewable; it also lets a future size-constrained image drop the meta package
without silently losing AMD GPU or Wi-Fi/Bluetooth firmware.

## Best-effort

These classes have the generic stack installed but are not individually
qualified.  They should work on most machines in the class and need a hardware
report before they are promoted to tested:

- AMD discrete GPUs and hybrid integrated/discrete configurations using
  `amdgpu`; the image installs no per-vendor switching service and does not
  configure PRIME or MUX handling.
- MediaTek, Realtek, Qualcomm Atheros and Intel Wi-Fi/Bluetooth variants.  The
  firmware packages are installed, but the reference laptop uses only one
  vendor's module, so the others are best-effort.
- Intel CPUs, graphics and audio.  `intel-ucode` and `linux-firmware-intel`
  remain in the list so an Intel test machine can boot and report results; this
  is not an Intel-supported image.
- Laptop codecs and microphone arrays that need a vendor-specific ALSA UCM
  profile not shipped by `alsa-ucm-conf`.
- Battery charge thresholds, fan curves and platform-specific performance
  knobs.  The kernel `platform_profile` and `power-profiles-daemon` cover the
  generic cases only.
- Bluetooth audio and headset microphones.  BlueZ and PipeWire are present, but
  codec availability depends on the adapter and headset.

## Explicitly unsupported

- **s2idle suspend and hibernation.**  The reference AMD laptop cannot resume
  from s2idle.  The image disables suspend, hibernation, hybrid sleep and
  suspend-then-hibernate in
  `/etc/systemd/sleep.conf.d/10-maria-padilha-no-s2idle.conf`, and the lid
  switch, suspend key and idle action are set to ignore in
  `/etc/systemd/logind.conf.d/10-maria-padilha-no-autosuspend.conf`.  Do not
  enable them as a workaround for an unrelated bug.
- **Automatic suspend.**  No idle timer or lid action suspends the machine.
  Locking the session on lid close is a compositor/user concern and does not
  require suspend.
- **TLP, auto-cpufreq, thermald or another power manager.**
  `power-profiles-daemon` is the single power/thermal manager.  `thermald` is
  Intel-specific; the others conflict with the intended policy.
- **NVIDIA proprietary drivers, PRIME offload and NVIDIA Optimus.**  The image
  has no NVIDIA userspace driver or per-model switching configuration.
- **Fingerprint readers, IR cameras, WWAN modems and other optional laptop
  modules.**  No userspace stack or per-device enables are included.
- **Overclocking, undervolting, fan/RGB control and vendor performance
  utilities.**  These are machine-specific and are not part of a generic
  laptop image.
- **Firmware flashing from the OS.**  `fwupd` is not installed; BIOS/EC updates
  are outside this profile.

## Configuration files

| path | purpose |
| --- | --- |
| `iso/packages.x86_64` | microcode, firmware, AMD graphics, audio and laptop packages |
| `iso/airootfs/etc/systemd/sleep.conf.d/10-maria-padilha-no-s2idle.conf` | disables suspend and hibernation while s2idle is broken |
| `iso/airootfs/etc/systemd/logind.conf.d/10-maria-padilha-no-autosuspend.conf` | ignores lid, suspend/hibernate keys and idle action |
| `iso/airootfs/etc/systemd/system/multi-user.target.wants/power-profiles-daemon.service` | enables the single power/thermal manager |
| `iso/airootfs/usr/local/bin/maria-padilha-hardware-check` | read-only check for a running image |

The package list is installed into the live root and therefore carried into the
Calamares target by the squashfs unpack.  The hardware support is not an
optional add-on group: a laptop missing firmware on first boot cannot install
it from an offline image.  The Calamares package chooser still has the desktop
and development groups for optional software.

## Checking a running image

The check is read-only, needs no root and does not start or test suspend or
hibernation:

```sh
maria-padilha-hardware-check
```

To inspect a mounted target from the build host:

```sh
bash scripts/check-hardware.sh --root /mnt
```

It verifies package presence when the target has a pacman database, checks the
AMD GPU and Wi-Fi/Bluetooth firmware trees, the SOF/UCM audio pieces, the
PipeWire commands, the enabled power/Bluetooth/network units and the
no-auto-suspend settings.  On the running root it also reports thermal zones,
battery, ACPI platform profile and the loaded CPU microcode revision.  Missing
packages or firmware trees are `FAIL`; unavailable runtime details are `SKIP`
or informational.  A failed check is a packaging bug, not a reason to disable
the check.

## Adding hardware

Add a package or firmware class, not a machine name.  If a new class needs a
kernel parameter, module option or service, document why it applies to the
whole class, add it to `iso/packages.x86_64` (or an explicitly documented
hardware group), extend `tests/hardware.sh`, and update the tables above.  A
workaround that only works on one board belongs in a hardware report or a
separate profile, not in this image.

Useful evidence for a report:

```sh
lspci -nnk
lsusb
journalctl -k -b
```

Do not include serial numbers, MAC addresses or other machine identifiers in a
report.  Never make suspend or hibernation a release criterion until the
reference machine has a working, tested resume path.
