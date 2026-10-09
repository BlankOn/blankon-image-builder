#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

mkdir -p "$fixture/source root/checkout" "$fixture/builder repo/tools" "$fixture/output root" "$fixture/bin"
cp "$SCRIPT_DIR/tools/podman-build-iso.sh" "$fixture/builder repo/tools/podman-build-iso.sh"
cat > "$fixture/bin/podman" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  info) printf 'true\n' ;;
  build) ;;
  run) printf '%s\n' "$@" > "$PODMAN_ARGS" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$fixture/bin/podman"

printf 'BUILD_LOCAL="%s"\n' "$fixture/source root" > "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH="%s"\n' "$fixture/output root" >> "$fixture/synthetic.env"
printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE="%s"\n' "$fixture/source root/build-lock" >> "$fixture/synthetic.env"
printf 'TELEGRAM_BOT_KEY=$(touch %s)\n' "$fixture/host-env-executed" >> "$fixture/synthetic.env"
PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/podman-args" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local 'checkout'
[[ ! -e "$fixture/host-env-executed" ]]
mapfile -t podman_arguments < "$fixture/podman-args"
[[ "${podman_arguments[-1]}" == "$fixture/source root/checkout" ]]
[[ " ${podman_arguments[*]} " == *" $fixture/source root/checkout:$fixture/source root/checkout:ro "* ]]
[[ " ${podman_arguments[*]} " != *" $fixture/source root:$fixture/source root "* ]]
[[ " ${podman_arguments[*]} " != *" $fixture/builder repo "* ]]
[[ " ${podman_arguments[*]} " == *" BUILD_LOCAL=$fixture/source root/checkout "* ]]
[[ " ${podman_arguments[*]} " == *" TELEGRAM_BOT_KEY=dummy-token "* ]]
[[ " ${podman_arguments[*]} " == *" /usr/local/bin/build-iso "* ]]
[[ " ${podman_arguments[*]} " == *" $fixture/builder repo/workdir/.package-cache.lock:/workdir/.package-cache.lock:ro "* ]]
[[ " ${podman_arguments[*]} " != *" --internal-podman-build-lockfile "* ]]
[[ " ${podman_arguments[*]} " == *" BUILD_LOCK_HELD=1 "* ]]
[[ -f "$fixture/source root/build-lock" ]]
[[ " ${podman_arguments[*]} " != *" $fixture/source root/checkout/workdir/.podman-build.lock:"* ]]
[[ " ${podman_arguments[*]} " != *" $fixture/source root/build-lock:$fixture/source root/build-lock:rw "* ]]
[[ " ${podman_arguments[*]} " == *" $fixture/output root:$fixture/output root:rw "* ]]

rm -f -- "$fixture/builder repo/workdir/.package-cache.lock"
ln -s "$fixture/output root" "$fixture/builder repo/workdir/.package-cache.lock"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/symlink-package-cache-lock-ran" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
  printf 'Error: Symlinked package cache lock was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$fixture/symlink-package-cache-lock-ran" ]]
rm -f -- "$fixture/builder repo/workdir/.package-cache.lock"

ln -s "$fixture/output root" "$fixture/source root/symlink-lock"
printf 'BUILD_LOCAL="%s"\n' "$fixture/source root" > "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH="%s"\n' "$fixture/output root" >> "$fixture/synthetic.env"
printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE="%s/symlink-lock"\n' "$fixture/source root" >> "$fixture/synthetic.env"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/should-not-run" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
  printf 'Error: Symlinked build lockfile was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$fixture/should-not-run" ]]

for root_assignment in BUILD_LOCAL BUILD_JAHITAN_PATH; do
  printf 'BUILD_LOCAL="%s"\n' "$fixture/source root" > "$fixture/synthetic.env"
  printf 'BUILD_JAHITAN_PATH="%s"\n' "$fixture/output root" >> "$fixture/synthetic.env"
  printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
  printf 'BUILD_LOCKFILE="%s"\n' "$fixture/source root/build lock.lock" >> "$fixture/synthetic.env"
  printf '%s=/\n' "$root_assignment" >> "$fixture/synthetic.env"
  if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/podman-args" \
    PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
    printf 'Error: Root %s assignment was accepted.\n' "$root_assignment" >&2
    exit 1
  fi
done

