#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/workspace/.build"
mount_log="$test_root/umount.log"

cat > "$test_root/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOUNT_LIST_FAIL:-}" == 1 ]]; then
  exit 33
fi
python3 - <<'PY'
import json
import os
root = os.environ["WORKSPACE_DIR"] + "/.build"
targets = [
    root,
    root + "/chroot/dev/pts",
    root + "/chroot/proc",
    root + "/chroot/sys",
    root + "/chroot/dev/pts/child",
    root + "/chroot/space mount",
    root + "/chroot/newline\nmount",
    "/home/test/blankon-live-build",
]
print(json.dumps({"filesystems": [{"target": target} for target in targets]}))
PY
EOF
cat > "$test_root/bin/umount" <<'EOF'
#!/usr/bin/env bash
python3 -c 'import json, os, sys; open(os.environ["UMOUNT_LOG"], "a").write(json.dumps(sys.argv[1:]) + "\n")' "$1"
if [[ "$1" == "$WORKSPACE_DIR/.build/chroot/dev/pts" ]]; then
  echo 'fake busy mount' >&2
  exit 32
fi
EOF
chmod +x "$test_root/bin/findmnt" "$test_root/bin/umount"

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

python3 - "$mount_log" "$test_root/workspace/.build" <<'PY'
import json
import sys
with open(sys.argv[1]) as log:
    actual = [json.loads(line) for line in log]
root = sys.argv[2]
expected = [
    [root + "/chroot/dev/pts/child"],
    [root + "/chroot/dev/pts"],
    [root + "/chroot/newline\nmount"],
    [root + "/chroot/space mount"],
    [root + "/chroot/proc"],
    [root + "/chroot/sys"],
]
assert actual == expected, (actual, expected)
PY
[[ $(<"$test_root/unmount-errors.log") == *"Failed to unmount workspace mount: $test_root/workspace/.build/chroot/dev/pts"* ]]

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
