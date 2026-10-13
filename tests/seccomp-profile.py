#!/usr/bin/env python3
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PodmanSecurityTests(unittest.TestCase):
    def test_builder_uses_exact_apt_installed_live_build_package(self):
        dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
        self.assertIn("        python3 \\\n", dockerfile)
        self.assertNotIn("patch-live-build-sysfs.py", dockerfile)
        self.assertIn(
            "live-build=1:20250814+git531cdb9854e04d08c3c3770463454d8a5e91b129+blankon1",
            dockerfile,
        )
        self.assertIn(
            "\"$(dpkg-query -W -f='${Version}' live-build)\" = '1:20250814+git531cdb9854e04d08c3c3770463454d8a5e91b129+blankon1'",
            dockerfile,
        )
        self.assertNotIn("apply --whitespace=error", dockerfile)
        self.assertNotIn("salsa.debian.org", dockerfile)
        self.assertNotIn("dpkg-buildpackage", dockerfile)

    def test_build_and_purge_keep_rootless_identity_mapping(self):
        for filename in ("build-iso", "purge-iso"):
            with self.subTest(filename=filename):
                source = (ROOT / filename).read_text(encoding="utf-8")
                self.assertRegex(source, r"--userns=host")
                self.assertRegex(source, r"--user\s+0:0")
                self.assertNotRegex(source, r"--privileged(?:\s|=|\))")
                self.assertNotRegex(
                    source, r"--security-opt\s*=?\s*['\"]?seccomp=unconfined"
                )

    def test_build_security_experiment_is_allowlisted_and_preserves_baseline(self):
        source = (ROOT / "build-iso").read_text(encoding="utf-8")
        self.assertIn("--cap-add=SYS_ADMIN", source)
        self.assertIn("unmask=/proc/*", source)
        self.assertIn(
            "baseline)\n      BUILD_PODMAN_SECURITY_PROFILE=baseline-v1\n"
            "      BUILD_PODMAN_SECURITY_ARGS=(--security-opt 'unmask=/proc/*')",
            source,
        )
        self.assertIn(
            "no-proc-unmask)\n"
            "      BUILD_PODMAN_SECURITY_PROFILE=no-proc-unmask-experiment-v1\n"
            "      BUILD_PODMAN_SECURITY_ARGS=()",
            source,
        )
        self.assertIn(
            "no-new-privileges)\n"
            "      BUILD_PODMAN_SECURITY_PROFILE=no-new-privileges-experiment-v1\n"
            "      BUILD_PODMAN_SECURITY_ARGS=(--security-opt 'unmask=/proc/*' --security-opt no-new-privileges)",
            source,
        )
        self.assertIn("no-new-privileges-experiment-v1", source)
        self.assertIn(
            "BUILD_PODMAN_SECURITY_PROFILE=no-proc-unmask-experiment-v1", source
        )
        self.assertIn("BUILD_PODMAN_SECURITY_PROFILE=baseline-v1", source)
        self.assertIn("validate_podman_experiment || return $?", source)
        self.assertNotIn("--security-opt seccomp=", source)
        self.assertNotIn("--security-opt=seccomp=", source)

    def test_namespace_fixture_covers_actual_unshare_argument_vectors(self):
        source = (ROOT / "build-iso").read_text(encoding="utf-8")
        self.assertEqual(
            len(
                re.findall(
                    r"unshare\s+--user\s+--map-users\s+all\s+--map-groups\s+all", source
                )
            ),
            2,
        )
        self.assertNotIn("--map-root-user", source)


if __name__ == "__main__":
    unittest.main()