printf 'BUILD_LOCAL="%s"\n' "$fixture/source root" > "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH="%s"\n' "$fixture/source root" >> "$fixture/synthetic.env"
printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE="%s"\n' "$fixture/source root/build lock.lock" >> "$fixture/synthetic.env"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/podman-args" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
  printf 'Error: Writable path overlapping the source checkout was accepted.\n' >&2
  exit 1
fi

for overlapping_output in "$fixture/source root" "$fixture" "$fixture/source root/checkout" "$fixture/builder repo" "$fixture/builder repo/workdir"; do
  printf 'BUILD_LOCAL="%s"\n' "$fixture/source root" > "$fixture/synthetic.env"
  printf 'BUILD_JAHITAN_PATH="%s"\n' "$overlapping_output" >> "$fixture/synthetic.env"
  printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
  printf 'BUILD_LOCKFILE="%s/build lock.lock"\n' "$fixture/source root" >> "$fixture/synthetic.env"
  if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/podman-args" \
    PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
    printf 'Error: Overlapping output path was accepted: %s\n' "$overlapping_output" >&2
    exit 1
  fi
done

printf 'BUILD_LOCAL="%s"\n' "$fixture/source root" > "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH="%s/source root/checkout"\n' "$fixture" >> "$fixture/synthetic.env"
printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE="%s/build lock.lock"\n' "$fixture/source root" >> "$fixture/synthetic.env"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/should-not-run" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --remote https://example.invalid/live.git main; then
  printf 'Error: Remote output overlapping BUILD_LOCAL was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$fixture/should-not-run" ]]

rm -rf -- "$fixture/builder repo/workdir"
mkdir -p "$fixture/external-workdir"
ln -s "$fixture/external-workdir" "$fixture/builder repo/workdir"
printf 'BUILD_LOCAL="%s"\n' "$fixture/source root" > "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH="%s"\n' "$fixture/output root" >> "$fixture/synthetic.env"
printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE="%s/build lock.lock"\n' "$fixture/source root" >> "$fixture/synthetic.env"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/should-not-run" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
  printf 'Error: Symlinked workdir was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$fixture/should-not-run" ]]

printf 'BUILD_LOCAL=%s\n' "$fixture/source root" > "$fixture/synthetic.env"
printf 'BUILD_LOCAL=%s\n' "$fixture/source root" >> "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH=%s\n' "$fixture/output root" >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE=%s\n' "$fixture/source root/build lock.lock" >> "$fixture/synthetic.env"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/podman-args" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
  printf 'Error: Duplicate path assignment was accepted.\n' >&2
  exit 1
fi

printf 'BUILD_LOCAL="$(touch %s)"\n' "$fixture/shell-syntax-executed" > "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH="%s"\n' "$fixture/output root" >> "$fixture/synthetic.env"
printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE="%s"\n' "$fixture/source root/build lock.lock" >> "$fixture/synthetic.env"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/podman-args" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
  printf 'Error: Shell expansion was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$fixture/shell-syntax-executed" ]]

printf 'BUILD_LOCAL="%s"\n' "$fixture/source root" > "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH="%s"\n' "$fixture/output root" >> "$fixture/synthetic.env"
printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE="%s/checkout/build-lock"\n' "$fixture/source root" >> "$fixture/synthetic.env"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/should-not-run" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --local checkout; then
  printf 'Error: Build lock overlapping the local source was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$fixture/should-not-run" ]]

rm -f -- "$fixture/builder repo/workdir"
mkdir -p "$fixture/builder repo/workdir"
printf 'BUILD_LOCAL="%s/builder repo"\n' "$fixture" > "$fixture/synthetic.env"
printf 'BUILD_JAHITAN_PATH="%s"\n' "$fixture/output root" >> "$fixture/synthetic.env"
printf 'BUILD_PUBLISH_URL=https://example.invalid\n' >> "$fixture/synthetic.env"
printf 'BUILD_LOCKFILE="%s/builder repo/workdir/build-lock"\n' "$fixture" >> "$fixture/synthetic.env"
if PODMAN_ENV_FILE="$fixture/synthetic.env" PODMAN_ARGS="$fixture/should-not-run" \
  PATH="$fixture/bin:$PATH" bash "$fixture/builder repo/tools/podman-build-iso.sh" --remote https://example.invalid/live.git main; then
  printf 'Error: Workdir build lock was accepted.\n' >&2
  exit 1
fi
[[ ! -e "$fixture/should-not-run" ]]

printf 'Podman wrapper parser checks passed.\n'
