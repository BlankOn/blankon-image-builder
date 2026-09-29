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
  cp -- "$repo_dir/build-iso" "$repo_dir/purge-iso" "$scripts_dir/"
  printf 'smoke\n' > "$source_dir/variant"
  printf 'archive fixture\n' > "$source_dir/config/common/includes.chroot/etc/blankon/archive.conf"
  printf '<svg>BUILD_NUMBER</svg>\n' > "$source_dir/config/common/bootloaders/syslinux_common/splash.svg"
  printf 'variant fixture\n' > "$source_dir/config/smoke/variant-marker"

  cat > "$test_root/bin/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAKE_CURRENT_COPY_FAIL:-}" == 1 && "$1" == cp && "$2" == -vR ]]; then
  echo 'fake current output copy failure' >&2
  exit 43
fi
if [[ "${FAKE_CURRENT_PROMOTE_FAIL:-}" == 1 && "$1" == mv && "$2" == -- && \
      "$3" == "$BUILD_JAHITAN_PATH/.current.stage."* ]]; then
  echo 'fake current output promotion failure' >&2
  exit 44
fi
exec "$@"
EOF
  cat > "$test_root/bin/mount" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$test_root/bin/umount" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> "$TEST_CURL_LOG"
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
case "$1" in
  clean|config) exit 0 ;;
  build)
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
  chmod +x "$test_root/bin/"*

  export PATH="$test_root/bin:$PATH"
  export BUILDER_CONTAINER=1
  export TELEGRAM_BOT_KEY=ci-unused-token
  export BUILD_LOCKFILE="$test_root/build.lock"
  export BUILD_JAHITAN_PATH="$test_root/output"
  export BUILD_PUBLISH_URL=https://example.invalid/iso
  export BUILD_LOCAL="$test_root/local"
  HOST_UID=$(id -u)
  HOST_GID=$(id -g)
  export HOST_UID HOST_GID
  export TEST_CURL_LOG="$test_root/curl.log"
  export TEST_CACHE_LOG="$test_root/cache.log"

  cd -- "$test_root/workdir"
}
