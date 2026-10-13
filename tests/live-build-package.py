import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATCH_PATH = ROOT / "tools/live-build-sysfs-recursive-unmount.patch"
DOCKERFILE_PATH = ROOT / "Dockerfile"
UPSTREAM_COMMIT = "531cdb9854e04d08c3c3770463454d8a5e91b129"
PACKAGE_VERSION = f"1:20250814+git{UPSTREAM_COMMIT}+blankon1"


def upstream_helper_fixture():
    return """#!/bin/sh
set -e
case "${_ACTION}" in
	install)
		mount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys || mount -o rbind /sys chroot/sys
		Create_stagefile
		;;
	remove)
		Ensure_stagefile_exists
		Acquire_lockfile

		# Unmounting /sys/firmware/efi/efivars
		if mountpoint -q chroot/sys/firmware/efi/efivars
		then
			umount chroot/sys/firmware/efi/efivars
		fi

		# Unmounting /sys
		if mountpoint -q chroot/sys
		then
			umount chroot/sys
		fi

		# Removing stage file
		Remove_stagefile
		;;
esac
"""


class LiveBuildPackageTests(unittest.TestCase):
    def run_patch(self, source_text, check_only=False):
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_root = Path(temporary_directory)
            helper_path = source_root / "scripts/build/chroot_sysfs"
            helper_path.parent.mkdir(parents=True)
            helper_path.write_text(source_text, encoding="utf-8")
            command = ["git", "apply"]
            if check_only:
                command.append("--check")
            command.extend(["--whitespace=error", str(PATCH_PATH)])
            result = subprocess.run(
                command,
                cwd=source_root,
                capture_output=True,
                text=True,
                check=False,
            )
            return result, helper_path.read_text(encoding="utf-8")

    def test_patch_keeps_install_fallback_and_recursively_unmounts_only_sys_root(self):
        result, patched_source = self.run_patch(upstream_helper_fixture())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "mount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys || mount -o rbind /sys chroot/sys",
            patched_source,
        )
        self.assertIn("umount -R chroot/sys", patched_source)
        self.assertNotIn(
            "umount -R", patched_source.replace("umount -R chroot/sys", "")
        )
        self.assertIn("umount chroot/sys/firmware/efi/efivars", patched_source)
        self.assertLess(
            patched_source.index("umount chroot/sys/firmware/efi/efivars"),
            patched_source.index("umount -R chroot/sys"),
        )
        self.assertLess(
            patched_source.index("umount -R chroot/sys"),
            patched_source.index("Remove_stagefile"),
        )
        self.assertIn("set -e", patched_source)

    def test_patch_check_rejects_unexpected_upstream_teardown_without_changes(self):
        helper_source = upstream_helper_fixture().replace(
            "umount chroot/sys", "umount --lazy chroot/sys"
        )
        result, resulting_source = self.run_patch(helper_source, check_only=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(resulting_source, helper_source)

    def test_failed_recursive_unmount_keeps_stage_file_and_success_removes_it(self):
        result, patched_source = self.run_patch(upstream_helper_fixture())
        self.assertEqual(result.returncode, 0, result.stderr)
        shell_functions = """Echo_message() { :; }
Ensure_stagefile_exists() { :; }
Acquire_lockfile() { :; }
Remove_stagefile() { printf 'stage-removed\\n'; }
mountpoint() { return 0; }
umount() { return "$UNMOUNT_STATUS"; }
_ACTION=remove
"""
        failed_unmount = subprocess.run(
            ["sh", "-c", shell_functions + patched_source],
            capture_output=True,
            text=True,
            env={"UNMOUNT_STATUS": "1"},
            check=False,
        )
        successful_unmount = subprocess.run(
            ["sh", "-c", shell_functions + patched_source],
            capture_output=True,
            text=True,
            env={"UNMOUNT_STATUS": "0"},
            check=False,
        )
        self.assertNotEqual(failed_unmount.returncode, 0)
        self.assertNotIn("stage-removed", failed_unmount.stdout)
        self.assertEqual(successful_unmount.returncode, 0, successful_unmount.stderr)
        self.assertIn("stage-removed", successful_unmount.stdout)

    def test_dockerfile_installs_the_exact_published_apt_package(self):
        dockerfile = DOCKERFILE_PATH.read_text(encoding="utf-8")
        self.assertEqual(dockerfile.count("\nFROM "), 0)
        self.assertIn(
            "FROM ghcr.io/blankon/blankon-nightly@sha256:76b7e3b7feba1221d649481673af63bf65c310361916d574c6fe1cb90a02fea5",
            dockerfile,
        )
        self.assertNotIn("ARG LIVE_BUILD_PACKAGE_VERSION", dockerfile)
        self.assertIn(f"live-build={PACKAGE_VERSION} \\\n", dockerfile)
        self.assertIn(
            f"\"$(dpkg-query -W -f='${{Version}}' live-build)\" = '{PACKAGE_VERSION}'",
            dockerfile,
        )
        self.assertNotIn("salsa.debian.org", dockerfile)
        self.assertNotIn("git fetch", dockerfile)
        self.assertNotIn("dpkg-buildpackage", dockerfile)
        self.assertNotIn("dpkg-checkbuilddeps", dockerfile)
        self.assertNotIn("tools/live-build-sysfs-recursive-unmount.patch", dockerfile)
        self.assertNotIn("/tmp/live-build.deb", dockerfile)
        self.assertIn("        git \\\n", dockerfile)
        self.assertIn("        python3 \\\n", dockerfile)
        self.assertIn("        blankon-keyring \\\n", dockerfile)
        for build_only_dependency in (
            "build-essential",
            "debhelper",
            "devscripts",
            "gettext",
            "po4a",
        ):
            self.assertNotIn(build_only_dependency, dockerfile)
        self.assertNotIn("patch-live-build-sysfs.py", dockerfile)


if __name__ == "__main__":
    unittest.main()
