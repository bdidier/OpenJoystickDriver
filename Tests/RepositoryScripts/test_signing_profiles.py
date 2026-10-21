"""Behavior tests for the provisioning-profile checks in signing configure and doctor."""

from __future__ import annotations

import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts" / "Signing"))

import profile_certs

from Scripts.Signing import configure, doctor

DEXT = "com.openjoystickdriver.XboxUSBDevice"
USB = "com.apple.developer.driverkit.transport.usb"
FORBIDDEN_DEXT_KEYS = (
    "com.apple.developer.hid.virtual.device",
    "com.apple.developer.driverkit.family.hid.device",
    "com.apple.developer.driverkit.transport.hid",
    "com.apple.developer.driverkit.family.hid.eventservice",
    "com.apple.developer.driverkit.allow-any-userclient-access",
)
USERCLIENT = "com.apple.developer.driverkit.userclient-access"
ALLOW_ANY = "com.apple.developer.driverkit.allow-any-userclient-access"
OTHER_DRIVER = "com.example.OtherDriver"
HOST = {
    "com.apple.developer.system-extension.install": True,
    "com.apple.developer.hid.virtual.device": True,
    USERCLIENT: [DEXT],
}
FULL_DEXT = {
    "com.apple.developer.driverkit": True,
    USB: doctor.PRODUCTION_USB,
}


def without(entitlements: dict, key: str) -> dict:
    return {name: value for name, value in entitlements.items() if name != key}


class ConfigureProfileTests(unittest.TestCase):
    def check(self, function, entitlements: dict, **kwargs) -> None:
        with patch.object(
            configure, "decode_profile", return_value={"Entitlements": entitlements}
        ):
            function("profile", "label", **kwargs)

    def test_dext_profile_accepts_exact_usb_grant(self) -> None:
        self.check(configure.require_dext_profile, FULL_DEXT)

    def test_dext_profile_rejects_missing_driverkit_or_usb_grant(self) -> None:
        for key in FULL_DEXT:
            with self.subTest(key=key), self.assertRaises(SystemExit):
                self.check(configure.require_dext_profile, without(FULL_DEXT, key))

    def test_dext_profile_rejects_wrong_usb_and_forbidden_keys(self) -> None:
        wrong_usb = (
            [],
            doctor.PRODUCTION_USB[:-1],
            [*doctor.PRODUCTION_USB, {"idVendor": 1118, "idProduct": 1}],
        )
        for entitlements in (
            *({**FULL_DEXT, USB: value} for value in wrong_usb),
            *({**FULL_DEXT, key: True} for key in FORBIDDEN_DEXT_KEYS),
        ):
            with self.subTest(entitlements=entitlements), self.assertRaises(SystemExit):
                self.check(configure.require_dext_profile, entitlements)

    def test_host_profile_userclient_states(self) -> None:
        self.check(configure.require_host_profile, HOST)
        self.check(
            configure.require_host_profile,
            without(HOST, USERCLIENT),
            allow_ungranted_userclient=True,
        )
        with self.assertRaises(SystemExit):
            self.check(configure.require_host_profile, without(HOST, USERCLIENT))
        self.check(
            configure.require_host_profile,
            {**HOST, USERCLIENT: ["com.example.OldDriver"]},
            allow_ungranted_userclient=True,
        )
        self.check(
            configure.require_host_profile,
            {**HOST, USERCLIENT: [DEXT, "other"]},
            allow_ungranted_userclient=True,
        )
        for value in ("*", [DEXT, 1]):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                self.check(
                    configure.require_host_profile,
                    {**HOST, USERCLIENT: value},
                    allow_ungranted_userclient=True,
                )

    def test_host_profile_accepts_grant_that_includes_virtual_hid(self) -> None:
        self.check(
            configure.require_host_profile, {**HOST, USERCLIENT: [DEXT, OTHER_DRIVER]}
        )

    def test_host_profile_refuses_allow_any_userclient_access(self) -> None:
        with self.assertRaises(SystemExit):
            self.check(configure.require_host_profile, {**HOST, ALLOW_ANY: True})

    def test_release_host_profile_without_dext_grant_is_refused(self) -> None:
        for value in (None, [OTHER_DRIVER]):
            entitlements = {**HOST, USERCLIENT: value}
            with self.subTest(value=value), self.assertRaises(SystemExit):
                self.check(configure.require_host_profile, entitlements)


