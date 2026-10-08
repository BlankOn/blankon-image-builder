#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"

cat > "$test_root/bin/unshare" <<'EOF'
#!/usr/bin/env bash
expected_options=(--user --map-root-user --mount --pid --fork --mount-proc --propagation private)
for index in "${!expected_options[@]}"; do
  argument_index=$((index + 1))
  [[ "${!argument_index}" == "${expected_options[$index]}" ]] || exit 20
done
[[ $# -ge 9 ]] || exit 21
if [[ "${!#}" == true ]]; then
  [[ $# -eq 9 ]] || exit 22
  printf 'probe\n' >> "$NAMESPACE_TEST_LOG"
  exit 0
fi
[[ "$9" == "$NAMESPACE_TEST_SCRIPT" && "${10}" == --container-build ]] || exit 23
printf 'exec\n' >> "$NAMESPACE_TEST_LOG"
shift 9
bash -c '
  source "$1"
  shift
  run_container_build() {
    [[ "$BUILDER_CONTAINER" == 1 && "$MODE" == --remote && "$REPO" == fixture/repo && "$BRANCH" == fixture-branch ]]
    printf "container-build\n" >> "$NAMESPACE_TEST_LOG"
  }
  main "$@"
' bash "$NAMESPACE_TEST_SCRIPT" "$@"
EOF
chmod +x "$test_root/bin/unshare"

export NAMESPACE_TEST_LOG="$test_root/dispatch.log"
export NAMESPACE_TEST_SCRIPT="$repo_dir/build-iso"
PATH="$test_root/bin:$PATH" bash "$repo_dir/build-iso" --namespace-build --remote fixture/repo fixture-branch

expected_dispatch=$'probe\nexec\ncontainer-build'
[[ "$(<"$NAMESPACE_TEST_LOG")" == "$expected_dispatch" ]]
printf 'Namespace dispatch fixture passed.\n'
