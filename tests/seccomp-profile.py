#!/usr/bin/env python3
import copy
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import generate_seccomp_profile as generator


class SeccompProfileTests(unittest.TestCase):
    def setUp(self):
        self.baseline = {
            "defaultAction": "SCMP_ACT_ERRNO",
            "defaultErrnoRet": 1,
            "archMap": [
                {
                    "architecture": "SCMP_ARCH_X86_64",
                    "subArchitectures": ["SCMP_ARCH_X86"],
                }
            ],
            "syscalls": [
                {"names": ["read", "write"], "action": "SCMP_ACT_ALLOW"},
                {
                    "names": [
                        "unshare",
                        "mount",
                        "umount",
                        "umount2",
                        "open_tree",
                        "move_mount",
                        "mount_setattr",
                        "fsopen",
                        "fsconfig",
                        "fsmount",
                        "fspick",
                        "bpf",
                    ],
                    "action": "SCMP_ACT_ALLOW",
                    "includes": {"caps": ["CAP_SYS_ADMIN"]},
                },
                {
                    "names": ["chroot"],
                    "action": "SCMP_ACT_ALLOW",
                    "includes": {"caps": ["CAP_SYS_CHROOT"]},
                },
                {"names": ["pivot_root"], "action": "SCMP_ACT_ERRNO"},
            ],
        }

    def test_profile_preserves_default_policy_and_tightly_limits_unshare(self):
        expected_arch_map = copy.deepcopy(self.baseline["archMap"])
        profile = generator.create_custom_profile(copy.deepcopy(self.baseline))
        encoded = json.dumps(profile)
        decoded = json.loads(encoded)
        self.assertEqual(decoded["defaultAction"], "SCMP_ACT_ERRNO")
        self.assertEqual(decoded["defaultErrnoRet"], 1)
        self.assertEqual(decoded["archMap"], expected_arch_map)
        self.assertIn(
            {"names": ["read", "write"], "action": "SCMP_ACT_ALLOW"},
            decoded["syscalls"],
        )

        self.assertIn(
            {"names": ["pivot_root"], "action": "SCMP_ACT_ERRNO"}, decoded["syscalls"]
        )
        unshare_rules = [
            rule for rule in decoded["syscalls"] if "unshare" in rule["names"]
        ]
        self.assertEqual(
            unshare_rules,
            [
                {
                    "names": ["unshare"],
                    "action": "SCMP_ACT_ALLOW",
                    "args": [{"index": 0, "value": 805437440, "op": "SCMP_CMP_EQ"}],
                }
            ],
        )
        for rule in decoded["syscalls"]:
            if rule["action"] == "SCMP_ACT_ALLOW":
                self.assertFalse(
                    set(rule["names"])
                    & {
                        "mount",
                        "umount",
                        "umount2",
                        "chroot",
                        "open_tree",
                        "move_mount",
                        "mount_setattr",
                        "fsopen",
                        "fsconfig",
                        "fsmount",
                        "fspick",
                    }
                    and "includes" in rule
                )
            self.assertNotIn(
                "unshare", rule["names"] if rule not in unshare_rules else []
            )
        self.assertIn(
            {
                "names": [
                    "mount",
                    "umount",
                    "umount2",
                    "chroot",
                    "open_tree",
                    "move_mount",
                    "mount_setattr",
                    "fsopen",
                    "fsconfig",
                    "fsmount",
                    "fspick",
                ],
                "action": "SCMP_ACT_ALLOW",
            },
            decoded["syscalls"],
        )

    def test_profile_rejects_unexpected_target_syscall_rules(self):
        invalid_rules = [
            {"names": ["mount"], "action": "SCMP_ACT_ALLOW"},
            {
                "names": ["mount"],
                "action": "SCMP_ACT_ERRNO",
                "includes": {"caps": ["CAP_SYS_ADMIN"]},
            },
            {
                "names": ["mount"],
                "action": "SCMP_ACT_ALLOW",
                "includes": {"caps": ["CAP_SYS_ADMIN"], "arches": ["SCMP_ARCH_X86_64"]},
            },
            {
                "names": ["mount"],
                "action": "SCMP_ACT_ALLOW",
                "includes": {"caps": ["CAP_SYS_ADMIN"]},
                "args": [{"index": 0, "value": 1, "op": "SCMP_CMP_EQ"}],
            },
        ]
        for invalid_rule in invalid_rules:
            with self.subTest(invalid_rule=invalid_rule):
                profile = copy.deepcopy(self.baseline)
                profile["syscalls"].append(invalid_rule)
                with self.assertRaisesRegex(ValueError, "mount"):
                    generator.create_custom_profile(profile)

    @patch("generate_seccomp_profile.urllib.request.urlopen")
    def test_fetch_uses_exact_server_version_tag(self, mocked_urlopen):
        response = MagicMock()
        response.__enter__.return_value.status = 200
        response.__enter__.return_value.read.return_value = json.dumps(
            self.baseline
        ).encode()
        mocked_urlopen.return_value = response
        self.assertEqual(generator.fetch_default_profile("29.8.0"), self.baseline)
        request = mocked_urlopen.call_args.args[0]
        self.assertEqual(
            request.full_url,
            "https://raw.githubusercontent.com/moby/moby/docker-v29.8.0/vendor/github.com/moby/profiles/seccomp/default.json",
        )

    def test_podman_entrypoints_use_host_root_identity_and_default_seccomp(self):
        root = Path(__file__).resolve().parents[1]
        build_text = (root / "build-iso").read_text(encoding="utf-8")
        purge_text = (root / "purge-iso").read_text(encoding="utf-8")
        for script_text in (build_text, purge_text):
            self.assertIn("--userns=host --user 0:0", script_text)
            self.assertNotIn("--security-opt seccomp=unconfined", script_text)
            self.assertNotIn("--security-opt=seccomp=unconfined", script_text)

    def test_namespace_maps_all_outer_user_and_group_ids(self):
        build_script = Path(__file__).resolve().parents[1] / "build-iso"
        build_text = build_script.read_text(encoding="utf-8")
        self.assertEqual(build_text.count("--map-users all --map-groups all"), 2)
        self.assertNotIn("--map-root-user", build_text)


if __name__ == "__main__":
    unittest.main()
