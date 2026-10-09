# BlankOn image-builder

Orchestration for building BlankOn live-build images. `build-iso` validates the
request, then runs the build through Docker Compose as root under a rootless
Docker daemon. The container enters nested user, PID, and mount namespaces
for live-build, inheriting the daemon's subordinate UID/GID mappings. Host directories
are mounted at their same absolute paths inside the container.

Keep `.env` beside `build-iso`; `build-iso` loads that file from its own
repository directory.

## Requirements

- Linux host with a rootless Docker Engine and the Docker Compose plugin.
- Host-installed `newuidmap` and `newgidmap`, plus at least 65,536 subordinate
  UIDs and GIDs assigned to the user in `/etc/subuid` and `/etc/subgid`.
- Permission to use Docker with a compatible, narrowly scoped runtime policy.
- Writable host directories for `BUILD_LOCAL`, `BUILD_JAHITAN_PATH`, and the
  repository's `workdir`; Docker must be allowed to mount them.
- A Telegram bot token for build notifications. Keep it private.

The project does not install or configure host Docker, start a Docker daemon,
or edit host subordinate-ID files. Configure rootless Docker and its subordinate
ID ranges on the host before building. `build-iso` rejects a selected daemon
unless Docker reports the `rootless` security option; it does not change the
global Docker context or daemon selection.

The host kernel must enable unprivileged user namespaces. Before starting the
builder, `build-iso` asks Docker for its server version and runs a generator
container using that same builder image. The generator fetches the exact Moby
Engine `docker-v<server-version>` default seccomp profile and writes a
full-derived profile to `workdir/seccomp-livebuild.json`. This requires network
access from the generator container to `raw.githubusercontent.com`; generation
fails closed and the builder is not started if the matching profile cannot be
fetched, parsed, or validated. The generated file is ignored and recreated for
each build. The seccomp baseline version therefore tracks the Docker Engine
server, not the Docker CLI or image. Upstream version tags are fetched over
HTTPS but are not pinned to a commit or content digest so this remains portable
across Engine versions. Structural and policy validation detects malformed or
unexpected profile structure, but does not cryptographically authenticate the
tag contents; trusting GitHub and Moby's version tags is a residual supply-chain
risk.

## Experimental rootless Podman path

On the `podman` branch, `tools/podman-build-iso.sh` builds the existing
Dockerfile and runs `/usr/local/bin/build-iso` as container `0:0` in a rootless
Podman engine. Podman's rootless user namespace maps container root to the
invoking host user and provides the subordinate UID/GID mappings needed for
package ownership such as `root:shadow`. The builder receives `CAP_SYS_ADMIN`
only inside that rootless container and uses Podman's default seccomp profile;
Docker and Compose are not used by this path. This remains experimental and
has not been runtime-verified locally.

Host prerequisites are Linux, Podman configured for rootless use, `newuidmap`
and `newgidmap`, at least 65,536 subordinate UIDs and GIDs in `/etc/subuid` and
`/etc/subgid`, and enabled unprivileged user namespaces. Provide the same
required `.env` values described above, plus writable `workdir` and output
directories. Local mode also requires a readable selected source directory.
Run as the user owning the rootless Podman engine:

```sh
bash tools/podman-build-iso.sh --local blankon-live-build
```

The wrapper requires `podman info` to report rootless mode. It never mounts the
builder repository, so the builder repository `.env` is not mounted into the
Podman build container. Local mode mounts only the canonical selected live-build
source directory read-only at its absolute path, plus writable `workdir` and
`BUILD_JAHITAN_PATH`. The canonical output path must not overlap `BUILD_LOCAL`
in either mode, so the writable output mount never exposes the source root.
`BUILD_LOCKFILE` must be a regular, non-symlink file below `BUILD_LOCAL` and
outside the workdir, output path, and local selected source; it is flocked on the
host and is not mounted in the container. Remote mode mounts no source tree; its
clone stays under writable `/workdir`. Podman mode disables Telegram notifications and passes only
a dummy token. Both `--local` and `--remote` are supported. The `podman` branch's
GitHub Actions workflow exercises the minimal local E2E source and uploads the
resulting ISO as an artifact; it does not send notifications or use real
tokens. The existing Docker workflow continues on other push branches and
pull requests, but skips every event on `refs/heads/podman`.

