# BlankOn live-builder

Build orchestration for BlankOn live-build. Run from the Kang Jahit workdir;
the live-build checkout is mounted at `/source`, and this repository at
`/builder`.

Keep `.env` beside `build-iso`; it is mounted at `/builder/.env`. Copy
`.env.example` to `.env`, configure the build environment, then run:

```sh
/builder/build-iso --local /source
/builder/build-iso --remote <repo> <branch> [commit]
```
