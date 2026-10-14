"""Check the OpenJoystickDriver version that an issue form reports.

An issue must name the exact build, as the About window shows it:
`<release>+build.<bundle>.sha.<12-character commit>[.dirty]`, optionally
followed by ` (<bundle>)`. Prints the problem and exits 1 when the version is
missing or vague; exits 0 when it names a build.
"""

from __future__ import annotations

import os
import re
import sys

from Scripts.Release.bundle_version import BUNDLE_VERSION, SEMVER

FIELD = "### OpenJoystickDriver version"
EXAMPLE = "0.6.0-alpha.1+build.1.8.74.sha.08bc747d93f6.dirty (1.8.74)"
METADATA = re.compile(r"build\.(?P<bundle>.+)\.sha\.[0-9a-f]{12}(?:\.dirty)?")
SUFFIX = re.compile(r"(?P<version>\S+) \((?P<bundle>[^()]+)\)")


def reported_version(body: str) -> str | None:
    """The value of the version field in an issue form body, or None."""
    lines = body.splitlines()
    try:
        start = [line.strip() for line in lines].index(FIELD) + 1
    except ValueError:
        return None
    for line in lines[start:]:
        if line.startswith("### "):
            break
        value = line.strip().strip("`").strip()
        if value:
            return None if value == "_No response_" else value
    return None


def version_problem(value: str) -> str | None:
    """Why `value` does not name one build, or None when it does."""
    suffix = None
    if match := SUFFIX.fullmatch(value):
        value, suffix = match["version"], match["bundle"]
    semver = SEMVER.fullmatch(value)
    if semver is None or semver.group(5) is None:
        return "it is not a full build version"
    metadata = METADATA.fullmatch(semver.group(5))
    if metadata is None or BUNDLE_VERSION.fullmatch(metadata["bundle"]) is None:
        return "its build metadata does not name a build number and a commit"
    if suffix is not None and suffix != metadata["bundle"]:
        return f"the build number in parentheses is not {metadata['bundle']}"
    return None


def main() -> int:
    body = os.environ.get("ISSUE_BODY")
    value = reported_version(sys.stdin.read() if body is None else body)
    problem = (
        "the issue has no OpenJoystickDriver version"
        if value is None
        else version_problem(value)
    )
    if problem is None:
        return 0
    print(f"The OpenJoystickDriver version is not usable: {problem}.")
    print(
        f"Expected the whole line from About OpenJoystickDriver, such as `{EXAMPLE}`."
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
