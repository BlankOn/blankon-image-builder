#!/usr/bin/env bash
set -euo pipefail

source /builder/build-iso
WORKSPACE_DIR=/workdir
ARCH=amd64
cache_key=$(package_cache_key)
cache_dir="$WORKSPACE_DIR/package-cache/$cache_key"
[[ -d "$cache_dir" ]] || {
  echo "Error: package cache was not saved under key $cache_key" >&2
  exit 1
}
saved_count=$(find "$cache_dir" -type f -name '*.deb' | wc -l)
(( saved_count > 0 )) || {
  echo 'Error: package cache contains no downloaded .deb files' >&2
  exit 1
}

# Copy the cache with hard links so the restore sees a fresh workspace without
# duplicating the downloaded packages on the runner's disk.
restore_root=$(mktemp -d "$WORKSPACE_DIR/.cache-restore.XXXXXXXX")
cp -al -- "$WORKSPACE_DIR/package-cache" "$restore_root/package-cache"
WORKSPACE_DIR="$restore_root"
restore_package_cache "$cache_key"

(cd "$restore_root/package-cache/$cache_key" && \
  find . -type f -name '*.deb' -print0 | sort -z | xargs -0 -r sha256sum) \
  > "$restore_root/saved.sha256"
(cd "$restore_root/.build/cache" && \
  find . -type f -name '*.deb' -print0 | sort -z | xargs -0 -r sha256sum) \
  > "$restore_root/restored.sha256"
cmp "$restore_root/saved.sha256" "$restore_root/restored.sha256"
echo "Restored $saved_count real package files from the build cache."