class DoctorProfileTests(unittest.TestCase):
    def test_userclient_access_states(self) -> None:
        granted = {"Entitlements": HOST}
        absent = {"Entitlements": without(HOST, USERCLIENT)}
        wider = {"Entitlements": {**HOST, USERCLIENT: [DEXT, "other"]}}
        self.assertEqual(doctor.userclient_access_errors("host", granted), [])
        self.assertEqual(
            doctor.userclient_access_errors("host", absent, allow_ungranted=True), []
        )
        other = {"Entitlements": {**HOST, USERCLIENT: ["com.example.OtherDriver"]}}
        self.assertEqual(
            doctor.userclient_access_errors("host", other, allow_ungranted=True), []
        )
        self.assertEqual(len(doctor.userclient_access_errors("host", absent)), 1)
        self.assertEqual(
            doctor.userclient_access_errors("host", wider, allow_ungranted=True), []
        )

    def test_userclient_access_accepts_grant_that_includes_virtual_hid(self) -> None:
        profile = {"Entitlements": {**HOST, USERCLIENT: [DEXT, OTHER_DRIVER]}}
        self.assertEqual(doctor.userclient_access_errors("host", profile), [])

    def test_userclient_access_refuses_wildcard_and_non_string_items(self) -> None:
        for value in ("*", [DEXT, 1]):
            profile = {"Entitlements": {**HOST, USERCLIENT: value}}
            with self.subTest(value=value):
                errors = doctor.userclient_access_errors(
                    "host", profile, allow_ungranted=True
                )
                self.assertEqual(len(errors), 1)

    def test_userclient_access_refuses_release_grant_without_dext(self) -> None:
        profile = {"Entitlements": {**HOST, USERCLIENT: [OTHER_DRIVER]}}
        self.assertEqual(len(doctor.userclient_access_errors("host", profile)), 1)

    def test_dext_profile_accepts_exact_usb_grant(self) -> None:
        self.assertEqual(
            doctor.dext_profile_errors("dext", {"Entitlements": FULL_DEXT}), []
        )

    def test_dext_profile_requires_driverkit_and_exact_usb_grant(self) -> None:
        for key in FULL_DEXT:
            with self.subTest(key=key):
                profile = {"Entitlements": without(FULL_DEXT, key)}
                self.assertEqual(len(doctor.dext_profile_errors("dext", profile)), 1)
        for value in ([], doctor.PRODUCTION_USB[:-1]):
            with self.subTest(usb=value):
                profile = {"Entitlements": {**FULL_DEXT, USB: value}}
                self.assertEqual(len(doctor.dext_profile_errors("dext", profile)), 1)

    def test_dext_profile_rejects_forbidden_entitlements(self) -> None:
        for key in FORBIDDEN_DEXT_KEYS:
            with self.subTest(key=key):
                profile = {"Entitlements": {**FULL_DEXT, key: True}}
                self.assertTrue(doctor.dext_profile_errors("dext", profile))

    def test_match_terms_outside_the_grant_are_named(self) -> None:
        granted = [721, 733, 739, 746, 2816, 2826, 2834]
        documents = {
            "entitlements": {USB: [{"idVendor": 1118, "idProductArray": granted}]},
            "personality": {
                "IOKitPersonalities": {
                    "Driver": {"idVendor": 1118, "idProductArray": granted}
                }
            },
            "signing entitlements": {USB: doctor.PRODUCTION_USB},
        }
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for name, document in documents.items():
                path = Path(directory, name)
                path.write_bytes(plistlib.dumps(document))
                paths.append(path)
            self.assertEqual(doctor.match_term_errors(paths), [])

            outside = {
                "extra product": {
                    USB: [{"idVendor": 1118, "idProductArray": [721, 767]}]
                },
                "other vendor": {
                    "IOKitPersonalities": {
                        "Driver": {"idVendor": 3695, "idProduct": 721}
                    }
                },
                "vendor-wide": {"IOKitPersonalities": {"Driver": {"idVendor": 1118}}},
            }
            for name, document in outside.items():
                with self.subTest(name):
                    path = Path(directory, name)
                    path.write_bytes(plistlib.dumps(document))
                    errors = doctor.match_term_errors([path])
                    self.assertEqual(len(errors), 1)
            errors = doctor.match_term_errors([Path(directory, "extra product")])
            self.assertIn("045E:02FF", errors[0])

    def test_tree_match_terms_stay_within_the_grant(self) -> None:
        self.assertEqual(doctor.match_term_errors(doctor.DEXT_MATCH_FILES), [])


if __name__ == "__main__":
    unittest.main()


DRIVERKIT_SCRIPT = Path(__file__).resolve().parents[2] / "Scripts/Build/driverkit.sh"
DEXT = "com.openjoystickdriver.XboxUSBDevice"
OTHER_DRIVER = "com.example.OtherDriver"


