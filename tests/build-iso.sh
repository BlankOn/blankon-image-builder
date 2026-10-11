#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
fixture_init

output_mode_probe="$test_root/output-mode-probe"
: > "$output_mode_probe"
expected_output_mode=$(stat -c '%a' "$output_mode_probe")
rm -- "$output_mode_probe"

today=$(date '+%Y%m%d')
mkdir -p "$BUILD_JAHITAN_PATH/$today-1" "$BUILD_JAHITAN_PATH/$today-3"
printf 'stale output\n' > "$BUILD_JAHITAN_PATH/$today-3/stale.txt"

assert_build_lock_available() {
  exec {check_lock_fd}>>"$BUILD_LOCKFILE"
  flock -n "$check_lock_fd"
  exec {check_lock_fd}>&-
}

env -u TELEGRAM_BOT_KEY -u TELEGRAM_BOT_KEY_FILE BUILD_SEND_TELEGRAM=1 \
  bash "$scripts_dir/build-iso" --local "$source_dir"

output_dir="$BUILD_JAHITAN_PATH/$today-4"
[[ -n "$output_dir" && -d "$output_dir" ]]
[[ "$(basename -- "$output_dir")" == "$today-4" ]]
[[ $(<"$BUILD_JAHITAN_PATH/$today-3/stale.txt") == 'stale output' ]]
image_name=blankon-live-image-smoke-amd64
for suffix in contents files packages hybrid.iso hybrid.iso.zsync hybrid.iso.sha256sum; do
  [[ -s "$output_dir/$image_name.$suffix" ]]
  [[ -s "$BUILD_JAHITAN_PATH/current/$image_name.$suffix" ]]
done
[[ -f "$output_dir/$image_name.build.log.txt" ]]
[[ -f "$output_dir/$image_name.tail100.build.log.txt" ]]
for marker in 'fake lb stdout marker' 'fake lb stderr marker'; do
  [[ $(<"$output_dir/$image_name.build.log.txt") == *"$marker"* ]]
done
[[ $(<"$output_dir/$image_name.build.log.txt") != *'stale-log marker'* ]]
python3 - "$output_dir/$image_name.build-manifest.json" "$output_dir/$image_name.hybrid.iso" \
  "$BUILD_JAHITAN_PATH/current/$image_name.build-manifest.json" "$test_root" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest_text = manifest_path.read_text()
manifest = json.loads(manifest_text)
assert set(manifest) == {
    "schema_version",
    "builder_git_sha",
    "live_source_git_sha",
    "live_source_status",
    "oci_base_reference",
    "builder_image_id",
    "live_build_version",
    "debootstrap_version",
    "podman_version",
    "host_kernel",
    "host_os",
    "rootless",
    "userns_mode",
    "security_profile",
    "host_selinux_state",
    "selinux_enforcing",
    "podman_selinux_enabled",
    "output_sha256",
    "build_result",
}
assert manifest["schema_version"] == 1
assert manifest["builder_git_sha"] == "fixture-builder-sha"
assert manifest["live_source_git_sha"] == "unknown"
assert manifest["live_source_status"] == "unavailable"
assert manifest["oci_base_reference"] == "ghcr.io/blankon/blankon-nightly@sha256:76b7e3b7feba1221d649481673af63bf65c310361916d574c6fe1cb90a02fea5", manifest["oci_base_reference"]
assert manifest["builder_image_id"] == "sha256:fixture-builder-image"
assert manifest["live_build_version"] == "live-build fixture"
assert manifest["debootstrap_version"] == "debootstrap fixture"
assert manifest["podman_version"] == "podman version fixture"
assert manifest["host_kernel"] == "fixture-kernel"
assert manifest["host_os"] == "fixture-linux/1"
assert manifest["rootless"] is True
assert manifest["userns_mode"] == "host"
assert manifest["security_profile"] == "baseline-v1"
assert manifest["host_selinux_state"] == "Enforcing"
assert manifest["selinux_enforcing"] is True
assert manifest["podman_selinux_enabled"] is False
assert manifest["output_sha256"] == hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()
assert manifest["build_result"] == "success"
assert Path(sys.argv[3]).read_bytes() == manifest_path.read_bytes()
assert "ci-unused-token" not in manifest_text
assert sys.argv[4] not in manifest_text
PY
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
[[ -d "$BUILD_JAHITAN_PATH/$today-5" ]]
[[ ! -e "$BUILD_JAHITAN_PATH/$today-5/$image_name.hybrid.iso" ]]
[[ ! -e "$BUILD_JAHITAN_PATH/$today-5/$image_name.build-manifest.json" ]]
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$today-4" ]]
if FAKE_LB_FAIL=1 bash "$scripts_dir/build-iso" --local "$source_dir"; then
  echo 'Error: repeated fake live-build failure was accepted' >&2
  exit 1
