#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repository_root/tests/e2e/verify-iso-acceptance.sh"
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/blankon-iso-acceptance-test.XXXXXXXX")
trap 'rm -rf -- "$fixture_root"' EXIT
mkdir -p "$fixture_root/bin" "$fixture_root/tmp"
iso_path="$fixture_root/image.iso"
manifest_path="$fixture_root/status"
printf 'synthetic ISO fixture\n' > "$iso_path"

cat > "$fixture_root/bin/xorriso" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" -report_el_torito "* ]]; then
  case "${REPORT_MODE:-valid}" in
    valid) printf '%s\n' 'El Torito boot img : 1 BIOS' 'El Torito boot img : 2 UEFI' ;;
    no-efi) printf '%s\n' 'El Torito boot img : 1 BIOS' ;;
    no-bios) printf '%s\n' 'El Torito boot img : 2 UEFI' ;;
  esac
  exit 0
fi
while (($#)); do
  if [[ "$1" == -extract ]]; then
    destination=$3
    printf 'synthetic extracted content\n' > "$destination"
    shift 3
  else
    shift
  fi
done
STUB

cat > "$fixture_root/bin/unsquashfs" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == -cat ]]
cat "$MANIFEST_PATH"
STUB

cat > "$fixture_root/bin/qemu-system-x86_64" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
exec python3 - "$@" <<'PYTHON'
import os
import signal
import sys
import time

arguments = sys.argv[1:]
serial_path = next(value.removeprefix("file:") for value in arguments if value.startswith("file:"))
with open(os.environ["QEMU_ARGUMENTS_FILE"], "w", encoding="utf-8") as argument_file:
    argument_file.write("\n".join(arguments))
with open(os.environ["QEMU_PID_FILE"], "w", encoding="ascii") as pid_file:
    pid_file.write(str(os.getpid()))
mode = os.environ.get("QEMU_MODE")
serial_lines = {
    "marker-lf": "BLANKON_LIVE_BOOT_OK\n",
    "marker-crlf": "BLANKON_LIVE_BOOT_OK\r\n",
    "prefix": "NOT_BLANKON_LIVE_BOOT_OK\n",
    "suffix": "BLANKON_LIVE_BOOT_OK_EXTRA\n",
    "diagnostic": "[  OK  ] BLANKON_LIVE_BOOT_OK\n",
}
if mode in serial_lines:
    with open(serial_path, "a", encoding="ascii", newline="") as serial_file:
        serial_file.write(serial_lines[mode])
if mode == "early" or mode in {"prefix", "suffix", "diagnostic"}:
    raise SystemExit(23)
stopping = False

def stop_process(signum, frame):
    global stopping
    stopping = True

signal.signal(signal.SIGTERM, stop_process)
while not stopping:
    time.sleep(0.02)
PYTHON
STUB
chmod +x "$fixture_root/bin/xorriso" "$fixture_root/bin/unsquashfs" "$fixture_root/bin/qemu-system-x86_64"

write_manifest() {
  local include_keyring=${1:-yes}
  : > "$manifest_path"
  if [[ "$include_keyring" == yes ]]; then
    printf 'Package: blankon-keyring\nStatus: install ok installed\n\n' >> "$manifest_path"
  fi
  printf '%s\n' \
    'Package: live-boot' 'Status: install ok installed' '' \
    'Package: live-config' 'Status: install ok installed' '' \
    'Package: live-config-systemd' 'Status: install ok installed' '' \
    'Package: systemd-sysv' 'Status: install ok installed' '' \
    'Package: linux-image-6.1-test' 'Status: install ok installed' '' \
    'Package: live-config-doc' 'Status: deinstall ok config-files' '' > "$fixture_root/manifest-tail"
  cat "$fixture_root/manifest-tail" >> "$manifest_path"
}

acceptance_command=(bash "$helper" "$iso_path")
acceptance_environment=(
  "PATH=$fixture_root/bin:$PATH"
  "TMPDIR=$fixture_root/tmp"
  "MANIFEST_PATH=$manifest_path"
  "QEMU_ARGUMENTS_FILE=$fixture_root/qemu-arguments"
  "QEMU_PID_FILE=$fixture_root/qemu.pid"
)

