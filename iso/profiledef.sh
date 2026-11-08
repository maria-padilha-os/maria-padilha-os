#!/usr/bin/env bash
# Profile definition for the Maria Padilha live/installer image.
#
# Build it from an Arch container with ../build.sh. The package version is
# pinned in iso/package-version (currently 0.2.0, matching
# maria-padilha-de/packaging/PKGBUILD); build.sh exports
# MARIA_PADILHA_VERSION so a locally built package and the ISO agree.
# shellcheck disable=SC2034

_profile_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
maria_padilha_version="${MARIA_PADILHA_VERSION:-$(<"${_profile_dir}/package-version")}"

iso_name="maria-padilha"
iso_label="MARIA_PADILHA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Maria Padilha <https://github.com/maria-padilha-os>"
iso_application="Maria Padilha live desktop"
iso_version="${maria_padilha_version}"
install_dir="padilha"
arch="x86_64"
pacman_conf="pacman.conf"
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
kernel_params="quiet"
declare -A file_permissions=()
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d/10-maria-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/etc/skel"]="0:0:755"
  ["/etc/skel/.bashrc"]="0:0:644"
  ["/etc/skel/.profile"]="0:0:644"
  ["/etc/skel/.bash_logout"]="0:0:644"
)
