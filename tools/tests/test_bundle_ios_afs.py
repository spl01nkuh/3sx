"""Tests use generated archives and inject their digest; no game data is included."""

import hashlib
import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "bundle-ios-afs.py"
SPEC = importlib.util.spec_from_file_location("bundle_ios_afs", SCRIPT)
bundler = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bundler)
PRODUCTION_DIGEST = bundler.EXPECTED_AFS_SHA256


class BundleIPATests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.ipa = self.root / "input.ipa"
        self.afs = self.root / "SF33RD.AFS"
        self.output = self.root / "result.ipa"
        self.data = b"AFS\0" + struct.pack("<III", 1, 16, 12) + b"fixture-data"
        self.afs.write_bytes(self.data)
        self.digest_patch = mock.patch.object(bundler, "EXPECTED_AFS_SHA256", hashlib.sha256(self.data).hexdigest())
        self.digest_patch.start()
        self.addCleanup(self.digest_patch.stop)
        self.make_ipa()

    def make_ipa(self, *, duplicate_afs=False, executable=True, second_app=False, nested_plugin=False):
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.comment = b"preserved archive comment"
            archive.writestr("Payload/3SX.app/Info.plist", plistlib.dumps({"CFBundleExecutable": "3SX"}))
            if executable:
                archive.writestr("Payload/3SX.app/3SX", b"test executable placeholder")
            asset = zipfile.ZipInfo("Payload/3SX.app/assets/asset.txt", (2024, 5, 6, 7, 8, 10))
            asset.compress_type = zipfile.ZIP_STORED
            asset.create_system = 3
            asset.external_attr = 0o100755 << 16
            asset.comment = b"entry comment"
            asset.extra = b"\xfe\xca\x02\x00\x01\x02"
            archive.writestr(asset, b"preserved asset")
            if duplicate_afs:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    archive.writestr("Payload/3SX.app/resources/SF33RD.AFS", b"old AFS")
                    archive.writestr("Payload/3SX.app/resources/SF33RD.AFS", b"duplicate old AFS")
            if second_app:
                archive.writestr("Payload/Other.app/Info.plist", b"other app")
            if nested_plugin:
                archive.writestr("Payload/3SX.app/PlugIns/Nested.app/Info.plist", b"nested plugin")

    def assert_no_partial_output(self):
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.root.glob(".result.ipa.*.tmp")), [])

    def test_embeds_archive_and_preserves_other_entries_and_metadata(self):
        with mock.patch.object(bundler, "CHUNK_SIZE", 7):
            self.assertEqual(bundler.bundle_ipa(self.ipa, self.afs, self.output), self.output)
        with zipfile.ZipFile(self.ipa) as original, zipfile.ZipFile(self.output) as result:
            self.assertEqual(result.read("Payload/3SX.app/resources/SF33RD.AFS"), self.data)
            self.assertEqual(result.comment, original.comment)
            for name in original.namelist():
                self.assertEqual(result.read(name), original.read(name))
                before, after = original.getinfo(name), result.getinfo(name)
                for field in ("date_time", "compress_type", "create_system", "external_attr", "comment", "extra"):
                    self.assertEqual(getattr(after, field), getattr(before, field), field)
            self.assertIsNone(result.testzip())
        self.assertEqual(self.afs.read_bytes(), self.data)

    def test_replaces_all_duplicate_embedded_archives(self):
        self.make_ipa(duplicate_afs=True)
        bundler.bundle_ipa(self.ipa, self.afs, self.output)
        with zipfile.ZipFile(self.output) as result:
            target = "Payload/3SX.app/resources/SF33RD.AFS"
            self.assertEqual(result.namelist().count(target), 1)
            self.assertEqual(result.read(target), self.data)

    def test_fixture_is_rejected_by_real_production_checksum(self):
        with mock.patch.object(bundler, "EXPECTED_AFS_SHA256", PRODUCTION_DIGEST):
            with self.assertRaisesRegex(bundler.BundleError, "checksum"):
                bundler.bundle_ipa(self.ipa, self.afs, self.output)
        self.assert_no_partial_output()

    def test_bad_header_and_truncated_table_are_rejected(self):
        for data in (b"7z not an AFS", b"AFS\0" + struct.pack("<I", 200)):
            with self.subTest(data=data):
                self.afs.write_bytes(data)
                with self.assertRaises(bundler.BundleError):
                    bundler.bundle_ipa(self.ipa, self.afs, self.output)
                self.assert_no_partial_output()

    def test_same_input_and_output_and_existing_output_are_protected(self):
        original = self.ipa.read_bytes()
        with self.assertRaisesRegex(bundler.BundleError, "different"):
            bundler.bundle_ipa(self.ipa, self.afs, self.ipa, force=True)
        self.assertEqual(self.ipa.read_bytes(), original)
        self.output.write_bytes(b"existing output")
        with self.assertRaisesRegex(bundler.BundleError, "already exists"):
            bundler.bundle_ipa(self.ipa, self.afs, self.output)
        self.assertEqual(self.output.read_bytes(), b"existing output")
        bundler.bundle_ipa(self.ipa, self.afs, self.output, force=True)
        self.assertTrue(zipfile.is_zipfile(self.output))

    def test_missing_executable_or_second_main_app_is_rejected(self):
        for kwargs in ({"executable": False}, {"second_app": True}):
            with self.subTest(kwargs=kwargs):
                self.make_ipa(**kwargs)
                with self.assertRaises(bundler.BundleError):
                    bundler.bundle_ipa(self.ipa, self.afs, self.output)
                self.assert_no_partial_output()

    def test_nested_plugin_is_not_counted_as_a_second_main_app(self):
        self.make_ipa(nested_plugin=True)
        bundler.bundle_ipa(self.ipa, self.afs, self.output)
        with zipfile.ZipFile(self.output) as result:
            self.assertIn("Payload/3SX.app/resources/SF33RD.AFS", result.namelist())
            self.assertIn("Payload/3SX.app/PlugIns/Nested.app/Info.plist", result.namelist())

    def test_failed_copy_cleans_temporary_output_and_preserves_existing_destination(self):
        self.output.write_bytes(b"existing output")
        with mock.patch.object(bundler.shutil, "copyfileobj", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                bundler.bundle_ipa(self.ipa, self.afs, self.output, force=True)
        self.assertEqual(self.output.read_bytes(), b"existing output")
        self.assertEqual(list(self.root.glob(".result.ipa.*.tmp")), [])

    def test_afs_changed_after_validation_is_not_published(self):
        validate = bundler.validate_afs

        def validate_then_change(path):
            details = validate(path)
            self.afs.write_bytes(self.data + b"changed")
            return details

        with mock.patch.object(bundler, "validate_afs", side_effect=validate_then_change):
            with self.assertRaisesRegex(bundler.BundleError, "changed"):
                bundler.bundle_ipa(self.ipa, self.afs, self.output)
        self.assert_no_partial_output()

    def test_invalid_zip_is_rejected_without_output(self):
        self.ipa.write_bytes(b"not a zip")
        with self.assertRaises(zipfile.BadZipFile):
            bundler.bundle_ipa(self.ipa, self.afs, self.output)
        self.assert_no_partial_output()


if __name__ == "__main__":
    unittest.main()