def _signed_host_access_check() -> str:
    """The Python that `_require_signed_host_access` in driverkit.sh runs."""
    body = DRIVERKIT_SCRIPT.read_text().split("_require_signed_host_access() {", 1)[1]
    return body.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]


class SignedHostAccessTests(unittest.TestCase):
    def _check(self, signed: object, profile: object) -> int:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "check.py"
            script.write_text(_signed_host_access_check())
            signed_path = root / "signed.plist"
            signed_path.write_bytes(
                plistlib.dumps({} if signed is None else {USERCLIENT: signed})
            )
            profile_path = root / "profile.plist"
            entitlements = {} if profile is None else {USERCLIENT: profile}
            profile_path.write_bytes(plistlib.dumps({"Entitlements": entitlements}))
            command = [sys.executable, script, signed_path, profile_path, "1", DEXT]
            return subprocess.run(command, capture_output=True, check=False).returncode

    def test_host_signed_for_the_dext_passes_with_a_profile_that_also_grants_virtual_hid(
        self,
    ) -> None:
        self.assertEqual(self._check([DEXT], [DEXT, OTHER_DRIVER]), 0)
        self.assertEqual(self._check([DEXT], [DEXT]), 0)

    def test_host_must_claim_only_a_dext_the_profile_grants(self) -> None:
        self.assertNotEqual(self._check([DEXT, OTHER_DRIVER], [DEXT, OTHER_DRIVER]), 0)
        self.assertNotEqual(self._check([DEXT], [OTHER_DRIVER]), 0)
        self.assertNotEqual(self._check(None, [DEXT]), 0)


class SharedIdentityTests(unittest.TestCase):
    HOST_PATH = "/profiles/Host.provisionprofile"
    DEXT_PATH = "/profiles/Dext.provisionprofile"

    def pick(self, host: list[str], dext: list[str], keychain: dict[str, str]) -> str:
        embedded = {self.HOST_PATH: host, self.DEXT_PATH: dext}
        with (
            patch.object(
                configure,
                "embedded_cert_sha1s_from_profile",
                side_effect=lambda path: embedded[path],
            ),
            patch.object(profile_certs, "keychain_identities", return_value=keychain),
            patch.dict("os.environ", {"APPLE_DEV_IDENTITY": ""}),
        ):
            return configure.pick_identity_matching_profiles(
                "Apple Development", [self.HOST_PATH, self.DEXT_PATH]
            )

    def test_identity_after_first_embedded_cert_is_chosen(self) -> None:
        chosen = self.pick(
            ["a" * 40, "b" * 40, "c" * 40],
            ["a" * 40, "b" * 40, "c" * 40],
            {"b" * 40: "Apple Development: X", "c" * 40: "Apple Development: Y"},
        )
        self.assertEqual(chosen, "b" * 40)

    def test_identity_must_be_embedded_in_both_profiles(self) -> None:
        chosen = self.pick(
            ["a" * 40, "b" * 40],
            ["a" * 40, "c" * 40],
            {"b" * 40: "Apple Development: X", "a" * 40: "Apple Development: Z"},
        )
        self.assertEqual(chosen, "a" * 40)

    def test_no_shared_identity_lists_every_sha1(self) -> None:
        with self.assertRaises(SystemExit) as raised:
            self.pick(
                ["a" * 40, "b" * 40],
                ["c" * 40],
                {"b" * 40: "Apple Development: X"},
            )
        text = str(raised.exception)
        for sha1 in ("a" * 40, "b" * 40, "c" * 40):
            self.assertIn(sha1, text)

    def test_empty_keychain_fails(self) -> None:
        with self.assertRaises(SystemExit) as raised:
            self.pick(["a" * 40], ["a" * 40], {})
        self.assertIn("NONE", str(raised.exception))

    def test_helper_sorts_qualifying_identities(self) -> None:
        shared = profile_certs.shared_identity_sha1s(
            [["b", "a", "z"], ["a", "b"]], {"b": "n", "a": "n", "z": "n"}
        )
        self.assertEqual(shared, ["a", "b"])

    def test_certificate_sha1_list_reads_every_certificate(self) -> None:
        profile = {"DeveloperCertificates": [b"one", b"two"]}
        self.assertEqual(len(profile_certs.certificate_sha1_list(profile)), 2)

    def test_certificate_sha1_list_fails_on_a_certificate_that_is_not_data(
        self,
    ) -> None:
        profile = {"DeveloperCertificates": [b"one", "two"]}
        with self.assertRaisesRegex(TypeError, r"DeveloperCertificates\[1\] is str"):
            profile_certs.certificate_sha1_list(profile)
