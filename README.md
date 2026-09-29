# BlankOn image-builder

Orchestration for building BlankOn live-build images. `build-iso` validates the
request, then runs the build through Docker Compose in the privileged, root
`builder` container. Host directories are mounted at their same absolute paths
inside the container.

Keep `.env` beside `build-iso`; `build-iso` loads that file from its own
repository directory.

## Requirements

- Linux host with Docker Engine and the Docker Compose plugin.
- Permission to use Docker, including privileged containers.
- Writable host directories for `BUILD_LOCAL`, `BUILD_JAHITAN_PATH`, and the
  repository's `workdir`; Docker must be allowed to mount them.
- A Telegram bot token for build notifications. Keep it private.

The container is intentionally privileged and runs as root because live-build
needs mounts and root-owned build state. Do not remove that requirement from
the Compose service.

Run `./build-iso` as the host user that should own generated files. The
`workdir` directory, its generated build directories, and `BUILD_JAHITAN_PATH`
itself, plus the new date-stamped output/`current` copy, are handed to that
user's numeric UID/GID after logs are written, including after failed builds.
Older date-stamped outputs are not changed.
Handoff is skipped if a mount exists beneath either target. The builder remains
root and privileged; root callers consequently retain ownership.

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

## Validate without building an ISO

Use the same environment file as `build-iso`:

```sh
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose --env-file .env config --quiet
docker compose --env-file .env build
```

These commands validate Compose interpolation and build the Docker image only;
they do not build an ISO or contact Telegram.

## Troubleshooting

- **Missing `BUILD_LOCAL`**: copy `.env.example` to `.env`, set an absolute
  existing path, and run from this repository.
- **Local path outside `BUILD_LOCAL`**: move the checkout below that directory
  or use a relative path such as `blankon-live-build`.
- **Docker unavailable**: start Docker Engine and verify the Compose plugin with
  `docker compose version`; ensure the user can use Docker.
- **Mount or permission errors**: create the configured host directories, make
  them writable for Docker, and check Docker's host-path sharing policy.
- **Stale lock**: confirm no build is running, then remove the lock in the
  environment visible to the container, or let the next run remove it after
  confirming its recorded PID is no longer active.
- **Missing Telegram token**: set `TELEGRAM_BOT_KEY` in `.env`; do not disclose
  the token in command output, logs, or issue reports.
