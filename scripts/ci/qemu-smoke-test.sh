#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Headless QEMU smoke boot for a Maria Padilha ISO.
#
# The ISO must have been built with a serial console and the CI boot-marker
# service enabled.  The CI workflow passes:
#
#   MARIA_PADILHA_KERNEL_PARAMS="quiet splash console=tty0 \
#     console=ttyS0,115200 systemd.wants=serial-getty@ttyS0.service \
#     maria-padilha.ci=1"
#
# The script boots the ISO with no display and no network, watches the serial
# log for MARIA_PADILHA_BOOT_OK and a serial login prompt, and fails on a
# kernel panic, a bootloader error or a timeout.  It never mounts the ISO and
# never runs a privileged host command.
set -Eeuo pipefail

script_name="${0##*/}"
root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

iso=""
timeout="${SMOKE_TIMEOUT:-900}"
boot_marker="${SMOKE_BOOT_MARKER:-MARIA_PADILHA_BOOT_OK}"
login_regex="${SMOKE_LOGIN_REGEX:-(^|[[:space:]])login:[[:space:]]*$}"
panic_regex="${SMOKE_PANIC_REGEX:-Kernel panic|panic - not syncing|end Kernel panic|BUG: unable to handle kernel|Oops: [0-9]+|Fatal exception in interrupt|No bootable device}"
memory_mb="${SMOKE_MEMORY_MB:-3072}"
cpus="${SMOKE_CPUS:-2}"
log_dir="${SMOKE_LOG_DIR:-$root/out/qemu-smoke}"

log() { printf '[qemu-smoke] %s\n' "$*" >&2; }
die() { printf '[qemu-smoke] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
usage: $script_name ISO

Boot ISO headlessly with a serial console.  Exit 0 only after the serial log
contains the boot marker and a login prompt.  Exit non-zero on a kernel panic,
bootloader failure or timeout.

Environment:
  SMOKE_TIMEOUT       seconds to wait for marker + login (default 900)
  SMOKE_BOOT_MARKER  exact marker written by the CI boot-marker unit
                     (default MARIA_PADILHA_BOOT_OK)
  SMOKE_LOGIN_REGEX  extended regex for the login prompt
                     (default: a line ending in 'login:')
  SMOKE_PANIC_REGEX  extended regex for fatal boot failures
  SMOKE_MEMORY_MB    guest RAM in MiB (default 3072)
  SMOKE_CPUS         guest vCPUs (default 2)
  SMOKE_LOG_DIR      serial/QEMU logs (default out/qemu-smoke)

The ISO must carry the CI serial kernel parameters.  The workflow sets them
when the opt-in smoke_test input is enabled; a normal production ISO has no
serial getty or CI marker and will time out here.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    '')
        die "missing ISO path (try --help)"
        ;;
    -*)
        die "unknown option: $1 (try --help)"
        ;;
    *)
        iso="$1"
        shift
        ;;
esac
(($# == 0)) || die "unexpected argument: $1"
[[ -f "$iso" ]] || die "ISO not found: $iso"
[[ "$timeout" =~ ^[0-9]+$ ]] || die "SMOKE_TIMEOUT must be an integer"
[[ "$memory_mb" =~ ^[0-9]+$ ]] || die "SMOKE_MEMORY_MB must be an integer"
[[ "$cpus" =~ ^[0-9]+$ ]] || die "SMOKE_CPUS must be an integer"
command -v qemu-system-x86_64 >/dev/null 2>&1 ||
    die "qemu-system-x86_64 is not installed"

mkdir -p "$log_dir"
serial_log="$log_dir/serial.log"
scan_log="$log_dir/serial.normalized.log"
qemu_log="$log_dir/qemu.log"
: >"$serial_log"
: >"$scan_log"
: >"$qemu_log"

qemu_pid=""
stop_qemu() {
    if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            kill -0 "$qemu_pid" 2>/dev/null || break
            sleep 0.2
        done
        kill -9 "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
}
trap 'stop_qemu' EXIT
trap 'stop_qemu; exit 130' INT TERM

if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    accel_args=(-accel kvm -cpu host)
    accel_name="kvm"
else
    accel_args=(-accel 'tcg,thread=multi' -cpu max)
    accel_name="tcg"
fi

log "ISO: $iso"
log "accelerator: $accel_name (memory ${memory_mb} MiB, ${cpus} vCPU)"
log "logs: $log_dir"

qemu-system-x86_64 \
    -name "maria-padilha-smoke" \
    -machine pc \
    "${accel_args[@]}" \
    -m "$memory_mb" \
    -smp "$cpus" \
    -cdrom "$iso" \
    -boot "order=d,menu=off" \
    -nic none \
    -display none \
    -monitor none \
    -serial "file:$serial_log" \
    -no-reboot \
    >"$qemu_log" 2>&1 &
qemu_pid=$!

marker_seen=0
login_seen=0
start=$SECONDS

while :; do
    tr -d '\r' <"$serial_log" >"$scan_log" 2>/dev/null || true

    if grep -aEq -- "$panic_regex" "$scan_log"; then
        printf '\n[qemu-smoke] FATAL boot failure found in serial log:\n' >&2
        grep -aEn -- "$panic_regex" "$scan_log" | tail -n 10 >&2 || true
        printf '\n--- last serial lines ---\n' >&2
        tail -n 80 "$serial_log" >&2 || true
        die "kernel panic or fatal boot error (full log: $serial_log)"
    fi

    if ((marker_seen == 0)) && grep -aFq -- "$boot_marker" "$scan_log"; then
        marker_seen=1
        log "boot marker seen: $boot_marker"
    fi
    if ((login_seen == 0)) && grep -aEq -- "$login_regex" "$scan_log"; then
        login_seen=1
        log "login prompt seen"
    fi

    if ((marker_seen == 1 && login_seen == 1)); then
        log "PASS: boot marker and serial login prompt observed after $((SECONDS - start))s"
        exit 0
    fi

    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        rc=0
        wait "$qemu_pid" 2>/dev/null || rc=$?
        printf '\n[qemu-smoke] QEMU exited before the smoke markers (status %s)\n' "$rc" >&2
        printf '%s\n' '--- QEMU output ---' >&2
        tail -n 40 "$qemu_log" >&2 || true
        printf '%s\n' '--- last serial lines ---' >&2
        tail -n 80 "$serial_log" >&2 || true
        die "QEMU exited before boot marker and login prompt (full logs: $log_dir)"
    fi

    if ((SECONDS - start >= timeout)); then
        printf '\n[qemu-smoke] timed out after %ss (marker=%s login=%s)\n' \
            "$timeout" "$marker_seen" "$login_seen" >&2
        printf '%s\n' '--- last serial lines ---' >&2
        tail -n 100 "$serial_log" >&2 || true
        die "timed out waiting for boot marker and login prompt (full logs: $log_dir)"
    fi

    sleep 2
done
