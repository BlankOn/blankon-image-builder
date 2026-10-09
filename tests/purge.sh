#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
fixture_init

for stage in bootstrap chroot binary; do
  mkdir -p "$cache_root/key/packages.$stage"
  printf 'cached package\n' > "$cache_root/key/packages.$stage/fixture.deb"
done
mkdir -p .build/config "$BUILD_JAHITAN_PATH/current"
printf 'keep\n' > .build/config/marker
printf 'keep\n' > "$BUILD_JAHITAN_PATH/current/marker"

bash "$scripts_dir/purge-iso"
[[ ! -e "$cache_root" ]]
[[ -f .build/config/marker ]]
[[ -f "$BUILD_JAHITAN_PATH/current/marker" ]]

mkdir -p "$test_root/preserved"
printf 'keep\n' > "$test_root/preserved/marker"
ln -s "$test_root/preserved" "$cache_root"
[[ -L "$cache_root" ]] || {
  echo 'Error: Test environment could not create a symbolic link' >&2
  exit 1
}
if bash "$scripts_dir/purge-iso"; then
  echo 'Error: purge accepted a symlinked cache' >&2
  exit 1
fi
[[ -f "$test_root/preserved/marker" ]]

rm -- "$cache_root"
mkdir -p "$cache_root/key"
ln -s "$test_root/preserved" "$cache_root/key/linked"
[[ -L "$cache_root/key/linked" ]]
if bash "$scripts_dir/purge-iso"; then
  echo 'Error: purge accepted a nested cache symlink' >&2
  exit 1
fi
[[ -f "$test_root/preserved/marker" ]]

rm -- "$cache_root/key/linked"
printf 'cached package\n' > "$cache_root/key/fixture.deb"
cat > "$test_root/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$TEST_MOUNT_TARGET"
EOF
chmod +x "$test_root/bin/findmnt"
export TEST_MOUNT_TARGET="$cache_root/key"
if bash "$scripts_dir/purge-iso"; then
  echo 'Error: purge accepted a mount beneath the cache' >&2
  exit 1
fi
[[ -f "$cache_root/key/fixture.deb" ]]

mkdir -p "$scripts_dir/workdir"
cp "$repo_dir/Dockerfile" "$scripts_dir/Dockerfile"
printf 'BUILD_LOCAL=%s\n' "$test_root/local" > "$scripts_dir/.env"
cat > "$test_root/bin/podman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  info) [[ "${TEST_PODMAN_ROOTFUL:-0}" == 1 ]] && printf 'false\n' || printf 'true\n' ;;
  build) printf 'build:%s\n' "$*" >> "$TEST_PURGE_PODMAN_LOG" ;;
  run)
    [[ " $* " == *' --userns=host '* ]] || exit 31
    [[ " $* " == *'/workdir:rw'* ]] || exit 32
    [[ " $* " == *'/.package-cache.lock:/workdir/.package-cache.lock:ro'* ]] || exit 33
    printf 'run:%s\n' "$*" >> "$TEST_PURGE_PODMAN_LOG"
    ;;
  *) exit 34 ;;
esac
EOF
chmod +x "$test_root/bin/podman"
export TEST_PURGE_PODMAN_LOG="$test_root/purge-podman.log"
if TEST_PODMAN_ROOTFUL=1 env -u BUILDER_CONTAINER bash "$scripts_dir/purge-iso"; then
  echo 'Error: purge accepted rootful Podman' >&2
  exit 1
fi
[[ ! -e "$TEST_PURGE_PODMAN_LOG" ]]
TEST_PODMAN_ROOTFUL=0 env -u BUILDER_CONTAINER bash "$scripts_dir/purge-iso"
[[ $(<"$TEST_PURGE_PODMAN_LOG") == $'build:build '*$'run:run '* ]]
[[ $(<"$TEST_PURGE_PODMAN_LOG") != *"$test_root/local"* ]]
[[ $(<"$TEST_PURGE_PODMAN_LOG") != *"$BUILD_JAHITAN_PATH"* ]]

echo 'Purge ISO smoke checks passed.'
