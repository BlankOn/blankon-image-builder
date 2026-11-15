# PR 08: Isolated output staging

**Result:** PASS on the tested Void Linux host for both remote and local builds.

## Environment

- Builder commit: `5d8adc169f0fa7ecda07d7d2283a4d57edb77598`, with the uncommitted PR 08 staging change applied in the isolated test checkout.
- Live source branch: `sinambung-dummy`
- Live source commit: `fb1e0c22e2c82c09d0c6b674319f4142ee708968`
- Host: `void/unknown`
- Kernel: `6.18.54_1`
- Podman: `5.8.8`, rootless
- Security profile: `baseline-v1`

## Builds

| Mode | Result | ISO SHA-256 | Size |
|---|---|---|---:|
| Remote | PASS | `39a19f0d7b029b700961b916b6ac62304e4eee46ebaa44952ff3b54c6544807f` | 304087040 bytes |
| Local | PASS | `94c9adeed3873ce0b8cf8796d06b7ccb776c0537c34f67d982505793f2fc0101` | 304087040 bytes |

Both checksum files passed `sha256sum -c`. `file` identified each artifact as a bootable ISO 9660 image; no QEMU boot test was performed. The generated manifests record the source SHA, output SHA, and host/runtime metadata.

## Isolation checks

- The container received a writable bind of only the fresh staging directory at `/build-output`; it did not receive the public output-root bind.
- The host validated and promoted each staged release, then updated `current`.
- No `.build-stage.*` directories remained in the workspace or output root after either build.
- The fake-host fixture confirmed a sentinel in a previously published release remains unchanged and that failed/malformed stages do not update `current`.

This validates the staging flow on one host/runtime combination only. SELinux labeling and other host policies remain untested.
