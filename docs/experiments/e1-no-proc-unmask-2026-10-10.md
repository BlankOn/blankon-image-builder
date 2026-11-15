# E1: Remove procfs unmask

**Result:** PASS on the tested Void Linux host for both remote and local builds.

## Environment

- Builder commit: `018c00857f84b3d709fa200106675082b22f24c6`, with the uncommitted PR 06 experiment selector applied in the isolated test checkout.
- Live source branch: `sinambung-dummy`
- Live source commit: `fb1e0c22e2c82c09d0c6b674319f4142ee708968`
- Host: `void/unknown`
- Kernel: `6.18.54_1`
- Podman: `5.8.8`, rootless
- Effective profile: `no-proc-unmask-experiment-v1`
- Runtime retained `--userns=host`, `--user 0:0`, `--cap-add=SYS_ADMIN`, and default seccomp. It omitted only `unmask=/proc/*`; it did not use `--privileged`.

## Builds

| Mode | Result | ISO SHA-256 | Size |
|---|---|---|---:|
| Remote | PASS | `e76ad1e8cea7d6548459d21de344a49af48670cc18e8b528e196f55d97dbff0d` | 304087040 bytes |
| Local | PASS | `29ed2542cc99e39e0cc4da6f24eb14fd73f7bb05c211ca32f7715e0e5e41e7c4` | 304087040 bytes |

Both checksum files passed `sha256sum -c`. `file` identified each artifact as a bootable ISO 9660 image; no QEMU boot test was performed. The generated manifests recorded the E1 profile, source SHA, output SHA, and host/runtime metadata.

## Limitations

This is evidence for one Void Linux kernel/runtime combination only. Keep the baseline default and `no-proc-unmask` opt-in until tested on other supported hosts, especially Fedora with SELinux enforcing.
