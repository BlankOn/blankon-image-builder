# E2: Enable no-new-privileges

**Result:** PASS on the tested Void Linux host for both remote and local builds.

## Environment

- Builder commit: `68141633a9f6679ae609c7f98da845e1c331c1cf`, with the uncommitted PR 07 E2 selector applied in the isolated test checkout.
- Live source branch: `sinambung-dummy`
- Live source commit: `fb1e0c22e2c82c09d0c6b674319f4142ee708968`
- Host: `void/unknown`
- Kernel: `6.18.54_1`
- Podman: `5.8.8`, rootless
- Effective profile: `no-new-privileges-experiment-v1`
- Runtime retained `--userns=host`, `--user 0:0`, `--cap-add=SYS_ADMIN`, default seccomp, and `unmask=/proc/*`; it added only `no-new-privileges` and did not use `--privileged`.

## Builds

| Mode | Result | ISO SHA-256 | Size |
|---|---|---|---:|
| Remote | PASS | `c6b3b6df29111d9379fbba073d454ecde90a3ade6fca994dbd187b55d52dd886` | 304087040 bytes |
| Local | PASS | `44cdcf6441dca2b1b4d150838fcc8d14958a71bff0615dad792a1cd4b3b37d47` | 304087040 bytes |

Both checksum files passed `sha256sum -c`. `file` identified each artifact as a bootable ISO 9660 image; no QEMU boot test was performed. The generated manifests recorded the E2 profile, source SHA, output SHA, and host/runtime metadata.

## Limitations

This is evidence for one Void Linux kernel/runtime combination only. Keep `no-new-privileges` opt-in until tested on other supported hosts and reviewed for package-hook compatibility.
