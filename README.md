# BlankOn image-builder

`build-iso` and `purge-iso` are the host entrypoints. They use rootless Podman
directly; Docker Engine and Compose are not runtime dependencies. Keep the
private `.env` beside `build-iso`.

## Requirements and setup

- Linux, rootless Podman, and enabled unprivileged user namespaces.
- `newuidmap` and `newgidmap`, with at least 65,536 subordinate UIDs and GIDs
  assigned to the caller in `/etc/subuid` and `/etc/subgid`.
- Host Bash, coreutils, util-linux; Python 3/curl for notifications.
- Writable workdir and output directories; readable local source beneath
  `BUILD_LOCAL` for local builds.

Run as the user owning the rootless Podman engine. Verify with
`podman info --format '{{.Host.Security.Rootless}}'`. This project does not
install/configure Podman, edit subordinate-ID files, or alter global host
configuration.

The image build automatically applies the live-build sysfs compatibility patch.
Users do not need to run the helper or patch their host; rootless Podman's host
requirements still need to be satisfied.

Keep the builder and live-build checkouts as siblings beneath `BUILD_LOCAL`:

```text
/srv/blankon/blankon-image-builder/
/srv/blankon/blankon-live-build/
```

Clone both repositories, enter the builder checkout, and copy `.env.example` to
`.env`. Set required values as literal `KEY=value` lines, without shell
expansion or command substitution:

- `BUILD_LOCAL`: absolute existing directory containing local checkouts.
- `BUILD_JAHITAN_PATH`: absolute writable output directory. It cannot be `/`,
  equal to or contain `BUILD_LOCAL`, or overlap the builder checkout/workdir. It
  may be a separate child of `BUILD_LOCAL`; selected source cannot overlap it.
- `BUILD_LOCKFILE`: absolute host lock path with an existing parent; cannot be
  a symlink or non-regular existing file, or overlap workdir, output, or source.
  It may be outside `BUILD_LOCAL` and is flocked on the host, never mounted.
- `BUILD_PUBLISH_URL`: base URL for published artifacts and zsync metadata.
- `BUILD_SEND_TELEGRAM`: optional; defaults to enabled, set `0` to disable.
- `TELEGRAM_BOT_KEY`: optional Telegram token, needed only when notifications
  are enabled. Keep `.env` private and untracked.

Entrypoints validate path overlap, symlinks, lock type, and nested mounts. Only
selected local source is mounted read-only; workdir is writable. The host mounts
a fresh hidden staging directory under workdir, not the published output root,
into the container. Before promotion, the host validates the bounded JSON
provenance manifest against its versioned schema and checks its ISO SHA-256
claim against a host measurement. It overwrites host/runtime fields with
independently measured host values; source revision/status and in-container
live-build/debootstrap claims remain sourced from the build container. The host
promotes only after validation succeeds, to a reserved dated output directory,
and updates `current`.
Remote clones stay under workdir; no source tree is mounted. The builder
checkout, `.env`, and token are not passed to the container, which receives
`BUILD_SEND_TELEGRAM=0`. Optional notification runs on the host after the
container exits. Rootless mapping keeps generated files owned by the invoking
UID/GID, including after failed builds.

## Build and maintenance

The builder uses the BlankOn Nightly OCI base pinned to manifest digest
`sha256:76b7e3b7feba1221d649481673af63bf65c310361916d574c6fe1cb90a02fea5`.
On 2026-10-10, GHCR reported this as a single `linux/amd64` manifest, and the
manifest body SHA-256 matched the registry digest. This platform matches the
current x86_64 CI image jobs. To refresh the base, intentionally re-query GHCR
and verify both the manifest digest and platform in a dedicated review. Pinning
the base alone does not guarantee complete build reproducibility.

Local paths must remain beneath canonical `BUILD_LOCAL`. A selected source
contains `variant`, `config/common`, `config/<variant>`, and `auto`:

```sh
./build-iso --local blankon-live-build
./build-iso --local /srv/blankon/blankon-live-build
```

Remote mode clones a repository branch and can pin a commit:

```sh
./build-iso --remote <repo> <branch> [commit]
./build-iso --remote https://github.com/BlankOn/blankon-live-build.git sinambung-dummy <sha>
```

Outputs include a date-stamped ISO, checksum, zsync metadata, build logs, a
`<image>.build-manifest.json` provenance record, and a `current` pointer beneath
`BUILD_JAHITAN_PATH`. The manifest is written only after a successful build and
contains the builder revision, live source commit and clean/dirty/unavailable
status, pinned OCI base reference, built image ID, in-container live-build and
debootstrap versions, host/runtime and SELinux identifiers, output SHA-256, and
successful build result. It excludes credentials, usernames, and full host
paths. Unavailable inputs are identified explicitly. Host-side validation and
host-field overwrite are not cryptographic attestation, do not establish
deterministic ISO bytes, and do not guarantee byte reproducibility.

- `workdir/.build`: prepared live-build tree and logs.
- `workdir/tmp`: remote clones and transient state.
- `workdir/package-cache`: downloaded `.deb` files, reused by architecture and
  `archive.conf`; bootstrap/chroot filesystems start fresh.
- `./purge-iso`: removes only the validated package cache, preserving the
  prepared tree and published output. An absent cache is a no-op. It shares
  `workdir/.package-cache.lock` with builds; do not purge during a build.

## Runtime boundary

The container runs as `0:0` under rootless user mapping, with narrowly required
`CAP_SYS_ADMIN` and default Podman seccomp. By default, the builder also uses
`unmask=/proc/*` for the nested live-build proc mount. Host-side experiments
are opt-in through the invoking process environment; the selector is not read
from `.env`, and `baseline` remains the default. `BUILD_PODMAN_EXPERIMENT=no-proc-unmask`
omits only the proc unmask. The separate E2 experiment
`BUILD_PODMAN_EXPERIMENT=no-new-privileges` retains the baseline proc unmask and
adds only Podman's `no-new-privileges` security option. The profiles are
independent and must not be combined. Both passed full local and remote builds
on one Void Linux host, but remain experimental until tested on other supported
hosts. Neither changes the default. All profiles retain `CAP_SYS_ADMIN` and
default seccomp. The container does not use privileged mode, disable seccomp,
unmask other system paths, or request host `CAP_SYS_ADMIN`. These capability
and proc-unmask exceptions remain meaningful risks: a malicious source or
vulnerable kernel may escape the user-namespace boundary. Host kernel, LSM, and
runtime policy may add restrictions. Do not weaken these defaults to work
around host policy failures.

CI also runs mocked script fixtures in Fedora, Void glibc, and Arch userland
containers on an Ubuntu runner. These jobs test userland and script
compatibility only; they do not simulate or validate the distro's host kernel,
LSM, SELinux, or Podman runtime. Void musl remains experimental and is not in
the required matrix. The matrix images are pinned by digest and should be
refreshed deliberately.
