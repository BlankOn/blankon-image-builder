# BlankOn image-builder

`build-iso` and `purge-iso` are the host runtime entrypoints. They run the
builder directly through rootless Podman; Docker and Compose are not runtime
dependencies. Keep `.env` beside `build-iso`; it is loaded from this repository.

## Requirements and setup

- Linux with rootless Podman and enabled unprivileged user namespaces.
- `newuidmap` and `newgidmap`, with at least 65,536 subordinate UIDs and GIDs
  assigned to the user in `/etc/subuid` and `/etc/subgid`.
- Host Bash, coreutils, util-linux, and, for notifications, Python 3 and curl.
- Writable `workdir` and output directories and, for local builds, readable
  source beneath `BUILD_LOCAL`.
- A Telegram bot token if build notifications are wanted.

The project does not install or configure host Podman, edit subordinate-ID
files, or change global container configuration. Run as the user owning the
rootless Podman engine. The entrypoints check that Podman reports rootless mode.
Confirm with `podman info --format '{{.Host.Security.Rootless}}'`.

Keep the builder and live-build repositories as siblings beneath `BUILD_LOCAL`:

```text
/srv/blankon/
├── blankon-image-builder/
└── blankon-live-build/
```

Clone them and configure the builder:

```sh
cd /srv/blankon
git clone <builder-repo> blankon-image-builder
git clone <live-build-repo> blankon-live-build
cd blankon-image-builder
cp .env.example .env
```

Set every required value using literal `KEY=value` lines, without shell
expansion or command substitution:

- `TELEGRAM_BOT_KEY`: Telegram token. Keep `.env` private and untracked.
- `BUILD_LOCKFILE`: absolute host path to the build lock. Its
  parent must exist; it cannot be a symlink and, if present, must be a regular
  file. It must not overlap the workdir, output, or selected local source. It
  may be outside `BUILD_LOCAL` and is flocked on the host, never mounted in the
  container.
- `BUILD_PUBLISH_URL`: base URL for published artifacts and zsync metadata.
- `BUILD_JAHITAN_PATH`: absolute writable host output directory. It must not
  equal or contain `BUILD_LOCAL`, be `/`, or overlap the builder checkout or
  workdir. It may be a child of `BUILD_LOCAL` (for example,
  `/srv/blankon/jahitan`) when separate from the selected source. The selected
  local source cannot overlap the output.
- `BUILD_LOCAL`: absolute existing host directory containing local checkouts.
- `BUILD_SEND_TELEGRAM`: optional; notifications are enabled by default. Set
  to `0` to suppress them, including in CI.

The entrypoints mount only the validated selected local source read-only,
`workdir` and output writable, and the package-cache lock read-only. Remote
mode does not mount a source tree; the clone stays under `workdir`. The builder
repository, `.env`, and Telegram token are not mounted or passed to the
container; it receives `BUILD_SEND_TELEGRAM=0`. After Podman exits, the host
entrypoint may send the notification using the host-held token. Path overlap,
symlink, lock type, and nested-mount checks protect these boundaries. Container
root maps to the invoking host user through rootless Podman's outer user
namespace, so generated directories and outputs should remain owned by the
invoking UID/GID, including after failed builds.

## Local and remote builds

Run local builds from the builder checkout:

```sh
./build-iso --local blankon-live-build
./build-iso --local /srv/blankon/blankon-live-build
```

Relative paths resolve beneath `BUILD_LOCAL`; absolute paths must remain
beneath its canonical directory. The source must contain `variant`,
`config/common`, `config/<variant>`, and `auto`.

Remote builds clone a repository branch and optionally check out a commit:

```sh
./build-iso --remote <repo> <branch> [commit]
```

Both modes publish local and remote date-stamped outputs and send the configured
Telegram notification unless `BUILD_SEND_TELEGRAM=0`. The container always
receives `BUILD_SEND_TELEGRAM=0` and no Telegram token, environment file, or
Podman secret. The host entrypoint parses the token from the protected `.env`
and, after the container exits, sends the optional notification using curl stdin
configuration and a JSON payload. Keep the host `.env` restricted and do not
include it in logs or artifacts.

