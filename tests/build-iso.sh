#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
fixture_init

assert_build_lock_available() {
  exec {check_lock_fd}>>"$BUILD_LOCKFILE"
  flock -n "$check_lock_fd"
  exec {check_lock_fd}>&-
}

env -u TELEGRAM_BOT_KEY -u TELEGRAM_BOT_KEY_FILE BUILD_SEND_TELEGRAM=1 \
  bash "$scripts_dir/build-iso" --local "$source_dir"

output_dir=$(find "$BUILD_JAHITAN_PATH" -mindepth 1 -maxdepth 1 -type d ! -name current -print)
[[ -n "$output_dir" && -d "$output_dir" ]]
image_name=blankon-live-image-smoke-amd64
for suffix in contents files packages hybrid.iso hybrid.iso.zsync hybrid.iso.sha256sum; do
  [[ -s "$output_dir/$image_name.$suffix" ]]
  [[ -s "$BUILD_JAHITAN_PATH/current/$image_name.$suffix" ]]
done
[[ -f "$output_dir/$image_name.build.log.txt" ]]
[[ -f "$output_dir/$image_name.tail100.build.log.txt" ]]
[[ -f .build/config/variant-marker ]]
[[ -f .build/config/includes.chroot/etc/blankon/archive.conf ]]
[[ -f "$BUILD_LOCKFILE" ]]
[[ ! -s "$BUILD_LOCKFILE" ]]
assert_build_lock_available
[[ ! -e "$TEST_CURL_LOG" ]]
(cd -- "$output_dir" && sha256sum -c "$image_name.hybrid.iso.sha256sum")
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$(basename -- "$output_dir")" ]]

if FAKE_LB_FAIL=1 bash "$scripts_dir/build-iso" --local "$source_dir"; then
  echo 'Error: fake live-build failure was accepted' >&2
  exit 1
fi
[[ -f "$BUILD_LOCKFILE" ]]
[[ ! -s "$BUILD_LOCKFILE" ]]
assert_build_lock_available
[[ ! -e "$TEST_CURL_LOG" ]]
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$(basename -- "$output_dir")" ]]

if FAKE_CURRENT_COPY_FAIL=1 bash "$scripts_dir/build-iso" --local "$source_dir"; then
  echo 'Error: current output copy failure was accepted' >&2
  exit 1
fi
[[ -f "$BUILD_LOCKFILE" ]]
[[ ! -s "$BUILD_LOCKFILE" ]]
assert_build_lock_available
[[ -s "$BUILD_JAHITAN_PATH/current/$image_name.hybrid.iso" ]]
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$(basename -- "$output_dir")" ]]
[[ -z $(find "$BUILD_JAHITAN_PATH" -maxdepth 1 -name '.current.stage.*' -print -quit) ]]

if FAKE_CURRENT_PROMOTE_FAIL=1 bash "$scripts_dir/build-iso" --local "$source_dir"; then
  echo 'Error: current output promotion failure was accepted' >&2
  exit 1
fi
[[ -f "$BUILD_LOCKFILE" ]]
[[ ! -s "$BUILD_LOCKFILE" ]]
assert_build_lock_available
[[ -s "$BUILD_JAHITAN_PATH/current/$image_name.hybrid.iso" ]]
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$(basename -- "$output_dir")" ]]
[[ -z $(find "$BUILD_JAHITAN_PATH" -maxdepth 1 -name '.current.stage.*' -print -quit) ]]
[[ -z $(find "$BUILD_JAHITAN_PATH" -maxdepth 1 -name '.current.backup.*' -print -quit) ]]

git -C "$source_dir" init -q -b ci-smoke
git -C "$source_dir" add .
git -C "$source_dir" -c commit.gpgsign=false -c user.name=CI -c user.email=ci@example.invalid commit -qm pinned
pinned_commit=$(git -C "$source_dir" rev-parse HEAD)
printf 'branch tip\n' > "$source_dir/config/smoke/variant-marker"
git -C "$source_dir" -c commit.gpgsign=false -c user.name=CI -c user.email=ci@example.invalid commit -qam tip

bash "$scripts_dir/build-iso" --remote "$source_dir" ci-smoke "$pinned_commit"
[[ $(<.build/config/variant-marker) == 'variant fixture' ]]
[[ $(<.build/config/bootloaders/syslinux_common/splash.svg) != *BUILD_NUMBER* ]]

bash "$scripts_dir/build-iso" --remote "$source_dir" ci-smoke
[[ $(<.build/config/variant-marker) == 'branch tip' ]]
latest_current=$(<"$BUILD_JAHITAN_PATH/current/current.txt")

if bash "$scripts_dir/build-iso" --remote "$source_dir" missing-branch; then
  echo 'Error: missing remote branch was accepted' >&2
  exit 1
fi
if bash "$scripts_dir/build-iso" --remote "$source_dir" ci-smoke deadbeef; then
  echo 'Error: missing remote commit was accepted' >&2
  exit 1
fi
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$latest_current" ]]

exec {build_lock_fd}>>"$BUILD_LOCKFILE"
flock -n "$build_lock_fd"
if lock_output=$(bash "$scripts_dir/build-iso" --local "$source_dir" 2>&1); then
  echo 'Error: active build lock was ignored' >&2
  exit 1
fi
[[ "$lock_output" == *'Build is already in progress'* ]]
[[ "$lock_output" != *'Done in'* ]]
exec {build_lock_fd}>&-
bash "$scripts_dir/build-iso" --local "$source_dir"
[[ -f "$BUILD_LOCKFILE" ]]
assert_build_lock_available
latest_current=$(<"$BUILD_JAHITAN_PATH/current/current.txt")

mkdir -p "$test_root/outside"
if env -u BUILDER_CONTAINER bash "$scripts_dir/build-iso" --local "$test_root/outside"; then
  echo 'Error: local source outside BUILD_LOCAL was accepted' >&2
  exit 1
fi
printf '../invalid\n' > "$source_dir/variant"
if bash "$scripts_dir/build-iso" --local "$source_dir"; then
  echo 'Error: invalid variant was accepted' >&2
  exit 1
fi
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$latest_current" ]]

echo 'Build ISO smoke checks passed.'
