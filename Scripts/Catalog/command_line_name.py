"""The kebab-case spelling of an UpperCamelCase document value.

Mirrors `CommandLineName.kebab` in `Sources/OpenJoystickDriverKit/CommandLine/CommandLineName.swift`:
a run of capitals and digits is one acronym, and a word starts at a capital that follows a
lowercase letter or is followed by one. `XboxGIP` is `xbox-gip`, `W3C` is `w3c` and
`VendorPS3ThirdParty` is `vendor-ps3-third-party`.
"""

from __future__ import annotations


def kebab(value: str) -> str:
    """The lowercase kebab-case spelling of `value`."""
    result: list[str] = []
    for index, character in enumerate(value):
        if character.isupper() and index > 0:
            following = value[index + 1] if index + 1 < len(value) else ""
            if value[index - 1].islower() or following.islower():
                result.append("-")
        result.append(character.lower())
    return "".join(result)
