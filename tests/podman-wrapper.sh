#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/builder" "$fixture/source root/checkout" "$fixture/output root/20200101-1" "$fixture/locks"
mkdir -p "$fixture/output root/$(date '+%Y%m%d')-1"
printf 'published sentinel\n' > "$fixture/output root/sentinel.txt"
printf 'previous release sentinel\n' > "$fixture/output root/20200101-1/sentinel.txt"
printf 'same-day release sentinel\n' > "$fixture/output root/$(date '+%Y%m%d')-1/sentinel.txt"
cp "$repo_dir/build-iso" "$repo_dir/purge-iso" "$repo_dir/Dockerfile" "$fixture/builder/"
cat > "$fixture/bin/podman" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${TELEGRAM_BOT_KEY:-}" != synthetic-fixture-token && "${TELEGRAM_BOT_KEY_FILE:-}" == '' && " $* " != *synthetic-fixture-token* ]] || exit 83
printf '%s\n' "$*" >> "$PODMAN_CALL_LOG"
case "$1" in
  --version) printf 'podman version fixture\n' ;;
  image)
    exit 2
    ;;
  info)
    [[ "${TELEGRAM_BOT_KEY:-}" != synthetic-fixture-token && "${TELEGRAM_BOT_KEY_FILE:-}" == '' ]] || exit 80
    case "${2:-}" in
      --format)
        case "${3:-}" in
          '{{.Host.Security.Rootless}}') [[ "${ROOTFUL:-0}" == 1 ]] && printf 'false\n' || printf 'true\n' ;;
          '{{.Host.Security.SelinuxEnabled}}') printf 'true\n' ;;
          *) exit 89 ;;
        esac
        ;;
      *) exit 89 ;;
    esac
    ;;
  build|run)
    [[ "${TELEGRAM_BOT_KEY:-}" != synthetic-fixture-token && "${TELEGRAM_BOT_KEY_FILE:-}" == '' ]] || exit 81
    printf '%s\n' "$1" >> "$PODMAN_LOG"
    printf '%s\n' "$@" >> "$PODMAN_LOG"
    if [[ "$1" == build ]]; then
      if [[ -n "${BUILD_RELEASE_ID:-}" ]]; then
        [[ "$BUILD_RELEASE_ID" =~ ^[0-9]{8}-[1-9][0-9]*$ ]] || exit 89
        printf '%s\n' "$BUILD_RELEASE_ID" >> "$PODMAN_RELEASE_ID_LOG"
      fi
      [[ "${IMAGE_BUILD_FAIL:-0}" != 1 ]] || exit 43
      iidfile=
      while (($#)); do
        if [[ "$1" == --iidfile ]]; then iidfile=$2; shift 2; else shift; fi
      done
      [[ -n "$iidfile" ]] || exit 85
      if [[ "${RACE_BUILD:-0}" == 1 ]]; then
        printf 'sha256:%064d\n' "${RACE_BUILD_COUNT:-1}" > "$iidfile"
        printf 'sha256:%064d\n' "${RACE_BUILD_COUNT:-1}" > "$RACE_TAG_PATH"
      else
        printf 'sha256:%064d\n' 1 > "$iidfile"
      fi
      printf '%s\n' "$(<"$iidfile")" >> "$PODMAN_BUILD_ID_LOG"
      exit 0
    fi
    if [[ "$1" == run ]]; then
      for argument in "$@"; do
        if [[ "$argument" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
          printf '%s\n' "$argument" >> "$PODMAN_RUN_IMAGE_LOG"
        fi
      done
    fi
    if [[ "${RACE_BUILD:-0}" == 1 && ! -e "$RACE_MARKER" ]]; then
      touch "$RACE_MARKER"
      second_iid="$TMPDIR/second-build.iid"
      RACE_BUILD_COUNT=2 "$0" build --iidfile "$second_iid" --tag blankon-image-builder:podman
      [[ $(<"$second_iid") == "sha256:$(printf '%064d' 2)" ]]
      rm -f -- "$second_iid"
    fi
    if [[ "${RACE_BUILD:-0}" == 1 ]]; then
      [[ $(<"$RACE_TAG_PATH") == "sha256:$(printf '%064d' 2)" ]] || exit 86
      for argument in "$@"; do
        if [[ "$argument" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
          printf '%s\n' "$argument" > "$PODMAN_RUN_IMAGE_LOG"
        fi
      done
      [[ $(<"$PODMAN_RUN_IMAGE_LOG") == "sha256:$(printf '%064d' 1)" ]] || exit 87
    fi
    [[ "${RUN_FAIL:-0}" != 1 ]] || exit 42
    if [[ "$1" == run && " $* " == *':/build-output:rw'* ]]; then
      for argument in "$@"; do
        case "$argument" in
          *:/build-output:rw) stage_root=${argument%:/build-output:rw} ;;
        esac
      done
      [[ -n "${stage_root:-}" ]] || exit 84
      release_id=
      for argument in "$@"; do
        case "$argument" in
          BUILD_RELEASE_ID=*) release_id=${argument#BUILD_RELEASE_ID=} ;;
        esac
      done
      [[ "$release_id" =~ ^[0-9]{8}-[1-9][0-9]*$ ]] || exit 88
      release="$stage_root/${PODMAN_RELEASE_DIR_OVERRIDE:-$release_id}"
      mkdir -p "$release"
      image=blankon-live-image-fixture-amd64
      for suffix in contents files packages hybrid.iso hybrid.iso.zsync build.log.txt tail100.build.log.txt; do printf 'fixture %s\n' "$suffix" > "$release/$image.$suffix"; done
      if [[ "${MALFORMED_STAGE:-0}" != 1 ]]; then
        (cd "$release" && sha256sum "$image.hybrid.iso" > "$image.hybrid.iso.sha256sum")
      fi
      if [[ "${CHECKSUM_CASE:-valid}" == tampered ]]; then
        printf '%064d  %s\n' 0 "$image.hybrid.iso" > "$release/$image.hybrid.iso.sha256sum"
      fi
    fi
    ;;
  secret) exit 82 ;;
  *) exit 2 ;;
esac
SH
chmod +x "$fixture/bin/podman"
cat > "$fixture/bin/getenforce" <<'SH'
#!/usr/bin/env bash
printf 'Disabled\n'
SH
chmod +x "$fixture/bin/getenforce"
cat > "$fixture/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CURL_ARGUMENTS"
request_config=$(</dev/stdin)
printf '%s\n' "$request_config" >> "$CURL_CONFIG"
[[ " $* " == *' --connect-timeout 10 '* && " $* " == *' --max-time 30 '* ]]
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
export PODMAN_LOG="$fixture/podman.log" PODMAN_CALL_LOG="$fixture/podman-calls.log" PODMAN_BUILD_ID_LOG="$fixture/podman-build-ids.log" PODMAN_RUN_IMAGE_LOG="$fixture/podman-run-images.log" PATH="$fixture/bin:$PATH"
export CURL_ARGUMENTS="$fixture/curl-arguments" CURL_CONFIG="$fixture/curl-config"
export PODMAN_RELEASE_ID_LOG="$fixture/podman-release-ids.log"
export PODMAN_USERNS=keep-id
export TMPDIR="$fixture"


BUILD_RELEASE_ID=../../untrusted bash "$fixture/builder/build-iso" --local checkout
[[ $(<"$PODMAN_LOG") == *'--userns=host'* ]]
[[ $(<"$PODMAN_LOG") == *"$fixture/source root/checkout:$fixture/source root/checkout:ro"* ]]
[[ $(<"$PODMAN_LOG") == *'--cap-add=SYS_ADMIN'* ]]
[[ $(<"$PODMAN_LOG") == *'--security-opt'* ]]
[[ $(<"$PODMAN_LOG") == *'unmask=/proc/*'* ]]
[[ $(command grep -c '^--security-opt$' "$PODMAN_LOG") == 1 ]]
[[ $(<"$PODMAN_LOG") == *"$fixture/builder/workdir/.build-stage."* ]]
[[ -z $(command find "$fixture" -maxdepth 1 -name 'blankon-builder-iid.*' -print -quit) ]]
for manifest_metadata in BUILD_BUILDER_GIT_SHA BUILD_BUILDER_IMAGE_ID BUILD_PODMAN_VERSION BUILD_HOST_KERNEL BUILD_HOST_OS BUILD_HOST_SELINUX_STATE BUILD_SELINUX_ENFORCING BUILD_PODMAN_SELINUX_ENABLED BUILD_OCI_BASE_REFERENCE BUILD_ROOTLESS BUILD_USERNS_MODE BUILD_SECURITY_PROFILE; do
  [[ $(<"$PODMAN_LOG") != *"$manifest_metadata="* ]]
done
[[ $(<"$PODMAN_LOG") != *'no-new-privileges'* ]]
[[ $(<"$PODMAN_LOG") != *"$fixture/builder:$fixture/builder"* ]]
[[ $(<"$PODMAN_LOG") != *secret* && $(<"$PODMAN_LOG") != *synthetic-fixture-token* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_SEND_TELEGRAM=0'* ]]
[[ $(<"$PODMAN_CALL_LOG") == *"info --format {{.Host.Security.Rootless}}"* ]]
[[ $(<"$PODMAN_LOG") == *"$fixture/builder/workdir/.build-stage."*'/build-output:rw'* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_JAHITAN_PATH=/build-output'* ]]
[[ $(<"$PODMAN_LOG") == *'BUILD_PUBLISH_STAGING_ONLY=1'* ]]
[[ $(<"$PODMAN_LOG") != *"$fixture/output root:$fixture/output root:rw"* ]]
[[ $(<"$fixture/output root/sentinel.txt") == 'published sentinel' ]]
[[ $(<"$fixture/output root/20200101-1/sentinel.txt") == 'previous release sentinel' ]]
[[ $(<"$fixture/output root/$(date '+%Y%m%d')-1/sentinel.txt") == 'same-day release sentinel' ]]
[[ -f "$fixture/output root/current/current.txt" ]]
[[ $(<"$PODMAN_RELEASE_ID_LOG") == "$(<"$fixture/output root/current/current.txt")" ]]
[[ ! -e "$fixture/output root/current/blankon-live-image-fixture-amd64.build-manifest.json" ]]
promoted_iso="$fixture/output root/$(<"$fixture/output root/current/current.txt")/blankon-live-image-fixture-amd64.hybrid.iso"
(cd "$(dirname -- "$promoted_iso")" && sha256sum -c blankon-live-image-fixture-amd64.hybrid.iso.sha256sum)
[[ -z $(command find "$fixture/builder/workdir" -maxdepth 1 -name '.build-stage.*' -print -quit) ]]
initial_current=$(<"$fixture/output root/current/current.txt")
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
    "chat_id": -1001067745576,
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
[[ $(<"$PODMAN_LOG") != *'BUILD_PODMAN_EXPERIMENT='* ]]

: > "$PODMAN_LOG"
BUILD_PODMAN_EXPERIMENT=no-new-privileges bash "$fixture/builder/build-iso" --local checkout
[[ $(<"$PODMAN_LOG") == *'--cap-add=SYS_ADMIN'* ]]
[[ $(<"$PODMAN_LOG") == *'unmask=/proc/*'* ]]
[[ $(<"$PODMAN_LOG") == *'no-new-privileges'* ]]
[[ $(<"$PODMAN_LOG") != *'BUILD_PODMAN_EXPERIMENT='* ]]
[[ $(command grep -c '^--security-opt$' "$PODMAN_LOG") == 2 ]]
initial_current=$(<"$fixture/output root/current/current.txt")

: > "$PODMAN_LOG"
RACE_MARKER="$fixture/race-marker" RACE_TAG_PATH="$fixture/race-tag" PODMAN_RUN_IMAGE_LOG="$fixture/run-image" RACE_BUILD=1 bash "$fixture/builder/build-iso" --local checkout
[[ $(<"$fixture/race-tag") == "sha256:$(printf '%064d' 2)" ]]
[[ $(<"$fixture/run-image") == "sha256:$(printf '%064d' 1)" ]]
[[ -e "$fixture/race-marker" ]]
[[ -z $(command find "$fixture" -maxdepth 1 -name 'blankon-builder-iid.*' -print -quit) ]]
initial_current=$(<"$fixture/output root/current/current.txt")

make_restricted_path() {
  local destination="$1" missing_program="$2" program resolved
  mkdir -p "$destination"
  for program in bash dirname env realpath find findmnt flock sha256sum stat mktemp cp mv rm rmdir mkdir chmod date basename wc python3 podman curl; do
    [[ "$program" != "$missing_program" ]] || continue
    resolved=$(type -P "$program") || continue
    ln -s "$resolved" "$destination/$program"
  done
}

podman_calls_before_dependency_checks=$(<"$PODMAN_CALL_LOG")
for missing_program in python3 curl findmnt; do
  restricted_path="$fixture/path-without-$missing_program"
  make_restricted_path "$restricted_path" "$missing_program"
  if PATH="$restricted_path" bash "$fixture/builder/build-iso" --local checkout >"$fixture/missing-$missing_program-output" 2>&1; then
    printf 'Error: Build accepted missing host program %s.\n' "$missing_program" >&2
    exit 1
  fi
  [[ $(<"$fixture/missing-$missing_program-output") == *"Missing required host program(s): $missing_program"* ]]
  [[ $(<"$PODMAN_CALL_LOG") == "$podman_calls_before_dependency_checks" ]]
  [[ $(<"$fixture/output root/current/current.txt") == "$initial_current" ]]
  [[ -z $(command find "$fixture/output root" -maxdepth 1 -name '.build-stage.*' -print -quit) ]]
done

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF
restricted_path="$fixture/path-without-curl-disabled"
make_restricted_path "$restricted_path" curl
: > "$PODMAN_LOG"
PATH="$restricted_path" bash "$fixture/builder/build-iso" --local checkout
[[ $(<"$PODMAN_LOG") == *'run'* ]]
[[ $(<"$fixture/output root/current/current.txt") != "$initial_current" ]]
initial_current=$(<"$fixture/output root/current/current.txt")
cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
TELEGRAM_BOT_KEY=synthetic-fixture-token
BUILD_SEND_TELEGRAM=1
EOF

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
failed_release_id=$(python3 -c 'import sys; print(open(sys.argv[1]).read().splitlines()[-1])' "$PODMAN_RELEASE_ID_LOG")
[[ ! -e "$fixture/output root/$failed_release_id" ]]
[[ -z $(command find "$fixture" -maxdepth 1 -name 'blankon-builder-iid.*' -print -quit) ]]
[[ $(<"$fixture/output root/current/current.txt") == "$initial_current" ]]
[[ -z $(command find "$fixture/builder/workdir" -maxdepth 1 -name '.build-stage.*' -print -quit) ]]
if MALFORMED_STAGE=1 bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Malformed staged release was accepted.\n' >&2
  exit 1
fi
[[ $(<"$fixture/output root/current/current.txt") == "$initial_current" ]]
[[ -z $(command find "$fixture/output root" -maxdepth 1 -name '.build-stage.*' -print -quit) ]]
if CHECKSUM_CASE=tampered bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Tampered staged checksum was accepted.\n' >&2
  exit 1
fi
if MALFORMED_STAGE=1 bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Missing staged checksum was accepted.\n' >&2
  exit 1
fi
  [[ $(<"$fixture/output root/current/current.txt") == "$initial_current" ]]
if IMAGE_BUILD_FAIL=1 bash "$fixture/builder/build-iso" --local checkout; then exit 1; fi
failed_release_id=$(python3 -c 'import sys; print(open(sys.argv[1]).read().splitlines()[-1])' "$PODMAN_RELEASE_ID_LOG")
[[ ! -e "$fixture/output root/$failed_release_id" ]]
[[ -z $(command find "$fixture" -maxdepth 1 -name 'blankon-builder-iid.*' -print -quit) ]]
if PODMAN_RELEASE_DIR_OVERRIDE=20000101-777 bash "$fixture/builder/build-iso" --local checkout; then
  printf 'Error: Mismatched staged release directory was accepted.\n' >&2
  exit 1
fi
[[ $(<"$fixture/output root/current/current.txt") == "$initial_current" ]]
[[ $(<"$fixture/output root/20200101-1/sentinel.txt") == 'previous release sentinel' ]]

: > "$PODMAN_LOG"
published_before_notification_failure=$(<"$fixture/output root/current/current.txt")
CURL_FAIL=1 bash "$fixture/builder/build-iso" --local checkout >"$fixture/notification-failure-output" 2>&1
[[ $(<"$PODMAN_LOG") == *'run'* ]]
[[ $(<"$PODMAN_LOG") != *synthetic-fixture-token* ]]
[[ $(<"$fixture/output root/current/current.txt") != "$published_before_notification_failure" ]]
[[ $(<"$fixture/notification-failure-output") == *'Warning: Build notification failed'* ]]

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
EOF
: > "$CURL_CONFIG"
bash "$fixture/builder/build-iso" --remote repo branch
[[ ! -s "$CURL_CONFIG" ]]

cat >> "$fixture/builder/.env" <<'EOF'
TELEGRAM_BOT_KEY=synthetic-fixture-token
BUILD_SEND_TELEGRAM=1
TELEGRAM_CHAT_ID=-123456
TELEGRAM_MESSAGE_THREAD_ID=42
EOF
: > "$CURL_CONFIG"
bash "$fixture/builder/build-iso" --local checkout
python3 - "$CURL_CONFIG" <<'PY'
import json
import sys
from pathlib import Path

fields = dict(line.split(" = ", 1) for line in Path(sys.argv[1]).read_text().splitlines())
payload = json.loads(json.loads(fields["data"]))
assert payload["chat_id"] == -123456
assert type(payload["chat_id"]) is int
assert payload["message_thread_id"] == 42
assert type(payload["message_thread_id"]) is int
PY
for invalid_assignment in 'TELEGRAM_CHAT_ID=0' 'TELEGRAM_CHAT_ID=secret123' 'TELEGRAM_MESSAGE_THREAD_ID=0' 'TELEGRAM_MESSAGE_THREAD_ID=secret123'; do
  sed -i '/^TELEGRAM_CHAT_ID=/d; /^TELEGRAM_MESSAGE_THREAD_ID=/d' "$fixture/builder/.env"
  printf '%s\n' "$invalid_assignment" >> "$fixture/builder/.env"
  if bash "$fixture/builder/build-iso" --local checkout >"$fixture/invalid-notification-id-output" 2>&1; then exit 1; fi
  [[ $(<"$fixture/invalid-notification-id-output") != *synthetic-fixture-token* && $(<"$fixture/invalid-notification-id-output") != *secret123* ]]
done

cat > "$fixture/builder/.env" <<EOF
BUILD_LOCAL="$fixture/source root"
BUILD_LOCKFILE="$fixture/locks/build lock"
BUILD_JAHITAN_PATH="$fixture/output root"
BUILD_PUBLISH_URL=https://example.invalid/iso
BUILD_SEND_TELEGRAM=0
EOF

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
: > "$PODMAN_CALL_LOG"
if bash "$fixture/builder/build-iso" --local checkout; then exit 1; fi
: > "$PODMAN_CALL_LOG"
if bash "$fixture/builder/purge-iso"; then exit 1; fi
[[ ! -s "$PODMAN_LOG" ]]
[[ ! -s "$PODMAN_CALL_LOG" ]]
exec {held_cache_fd}>&-

: > "$PODMAN_LOG"
: > "$PODMAN_BUILD_ID_LOG"
: > "$PODMAN_RUN_IMAGE_LOG"
if bash "$fixture/builder/purge-iso" unexpected; then exit 1; fi
[[ ! -s "$PODMAN_LOG" ]]
mkdir -p "$fixture/builder/workdir/package-cache/key"
rm -f -- "$fixture/builder/.env"
bash "$fixture/builder/purge-iso"
[[ $(<"$PODMAN_BUILD_ID_LOG") == "sha256:$(printf '%064d' 1)" ]]
[[ $(<"$PODMAN_RUN_IMAGE_LOG") == "sha256:$(printf '%064d' 1)" ]]
[[ -z $(command find "$fixture" -maxdepth 1 -name 'blankon-purge-builder-iid.*' -print -quit) ]]
[[ $(<"$PODMAN_LOG") == *'--userns=host'* ]]
[[ $(<"$PODMAN_LOG") == *"$fixture/builder/workdir:/workdir:rw"* ]]
[[ $(<"$PODMAN_LOG") == *"$fixture/builder/workdir/.package-cache.lock:/workdir/.package-cache.lock:ro"* ]]
[[ $(<"$PODMAN_LOG") != *"$fixture/source root"* && $(<"$PODMAN_LOG") != *"$fixture/output root"* && $(<"$PODMAN_LOG") != *synthetic-fixture-token* ]]

: > "$PODMAN_LOG"
: > "$PODMAN_CALL_LOG"
if ROOTFUL=1 bash "$fixture/builder/purge-iso"; then
  printf 'Error: Rootful Podman was accepted.\n' >&2
  exit 1
fi
[[ ! -s "$PODMAN_LOG" ]]
[[ $(<"$PODMAN_CALL_LOG") == 'info --format {{.Host.Security.Rootless}}' ]]

printf 'Direct Podman host entrypoint fixtures passed.\n'
