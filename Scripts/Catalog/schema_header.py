"""The one place the Python tools name the `$id` of OJD's schemas and the `kind` of each document.

The `apiVersion` is the Swift constant `OpenJoystickDriverAPI.version`, which `OJDRepositoryTool facts`
prints. `Tests/RepositoryScripts/test_schema_header.py` checks these against every schema under
`Resources/Schemas`.
"""

from __future__ import annotations

from Scripts.Quality import repository_tool

SCHEMA_ID_BASE = "https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha1/"
SCHEMA_SUFFIX = ".schema.json"

# The `kind` of each document kind whose schema is `<stem>.schema.json`.
KINDS = {
    "controller": "Controller",
    "controller-patch": "ControllerPatch",
    "virtual-device": "VirtualDevice",
    "profile": "Profile",
    "mod-package": "ModPackage",
    "error-codes": "ErrorCatalog",
    "crosswalk": "Crosswalk",
    "access-grants": "AccessGrants",
    "protocol-description": "ProtocolDescription",
    "settings": "Settings",
    "service-listener-failure": "ServiceListenerFailure",
}


def schema_id(stem: str) -> str:
    return f"{SCHEMA_ID_BASE}{stem}{SCHEMA_SUFFIX}"


def header(kind: str) -> dict[str, str]:
    """The `apiVersion` and `kind` members every document of `kind` starts with."""
    return {"apiVersion": repository_tool.api_version(), "kind": kind}