write_manifest
if ! env "${acceptance_environment[@]}" QEMU_MODE=marker-lf "${acceptance_command[@]}" > "$fixture_root/marker.log" 2>&1; then
  printf 'ISO acceptance rejected a valid mocked ISO\n' >&2
  cat "$fixture_root/marker.log" >&2
  exit 1
fi
grep -Fq 'BIOS live-root userspace marker observed; this is not desktop acceptance' "$fixture_root/marker.log"
grep -Fq 'EFI was structurally checked only' "$fixture_root/marker.log"
for required_argument in '-accel' 'tcg' '-m' '768' '-snapshot' '-cdrom' '-boot' 'order=d' '-nic' 'none' '-display' 'none' '-monitor' 'none' '-serial'; do
  grep -Fxq -- "$required_argument" "$fixture_root/qemu-arguments"
done
qemu_pid=$(<"$fixture_root/qemu.pid")
[[ ! -e "/proc/$qemu_pid" ]]

if ! env "${acceptance_environment[@]}" QEMU_MODE=marker-crlf \
  "${acceptance_command[@]}" > "$fixture_root/marker-crlf.log" 2>&1; then
  printf 'ISO acceptance rejected a valid CRLF marker line\n' >&2
  cat "$fixture_root/marker-crlf.log" >&2
  exit 1
fi
grep -Fq 'BIOS live-root userspace marker observed; this is not desktop acceptance' "$fixture_root/marker-crlf.log"
qemu_pid=$(<"$fixture_root/qemu.pid")
[[ ! -e "/proc/$qemu_pid" ]]

for invalid_marker_mode in prefix suffix diagnostic; do
  if env "${acceptance_environment[@]}" "QEMU_MODE=$invalid_marker_mode" \
    "${acceptance_command[@]}" > "$fixture_root/$invalid_marker_mode.log" 2>&1; then
    printf 'ISO acceptance accepted invalid serial marker form: %s\n' "$invalid_marker_mode" >&2
    exit 1
  fi
  grep -Fq 'QEMU exited before the live-root marker' "$fixture_root/$invalid_marker_mode.log"
  qemu_pid=$(<"$fixture_root/qemu.pid")
  [[ ! -e "/proc/$qemu_pid" ]]
done

if env "${acceptance_environment[@]}" REPORT_MODE=no-efi QEMU_MODE=marker \
  "${acceptance_command[@]}" > "$fixture_root/no-efi.log" 2>&1; then
  printf 'ISO acceptance accepted an ISO without EFI boot structure\n' >&2
  exit 1
fi
grep -Fq 'no El Torito EFI boot entry' "$fixture_root/no-efi.log"

write_manifest no
if env "${acceptance_environment[@]}" QEMU_MODE=marker \
  "${acceptance_command[@]}" > "$fixture_root/missing-package.log" 2>&1; then
  printf 'ISO acceptance accepted a missing installed essential package\n' >&2
  exit 1
fi
grep -Fq 'Installed package missing: blankon-keyring' "$fixture_root/missing-package.log"

write_manifest
if env "${acceptance_environment[@]}" QEMU_MODE=early \
  "${acceptance_command[@]}" > "$fixture_root/early-exit.log" 2>&1; then
  printf 'ISO acceptance accepted early QEMU exit without the boot marker\n' >&2
  exit 1
fi
grep -Fq 'QEMU exited before the live-root marker' "$fixture_root/early-exit.log"
qemu_pid=$(<"$fixture_root/qemu.pid")
[[ ! -e "/proc/$qemu_pid" ]]

if env "${acceptance_environment[@]}" ISO_BOOT_TIMEOUT_SECONDS=1 QEMU_MODE=none \
  "${acceptance_command[@]}" > "$fixture_root/timeout.log" 2>&1; then
  printf 'ISO acceptance accepted timeout without the boot marker\n' >&2
  exit 1
fi
grep -Fq 'Timed out after 1 seconds' "$fixture_root/timeout.log"
qemu_pid=$(<"$fixture_root/qemu.pid")
[[ ! -e "/proc/$qemu_pid" ]]

shopt -s nullglob
remaining_temporary_directories=("$fixture_root/tmp"/blankon-iso-acceptance.*)
[[ ${#remaining_temporary_directories[@]} -eq 0 ]]
printf 'ISO acceptance mock checks passed.\n'
