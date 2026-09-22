# BlankOn live-builder

Build orchestration for BlankOn live-build. Host execution uses Docker Compose;
the build runs inside the `builder` container.

Keep `.env` beside `build-iso`. Copy `.env.example` to `.env`, set
`BUILD_LOCAL` to an absolute host directory, then run from this repository:

```sh
./build-iso --local blankon-live-build
./build-iso --local /home/user/blankon/blankon-live-build
./build-iso --remote <repo> <branch> [commit]
```

Relative `--local` paths resolve beneath `BUILD_LOCAL`. Absolute paths are
accepted only when they remain beneath `BUILD_LOCAL`; the existing source
directory is canonicalized before it is mounted. `BUILD_LOCAL` is mounted at
the same absolute path inside the container. `BUILD_JAHITAN_PATH` is mounted
for remote build output.

Build or validate the image directly with `docker compose build`.
Continuous integration runs shell syntax checks, Compose validation, and the
image build; it does not run an ISO build or contact Telegram.
