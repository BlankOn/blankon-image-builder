#!/usr/bin/env bash

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

fixture_init() {
  local temp_parent
  test_root=$(mktemp -d)
  temp_parent=$(realpath -- "${TMPDIR:-/tmp}")
  test_root=$(realpath -- "$test_root")
  [[ "$test_root" == "$temp_parent/"* && -d "$test_root" ]] || {
    echo 'Error: Temporary test directory is outside the expected root' >&2
    exit 1
  }
  trap 'rm -rf -- "$test_root"' EXIT

  scripts_dir="$test_root/scripts"
  source_dir="$test_root/local/source"
  cache_root="$test_root/workdir/package-cache"
  mkdir -p "$test_root/bin" "$scripts_dir" "$test_root/workdir" \
    "$source_dir/config/common/includes.chroot/etc/blankon" \
    "$source_dir/config/common/bootloaders/syslinux_common" \
    "$source_dir/config/smoke" "$source_dir/auto"
  cp -- "$repo_dir/build-iso" "$repo_dir/purge-iso" "$repo_dir/Dockerfile" "$scripts_dir/"
  printf 'smoke\n' > "$source_dir/variant"
  printf 'archive fixture\n' > "$source_dir/config/common/includes.chroot/etc/blankon/archive.conf"
  printf '<svg>BUILD_NUMBER</svg>\n' > "$source_dir/config/common/bootloaders/syslinux_common/splash.svg"
  printf 'variant fixture\n' > "$source_dir/config/smoke/variant-marker"
  printf 'auto fixture\n' > "$source_dir/auto/.fixture"
  printf '#!/bin/sh\nexit 0\n' > "$source_dir/auto/fixture-script"
  chmod 755 "$source_dir/auto/fixture-script"

  cat > "$test_root/bin/cp" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAKE_CURRENT_COPY_FAIL:-}" == 1 && "$1" == -vR ]]; then
  echo 'fake current output copy failure' >&2
  exit 43
fi
case "${FAKE_PREPARE_COPY_FAIL:-}" in
  common) [[ "$*" == *'/config/common/.'* ]] && exit 45 ;;
  variant) [[ "$*" == *'/config/smoke/.'* ]] && exit 45 ;;
  auto) [[ "$*" == *'/auto .build/auto'* ]] && exit 45 ;;
  final) [[ "$*" == *'/variant .build/variant'* ]] && exit 45 ;;
esac
exec /bin/cp "$@"
EOF
  cat > "$test_root/bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAKE_WORKSPACE_REMOVE_FAIL:-}" == 1 && "$*" == *'./chroot ./local ./cache ./tmp'* ]]; then
  echo 'fake workspace removal failure' >&2
  exit 48
fi
if [[ "${FAKE_PREPARE_REMOVE_FAIL:-}" == 1 && "$*" == *'.build'* ]]; then
  exit 46
fi
exec /bin/rm "$@"
EOF
  cat > "$test_root/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAKE_PREPARE_MKDIR_FAIL:-}" == 1 && "$*" == *'.build/config'* ]]; then
  exit 47
fi
if [[ -n "${FAKE_MKDIR_BARRIER_DIR:-}" && "$1" == "$BUILD_JAHITAN_PATH/"????????-* ]]; then
  barrier_marker="$FAKE_MKDIR_BARRIER_DIR/$FAKE_MKDIR_BARRIER_ID"
  if [[ ! -e "$barrier_marker" ]]; then
    : > "$barrier_marker"
    barrier_deadline=$((SECONDS + 10))
    until [[ -e "$FAKE_MKDIR_BARRIER_DIR/ready" ]]; do
      if ((SECONDS >= barrier_deadline)); then
        exit 124
      fi
      if [[ -e "$FAKE_MKDIR_BARRIER_DIR/first" && -e "$FAKE_MKDIR_BARRIER_DIR/second" ]]; then
        : > "$FAKE_MKDIR_BARRIER_DIR/ready"
        break
      fi
      sleep 0.02
    done
  fi
fi
exec /bin/mkdir "$@"
EOF
  cat > "$test_root/bin/mv" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAKE_CURRENT_PROMOTE_FAIL:-}" == 1 && "$1" == -- && \
      "$2" == "$BUILD_JAHITAN_PATH/.current.stage."* ]]; then
  echo 'fake current output promotion failure' >&2
  exit 44
fi
exec /bin/mv "$@"
EOF
  cat > "$test_root/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
emit_mounts() {
  python3 -c 'import json, sys; print(json.dumps({"filesystems": [{"target": target} for target in sys.argv[1:]]}))' "$@"
}
if [[ "${FAKE_PREPUBLICATION_MOUNT:-}" == 1 ]]; then
  if [[ " $* " == *' --json '* ]]; then
    mount_count=0
    [[ ! -f "$TEST_MOUNT_LOG" ]] || mount_count=$(<"$TEST_MOUNT_LOG")
    mount_count=$((mount_count + 1))
    printf '%s\n' "$mount_count" > "$TEST_MOUNT_LOG"
    if ((mount_count == 2)); then
      emit_mounts "$WORKSPACE_DIR/.build/chroot/proc"
      exit
    fi
    emit_mounts
    exit
  fi
fi
if [[ "${FAKE_WORKSPACE_MOUNT:-}" == 1 ]]; then
  if [[ " $* " == *' --json '* ]]; then
    emit_mounts "$WORKSPACE_DIR/.build/chroot/proc"
  else
    printf '%s\n' "$WORKSPACE_DIR/.build/chroot/proc"
  fi
elif [[ " $* " == *' --json '* ]]; then
  emit_mounts
else
  exit 0
