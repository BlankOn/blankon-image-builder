#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/workspace/.build"
mount_log="$test_root/umount.log"

cat > "$test_root/bin/mount" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOUNT_LIST_FAIL:-}" == 1 ]]; then
  exit 33
fi
printf 'devpts on %s type devpts (rw)\n' "$WORKSPACE_DIR/.build/chroot/dev/pts"
printf 'proc on %s type proc (rw)\n' "$WORKSPACE_DIR/.build/chroot/proc"
printf 'sysfs on %s type sysfs (ro)\n' "$WORKSPACE_DIR/.build/chroot/sys"
printf '/dev/test on /home/test/blankon-live-build type none (rw)\n'
EOF
cat > "$test_root/bin/umount" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$UMOUNT_LOG"
if [[ "$1" == *'/dev/pts' ]]; then
  echo 'fake busy mount' >&2
  exit 32
fi
EOF
chmod +x "$test_root/bin/mount" "$test_root/bin/umount"

source "$repo_dir/build-iso"
WORKSPACE_DIR="$test_root/workspace"
UMOUNT_LOG="$mount_log"
export WORKSPACE_DIR UMOUNT_LOG
PATH="$test_root/bin:$PATH"
export PATH
if unmount_build_workspace_mounts 2>"$test_root/unmount-errors.log"; then
  printf 'Error: failing workspace unmount was accepted\n' >&2
  exit 1
fi

expected="$test_root/workspace/.build/chroot/dev/pts
$test_root/workspace/.build/chroot/proc
$test_root/workspace/.build/chroot/sys"
[[ "$(<"$mount_log")" == "$expected" ]]
[[ "$(wc -l < "$mount_log")" -eq 3 ]]
[[ $(<"$test_root/unmount-errors.log") == *"Failed to unmount workspace mount: $test_root/workspace/.build/chroot/dev/pts"* ]]
if [[ "$(<"$mount_log")" == *'/home/test/blankon-live-build'* ]]; then
  printf 'Error: source mount was unmounted\n' >&2
  exit 1
fi

: > "$mount_log"
export MOUNT_LIST_FAIL=1
if unmount_build_workspace_mounts 2>"$test_root/mount-list-errors.log"; then
  printf 'Error: mount listing failure was accepted\n' >&2
  exit 1
fi
unset MOUNT_LIST_FAIL
[[ $(<"$test_root/mount-list-errors.log") == *'Failed to inspect build workspace mounts'* ]]
[[ ! -s "$mount_log" ]]

printf 'Mount cleanup regression checks passed.\n'
