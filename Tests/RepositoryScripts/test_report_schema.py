from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path
from typing import Any, cast

from Scripts.Quality import validate_schemas

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "support_report_binding.json"


def load_fixture() -> dict[str, Any]:
    with FIXTURE.open(encoding="utf-8") as source:
        return json.load(source)


class ReportSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.documents = validate_schemas.validate_schema_documents()
        self.registry = validate_schemas.schema_registry(self.documents)
        self.validator = validate_schemas.Draft202012Validator(
            self.documents["report.schema.json"],
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_accepts_a_report_with_a_bound_controller_and_a_rejected_candidate(
        self,
    ) -> None:
        report = load_fixture()
        controller = report["data"]["controllers"][0]
        self.assertTrue(controller["binding"]["interfaces"])
        unbound = report["data"]["unboundDevices"][0]
        self.assertTrue(unbound["binding"]["rejectedCandidates"])

        self.validator.validate(report)

    def test_accepts_the_five_stage_stamps_of_a_frame(self) -> None:
        report = load_fixture()
        stages = report["data"]["frameTimings"][0]["frames"][0]["stages"]
        self.assertEqual(
            [stage["stage"] for stage in stages],
            [
                "read",
                "parse",
                "dispatch",
                "delivery-virtual-device",
                "delivery-endpoint",
            ],
        )

        self.validator.validate(report)

    def test_rejects_an_unknown_frame_stage(self) -> None:
        report = copy.deepcopy(load_fixture())
        report["data"]["frameTimings"][0]["frames"][0]["stages"][0]["stage"] = "wire"

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_rejects_a_report_without_frame_timings(self) -> None:
        report = copy.deepcopy(load_fixture())
        del report["data"]["frameTimings"]

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_accepts_a_bluetooth_le_controller_on_a_core_bluetooth_gatt_link(
        self,
    ) -> None:
        report = copy.deepcopy(load_fixture())
        controller = report["data"]["controllers"][0]
        controller["binding"]["accessBackend"] = "coreBluetoothGATT"
        controller["connectionState"]["backend"] = "coreBluetoothGATT"
        controller["connectionState"]["transport"] = "bluetoothLE"

        self.validator.validate(report)

    def test_rejects_an_unknown_access_backend(self) -> None:
        report = copy.deepcopy(load_fixture())
        report["data"]["controllers"][0]["binding"]["accessBackend"] = "coreBluetooth"

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_rejects_a_top_level_catalog_record_id_on_an_unsupported_result(
        self,
    ) -> None:
        report = copy.deepcopy(load_fixture())
        report["data"]["unboundDevices"][0]["binding"]["catalogRecordID"] = "045e-02d1"

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def test_rejects_a_rejected_candidate_without_a_reason(self) -> None:
        report = copy.deepcopy(load_fixture())
        candidate = report["data"]["unboundDevices"][0]["binding"][
            "rejectedCandidates"
        ][0]
        del candidate["reason"]

        with self.assertRaises(validate_schemas.ValidationError):
            self.validator.validate(report)

    def system_words_report(self) -> dict[str, Any]:
        report = copy.deepcopy(load_fixture())
        report["data"]["systemGamepadAudit"] = {
            "source": "downloadedMobileAsset",
            "bundleVersions": ["10.5.2"],
            "systemExactDeviceCount": 1,
            "skippedAppleDeviceCount": 0,
            "ojdRecordCount": 1,
            "catalogListedOJDRecordCount": 1,
            "records": [
                {
                    "vendorID": 1234,
                    "productID": 5678,
                    "name": "Test Controller",
                    "catalogListed": True,
                    "systemIdentifiers": ["test.controller"],
                    "transportConstraints": [],
                    "versionConstraints": [],
                }
            ],
            "warnings": [],
            "caveat": "test",
        }
        return report

    def test_accepts_the_neutral_system_words(self) -> None:
        report = self.system_words_report()
        self.assertEqual(report["data"]["system"]["osName"], "macOS")

        self.validator.validate(report)

    def assert_old_word_is_rejected(
        self, report: dict[str, Any], old: str, new: str, names_new_word: bool
    ) -> None:
        errors = [error.message for error in self.validator.iter_errors(report)]
        self.assertTrue(errors, f"{old} was accepted")
        self.assertTrue(any(old in message for message in errors), errors)
        if names_new_word:
            self.assertTrue(any(new in message for message in errors), errors)

    def test_rejects_macos_version_and_names_os_version(self) -> None:
        report = self.system_words_report()
        system = report["data"]["system"]
        system["macOSVersion"] = system.pop("osVersion")

        self.assert_old_word_is_rejected(report, "macOSVersion", "osVersion", True)

    def test_rejects_a_report_without_os_name(self) -> None:
        report = self.system_words_report()
        del report["data"]["system"]["osName"]

        self.assert_old_word_is_rejected(report, "osName", "osName", True)

    def test_rejects_apple_game_controller_audit(self) -> None:
        report = self.system_words_report()
        data = report["data"]
        data["appleGameControllerAudit"] = data.pop("systemGamepadAudit")

        self.assert_old_word_is_rejected(
            report, "appleGameControllerAudit", "systemGamepadAudit", False
        )

    def test_rejects_apple_exact_device_count_and_names_the_new_word(self) -> None:
        report = self.system_words_report()
        audit = report["data"]["systemGamepadAudit"]
        audit["appleExactDeviceCount"] = audit.pop("systemExactDeviceCount")

        self.assert_old_word_is_rejected(
            report, "appleExactDeviceCount", "systemExactDeviceCount", True
        )

    def test_rejects_apple_identifiers_and_names_the_new_word(self) -> None:
        report = self.system_words_report()
        record = report["data"]["systemGamepadAudit"]["records"][0]
        record["appleIdentifiers"] = record.pop("systemIdentifiers")

        self.assert_old_word_is_rejected(
            report, "appleIdentifiers", "systemIdentifiers", True
        )

    def test_has_no_apple_record_definition(self) -> None:
        defs = cast(dict[str, Any], self.documents["report.schema.json"]["$defs"])

        self.assertNotIn("appleRecord", defs)
        self.assertIn("systemRecord", defs)


if __name__ == "__main__":
    unittest.main()
