# BlankOn image builder

## WHY using container?
Because why not

## Host requirements

- Linux with a working rootless Podman setup. Docker and Compose are not required.
- Host entrypoints also need Bash, coreutils, findutils, util-linux, and Python 3. `curl` is needed only for Telegram notifications.

## Configure

Keep a private, untracked `.env` beside `build-iso`. Start with:

```sh
cp .env.example .env
```

Set these four required values in `.env`:

```dotenv
BUILD_LOCAL=/srv/blankon
BUILD_LOCKFILE=/srv/blankon/.blankon-build.lock
BUILD_JAHITAN_PATH=/srv/blankon/jahitan
BUILD_PUBLISH_URL=http://arsip-dev.blankonlinux.id/iso
```

`BUILD_LOCAL` is the existing root containing the sibling builder and live-build checkouts. `BUILD_LOCKFILE` is the host lock path, `BUILD_JAHITAN_PATH` is a writable artifact directory, and `BUILD_PUBLISH_URL` is the publication base URL.

Telegram notifications are optional and disabled by default. To opt in, set `BUILD_SEND_TELEGRAM=1` and provide `TELEGRAM_BOT_KEY` in `.env`.

## Build

Build from a local checkout:

```sh
./build-iso --local /srv/blankon/blankon-live-build
```

Or build from a remote repository branch, optionally pinned to a commit:

```sh
./build-iso --remote <repo> <branch> [commit]
```

Artifacts are written under `$BUILD_JAHITAN_PATH`.

Optionally, purge the package cache with:

```sh
./purge-iso
```
