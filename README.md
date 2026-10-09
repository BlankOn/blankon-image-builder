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
selected local source is mounted read-only; workdir and output are writable.
Remote clones stay under workdir; no source tree is mounted. The builder
checkout, `.env`, and token are not passed to the container, which receives
`BUILD_SEND_TELEGRAM=0`. Optional notification runs on the host after the
container exits. Rootless mapping keeps generated files owned by the invoking
UID/GID, including after failed builds.

## Build and maintenance

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

Outputs include date-stamped ISO, checksum, zsync metadata, logs, and a
`current` pointer beneath `BUILD_JAHITAN_PATH`.

- `workdir/.build`: prepared live-build tree and logs.
- `workdir/tmp`: remote clones and transient state.
- `workdir/package-cache`: downloaded `.deb` files, reused by architecture and
  `archive.conf`; bootstrap/chroot filesystems start fresh.
- `./purge-iso`: removes only the validated package cache, preserving the
  prepared tree and published output. An absent cache is a no-op. It shares
  `workdir/.package-cache.lock` with builds; do not purge during a build.

## Runtime boundary

The container runs as `0:0` under rootless user mapping, with narrowly required
`CAP_SYS_ADMIN`, default Podman seccomp, and builder-only `unmask=/proc/*` for
the nested live-build proc mount. It does not use privileged mode, disable
seccomp, unmask other system paths, or request host `CAP_SYS_ADMIN`. These
capability and proc-unmask exceptions remain meaningful risks: a malicious
source or vulnerable kernel may escape the user-namespace boundary. Host
kernel, LSM, and runtime policy may add restrictions. Do not weaken these
defaults to work around host policy failures.
