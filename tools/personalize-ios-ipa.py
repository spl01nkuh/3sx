#!/usr/bin/env python3
"""Add a personal app icon locally. No network calls or uploads are made.

Run without arguments for file pickers, or use:
  py -3 personalize-ios-ipa.py INPUT.ipa --icon ICON.ico --output PERSONAL.ipa
Requires Pillow: py -3 -m pip install pillow
The resulting IPA must be signed again by your sideloading application.
"""
from __future__ import annotations
import argparse
import copy
import io
import os
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import zipfile


def personalize(input_ipa, icon_path, output_ipa):
    try:
        from PIL import Image
    except ImportError as error:
        raise ValueError("Install Pillow first: py -3 -m pip install pillow") from error
    source, icon, output = map(Path, (input_ipa, icon_path, output_ipa))
    if output.resolve() in (source.resolve(), icon.resolve()):
        raise ValueError("Choose a different output filename to preserve your originals.")
    if output.exists():
        raise ValueError("That output already exists. Choose a new output filename.")
    if not output.parent.is_dir():
        raise ValueError("The output folder does not exist.")
    sizes = {"PersonalIcon60.png": 60, "PersonalIcon60@2x.png": 120, "PersonalIcon60@3x.png": 180,
             "PersonalIcon76.png": 76, "PersonalIcon76@2x.png": 152, "PersonalIcon83.5@2x.png": 167}
    images = {}
    with Image.open(icon) as supplied:
        if supplied.format == "ICO":
            image = supplied.ico.getimage(max(supplied.ico.sizes(), key=lambda size: size[0] * size[1])).convert("RGBA")
        else:
            image = supplied.convert("RGBA")
        background = Image.new("RGB", image.size, (0, 0, 0))
        background.paste(image, mask=image.getchannel("A"))
        for name, size in sizes.items():
            buffer = io.BytesIO()
            background.resize((size, size), Image.Resampling.LANCZOS).save(buffer, format="PNG")
            images[name] = buffer.getvalue()
    pending = None
    try:
        with zipfile.ZipFile(source) as original:
            infos = [entry for entry in original.infolist()
                     if entry.filename.startswith("Payload/") and entry.filename.count("/") == 2
                     and entry.filename.endswith(".app/Info.plist")]
            if len(infos) != 1:
                raise ValueError("Expected one main app Info.plist in the IPA.")
            info_entry = infos[0]
            app = info_entry.filename.removesuffix("Info.plist")
            info = plistlib.loads(original.read(info_entry))
            if not info.get("CFBundleIdentifier"):
                raise ValueError("The IPA has no bundle identifier.")
            info["CFBundleIconFiles"] = ["PersonalIcon60", "PersonalIcon76", "PersonalIcon83.5"]
            info["CFBundleIconFile"] = "PersonalIcon60.png"
            info["CFBundleIcons"] = {"CFBundlePrimaryIcon": {
                "CFBundleIconFiles": ["PersonalIcon60"], "UIPrerenderedIcon": True}}
            info["CFBundleIcons~ipad"] = {"CFBundlePrimaryIcon": {
                "CFBundleIconFiles": ["PersonalIcon60", "PersonalIcon76", "PersonalIcon83.5"],
                "UIPrerenderedIcon": True}}
            with tempfile.NamedTemporaryFile(prefix=".personal-ipa-", suffix=".tmp", dir=output.parent, delete=False) as tmp:
                pending = Path(tmp.name)
            with zipfile.ZipFile(pending, "w", allowZip64=True) as result:
                result.comment = original.comment
                for entry in original.infolist():
                    if entry.filename == info_entry.filename or entry.filename in {app + name for name in images}:
                        continue
                    with original.open(entry) as reader, result.open(copy.copy(entry), "w",
                            force_zip64=entry.file_size >= zipfile.ZIP64_LIMIT) as writer:
                        shutil.copyfileobj(reader, writer, 1024 * 1024)
                metadata = copy.copy(info_entry)
                result.writestr(metadata, plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
                for name, data in images.items():
                    entry = zipfile.ZipInfo(app + name)
                    entry.create_system = 3
                    entry.external_attr = 0o100644 << 16
                    result.writestr(entry, data, compress_type=zipfile.ZIP_DEFLATED)
        # Publish a complete file without overwriting an existing output.
        os.link(pending, output)
        return output
    finally:
        if pending is not None:
            pending.unlink(missing_ok=True)


def gui():
    import tkinter as tk
    from tkinter import filedialog, messagebox
    root = tk.Tk(); root.withdraw()
    try:
        ipa = filedialog.askopenfilename(title="Select the downloaded 3SX IPA", filetypes=[("iOS application", "*.ipa")])
        if not ipa: return 0
        icon = filedialog.askopenfilename(title="Select your personal icon", filetypes=[("Icon image", "*.ico *.png")])
        if not icon: return 0
        output = filedialog.asksaveasfilename(title="Save your private IPA", defaultextension=".ipa",
            initialfile="3SX-personal.ipa", filetypes=[("iOS application", "*.ipa")])
        if not output: return 0
        personalize(ipa, icon, output)
        messagebox.showinfo("Personal IPA ready", "Your icon was added locally. Nothing was uploaded.\nSign and install this IPA using iLoader.")
        return 0
    except Exception as error:
        messagebox.showerror("Could not personalize IPA", str(error))
        return 1
    finally:
        root.destroy()


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if not args: return gui()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_ipa", type=Path)
    parser.add_argument("--icon", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    values = parser.parse_args(args)
    try:
        result = personalize(values.input_ipa, values.icon, values.output)
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    print(f"Created locally: {result}\nSign and install this IPA using iLoader. No files were uploaded.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
