from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WEBRTC_NAMES = ("webrtc", "livekit")


class CoreWithoutWebRTCTests(unittest.TestCase):
    def test_the_root_manifest_names_no_webrtc_package(self) -> None:
        manifest = (ROOT / "Package.swift").read_text(encoding="utf-8").lower()
        for name in WEBRTC_NAMES:
            self.assertNotIn(name, manifest)

    def test_the_root_resolution_pins_no_webrtc_package(self) -> None:
        resolved = json.loads((ROOT / "Package.resolved").read_text(encoding="utf-8"))
        for pin in resolved["pins"]:
            text = f"{pin['identity']} {pin['location']}".lower()
            for name in WEBRTC_NAMES:
                self.assertNotIn(name, text, pin)

    def test_the_root_manifest_takes_only_the_bridge_core_package(self) -> None:
        manifest = (ROOT / "Package.swift").read_text(encoding="utf-8")
        self.assertIn('.package(path: "Tools/BridgeCore")', manifest)
        core = (ROOT / "Tools/BridgeCore/Package.swift").read_text(encoding="utf-8")
        self.assertNotIn("dependencies:", core)
        self.assertNotIn(".package(", core)

    def test_the_bridge_core_sources_import_no_webrtc_module(self) -> None:
        for source in (ROOT / "Tools/BridgeCore/Sources").rglob("*.swift"):
            text = source.read_text(encoding="utf-8").lower()
            self.assertNotIn("import livekit", text, source)
            self.assertNotIn("import webrtc", text, source)

    def test_the_bridge_package_is_the_one_that_links_webrtc(self) -> None:
        manifest = (ROOT / "Tools/WebRTCBridge/Package.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn("webrtc-xcframework", manifest)


if __name__ == "__main__":
    unittest.main()
