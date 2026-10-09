#!/usr/bin/env bash
set -euo pipefail

iso_path=${1:?Usage: verify-iso-acceptance.sh ISO}
[[ -f "$iso_path" && -s "$iso_path" ]] || {
  printf 'ISO is missing or empty: %s\n' "$iso_path" >&2
  exit 1
}

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/blankon-iso-acceptance.XXXXXXXX")
qemu_pid=''
serial_log="$temporary_root/serial.log"
qemu_log="$temporary_root/qemu.log"

stop_qemu() {
  local process_state attempt
  if [[ -n "$qemu_pid" ]]; then
    kill -TERM "$qemu_pid" 2>/dev/null || true
    for attempt in {1..20}; do
      process_state=$(ps -o stat= -p "$qemu_pid" 2>/dev/null || true)
      if [[ -z "$process_state" || "$process_state" == Z* ]]; then
        break
      fi
      sleep 0.1
    done
    process_state=$(ps -o stat= -p "$qemu_pid" 2>/dev/null || true)
    if [[ -n "$process_state" && "$process_state" != Z* ]]; then
      kill -KILL "$qemu_pid" 2>/dev/null || true
    fi
    wait "$qemu_pid" 2>/dev/null || true
    qemu_pid=''
  fi
}

finish_acceptance() {
  result=$?
  if (( result != 0 )); then
    printf '\nISO acceptance diagnostics (last 80 lines):\n' >&2
    if [[ -s "$serial_log" ]]; then
      tail -n 80 "$serial_log" >&2
    fi
    if [[ -s "$qemu_log" ]]; then
      tail -n 80 "$qemu_log" >&2
    fi
  fi
  stop_qemu
  rm -rf -- "$temporary_root"
  return "$result"
}

trap finish_acceptance EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

command -v xorriso >/dev/null
command -v unsquashfs >/dev/null
command -v qemu-system-x86_64 >/dev/null

if ! boot_report=$(xorriso -no_rc -indev "$iso_path" -report_el_torito plain 2>&1); then
  printf 'xorriso could not inspect the ISO boot catalog\n' >&2
  tail -n 60 <<<"$boot_report" >&2
  exit 1
fi
if ! grep -Eqi 'El Torito boot img.*BIOS' <<<"$boot_report"; then
  printf 'ISO has no El Torito BIOS boot entry\n' >&2
  exit 1
fi
if ! grep -Eqi 'El Torito boot img.*(UEFI|EFI)' <<<"$boot_report"; then
  printf 'ISO has no El Torito EFI boot entry\n' >&2
  exit 1
fi

xorriso -no_rc -osirrox on -indev "$iso_path" \
  -extract /live/vmlinuz "$temporary_root/vmlinuz" \
  -extract /live/initrd.img "$temporary_root/initrd.img" \
  -extract /live/filesystem.squashfs "$temporary_root/filesystem.squashfs" \
  > "$qemu_log" 2>&1
for required_file in vmlinuz initrd.img filesystem.squashfs; do
  if [[ ! -s "$temporary_root/$required_file" ]]; then
    printf 'ISO is missing required nonempty /live/%s\n' "$required_file" >&2
    exit 1
  fi
done

if ! unsquashfs -cat "$temporary_root/filesystem.squashfs" /var/lib/dpkg/status \
  | awk '
    function check_package() {
      if (status == "install ok installed") {
        if (package == "blankon-keyring" || package == "live-boot" || package == "live-config" || package == "live-config-systemd" || package == "systemd-sysv") {
          found[package] = 1
        }
        if (package ~ /^linux-image(-|$)/) {
          kernel_found = 1
        }
        if (package == "gnome-shell" || package == "gdm3" || package == "calamares") {
          forbidden[package] = 1
        }
      }
    }
    /^Package: / { package = substr($0, 10) }
    /^Status: / { status = substr($0, 9) }
    /^$/ { check_package(); package = ""; status = "" }
    END {
      check_package()
      required[1] = "blankon-keyring"
      required[2] = "live-boot"
      required[3] = "live-config"
      required[4] = "live-config-systemd"
      required[5] = "systemd-sysv"
      failed = 0
      for (item = 1; item <= 5; item++) {
        if (!found[required[item]]) {
          printf "Installed package missing: %s\n", required[item] > "/dev/stderr"
          failed = 1
        }
      }
      if (!kernel_found) {
        print "Installed linux-image package missing" > "/dev/stderr"
        failed = 1
      }
      for (package in forbidden) {
        printf "Unexpected installed desktop/installer package: %s\n", package > "/dev/stderr"
        failed = 1
      }
      exit failed
    }
  '; then
  printf 'ISO installed-package manifest check failed\n' >&2
  exit 1
fi

boot_timeout_seconds=${ISO_BOOT_TIMEOUT_SECONDS:-180}
if [[ ! "$boot_timeout_seconds" =~ ^[1-9][0-9]{0,2}$ ]] || (( boot_timeout_seconds > 900 )); then
  printf 'ISO_BOOT_TIMEOUT_SECONDS must be an integer from 1 to 900\n' >&2
  exit 1
fi

qemu-system-x86_64 \
  -accel tcg \
  -m 768 \
  -snapshot \
  -cdrom "$iso_path" \
  -boot order=d \
  -nic none \
  -display none \
  -monitor none \
  -serial "file:$serial_log" \
  -no-reboot \
  > "$qemu_log" 2>&1 &
qemu_pid=$!
deadline=$((SECONDS + boot_timeout_seconds))
while (( SECONDS < deadline )); do
  if [[ -s "$serial_log" ]] && grep -Eqx $'BLANKON_LIVE_BOOT_OK\r?' "$serial_log"; then
    stop_qemu
    printf 'ISO structure and installed package checks passed. BIOS live-root userspace marker observed; this is not desktop acceptance. EFI was structurally checked only.\n'
    exit 0
  fi
  process_state=$(ps -o stat= -p "$qemu_pid" 2>/dev/null || true)
  if [[ -z "$process_state" || "$process_state" == Z* ]]; then
    qemu_status=0
    wait "$qemu_pid" || qemu_status=$?
    qemu_pid=''
    printf 'QEMU exited before the live-root marker (status %s)\n' "$qemu_status" >&2
    exit 1
  fi
  sleep 0.1
done

printf 'Timed out after %s seconds waiting for the BIOS live-root marker\n' "$boot_timeout_seconds" >&2
exit 1