fi
[[ -d "$BUILD_JAHITAN_PATH/$today-6" ]]
current_before_concurrent_builds=$(<"$BUILD_JAHITAN_PATH/current/current.txt")
mkdir -p "$test_root/concurrent/barrier" "$test_root/concurrent/work-a" "$test_root/concurrent/work-b"
cp -- "$scripts_dir/build-iso" "$test_root/concurrent/build-a"
cp -- "$scripts_dir/build-iso" "$test_root/concurrent/build-b"
(cd -- "$test_root/concurrent/work-a" && \
  env BUILD_LOCKFILE="$test_root/concurrent/lock-a" \
    FAKE_MKDIR_BARRIER_DIR="$test_root/concurrent/barrier" FAKE_MKDIR_BARRIER_ID=first \
    FAKE_LB_FAIL=1 bash "$test_root/concurrent/build-a" --local "$source_dir") \
  > "$test_root/concurrent/build-a.log" 2>&1 &
concurrent_build_a=$!
(cd -- "$test_root/concurrent/work-b" && \
  env BUILD_LOCKFILE="$test_root/concurrent/lock-b" \
    FAKE_MKDIR_BARRIER_DIR="$test_root/concurrent/barrier" FAKE_MKDIR_BARRIER_ID=second \
    FAKE_LB_FAIL=1 bash "$test_root/concurrent/build-b" --local "$source_dir") \
  > "$test_root/concurrent/build-b.log" 2>&1 &
concurrent_build_b=$!
if wait "$concurrent_build_a"; then
  echo 'Error: concurrent fake live-build failure was accepted for build A' >&2
  exit 1
fi
if wait "$concurrent_build_b"; then
  echo 'Error: concurrent fake live-build failure was accepted for build B' >&2
  exit 1
fi
[[ -e "$test_root/concurrent/barrier/ready" ]]
[[ -d "$BUILD_JAHITAN_PATH/$today-7" && -d "$BUILD_JAHITAN_PATH/$today-8" ]]
[[ $(find "$BUILD_JAHITAN_PATH" -mindepth 1 -maxdepth 1 -type d -name "$today-*" | wc -l) == 7 ]]
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$current_before_concurrent_builds" ]]
[[ -f "$BUILD_LOCKFILE" ]]
[[ ! -s "$BUILD_LOCKFILE" ]]
assert_build_lock_available
[[ ! -e "$TEST_CURL_LOG" ]]
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$(basename -- "$output_dir")" ]]

