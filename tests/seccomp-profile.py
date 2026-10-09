#!/usr/bin/env python3
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PodmanSecurityTests(unittest.TestCase):
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

    def test_build_adds_only_the_required_builder_capability_and_proc_unmask(self):
        source = (ROOT / "build-iso").read_text(encoding="utf-8")
        self.assertIn("--cap-add=SYS_ADMIN", source)
        self.assertIn("unmask=/proc/*", source)
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
