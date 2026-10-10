#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/builder" "$fixture/source root/checkout" "$fixture/output root" "$fixture/locks"
cp "$repo_dir/build-iso" "$repo_dir/purge-iso" "$repo_dir/Dockerfile" "$fixture/builder/"
mkdir -p "$fixture/builder/tools"
cp "$repo_dir/tools/patch-live-build-sysfs.py" "$fixture/builder/tools/"
cat > "$fixture/bin/podman" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${TELEGRAM_BOT_KEY:-}" != synthetic-fixture-token && "${TELEGRAM_BOT_KEY_FILE:-}" == '' && " $* " != *synthetic-fixture-token* ]] || exit 83
printf '%s\n' "$*" >> "$PODMAN_CALL_LOG"
case "$1" in
  --version) printf 'podman version fixture\n' ;;
  image)
    [[ "$2" == inspect && "$3" == --format && "$4" == '{{.Id}}' && "$5" == blankon-image-builder:podman ]] || exit 2
    printf 'sha256:fixture-builder-image\n'
    ;;
  info) [[ "${TELEGRAM_BOT_KEY:-}" != synthetic-fixture-token && "${TELEGRAM_BOT_KEY_FILE:-}" == '' ]] || exit 80; [[ "${ROOTFUL:-0}" == 1 ]] && printf 'false\n' || printf 'true\n' ;;
  build|run) [[ "${TELEGRAM_BOT_KEY:-}" != synthetic-fixture-token && "${TELEGRAM_BOT_KEY_FILE:-}" == '' ]] || exit 81; printf '%s\n' "$1" >> "$PODMAN_LOG"; printf '%s\n' "$@" >> "$PODMAN_LOG"; [[ "$1" != run || "${RUN_FAIL:-0}" != 1 ]] || exit 42 ;;
  secret) exit 82 ;;
  *) exit 2 ;;
esac
SH
chmod +x "$fixture/bin/podman"
cat > "$fixture/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CURL_ARGUMENTS"
request_config=$(</dev/stdin)
printf '%s\n' "$request_config" >> "$CURL_CONFIG"
[[ "${TELEGRAM_BOT_KEY:-}" != synthetic-fixture-token ]]
[[ "${CURL_FAIL:-0}" != 1 ]]
SH
chmod +x "$fixture/bin/curl"
cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
TELEGRAM_BOT_KEY=synthetic-fixture-token
BUILD_SEND_TELEGRAM=1
EOF
export PODMAN_LOG="$fixture/podman.log" PODMAN_CALL_LOG="$fixture/podman-calls.log" PATH="$fixture/bin:$PATH"
export CURL_ARGUMENTS="$fixture/curl-arguments" CURL_CONFIG="$fixture/curl-config"
export PODMAN_USERNS=keep-id

