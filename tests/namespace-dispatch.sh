#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"
mkdir -p "$test_root/checkout"
cp "$repo_dir/build-iso" "$test_root/checkout/build-iso"
printf 'BUILD_LOCAL=%s\nBUILD_LOCKFILE=%s\nBUILD_JAHITAN_PATH=%s\nBUILD_PUBLISH_URL=https://fixture\nBUILD_SEND_TELEGRAM=0\n' "$test_root" "$test_root/build.lock" "$test_root/output" > "$test_root/checkout/.env"

cat > "$test_root/bin/podman" <<'EOF'
#!/usr/bin/env bash
exit 90
EOF
cat > "$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 91
EOF
chmod +x "$test_root/bin/podman" "$test_root/bin/curl"

cat > "$test_root/bin/unshare" <<'EOF'
#!/usr/bin/env bash
if [[ "${PODMAN_MODE:-}" == 1 ]]; then
  expected_options=(--mount --pid --fork --mount-proc --propagation private)
else
  expected_options=(--user --map-users all --map-groups all --mount --pid --fork --mount-proc --propagation private)
fi
for index in "${!expected_options[@]}"; do
  argument_index=$((index + 1))
  [[ "${!argument_index}" == "${expected_options[$index]}" ]] || exit 20
done
expected_count=${#expected_options[@]}
[[ $# -ge $((expected_count + 1)) ]] || exit 21
if [[ "${!#}" == true ]]; then
  [[ $# -eq $((expected_count + 1)) ]] || exit 22
  printf 'probe\n' >> "$NAMESPACE_TEST_LOG"
  exit 0
fi
script_index=$((expected_count + 1))
mode_index=$((expected_count + 2))
[[ "${!script_index}" == "$NAMESPACE_TEST_SCRIPT" && "${!mode_index}" == --container-build ]] || exit 23
printf 'exec\n' >> "$NAMESPACE_TEST_LOG"
shift "$((expected_count + 2))"
bash -c '
  source "$NAMESPACE_TEST_SCRIPT"
  run_container_build() {
    [[ "$BUILDER_CONTAINER" == 1 && "$MODE" == --remote && "$REPO" == fixture/repo && "$BRANCH" == fixture-branch ]]
    printf "container-build\n" >> "$NAMESPACE_TEST_LOG"
  }
  main --container-build "$@"
' bash "$@"
EOF
chmod +x "$test_root/bin/unshare"

export NAMESPACE_TEST_LOG="$test_root/dispatch.log"
export NAMESPACE_TEST_SCRIPT="$test_root/checkout/build-iso"
BUILDER_CONTAINER=1 TELEGRAM_BOT_KEY=fixture BUILD_LOCKFILE=/tmp/fixture BUILD_JAHITAN_PATH=/tmp/fixture BUILD_PUBLISH_URL=https://fixture BUILD_LOCAL=/tmp PATH="$test_root/bin:$PATH" bash "$test_root/checkout/build-iso" --namespace-build --remote fixture/repo fixture-branch
podman_log="$test_root/podman-dispatch.log"
PODMAN_MODE=1 BUILDER_CONTAINER=1 NAMESPACE_TEST_LOG="$podman_log" TELEGRAM_BOT_KEY=fixture BUILD_LOCKFILE=/tmp/fixture BUILD_JAHITAN_PATH=/tmp/fixture BUILD_PUBLISH_URL=https://fixture BUILD_LOCAL=/tmp PATH="$test_root/bin:$PATH" bash "$test_root/checkout/build-iso" --namespace-build --remote fixture/repo fixture-branch

expected_dispatch=$'probe\nexec\ncontainer-build'
[[ "$(<"$NAMESPACE_TEST_LOG")" == "$expected_dispatch" ]]
[[ "$(<"$podman_log")" == "$expected_dispatch" ]]
printf 'Namespace dispatch fixture passed.\n'
