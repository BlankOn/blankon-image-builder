#!/usr/bin/env python3
import json
import os
import re
import stat
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path


PROFILE_PATH = Path("/workdir/seccomp-livebuild.json")
PROFILE_URL = "https://raw.githubusercontent.com/moby/moby/docker-v{version}/vendor/github.com/moby/profiles/seccomp/default.json"
NAMESPACE_FLAGS = 805437440
VALID_ACTIONS = {
    "SCMP_ACT_ALLOW",
    "SCMP_ACT_ERRNO",
    "SCMP_ACT_KILL",
    "SCMP_ACT_KILL_PROCESS",
    "SCMP_ACT_KILL_THREAD",
    "SCMP_ACT_LOG",
    "SCMP_ACT_NOTIFY",
    "SCMP_ACT_TRACE",
    "SCMP_ACT_TRAP",
}
VALID_COMPARATORS = {
    "SCMP_CMP_EQ",
    "SCMP_CMP_GE",
    "SCMP_CMP_GT",
    "SCMP_CMP_LE",
    "SCMP_CMP_LT",
    "SCMP_CMP_MASKED_EQ",
    "SCMP_CMP_NE",
}


def fetch_default_profile(version):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError(f"Unsupported Docker Engine version format: {version!r}")
    url = PROFILE_URL.format(version=version)
    request = urllib.request.Request(
        url, headers={"User-Agent": "blankon-image-builder"}
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise ValueError(
                    f"Upstream profile request returned HTTP {response.status}"
                )
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise ValueError(
            f"Cannot fetch or decode the Docker Engine {version} seccomp baseline: {error}"
        ) from error


def validate_baseline(profile):
    if not isinstance(profile, dict) or not isinstance(profile.get("syscalls"), list):
        raise ValueError("Upstream seccomp profile has an invalid structure")
    if set(profile) - {"defaultAction", "defaultErrnoRet", "archMap", "syscalls"}:
        raise ValueError(
            "Upstream seccomp profile contains unexpected top-level fields"
        )
    if profile.get("defaultAction") != "SCMP_ACT_ERRNO":
        raise ValueError("Upstream seccomp profile is not default-deny")
    if not isinstance(profile.get("archMap"), list) or not profile["archMap"]:
        raise ValueError("Upstream seccomp profile has no valid architecture map")
    if "defaultErrnoRet" in profile and not isinstance(profile["defaultErrnoRet"], int):
        raise ValueError("Upstream seccomp profile has an invalid default errno")
    for architecture in profile["archMap"]:
        if (
            not isinstance(architecture, dict)
            or set(architecture) - {"architecture", "subArchitectures"}
            or not isinstance(architecture.get("architecture"), str)
            or not architecture["architecture"]
            or (
                architecture.get("subArchitectures") is not None
                and (
                    not isinstance(architecture["subArchitectures"], list)
                    or not all(
                        isinstance(name, str)
                        for name in architecture["subArchitectures"]
                    )
                )
            )
        ):
            raise ValueError(
                "Upstream seccomp profile contains an invalid architecture map entry"
            )
    for rule in profile["syscalls"]:
        if (
            not isinstance(rule, dict)
            or set(rule)
            - {"names", "action", "args", "includes", "excludes", "comment", "errnoRet"}
            or not isinstance(rule.get("names"), list)
            or not rule["names"]
            or not all(isinstance(name, str) and name for name in rule["names"])
            or rule.get("action") not in VALID_ACTIONS
        ):
            raise ValueError(
                "Upstream seccomp profile contains a malformed syscall rule"
            )
        if "comment" in rule and not isinstance(rule["comment"], str):
            raise ValueError(
                "Upstream seccomp profile contains an invalid rule comment"
            )
        if "errnoRet" in rule and not isinstance(rule["errnoRet"], int):
            raise ValueError("Upstream seccomp profile contains an invalid rule errno")
        if "args" in rule:
            if not isinstance(rule["args"], list):
                raise ValueError(
                    "Upstream seccomp profile contains invalid syscall arguments"
                )
            for argument in rule["args"]:
                if (
                    not isinstance(argument, dict)
                    or not isinstance(argument.get("index"), int)
                    or argument["index"] not in range(6)
                    or not isinstance(argument.get("value"), int)
                    or argument.get("op") not in VALID_COMPARATORS
                    or (
                        "valueTwo" in argument
                        and not isinstance(argument["valueTwo"], int)
                    )
                ):
                    raise ValueError(
                        "Upstream seccomp profile contains an invalid argument constraint"
                    )
        for condition_name in ("includes", "excludes"):
            if condition_name in rule:
                condition = rule[condition_name]
                if not isinstance(condition, dict) or any(
                    key not in {"arches", "caps", "minKernel"} for key in condition
                ):
                    raise ValueError(
                        "Upstream seccomp profile contains an invalid rule condition"
                    )
                if any(
                    key in condition
                    and (
                        not isinstance(condition[key], list)
                        or not all(isinstance(value, str) for value in condition[key])
                    )
                    for key in ("arches", "caps")
                ):
                    raise ValueError(
                        "Upstream seccomp profile contains an invalid rule condition list"
                    )
                if "minKernel" in condition and not isinstance(
                    condition["minKernel"], str
                ):
                    raise ValueError(
                        "Upstream seccomp profile contains an invalid kernel condition"
                    )


def move_names_to_unconditional(profile, syscall_names):
    found = set()
    retained_rules = []
    for rule in profile["syscalls"]:
        removed = set(rule["names"]) & syscall_names
        found.update(removed)
        remaining_names = [name for name in rule["names"] if name not in syscall_names]
        if remaining_names:
            retained_rule = dict(rule)
            retained_rule["names"] = remaining_names
            retained_rules.append(retained_rule)
    if found != syscall_names:
        raise ValueError(
            f"Baseline syscall rules differ from expected policy: {sorted(syscall_names - found)}"
        )
    profile["syscalls"] = retained_rules


def validate_target_rules(profile):
    syscall_capabilities = {
        "unshare": "CAP_SYS_ADMIN",
        "mount": "CAP_SYS_ADMIN",
        "umount": "CAP_SYS_ADMIN",
        "umount2": "CAP_SYS_ADMIN",
        "open_tree": "CAP_SYS_ADMIN",
        "move_mount": "CAP_SYS_ADMIN",
        "mount_setattr": "CAP_SYS_ADMIN",
        "fsopen": "CAP_SYS_ADMIN",
        "fsconfig": "CAP_SYS_ADMIN",
        "fsmount": "CAP_SYS_ADMIN",
        "fspick": "CAP_SYS_ADMIN",
        "chroot": "CAP_SYS_CHROOT",
    }
    occurrences = {name: 0 for name in syscall_capabilities}
    for rule in profile["syscalls"]:
        target_names = set(rule["names"]) & syscall_capabilities.keys()
        for name in target_names:
            occurrences[name] += rule["names"].count(name)
            if (
                rule["action"] != "SCMP_ACT_ALLOW"
                or rule.get("includes") != {"caps": [syscall_capabilities[name]]}
                or "excludes" in rule
                or "args" in rule
                or "errnoRet" in rule
            ):
                raise ValueError(
                    f"Baseline syscall rule for {name} differs from expected capability-gated allow policy"
                )
    unexpected = sorted(name for name, count in occurrences.items() if count != 1)
    if unexpected:
        raise ValueError(
            f"Baseline syscall rules differ from expected policy: {unexpected}"
        )


def create_custom_profile(profile):
    validate_baseline(profile)
    target_syscalls = {
        "unshare",
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
    validate_target_rules(profile)
    move_names_to_unconditional(profile, target_syscalls)
    profile["syscalls"].extend(
        [
            {
                "names": ["unshare"],
                "action": "SCMP_ACT_ALLOW",
                "args": [{"index": 0, "value": NAMESPACE_FLAGS, "op": "SCMP_CMP_EQ"}],
            },
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
        ]
    )
    return profile


def write_profile(profile):
    PROFILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_path = tempfile.mkstemp(
        prefix=".seccomp-livebuild.", dir=PROFILE_PATH.parent
    )
    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as output:
            json.dump(profile, output, indent=2)
            output.write("\n")
            output.flush()
            os.fchmod(output.fileno(), stat.S_IRUSR | stat.S_IWUSR)
        os.replace(temporary_path, PROFILE_PATH)
    except Exception:
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass
        raise


def main():
    if len(sys.argv) != 2:
        raise ValueError("Usage: generate-seccomp-profile.py <docker-server-version>")
    profile = create_custom_profile(fetch_default_profile(sys.argv[1]))
    write_profile(profile)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
