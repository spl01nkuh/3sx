import importlib.util
import io
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

try:
    from PIL import Image
except ImportError:
    Image = None

spec = importlib.util.spec_from_file_location("personalize", Path(__file__).parents[1] / "personalize-ios-ipa.py")
personalize = importlib.util.module_from_spec(spec)
spec.loader.exec_module(personalize)

@unittest.skipIf(Image is None, "Pillow is an optional local icon-tool dependency")
class PersonalIconTests(unittest.TestCase):
    def test_icon_is_added_locally_and_app_identity_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, icon, output = root / "input.ipa", root / "private.png", root / "personal.ipa"
            Image.new("RGBA", (64, 64), (200, 10, 20, 128)).save(icon)
            with zipfile.ZipFile(source, "w") as z:
                z.writestr("Payload/3SX.app/Info.plist", plistlib.dumps({
                    "CFBundleIdentifier": "org.crowdedstreet.3sx", "CFBundleExecutable": "3SX"}))
                z.writestr("Payload/3SX.app/3SX", b"original executable")
            personalize.personalize(source, icon, output)
            with zipfile.ZipFile(output) as z:
                info = plistlib.loads(z.read("Payload/3SX.app/Info.plist"))
                self.assertEqual(info["CFBundleIdentifier"], "org.crowdedstreet.3sx")
                self.assertEqual(z.read("Payload/3SX.app/3SX"), b"original executable")
                self.assertIn("CFBundleIcons", info)
                self.assertIn("CFBundleIcons~ipad", info)
                with Image.open(io.BytesIO(z.read("Payload/3SX.app/PersonalIcon60@3x.png"))) as png:
                    self.assertEqual(png.size, (180, 180))
                    self.assertEqual(png.mode, "RGB")
                self.assertNotIn("Payload/3SX.app/private.png", z.namelist())
            with self.assertRaisesRegex(ValueError, "already exists"):
                personalize.personalize(source, icon, output)
            with self.assertRaisesRegex(ValueError, "different output"):
                personalize.personalize(source, icon, source)

if __name__ == "__main__":
    unittest.main()