The builder profile permits only the exact `unshare` namespace flags used by
the build and enables `mount`, `umount`, `umount2`, `chroot`, and the newer mount
API calls `open_tree`, `move_mount`, `mount_setattr`, `fsopen`, `fsconfig`,
`fsmount`, and `fspick` without adding capabilities or privileged mode. Kernel
namespace capability checks still gate these calls; the process receives those
capabilities only inside its new user namespace. Seccomp cannot constrain mount
source or target strings or the operations selected through these mount APIs,
which is an explicit residual risk of permitting these syscall families. Hosts
with other LSMs may impose additional policy; AppArmor and SELinux are not
disabled here.

Only the `builder` also uses `systempaths=unconfined`. Docker's default masked
and read-only `/proc` entries prevent the kernel from mounting a fresh procfs
inside the nested user/mount namespace; unconfined system paths allow that
`--mount-proc` step. This turns off Docker's default masked-path and read-only-
path confinement, broadening visibility and writability of system paths inside
the builder. It is a builder-only tradeoff: the custom seccomp filter and
user/mount namespace capability checks remain active. No privileged mode, outer
`CAP_SYS_ADMIN`, or `seccomp=unconfined` is used.

Run `./build-iso` as the rootless Docker daemon's owning host user. Container
root maps to that caller through rootless Docker's outer mapping, so the
`workdir` directory, generated build directories, and outputs remain user-owned,
including after failed builds.
Older date-stamped outputs are not changed. Rootless UID mapping makes an
ownership handoff unnecessary. The nested `unshare` maps all outer user and
group IDs so package owners such as `shadow` remain mapped. Host user-namespace
and ID-map configuration must provide the required ranges.

## Layout and setup

Keep the two repositories as siblings below `BUILD_LOCAL`:

```text
/srv/blankon/
├── blankon-image-builder/
└── blankon-live-build/
```

Clone both repositories, then configure the builder:

```sh
cd /srv/blankon
git clone <builder-repo> blankon-image-builder
git clone <live-build-repo> blankon-live-build
cd blankon-image-builder
cp .env.example .env
```

Edit every required value in `.env`:

- `TELEGRAM_BOT_KEY`: Telegram bot token used for build notifications.
- `BUILD_LOCKFILE`: absolute **host** path to the build lock, preferably under
  `BUILD_LOCAL` so the mounted container sees the same file, such as
  `/srv/blankon/.blankon-build.lock`; it must be writable. The lock prevents
  concurrent builds.
- `BUILD_PUBLISH_URL`: base URL used for published artifacts and their zsync
  metadata.
- `BUILD_JAHITAN_PATH`: absolute, writable **host** directory for build
  output. It is mounted into the container at the same path.
- `BUILD_LOCAL`: absolute, existing, readable **host** directory containing
  local source checkouts. It is mounted into the container at the same path.
- `BUILD_SEND_TELEGRAM`: optional; set to `0` to suppress build notifications,
  for example in CI. Notifications are enabled by default.

`.env` contains a secret and is ignored by Git. Keep it untracked; never paste
its contents into logs or issues.

## Local builds

Run from `blankon-image-builder`:

```sh
./build-iso --local blankon-live-build
./build-iso --local /srv/blankon/blankon-live-build
```

Relative paths resolve beneath `BUILD_LOCAL`. Absolute paths are accepted only
when they remain beneath the canonical `BUILD_LOCAL` directory. The source
checkout must contain `variant`, `config/common`, `config/<variant>`, and
`auto`, where `<variant>` is the value in `variant`. Local builds publish the
same artifacts as remote builds; only the source preparation differs.

## Remote builds

```sh
./build-iso --remote <repo> <branch> [commit]
```

The container clones `<repo>` at `<branch>` into its work area, optionally
checks out `<commit>`, builds the selected revision, and publishes the results
under `BUILD_JAHITAN_PATH`. Omit `commit` to use the branch tip. Both local and
remote builds send their configured Telegram notification.

## State and output

- `workdir/.build`: prepared live-build tree and build logs.
- `workdir/tmp`: remote clones and transient build state.
- `BUILD_JAHITAN_PATH`: local and remote date-stamped output, copied `current`
  output, ISO files, checksums, metadata, and build logs.
- Generated build state is ignored by Git. Preserve `workdir` and the output
  directory when you need logs or artifacts after a run.

