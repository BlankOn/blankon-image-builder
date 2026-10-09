#!/usr/bin/env python3
import argparse
import os
import tempfile
from pathlib import Path


ORIGINAL_COMMAND = "mount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys"
PATCHED_COMMAND = """if [ "${PODMAN_MODE:-}" = 1 ]; then
		mount --bind /sys chroot/sys
		mount -o remount,bind,ro chroot/sys
	else
		mount -t sysfs -o x-gvfs-hide sysfs-live chroot/sys
	fi"""


def patch_helper(helper_path):
    helper_text = helper_path.read_text()
    command_occurrences = helper_text.count(ORIGINAL_COMMAND)
    patched_occurrences = helper_text.count(PATCHED_COMMAND)
    if patched_occurrences == 1 and command_occurrences == 1:
        return False
    if patched_occurrences != 0:
        raise ValueError(
            f"Expected exactly one complete sysfs helper patch in {helper_path}; found {patched_occurrences}"
        )
    if command_occurrences != 1:
        raise ValueError(
            f"Expected exactly one installed sysfs mount command in {helper_path}; found {command_occurrences}"
        )
    patched_text = helper_text.replace(ORIGINAL_COMMAND, PATCHED_COMMAND, 1)
    file_mode = helper_path.stat().st_mode
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=helper_path.parent, delete=False
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            temporary_file.write(patched_text)
        os.chmod(temporary_path, file_mode)
        os.replace(temporary_path, helper_path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "helper_path",
        nargs="?",
        type=Path,
        default=Path("/usr/lib/live/build/chroot_sysfs"),
    )
    arguments = parser.parse_args()
    try:
        changed = patch_helper(arguments.helper_path)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(
        f"Patched {arguments.helper_path}"
        if changed
        else f"Already patched {arguments.helper_path}"
    )


if __name__ == "__main__":
    main()
