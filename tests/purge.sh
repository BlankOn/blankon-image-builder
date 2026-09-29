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

echo 'Purge ISO smoke checks passed.'
