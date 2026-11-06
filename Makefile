SHELL := /bin/bash

.PHONY: all test iso package prereqs clean

all: test

test:
	bash tests/all.sh

# Build the package and the ISO. This must run inside an Arch container as root.
iso:
	./build.sh

# Build only maria-padilha and stop before mkarchiso.
package:
	./build.sh --package-only

# Print the host/container prerequisites; does not modify the host.
prereqs:
	@printf '%s\n' \
		'Run the ISO build as root inside an Arch Linux container with:' \
		'  pacman -Syu --needed --noconfirm archiso base-devel git' \
		'Then, with maria-padilha-de mounted at /pkg/maria-padilha-de:' \
		'  MARIA_PADILHA_DE=/pkg/maria-padilha-de ./build.sh' \
		'' \
		'Required commands: mkarchiso pacstrap arch-chroot xorriso mksquashfs' \
		'                  mkfs.fat mmd mcopy makepkg repo-add git bsdtar'

clean:
	rm -rf out .scratch/iso-build
