SHELL := /bin/bash

.PHONY: all test iso package ci-iso smoke-test prereqs first-boot hardware-check clean

all: test

test:
	bash tests/all.sh

# Build the package and the ISO. This must run inside an Arch container as root.
iso:
	./build.sh

# Same build through the CI wrapper: privileged Arch container, checksum and
# build metadata under out/. Never needs host root privileges.
ci-iso:
	bash scripts/ci/build-iso.sh

# Boot the newest smoke-enabled ISO headlessly and wait for the serial login.
smoke-test:
	@iso="$$(ls -1t out/maria-padilha-*.iso 2>/dev/null | head -n1)"; \
	if [ -z "$$iso" ]; then \
		echo "no ISO under out/; run 'make ci-iso' first" >&2; \
		exit 1; \
	fi; \
	bash scripts/ci/qemu-smoke-test.sh "$$iso"

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

# Inspect an installed root (default /) for first-login readiness.  Run this
# inside the target chroot/nspawn, or pass ROOT=/mnt from the build host.
first-boot:
	bash tests/first-boot.sh --root "$${ROOT:-/}"

# Read-only hardware enablement check for the running image or ROOT=/mnt.
hardware-check:
	bash scripts/check-hardware.sh --root "$${ROOT:-/}"

clean:
	rm -rf out .scratch/iso-build
