#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
fixture_init

FAKE_LB_EXPECT_CACHE=absent bash "$scripts_dir/build-iso" --local "$source_dir"
[[ $(<"$TEST_CACHE_LOG") == absent ]]
old_cache_dir=$(find "$cache_root" -mindepth 1 -maxdepth 1 -type d -print -quit)
for stage in bootstrap chroot binary; do
  [[ -f "$old_cache_dir/packages.$stage/fixture.deb" ]]
done

FAKE_LB_EXPECT_CACHE=present bash "$scripts_dir/build-iso" --local "$source_dir"
[[ $(tail -n 1 "$TEST_CACHE_LOG") == present ]]
[[ $(find "$cache_root" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 1 ]]

printf 'changed archive fixture\n' > "$source_dir/config/common/includes.chroot/etc/blankon/archive.conf"
FAKE_LB_EXPECT_CACHE=absent bash "$scripts_dir/build-iso" --local "$source_dir"
[[ $(tail -n 1 "$TEST_CACHE_LOG") == absent ]]
[[ $(find "$cache_root" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 2 ]]
new_cache_dir=$(find "$cache_root" -mindepth 1 -maxdepth 1 -type d ! -path "$old_cache_dir" -print -quit)
for stage in bootstrap chroot binary; do
  [[ -f "$old_cache_dir/packages.$stage/fixture.deb" ]]
  [[ -f "$new_cache_dir/packages.$stage/fixture.deb" ]]
done

current_before_lock=$(<"$BUILD_JAHITAN_PATH/current/current.txt")
exec {cache_lock_fd}>"$test_root/workdir/.package-cache.lock"
flock -n "$cache_lock_fd"
if bash "$scripts_dir/build-iso" --local "$source_dir"; then
  echo 'Error: build ignored the package-cache lock' >&2
  exit 1
fi
if bash "$scripts_dir/purge-iso"; then
  echo 'Error: purge ignored the package-cache lock' >&2
  exit 1
fi
[[ $(find "$cache_root" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 2 ]]
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$current_before_lock" ]]
exec {cache_lock_fd}>&-

echo 'Package cache smoke checks passed.'
