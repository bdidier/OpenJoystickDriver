"""Fail when Swift sources call a dispatcher or a physical-output claim outside a sink.

Every frame, activation and mapped physical-output claim reaches its destination through
`OutputSink.consume` (`InputSource.produce` for a source). A call to `.dispatch(`,
`.dispatchPublishing(`, `.activateOutput(for:`, `.activateOutputReportingFailure(for:` or
`.setMappingPhysicalOutput(`, `.releaseMappingPhysicalOutputs(` or
`.setProfilePhysicalColor(` goes around that boundary, unless it is a sink forwarding to the
output it wraps; those files are listed in `SINK_INTERNALS`.
"""

from __future__ import annotations

import pathlib
import re
import sys
from collections.abc import Iterable

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = "Sources"
# Output dispatchers and routers that are sinks and forward to the output they wrap.
SINK_INTERNALS = frozenset(
    {
        "Sources/OpenJoystickDriverKit/Output/Backends/VirtualOutputRouter.swift",
        "Sources/OpenJoystickDriverService/Remapping/Routing/RemappingOutputRouter.swift",
        "Sources/OpenJoystickDriverService/Runtime/OutputDispatch/AutomaticOutputDelivery.swift",
    }
)
BYPASS = re.compile(
    r"\.(?:dispatch|dispatchPublishing|setMappingPhysicalOutput|releaseMappingPhysicalOutputs|setProfilePhysicalColor)\("
    r"|\.activateOutput(?:ReportingFailure)?\(for:"
)


def violations(root: pathlib.Path = ROOT) -> list[str]:
    found: list[str] = []
    for path in sorted((root / SOURCES).rglob("*.swift")):
        relative = path.relative_to(root).as_posix()
        if relative in SINK_INTERNALS:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            match = BYPASS.search(line)
            if match:
                found.append(f"{relative}:{number}: {match.group(0)}")
    return found


def main(arguments: Iterable[str] = ()) -> int:
    del arguments
    found = violations()
    for entry in found:
        print(f"call outside an output sink: {entry}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
