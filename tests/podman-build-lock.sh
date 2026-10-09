#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$SCRIPT_DIR/build-iso"
workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
BUILD_LOCKFILE="$workdir/build.lock"

exec {owner_fd}>>"$BUILD_LOCKFILE"
flock -n "$owner_fd"
if (BUILDER_CONTAINER=1; BUILD_LOCKFILE="$BUILD_LOCKFILE"; LOCK_ACQUIRED=0; acquire_build_lock); then
  printf 'Error: Advisory lock did not exclude another process.\n' >&2
  exit 1
fi
exec {owner_fd}>&-

(
  exec {owner_fd}>>"$BUILD_LOCKFILE"
  flock -n "$owner_fd"
  kill -KILL "$BASHPID"
) >/dev/null 2>&1 || true
exec {recovery_fd}>"$BUILD_LOCKFILE"
flock -n "$recovery_fd"
exec {recovery_fd}>&-
[[ -f "$BUILD_LOCKFILE" ]]
[[ ! -s "$BUILD_LOCKFILE" ]]

(
  BUILDER_CONTAINER=1
  BUILD_LOCK_HELD=1
  PACKAGE_CACHE_LOCK_HELD=1
  LOCK_ACQUIRED=0
  BUILD_JAHITAN_PATH="$workdir/output"
  BUILD_SEND_TELEGRAM=0
  cache_saved="$workdir/cache-saved"
  build_finalized="$workdir/build-finalized"
  initialize_runtime_state
  prepare_output_directory() { :; }
  set_repository_name() { :; }
  clean_build_workspace() { :; }
  build_image() { :; }
  acquire_build_lock() {
    printf 'Error: Inner build lock must not be acquired.\n' >&2
    return 1
  }
  save_package_cache() { : > "$cache_saved"; }
  finalize_build() { : > "$build_finalized"; }
  run_container_build
  [[ "$LOCK_ACQUIRED" == 0 ]]
  [[ -n "$START" ]]
)
[[ -f "$workdir/cache-saved" ]]
[[ -f "$workdir/build-finalized" ]]

if (
  BUILDER_CONTAINER=1
  BUILD_LOCKFILE="$workdir/failed-build.lock"
  BUILD_JAHITAN_PATH="$workdir/failed-output"
  BUILD_SEND_TELEGRAM=0
  cache_saved="$workdir/failed-cache-saved"
  build_finalized="$workdir/failed-build-finalized"
  initialize_runtime_state
  acquire_package_cache_lock() { return 1; }
  save_package_cache() { : > "$cache_saved"; }
  finalize_build() { : > "$build_finalized"; }
  run_container_build
); then
  printf 'Error: Build continued without the package-cache lock.\n' >&2
  exit 1
fi
[[ ! -e "$workdir/failed-cache-saved" ]]
[[ ! -e "$workdir/failed-build-finalized" ]]

printf 'Advisory build-lock checks passed.\n'
