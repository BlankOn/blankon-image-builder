import importlib.util
import tempfile
import unittest
from pathlib import Path


TOOL_PATH = Path(__file__).resolve().parents[1] / "tools/patch-live-build-sysfs.py"
MODULE_SPEC = importlib.util.spec_from_file_location(
    "patch_live_build_sysfs", TOOL_PATH
)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError("Could not load the sysfs helper patch tool")
PATCH_MODULE = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(PATCH_MODULE)


class PatchLiveBuildSysfsTests(unittest.TestCase):
    def test_patches_exact_helper_command_with_podman_only_read_only_bind(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            helper_path = Path(temporary_directory) / "chroot_sysfs"
            helper_path.write_text(
                "#!/bin/sh\nmount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys\n"
            )

            self.assertTrue(PATCH_MODULE.patch_helper(helper_path))

            patched_text = helper_path.read_text()
            self.assertIn('if [ "${PODMAN_MODE:-}" = 1 ]; then', patched_text)
            self.assertIn("mount --bind /sys chroot/sys", patched_text)
            self.assertIn("mount -o remount,bind,ro chroot/sys", patched_text)
            self.assertIn(
                "mount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys", patched_text
            )
            self.assertLess(
                patched_text.index("mount -o remount,bind,ro chroot/sys"),
                patched_text.index("else"),
            )

    def test_unknown_helper_version_fails_without_modification(self):
        for helper_text in (
            "#!/bin/sh\nmount -t tmpfs sysfs-live chroot/sys\n",
            "#!/bin/sh\n"
            "mount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys\n"
            "mount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys\n",
        ):
            with (
                self.subTest(helper_text=helper_text),
                tempfile.TemporaryDirectory() as temporary_directory,
            ):
                helper_path = Path(temporary_directory) / "chroot_sysfs"
                helper_path.write_text(helper_text)

                with self.assertRaisesRegex(ValueError, "Expected exactly one"):
                    PATCH_MODULE.patch_helper(helper_path)

                self.assertEqual(helper_path.read_text(), helper_text)

    def test_patching_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            helper_path = Path(temporary_directory) / "chroot_sysfs"
            helper_path.write_text(
                "mount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys\n"
            )

            self.assertTrue(PATCH_MODULE.patch_helper(helper_path))
            patched_text = helper_path.read_text()
            self.assertFalse(PATCH_MODULE.patch_helper(helper_path))
            self.assertEqual(helper_path.read_text(), patched_text)


if __name__ == "__main__":
    unittest.main()
