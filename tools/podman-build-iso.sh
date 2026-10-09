#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
ENV_FILE=${PODMAN_ENV_FILE:-"$SCRIPT_DIR/.env"}

[[ -f "$ENV_FILE" ]] || { printf 'Error: Environment file not found: %s\n' "$ENV_FILE" >&2; exit 1; }
[[ ( "${1:-}" == --local && $# -eq 2 ) || ( "${1:-}" == --remote && ( $# -eq 3 || $# -eq 4 ) ) ]] || {
  printf 'Usage: %s --local <source-dir> | --remote <repo> <branch> [commit]\n' "$0" >&2
  exit 2
}
command -v podman >/dev/null 2>&1 || { printf 'Error: Podman is required but was not found in PATH.\n' >&2; exit 1; }

rootless=$(podman info --format '{{.Host.Security.Rootless}}') || { printf 'Error: Cannot inspect Podman engine.\n' >&2; exit 1; }
[[ "$rootless" == true ]] || { printf 'Error: A rootless Podman engine is required.\n' >&2; exit 1; }

read_build_values() {
  local line name value seen_variable
  BUILD_LOCAL=
  BUILD_LOCKFILE=
  BUILD_JAHITAN_PATH=
  BUILD_PUBLISH_URL=
  BUILD_LOCAL_SEEN=0
  BUILD_LOCKFILE_SEEN=0
  BUILD_JAHITAN_PATH_SEEN=0
  BUILD_PUBLISH_URL_SEEN=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*(BUILD_LOCAL|BUILD_LOCKFILE|BUILD_JAHITAN_PATH|BUILD_PUBLISH_URL)=(.*)$ ]] || continue
    name=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    seen_variable="${name}_SEEN"
    [[ "${!seen_variable}" != 1 ]] || { printf 'Error: Duplicate %s assignment in .env.\n' "$name" >&2; return 1; }
    printf -v "$seen_variable" '%s' 1
    if [[ "$value" == \"* ]]; then
      [[ "$value" == *\" ]] || { printf 'Error: Invalid quoted %s assignment in .env.\n' "$name" >&2; return 1; }
      value=${value:1:${#value}-2}
    elif [[ "$value" == \'* ]]; then
      [[ "$value" == *\' ]] || { printf 'Error: Invalid quoted %s assignment in .env.\n' "$name" >&2; return 1; }
      value=${value:1:${#value}-2}
    fi
    if [[ "$name" == BUILD_PUBLISH_URL ]]; then
      [[ "$value" =~ ^https?://[A-Za-z0-9._:/-]+$ ]] || { printf 'Error: Unsupported syntax in %s assignment in .env.\n' "$name" >&2; return 1; }
    elif [[ "$name" == BUILD_LOCKFILE ]]; then
      [[ "$value" == /* && "$value" =~ ^/[A-Za-z0-9_./\ -]+$ ]] || { printf 'Error: BUILD_LOCKFILE must be an absolute safe literal path.\n' >&2; return 1; }
    else
      [[ "$value" =~ ^[A-Za-z0-9_./[:space:]-]+$ ]] || { printf 'Error: Unsupported syntax in %s assignment in .env.\n' "$name" >&2; return 1; }
    fi
    printf -v "$name" '%s' "$value"
  done < "$ENV_FILE"
  [[ "$BUILD_JAHITAN_PATH" == /* ]] || { printf 'Error: BUILD_JAHITAN_PATH must be absolute.\n' >&2; return 1; }
  [[ -n "$BUILD_PUBLISH_URL" ]] || { printf 'Error: BUILD_PUBLISH_URL is required.\n' >&2; return 1; }
  [[ "$BUILD_LOCKFILE" == /* ]] || { printf 'Error: BUILD_LOCKFILE is required and must be absolute.\n' >&2; return 1; }
}

read_build_values || exit 1
[[ "$BUILD_JAHITAN_PATH" != / ]] || { printf 'Error: BUILD_JAHITAN_PATH cannot be /.\n' >&2; exit 1; }
SCRIPT_DIR=$(realpath -- "$SCRIPT_DIR")
WORKDIR_PATH="$SCRIPT_DIR/workdir"
[[ ! -L "$WORKDIR_PATH" ]] || { printf 'Error: workdir cannot be a symlink.\n' >&2; exit 1; }
mkdir -p -- "$WORKDIR_PATH"
WORKDIR_PATH=$(realpath -- "$WORKDIR_PATH")
[[ "$WORKDIR_PATH" == "$SCRIPT_DIR/workdir" ]] || { printf 'Error: workdir must resolve inside the builder checkout.\n' >&2; exit 1; }
BUILD_JAHITAN_PATH=$(realpath -m -- "$BUILD_JAHITAN_PATH")
[[ "$BUILD_LOCAL" == /* && -d "$BUILD_LOCAL" && "$BUILD_LOCAL" != / ]] || { printf 'Error: BUILD_LOCAL must be an existing absolute directory other than /.\n' >&2; exit 1; }
BUILD_LOCAL=$(realpath -- "$BUILD_LOCAL")
lock_parent=$(dirname -- "$BUILD_LOCKFILE")
[[ -d "$lock_parent" && ! -L "$BUILD_LOCKFILE" ]] || { printf 'Error: BUILD_LOCKFILE parent must exist and lockfile cannot be a symlink.\n' >&2; exit 1; }
lock_parent=$(realpath -- "$lock_parent")
BUILD_LOCKFILE="$lock_parent/$(basename -- "$BUILD_LOCKFILE")"
[[ ! -e "$BUILD_LOCKFILE" || -f "$BUILD_LOCKFILE" ]] || { printf 'Error: BUILD_LOCKFILE must be a regular file.\n' >&2; exit 1; }
paths_overlap() {
  [[ "$1" == "$2" || "$1" == "$2/"* || "$2" == "$1/"* ]]
}
[[ "$BUILD_LOCKFILE" == "$BUILD_LOCAL/"* ]] || { printf 'Error: BUILD_LOCKFILE must be under BUILD_LOCAL.\n' >&2; exit 1; }
[[ ! -e "$BUILD_LOCKFILE" || -f "$BUILD_LOCKFILE" ]] || { printf 'Error: BUILD_LOCKFILE must be a regular file.\n' >&2; exit 1; }
for protected_path in "$WORKDIR_PATH" "$BUILD_JAHITAN_PATH"; do
  if paths_overlap "$BUILD_LOCKFILE" "$protected_path"; then
    printf 'Error: BUILD_LOCKFILE must not overlap workdir or output path.\n' >&2
    exit 1
  fi
done
source_candidate=
container_build_local=/workdir
if [[ "$1" == --local ]]; then
  [[ "$BUILD_LOCAL" == /* && -d "$BUILD_LOCAL" && "$BUILD_LOCAL" != / ]] || { printf 'Error: BUILD_LOCAL must be an existing absolute directory other than /.\n' >&2; exit 1; }
  BUILD_LOCAL=$(realpath -- "$BUILD_LOCAL")
  source_candidate=$2
  if [[ "$source_candidate" != /* ]]; then source_candidate="$BUILD_LOCAL/$source_candidate"; fi
  [[ -d "$source_candidate" ]] || { printf 'Error: Local source directory not found under BUILD_LOCAL.\n' >&2; exit 2; }
  source_candidate=$(realpath -- "$source_candidate")
  [[ "$source_candidate" == "$BUILD_LOCAL/"* || "$source_candidate" == "$BUILD_LOCAL" ]] || {
    printf 'Error: Local source must stay under BUILD_LOCAL.\n' >&2
    exit 2
  }
  if paths_overlap "$source_candidate" "$SCRIPT_DIR"; then
    printf 'Error: Local source must not overlap the builder checkout.\n' >&2
    exit 2
  fi
  if paths_overlap "$BUILD_LOCKFILE" "$source_candidate"; then
    printf 'Error: BUILD_LOCKFILE must not overlap the local source directory.\n' >&2
    exit 1
  fi
  container_build_local=$source_candidate
fi

for read_only_path in "$SCRIPT_DIR" "$WORKDIR_PATH"; do
  if paths_overlap "$BUILD_JAHITAN_PATH" "$read_only_path"; then
    printf 'Error: Podman output path must be separate from BUILD_LOCAL, the builder checkout, and workdir, and must be user-writable.\n' >&2
    exit 1
  fi
done
if paths_overlap "$BUILD_JAHITAN_PATH" "$BUILD_LOCAL"; then
  printf 'Error: Podman output path must be separate from BUILD_LOCAL.\n' >&2
  exit 1
fi
if [[ -n "$source_candidate" ]] && paths_overlap "$BUILD_JAHITAN_PATH" "$source_candidate"; then
  printf 'Error: Podman output path must be separate from the local source directory.\n' >&2
  exit 1
fi
mkdir -p -- "$BUILD_JAHITAN_PATH"
BUILD_JAHITAN_PATH=$(realpath -- "$BUILD_JAHITAN_PATH")
[[ -d "$BUILD_JAHITAN_PATH" && -w "$BUILD_JAHITAN_PATH" ]] || { printf 'Error: BUILD_JAHITAN_PATH must be writable.\n' >&2; exit 1; }

[[ ! -L "$BUILD_LOCKFILE" ]] || { printf 'Error: BUILD_LOCKFILE cannot be a symlink.\n' >&2; exit 1; }
exec {BUILD_LOCK_FD}>>"$BUILD_LOCKFILE"
flock -n "$BUILD_LOCK_FD" || { printf 'Error: Build is already in progress.\n' >&2; exit 1; }
PACKAGE_CACHE_LOCK="$WORKDIR_PATH/.package-cache.lock"
[[ ! -L "$PACKAGE_CACHE_LOCK" ]] || { printf 'Error: Package cache lock cannot be a symlink.\n' >&2; exit 1; }
if [[ ! -e "$PACKAGE_CACHE_LOCK" ]]; then
  ( set -o noclobber; : > "$PACKAGE_CACHE_LOCK" ) 2>/dev/null || { printf 'Error: Cannot safely create package cache lock.\n' >&2; exit 1; }
fi
[[ -f "$PACKAGE_CACHE_LOCK" && ! -L "$PACKAGE_CACHE_LOCK" ]] || { printf 'Error: Package cache lock must be a regular file.\n' >&2; exit 1; }
exec {PACKAGE_CACHE_LOCK_FD}>>"$PACKAGE_CACHE_LOCK"
flock -n "$PACKAGE_CACHE_LOCK_FD" || { printf 'Error: Package cache is in use by another build or purge.\n' >&2; exit 1; }

podman build --tag blankon-image-builder:podman --file "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
podman_run_arguments=(run --rm --user 0:0 --cap-add=SYS_ADMIN \
  --security-opt 'unmask=/proc/*' \
  --workdir /workdir \
  --volume "$WORKDIR_PATH:/workdir:rw" \
  --volume "$PACKAGE_CACHE_LOCK:/workdir/.package-cache.lock:ro" \
  --volume "$BUILD_JAHITAN_PATH:$BUILD_JAHITAN_PATH:rw" \
  --env BUILDER_CONTAINER=1 \
  --env PODMAN_MODE=1 \
  --env BUILD_SEND_TELEGRAM=0 \
  --env TELEGRAM_BOT_KEY=dummy-token \
  --env "BUILD_LOCAL=$container_build_local" \
  --env "BUILD_JAHITAN_PATH=$BUILD_JAHITAN_PATH" \
  --env "BUILD_PUBLISH_URL=$BUILD_PUBLISH_URL" \
  --env PACKAGE_CACHE_LOCK_HELD=1)
podman_run_arguments+=(--env BUILD_LOCK_HELD=1)
if [[ -n "$source_candidate" ]]; then
  podman_run_arguments+=(--volume "$source_candidate:$source_candidate:ro")
fi
podman_run_arguments+=(blankon-image-builder:podman /usr/local/bin/build-iso --namespace-build)
podman_run_arguments+=("${@:1}")
if [[ "$1" == --local ]]; then
  podman_run_arguments[-1]=$source_candidate
fi
podman "${podman_run_arguments[@]}"
