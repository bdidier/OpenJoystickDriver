"""The one place the Python tools name the `apiVersion` and the `$id` of OJD's schemas.

`Tests/RepositoryScripts/test_schema_header.py` checks these against the Swift constant
`OpenJoystickDriverAPI.version` and against every schema under `Resources/Schemas`.
"""

from __future__ import annotations

API_VERSION = "openjoystickdriver/v1alpha1"
SCHEMA_ID_BASE = "https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha1/"
SCHEMA_SUFFIX = ".schema.json"

# The `kind` of each document kind whose schema is `<stem>.schema.json`.
KINDS = {
    "controller": "Controller",
    "controller-patch": "ControllerPatch",
    "persona": "Persona",
    "profile": "Profile",
    "mod-package": "ModPackage",
    "error-codes": "ErrorCatalog",
    "access-grants": "AccessGrants",
    "protocol-description": "ProtocolDescription",
}


def schema_id(stem: str) -> str:
    return f"{SCHEMA_ID_BASE}{stem}{SCHEMA_SUFFIX}"


def header(kind: str) -> dict[str, str]:
    """The `apiVersion` and `kind` members every document of `kind` starts with."""
    return {"apiVersion": API_VERSION, "kind": kind}