bash "$fixture/builder/build-iso" --local checkout
[[ $(<"$PODMAN_LOG") == *'--userns=host'* ]]
[[ $(<"$PODMAN_LOG") == *"$fixture/source root/checkout:$fixture/source root/checkout:ro"* ]]
[[ $(<"$PODMAN_LOG") == *'--cap-add=SYS_ADMIN'* ]]
[[ $(<"$PODMAN_LOG") == *'--security-opt'* ]]
[[ $(<"$PODMAN_LOG") == *'unmask=/proc/*'* ]]
[[ $(command grep -c '^--security-opt$' "$PODMAN_LOG") == 1 ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_BUILDER_GIT_SHA=unknown'* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_BUILDER_IMAGE_ID=sha256:fixture-builder-image'* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_PODMAN_VERSION=podman version fixture'* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_HOST_KERNEL='* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_HOST_OS='* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_ROOTLESS=true'* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_USERNS_MODE=host'* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_SECURITY_PROFILE=baseline-v1'* ]]
[[ $(<"$PODMAN_LOG") != *'no-new-privileges'* ]]
[[ $(<"$PODMAN_LOG") != *"$fixture/builder:$fixture/builder"* ]]
[[ $(<"$PODMAN_LOG") != *secret* && $(<"$PODMAN_LOG") != *synthetic-fixture-token* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_SEND_TELEGRAM=0'* ]]
python3 - "$CURL_CONFIG" <<'PY'
import json
import sys
from pathlib import Path

config = Path(sys.argv[1]).read_text()
fields = dict(line.split(" = ", 1) for line in config.splitlines())
url = json.loads(fields["url"])
payload = json.loads(json.loads(fields["data"]))
assert url.endswith("/sendMessage")
assert "synthetic-fixture-token" in url
assert {key: value for key, value in payload.items() if key != "text"} == {
    "chat_id": "-1001067745576",
    "message_thread_id": 51909,
    "parse_mode": "HTML",
    "disable_web_page_preview": True,
    "disable_notification": True,
}
assert "Local build" in payload["text"]
PY
: > "$CURL_CONFIG"
TELEGRAM_BOT_KEY=synthetic-fixture-token bash -c 'source "$1/build-iso"; TELEGRAM_BOT_KEY=synthetic-fixture-token; send_host_telegram $'"'"'quote " slash \\ newline\nnext'"'"'' bash "$fixture/builder"
python3 - "$CURL_CONFIG" <<'PY'
import json
import sys
from pathlib import Path

fields = dict(line.split(" = ", 1) for line in Path(sys.argv[1]).read_text().splitlines())
payload = json.loads(json.loads(fields["data"]))
assert payload["text"] == 'quote &quot; slash \\ newline\nnext'
PY

for obsolete_state in send_telegram RESULT ACTION COMMIT_URL CLEAN_REPO_URL CURRENT_OUTPUT_UPDATED LOCK_ACQUIRED; do
  if [[ $(<"$fixture/builder/build-iso") == *"$obsolete_state"* ]]; then
    printf 'Error: Obsolete build state remains: %s\n' "$obsolete_state" >&2
    exit 1
  fi
done

: > "$PODMAN_LOG"
bash "$fixture/builder/build-iso" --remote https://example.invalid/live.git main
[[ $(<"$PODMAN_LOG") == *'--userns=host'* ]]
[[ $(<"$PODMAN_LOG") != *"$fixture/source root/checkout:"* ]]

: > "$PODMAN_LOG"
BUILD_PODMAN_EXPERIMENT=no-proc-unmask bash "$fixture/builder/build-iso" --local checkout
[[ $(<"$PODMAN_LOG") == *'--cap-add=SYS_ADMIN'* ]]
[[ $(<"$PODMAN_LOG") != *'unmask=/proc/*'* ]]
[[ $(<"$PODMAN_LOG") != *'no-new-privileges'* ]]
[[ $(command grep -c '^--security-opt$' "$PODMAN_LOG" || true) == 0 ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_SECURITY_PROFILE=no-proc-unmask-experiment-v1'* ]]
[[ $(<"$PODMAN_LOG") != *'BUILD_PODMAN_EXPERIMENT='* ]]

: > "$PODMAN_LOG"
BUILD_PODMAN_EXPERIMENT=no-new-privileges bash "$fixture/builder/build-iso" --local checkout
[[ $(<"$PODMAN_LOG") == *'--cap-add=SYS_ADMIN'* ]]
[[ $(<"$PODMAN_LOG") == *'unmask=/proc/*'* ]]
[[ $(<"$PODMAN_LOG") == *'no-new-privileges'* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_SECURITY_PROFILE=no-new-privileges-experiment-v1'* ]]
[[ $(<"$PODMAN_LOG") != *'BUILD_PODMAN_EXPERIMENT='* ]]
[[ $(command grep -c '^--security-opt$' "$PODMAN_LOG") == 2 ]]

: > "$PODMAN_LOG"
: > "$PODMAN_CALL_LOG"
if BUILD_PODMAN_EXPERIMENT=unsupported-experiment bash "$fixture/builder/build-iso" --local checkout >"$fixture/unsupported-output" 2>&1; then
  printf 'Error: Unsupported Podman experiment was accepted.\n' >&2
  exit 1
fi
[[ ! -s "$PODMAN_LOG" ]]
[[ ! -s "$PODMAN_CALL_LOG" ]]
[[ $(<"$fixture/unsupported-output") == *'Unsupported BUILD_PODMAN_EXPERIMENT'* ]]
[[ $(<"$fixture/unsupported-output") != *'unsupported-experiment'* ]]

: > "$PODMAN_LOG"
if RUN_FAIL=1 bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Failed Podman run was accepted.\n' >&2
  exit 1
fi
[[ $(<"$PODMAN_LOG") != *secret* ]]

: > "$PODMAN_LOG"
if CURL_FAIL=1 bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Notification transport failure was accepted.\n' >&2
  exit 1
fi
[[ $(<"$PODMAN_LOG") == *'run'* ]]
[[ $(<"$PODMAN_LOG") != *synthetic-fixture-token* ]]

: > "$CURL_CONFIG"
if RUN_FAIL=1 bash "$fixture/builder/build-iso" --local checkout; then exit 1; fi
python3 - "$CURL_CONFIG" <<'PY'
import json
import sys
from pathlib import Path

fields = dict(line.split(" = ", 1) for line in Path(sys.argv[1]).read_text().splitlines())
payload = json.loads(json.loads(fields["data"]))
assert "status failure" in payload["text"]
PY
if RUN_FAIL=1 CURL_FAIL=1 bash "$fixture/builder/build-iso" --local checkout; then exit 1; else
  [[ "$?" -eq 42 ]]
fi

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF
: > "$CURL_CONFIG"
bash "$fixture/builder/build-iso" --remote repo branch
  [[ ! -s "$CURL_CONFIG" ]]

sed -i "s#BUILD_LOCKFILE=.*#BUILD_LOCKFILE=\"$fixture/source root/.build.lock\"#" "$fixture/builder/.env"
bash "$fixture/builder/build-iso" --local checkout
bash "$fixture/builder/build-iso" --remote repo branch
[[ -f "$fixture/source root/.build.lock" ]]
sed -i "s#BUILD_LOCKFILE=.*#BUILD_LOCKFILE=\"$fixture/locks/build lock\"#" "$fixture/builder/.env"

: > "$PODMAN_LOG"
if ROOTFUL=1 bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Rootful Podman build was accepted.\n' >&2
  exit 1
fi
[[ ! -s "$PODMAN_LOG" ]]

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/missing-parent/build.lock"
BUILD_JAHITAN_PATH="$fixture/not-created-output"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF
rm -rf -- "$fixture/builder/workdir"
if bash "$fixture/builder/build-iso" --remote repo branch; then exit 1; fi
[[ ! -e "$fixture/not-created-output" && ! -e "$fixture/builder/workdir" ]]

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF
for invalid_args in 'bad' '--local' '--local checkout extra' '--remote repo' '--remote repo branch commit extra' '--namespace-build --remote repo branch'; do
  : > "$PODMAN_LOG"
  if bash "$fixture/builder/build-iso" $invalid_args; then exit 1; fi
  [[ ! -s "$PODMAN_LOG" ]]
done

ln -s / "$fixture/root-alias"
sed -i "s#BUILD_LOCAL=.*#BUILD_LOCAL=\"$fixture/root-alias\"#" "$fixture/builder/.env"
if bash "$fixture/builder/build-iso" --remote repo branch; then exit 1; fi
[[ ! -s "$PODMAN_LOG" ]]
sed -i "s#BUILD_LOCAL=.*#BUILD_LOCAL=\"$fixture/source root\"#" "$fixture/builder/.env"
sed -i "s#BUILD_JAHITAN_PATH=.*#BUILD_JAHITAN_PATH=\"$fixture/root-alias\"#" "$fixture/builder/.env"
if bash "$fixture/builder/build-iso" --remote repo branch; then exit 1; fi
[[ ! -s "$PODMAN_LOG" ]]
sed -i "s#BUILD_JAHITAN_PATH=.*#BUILD_JAHITAN_PATH=\"$fixture/output root\"#" "$fixture/builder/.env"
sed -i "s#BUILD_LOCAL=.*#BUILD_LOCAL=\"$fixture\"#" "$fixture/builder/.env"
for refused_source in "$fixture/builder" "$fixture"; do
  if bash "$fixture/builder/build-iso" --local "$refused_source"; then exit 1; fi
done
cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF
ln -s "$fixture/locks" "$fixture/source root/outside-link"
if bash "$fixture/builder/build-iso" --local "$fixture/source root/outside-link"; then exit 1; fi
[[ ! -s "$PODMAN_LOG" ]]

child_output="$fixture/source root/safe-output"
sed -i "s#BUILD_JAHITAN_PATH=.*#BUILD_JAHITAN_PATH=\"$child_output\"#" "$fixture/builder/.env"
bash "$fixture/builder/build-iso" --remote repo branch
bash "$fixture/builder/build-iso" --local checkout
[[ -d "$child_output" ]]

refused_output="$fixture/source root/checkout/not-created/subdir"
sed -i "s#BUILD_JAHITAN_PATH=.*#BUILD_JAHITAN_PATH=\"$refused_output\"#" "$fixture/builder/.env"
: > "$PODMAN_LOG"
if bash "$fixture/builder/build-iso" --local checkout; then exit 1; fi
[[ ! -e "$refused_output" ]]

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/source root/checkout"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF
: > "$PODMAN_LOG"
if bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Output overlapping local source was accepted.\n' >&2
  exit 1
fi
[[ ! -s "$PODMAN_LOG" ]]

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/output root/build.lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF
: > "$PODMAN_LOG"
if bash "$fixture/builder/build-iso" --remote repo branch; then exit 1; fi
[[ ! -s "$PODMAN_LOG" ]]

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF
ln -s "$fixture/output root" "$fixture/locks/unsafe-lock"
sed -i "s#BUILD_LOCKFILE=.*#BUILD_LOCKFILE=\"$fixture/locks/unsafe-lock\"#" "$fixture/builder/.env"
if bash "$fixture/builder/build-iso" --remote https://example.invalid/live.git main; then
  printf 'Error: Symlinked build lock was accepted.\n' >&2
  exit 1
fi
[[ ! -s "$PODMAN_LOG" ]]

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF

exec {held_lock_fd}>>"$fixture/locks/build lock"
flock -n "$held_lock_fd"
: > "$PODMAN_LOG"
if bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Build lock contention was ignored.\n' >&2
  exit 1
fi
[[ ! -s "$PODMAN_LOG" ]]
exec {held_lock_fd}>&-

exec {held_cache_fd}>"$fixture/builder/workdir/.package-cache.lock"
flock -n "$held_cache_fd"
: > "$PODMAN_LOG"
if bash "$fixture/builder/build-iso" --local checkout; then exit 1; fi
if bash "$fixture/builder/purge-iso"; then exit 1; fi
[[ ! -s "$PODMAN_LOG" ]]
exec {held_cache_fd}>&-

: > "$PODMAN_LOG"
if bash "$fixture/builder/purge-iso" unexpected; then exit 1; fi
[[ ! -s "$PODMAN_LOG" ]]
bash "$fixture/builder/purge-iso"
[[ $(<"$PODMAN_LOG") == *'--userns=host'* ]]
[[ $(<"$PODMAN_LOG") == *"$fixture/builder/workdir:/workdir:rw"* ]]
[[ $(<"$PODMAN_LOG") == *"$fixture/builder/workdir/.package-cache.lock:/workdir/.package-cache.lock:ro"* ]]
[[ $(<"$PODMAN_LOG") != *"$fixture/source root"* && $(<"$PODMAN_LOG") != *"$fixture/output root"* && $(<"$PODMAN_LOG") != *synthetic-fixture-token* ]]

: > "$PODMAN_LOG"
if ROOTFUL=1 bash "$fixture/builder/purge-iso"; then
  printf 'Error: Rootful Podman was accepted.\n' >&2
  exit 1
fi
[[ ! -s "$PODMAN_LOG" ]]

printf 'Direct Podman host entrypoint fixtures passed.\n'