## Runtime security boundaries

The builder runs as container `0:0` with rootless user mapping, its narrowly
required `CAP_SYS_ADMIN`, default Podman seccomp, and builder-only
`unmask=/proc/*` to permit the nested live-build proc mount. It does not use
privileged mode, disable seccomp, unmask other system paths, or request host
`CAP_SYS_ADMIN`. The narrow capability and proc unmask are still meaningful
risks: live-build and mount behavior inside the user namespace is not a strong
boundary against a malicious build source or a vulnerable kernel. Host kernel,
LSM, and runtime policy may impose additional restrictions. Do not weaken these
defaults to work around a host policy failure.

## State, cache, and purge

- `workdir/.build`: prepared live-build tree and logs.
- `workdir/tmp`: remote clones and transient build state.
- `workdir/package-cache`: reusable downloaded packages.
- `BUILD_JAHITAN_PATH`: date-stamped outputs, `current`, ISO files, checksums,
  metadata, and build logs.

Downloaded `.deb` files are reused across builds with the same architecture and
`archive.conf`; the chroot and bootstrap filesystem start fresh. To discard
only the package download cache, run `./purge-iso` while no build is running.
It shares `workdir/.package-cache.lock` with builds and leaves `workdir/.build` and published
outputs intact. Purge refuses unsafe paths and nested mounts.

## CI and validation

Fixture boundaries and CI coverage are indexed in [tests/TESTING_MAP.md](tests/TESTING_MAP.md).

The Build ISO workflow installs rootless Podman and its subordinate-ID helpers,
proves rootless mode, runs the seccomp, namespace, mount-cleanup, build,
cache, purge, Podman wrapper/lock, and sysfs-patch fixture suites, then builds the minimal
`tests/e2e/live-build` ISO through the normal entrypoints in both local and
remote mode. Remote mode stages a temporary bare Git repository under `workdir`
so the container can clone `file:///workdir/ci-remote.git` without a source bind,
and exercises the branch/commit checkout path. CI uses a synthetic token and disables Telegram;
it checks ISO checksums, metadata, current outputs, and invoking-UID/GID
ownership. It verifies package-cache save/restore hashes and then purges the
real downloaded cache while checking build configuration and published output
remain. The ISO is not uploaded as an Actions artifact.

The manual `gnome` profile uses the upstream mutable `variant-gnome` branch and
full package archive, so it may expose upstream changes or archive drift and is
not a pinned reproducible build. The small fixture omits desktop, installer,
and firmware package lists and uses faster compression. Neither profile boots
the resulting ISO or verifies its complete package manifest. Legacy Moby
seccomp-generator tests are offline regression fixtures only; they are not in
the host or CI runtime path.

Cache and Purge ISO workflows exercise reuse, invalidation, locking, and unsafe
paths using fixtures. The container image still uses the existing Dockerfile
name and may use a published OCI base image; neither implies Docker Engine or
Compose is an operational dependency.

## Troubleshooting and acceptance status

- **Rootless mode unavailable**: configure Podman and subordinate UID/GID
  ranges for the caller; enable unprivileged user namespaces. This project does
  not modify host configuration.
- **Mount or permission errors**: verify configured host directories exist and
  are writable as required. Do not use privileged mode or disable seccomp.
- **Stale lock**: confirm no build or purge is active, then inspect the
  configured host lock before removing it.
- **Missing Telegram token**: set `TELEGRAM_BOT_KEY` in `.env`; never disclose
  it in output, logs, or issue reports.

Rootless `podman info` and `unshare` passed on Void Linux with Podman 5.8.8, but
there is not yet accepted real ISO/checksum evidence. The reported Sinambung
`libwebp7` archive mismatch remains unverified. Fixture success does not
establish live runtime acceptance.
