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
        self.assertNotIn("umount chroot/sys/firmware/efi/efivars", patched_source)
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

    def test_dockerfile_builds_and_installs_the_pinned_native_package(self):
        dockerfile = DOCKERFILE_PATH.read_text(encoding="utf-8")
        self.assertIn("AS live-build-package", dockerfile)
        dependency_layer, package_layer = dockerfile.split(
            "COPY tools/live-build-sysfs-recursive-unmount.patch", 1
        )
        self.assertIn("debhelper", dependency_layer)
        self.assertIn("devscripts", dependency_layer)
        self.assertLess(
            package_layer.index("RUN git init /tmp/live-build-source"),
            package_layer.index("fetch --depth=1"),
        )
        final_stage = dockerfile.rsplit("\nFROM ", 1)[1]
        self.assertIn("        git \\\n", final_stage)
        self.assertIn("        python3 \\\n", final_stage)
        for build_only_dependency in (
            "build-essential",
            "debhelper",
            "devscripts",
            "gettext",
            "po4a",
        ):
            self.assertNotIn(build_only_dependency, final_stage)
        self.assertIn(
            f"fetch --depth=1 https://salsa.debian.org/live-team/live-build.git {UPSTREAM_COMMIT}",
            dockerfile,
        )
        self.assertIn(f'rev-parse HEAD)" = {UPSTREAM_COMMIT}', dockerfile)
        self.assertIn("apply --check --whitespace=error", dockerfile)
        self.assertIn("dpkg-checkbuilddeps", dockerfile)
        self.assertIn("dpkg-buildpackage -b -us -uc", dockerfile)
        self.assertIn(
            "DEBEMAIL=builder@example.invalid DEBFULLNAME='BlankOn Image Builder' dch",
            dockerfile,
        )
        self.assertIn(f"--newversion '{PACKAGE_VERSION}'", dockerfile)
        self.assertIn(f"= '{PACKAGE_VERSION}'", dockerfile)
        self.assertIn("python3 \\", dockerfile)
        self.assertNotIn("patch-live-build-sysfs.py", dockerfile)


if __name__ == "__main__":
    unittest.main()