Downloaded `.deb` files are reused from `workdir/package-cache` across builds
with the same architecture and `archive.conf` (including different variants).
The chroot and bootstrap filesystem still start fresh. To discard only the
download cache, run `./purge-iso` while no build is running; it leaves
`workdir/.build` and Jahitan outputs intact. A cache purge refuses nested mounts
and unsafe paths.

## Validate without building an ISO

Use the same environment file as `build-iso`:

```sh
export HOST_UID=$(id -u) HOST_GID=$(id -g)
export BUILDER_UID=0 BUILDER_GID=0
docker compose --env-file .env config --quiet
docker compose --env-file .env build
```

These commands validate Compose interpolation and build the Docker image only;
they do not build an ISO or contact Telegram.

CI has separate Build ISO, Cache, and Purge ISO workflows on pushes and pull
requests. Build ISO runs its focused failure-path checks, then builds a small,
real Sinambung ISO in both local and remote mode from
`tests/e2e/live-build`. That source uses the BlankOn archive and signing key,
debootstrap, the live kernel and boot components, and the production ISO format.
It omits the desktop, installer, and firmware package lists and uses faster
compression. The remote job commits the same fixture into a temporary Git
repository and exercises the clone, branch, and commit path through `--remote`.
Build ISO checks that each ISO, checksum, zsync file, and `current` output were
published. The ISOs stay on the temporary runner and are not uploaded as
Actions artifacts. Archive connection timeouts are retried up to twice; other
build failures fail immediately. To build the complete GNOME image in both
modes, run the Build ISO workflow manually with the `gnome` profile; that
profile uses the `blankon-live-build` `variant-gnome` branch on GitHub.
The generated policy starts from the version-tagged Moby Engine default profile
and must be re-reviewed if supported Docker Engine defaults change.
After each small E2E ISO, CI also checks that real downloaded `.deb` files were
saved and that restoring the cache into a fresh workspace preserves their
SHA-256 hashes. It then purges that same runner's real package cache and checks
that the build configuration and published output remain. The separate Cache
and Purge ISO workflows test reuse, invalidation, locking, and unsafe paths
with fast fixtures on their own runners.

CI suppresses Telegram notifications and uses the published base image, which
is now configured for the Sinambung archive. It no longer creates a temporary
Dockerfile or Compose override for archive selection; the production Dockerfile
remains unchanged. Cache checks saving, reuse, `archive.conf` key changes, and
the shared build/purge lock. Purge ISO checks cache removal, symlinks, and mount
refusal. Publication stages a new `current` before replacing it; failed staging
leaves the previous output available.

## Troubleshooting

- **Missing `BUILD_LOCAL`**: copy `.env.example` to `.env`, set an absolute
  existing path, and run from this repository.
- **Local path outside `BUILD_LOCAL`**: move the checkout below that directory
  or use a relative path such as `blankon-live-build`.
- **Rootless Docker required**: configure and select a rootless Docker daemon
  for the caller, then verify it reports `rootless` in `docker info` and that
  `docker compose version` succeeds. Ensure host `newuidmap`/`newgidmap` and
  subordinate UID/GID ranges of at least 65,536 are configured. This project
  does not install/configure host Docker or edit `/etc/subuid` or `/etc/subgid`.
- **Rootless build namespace unavailable**: enable unprivileged user namespaces
  in the host kernel. The project generates a Docker-version-matched seccomp
  profile for the builder and purge services; host kernel, LSM, or runtime policy
  may still independently restrict user, PID, and mount namespaces or live-build
  syscalls. The builder additionally uses `systempaths=unconfined` to permit
  mounting proc in the nested namespace, which disables Docker's default masked
  and read-only system-path restrictions for that service. The custom seccomp
  filter and namespace capability checks remain active, while permitted mount
  syscall arguments remain unconstrained. Standard policies may block these
  operations; do not use privileged mode or `seccomp=unconfined`.
- **Mount or permission errors**: create the configured host directories, make
  them writable for Docker, and check Docker's host-path sharing policy.
- **Stale lock**: confirm no build is running, then remove the lock in the
  environment visible to the container, or let the next run remove it after
  confirming its recorded PID is no longer active.
- **Missing Telegram token**: set `TELEGRAM_BOT_KEY` in `.env`; do not disclose
  the token in command output, logs, or issue reports.