fi
EOF
  cat > "$test_root/bin/umount" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAKE_WORKSPACE_UMOUNT_FAIL:-}" == 1 ]]; then
  echo 'fake busy mount' >&2
  exit 32
fi
exit 0
EOF
  cat > "$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
request_config=$(</dev/stdin)
printf 'called\n' >> "$TEST_CURL_LOG"
printf '%s\n' "$request_config" >> "$TEST_CURL_CONFIG"
[[ " ${*} " == *' --config - '* && " ${*} " == *' --silent '* && " ${*} " == *' --fail '* ]]
[[ "${TELEGRAM_BOT_KEY:-}" != ci-unused-token ]]
EOF
  cat > "$test_root/bin/podman" <<'EOF'
#!/usr/bin/env bash
exit 97
EOF
  cat > "$test_root/bin/docker" <<'EOF'
#!/usr/bin/env bash
exit 98
EOF
  cat > "$test_root/bin/unshare" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
  cat > "$test_root/bin/sudo" <<'EOF'
#!/usr/bin/env bash
exit 100
EOF
  cat > "$test_root/bin/zsyncmake" <<'EOF'
#!/usr/bin/env bash
while (($#)); do
  case "$1" in
    -o)
      output=$2
      shift 2
      ;;
    *) shift ;;
  esac
done
printf 'zsync fixture\n' > "$output"
EOF
  cat > "$test_root/bin/lb" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then printf 'live-build fixture\n'; exit 0; fi
printf '%s\n' "$*" >> "$TEST_LB_LOG"
case "$1" in
  clean) exit 0 ;;
  config)
    printf 'stale-log marker\n' > ../"blankon-live-image-$(<variant)-amd64.build.log"
    exit 0
    ;;
  build)
    [[ -z "${FAKE_PREPUBLICATION_BUILT_MARKER:-}" ]] || : > "$FAKE_PREPUBLICATION_BUILT_MARKER"
    printf 'fake lb stdout marker\n'
    printf 'fake lb stderr marker\n' >&2
    case "${FAKE_LB_EXPECT_CACHE:-ignore}" in
      present|absent)
        for stage in bootstrap chroot binary; do
          cache_file="cache/packages.$stage/fixture.deb"
          if [[ "$FAKE_LB_EXPECT_CACHE" == present ]]; then
            [[ -f "$cache_file" && "$(<"$cache_file")" == 'cached package' ]] || {
              echo "Error: cached $stage package was not restored" >&2
              exit 40
            }
          else
            [[ ! -e "$cache_file" ]] || {
              echo "Error: unexpected cached $stage package was restored" >&2
              exit 41
            }
          fi
        done
        printf '%s\n' "$FAKE_LB_EXPECT_CACHE" >> "$TEST_CACHE_LOG"
        ;;
      ignore) ;;
      *) exit 2 ;;
    esac
    if [[ "${FAKE_LB_FAIL:-}" == 1 ]]; then
      printf 'fake live-build failure\n' >&2
      exit 42
    fi
    image_name="blankon-live-image-$(<variant)-amd64"
    for suffix in contents files packages hybrid.iso; do
      printf 'fixture %s\n' "$suffix" > "$image_name.$suffix"
    done
    for stage in bootstrap chroot binary; do
      mkdir -p "cache/packages.$stage"
      printf 'cached package\n' > "cache/packages.$stage/fixture.deb"
    done
    printf 'P: Build completed successfully\n'
    ;;
  *) exit 2 ;;
esac
EOF
  cat > "$test_root/bin/debootstrap" <<'EOF'
#!/usr/bin/env bash
printf 'debootstrap fixture\n'
EOF
  cat > "$test_root/bin/getenforce" <<'EOF'
#!/usr/bin/env bash
printf 'Enforcing\n'
EOF
  chmod +x "$test_root/bin/"*

  export PATH="$test_root/bin:$PATH"
  export BUILDER_CONTAINER=1
  export TELEGRAM_BOT_KEY=ci-unused-token
  export BUILD_LOCKFILE="$test_root/build.lock"
  export BUILD_JAHITAN_PATH="$test_root/output"
  export BUILD_PUBLISH_URL=https://example.invalid/iso
  export BUILD_LOCAL="$test_root/local"
  export BUILD_BUILDER_GIT_SHA=fixture-builder-sha
  export BUILD_BUILDER_IMAGE_ID=sha256:fixture-builder-image
  export BUILD_PODMAN_VERSION='podman version fixture'
  export BUILD_HOST_KERNEL=fixture-kernel
  export BUILD_HOST_OS=fixture-linux/1
  export BUILD_ROOTLESS=true
  export BUILD_USERNS_MODE=host
  export BUILD_SECURITY_PROFILE=baseline-v1
  export BUILD_OCI_BASE_REFERENCE=ghcr.io/blankon/blankon-nightly@sha256:76b7e3b7feba1221d649481673af63bf65c310361916d574c6fe1cb90a02fea5
  export BUILD_HOST_SELINUX_STATE=Enforcing BUILD_SELINUX_ENFORCING=true BUILD_PODMAN_SELINUX_ENABLED=false
  HOST_UID=$(id -u)
  HOST_GID=$(id -g)
  export HOST_UID HOST_GID
  export TEST_CURL_LOG="$test_root/curl.log"
  export TEST_CURL_CONFIG="$test_root/curl-config.log"
  export TEST_CACHE_LOG="$test_root/cache.log"
  export TEST_LB_LOG="$test_root/lb.log"
  export TEST_MOUNT_LOG="$test_root/mount.log"

  export WORKSPACE_DIR="$test_root/workdir"
  cd -- "$test_root/workdir"
}