current_before_prepare_failures=$(<"$BUILD_JAHITAN_PATH/current/current.txt")
for failure_case in common variant auto final; do
  lb_calls_before=$(wc -l < "$TEST_LB_LOG")
  if FAKE_PREPARE_COPY_FAIL="$failure_case" bash "$scripts_dir/build-iso" --local "$source_dir"; then
    echo "Error: build-tree copy failure for $failure_case was accepted" >&2
    exit 1
  fi
  [[ $(wc -l < "$TEST_LB_LOG") == "$lb_calls_before" ]]
  [[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$current_before_prepare_failures" ]]
done
for failure_variable in FAKE_PREPARE_REMOVE_FAIL FAKE_PREPARE_MKDIR_FAIL; do
  lb_calls_before=$(wc -l < "$TEST_LB_LOG")
  if env "$failure_variable=1" bash "$scripts_dir/build-iso" --local "$source_dir"; then
    echo "Error: build-tree $failure_variable failure was accepted" >&2
    exit 1
  fi
  [[ $(wc -l < "$TEST_LB_LOG") == "$lb_calls_before" ]]
  [[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$current_before_prepare_failures" ]]
done

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
[[ ! -e "$BUILD_JAHITAN_PATH/$today-16/$image_name.build-manifest.json" ]]
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
printf 'uncommitted source\n' > "$source_dir/untracked-local"
bash "$scripts_dir/build-iso" --local "$source_dir"
local_dirty_output="$BUILD_JAHITAN_PATH/$(<"$BUILD_JAHITAN_PATH/current/current.txt")"
python3 - "$local_dirty_output/$image_name.build-manifest.json" "$pinned_commit" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
assert manifest["live_source_git_sha"] == sys.argv[2]
assert manifest["live_source_status"] == "dirty"
PY
rm -- "$source_dir/untracked-local"
printf 'branch tip\n' > "$source_dir/config/smoke/variant-marker"
git -C "$source_dir" -c commit.gpgsign=false -c user.name=CI -c user.email=ci@example.invalid commit -qam tip

bash "$scripts_dir/build-iso" --remote "$source_dir" ci-smoke "$pinned_commit"
remote_output="$BUILD_JAHITAN_PATH/$(<"$BUILD_JAHITAN_PATH/current/current.txt")"
remote_clone=$(find tmp -mindepth 1 -maxdepth 1 -type d -print -quit)
[[ -n "$remote_clone" ]]
[[ $(stat -c '%a' tmp) == 700 ]]
[[ $(stat -c '%a' "$remote_clone") == 700 ]]
[[ $(stat -c '%u:%g' tmp) == "$(id -u):$(id -g)" ]]
[[ $(stat -c '%u:%g' "$remote_clone") == "$(id -u):$(id -g)" ]]
[[ -r "$remote_output/$image_name.hybrid.iso" ]]
[[ $(stat -c '%a' "$remote_output/$image_name.hybrid.iso") == "$expected_output_mode" ]]
for stage in bootstrap chroot binary; do
  [[ -n $(find "$cache_root" -path "*/packages.$stage/fixture.deb" -print -quit) ]]
done
[[ $(<.build/config/variant-marker) == 'variant fixture' ]]
[[ $(<"$remote_output/$image_name.build.log.txt") == *'fake lb stdout marker'* ]]
[[ $(<"$remote_output/$image_name.build.log.txt") == *'fake lb stderr marker'* ]]
[[ $(<"$remote_output/$image_name.build.log.txt") != *'stale-log marker'* ]]
[[ $(<.build/config/bootloaders/syslinux_common/splash.svg) != *BUILD_NUMBER* ]]
python3 - "$remote_output/$image_name.build-manifest.json" "$pinned_commit" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
assert manifest["live_source_git_sha"] == sys.argv[2]
assert manifest["live_source_status"] == "clean"
PY

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

lb_calls_before=$(wc -l < "$TEST_LB_LOG")
if FAKE_PREPUBLICATION_MOUNT=1 FAKE_WORKSPACE_UMOUNT_FAIL=1 FAKE_PREPUBLICATION_BUILT_MARKER="$test_root/prepublication-built" TEST_MOUNT_LOG="$test_root/prepublication-mount.log" bash "$scripts_dir/build-iso" --local "$source_dir" > "$test_root/prepublication-unmount.log" 2>&1; then
  echo 'Error: pre-publication workspace unmount failure was accepted' >&2
  exit 1
fi
[[ $(wc -l < "$TEST_LB_LOG") -gt "$lb_calls_before" ]]
[[ $(<"$test_root/prepublication-unmount.log") == *'Failed to unmount workspace mount:'* ]]
[[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$latest_current" ]]

for failure_variable in FAKE_WORKSPACE_UMOUNT_FAIL FAKE_WORKSPACE_REMOVE_FAIL; do
  lb_calls_before=$(wc -l < "$TEST_LB_LOG")
  if env "$failure_variable=1" FAKE_WORKSPACE_MOUNT=1 bash "$scripts_dir/build-iso" --local "$source_dir" > "$test_root/$failure_variable.log" 2>&1; then
    echo "Error: workspace cleanup failure $failure_variable was accepted" >&2
    exit 1
  fi
  [[ $(wc -l < "$TEST_LB_LOG") == "$lb_calls_before" ]]
  [[ $(<"$test_root/$failure_variable.log") == *'Failed to'* ]]
  [[ $(<"$BUILD_JAHITAN_PATH/current/current.txt") == "$latest_current" ]]
done

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
