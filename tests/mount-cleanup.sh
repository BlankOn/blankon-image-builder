#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/workspace/.build"
mount_log="$test_root/umount.log"

cat > "$test_root/bin/mount" <<'EOF'
#!/usr/bin/env bash
printf 'devpts on %s type devpts (rw)\n' "$WORKSPACE_DIR/.build/chroot/dev/pts"
printf 'proc on %s type proc (rw)\n' "$WORKSPACE_DIR/.build/chroot/proc"
printf 'sysfs on %s type sysfs (ro)\n' "$WORKSPACE_DIR/.build/chroot/sys"
printf '/dev/test on /home/test/blankon-live-build type none (rw)\n'
EOF
cat > "$test_root/bin/umount" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$UMOUNT_LOG"
EOF
chmod +x "$test_root/bin/mount" "$test_root/bin/umount"

source "$repo_dir/build-iso"
WORKSPACE_DIR="$test_root/workspace"
UMOUNT_LOG="$mount_log"
export WORKSPACE_DIR UMOUNT_LOG
PATH="$test_root/bin:$PATH"
export PATH
unmount_build_workspace_mounts

expected="$test_root/workspace/.build/chroot/dev/pts
$test_root/workspace/.build/chroot/proc
$test_root/workspace/.build/chroot/sys"
[[ "$(<"$mount_log")" == "$expected" ]]
[[ "$(wc -l < "$mount_log")" -eq 3 ]]
if [[ "$(<"$mount_log")" == *'/home/test/blankon-live-build'* ]]; then
  printf 'Error: source mount was unmounted\n' >&2
  exit 1
fi

printf 'Mount cleanup regression checks passed.\n'
