#!/usr/bin/env python3
"""Embed a verified, locally supplied PS2 AFS archive in an IPA before signing.

This tool does not extract the IPA, download game data, or sign the resulting app.
Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import sys
import tempfile
from xml.parsers.expat import ExpatError
import zipfile

EXPECTED_AFS_SHA256 = "f9fa50f3a124ec9fa9465aa9c8546c2d867887eb39f711a070762a0324ba5604"
CHUNK_SIZE = 1024 * 1024
MAX_PLIST_SIZE = 4 * 1024 * 1024
MAIN_APP_PATTERN = re.compile(r"^Payload/([^/]+\.app)(?:/|$)")


class BundleError(Exception):
    """An invalid input or unsafe output request."""


def validate_afs(path: Path) -> tuple[int, str]:
    """Validate the header and hash without loading the archive into memory."""
    with path.open("rb") as archive:
        size = os.fstat(archive.fileno()).st_size
        header = archive.read(8)
        if len(header) != 8 or header[:4] != b"AFS\0":
            raise BundleError("Game data must be an extracted SF33RD.AFS archive (invalid AFS header).")
        entry_count = struct.unpack_from("<I", header, 4)[0]
        if entry_count == 0 or 8 + entry_count * 8 > size:
            raise BundleError("The AFS entry table is missing or truncated.")
        digest = hashlib.sha256(header)
        while chunk := archive.read(CHUNK_SIZE):
            digest.update(chunk)
    actual = digest.hexdigest()
    if actual != EXPECTED_AFS_SHA256:
        raise BundleError(
            "AFS checksum does not match the PS2 archive required by 3SX.\n"
            f"Expected: {EXPECTED_AFS_SHA256}\n"
            f"Actual:   {actual}"
        )
    return size, actual


def _main_app(archive: zipfile.ZipFile) -> str:
    entries = archive.infolist()
    app_names = {
        match.group(1)
        for entry in entries
        if (match := MAIN_APP_PATTERN.match(entry.filename))
    }
    if len(app_names) != 1:
        raise BundleError("The IPA must contain exactly one main app under Payload/<name>.app/.")
    app = "Payload/" + app_names.pop()
    info_path = app + "/Info.plist"
    matching_info = [entry for entry in entries if entry.filename == info_path]
    if len(matching_info) != 1 or matching_info[0].is_dir():
        raise BundleError("The main app must contain exactly one Info.plist.")
    if matching_info[0].file_size > MAX_PLIST_SIZE:
        raise BundleError("The main app's Info.plist is unexpectedly large.")
    try:
        info = plistlib.loads(archive.read(matching_info[0]))
    except (plistlib.InvalidFileException, ValueError, TypeError, OverflowError, ExpatError) as error:
        raise BundleError("The main app's Info.plist cannot be read.") from error
    executable = info.get("CFBundleExecutable") if isinstance(info, dict) else None
    if (
        not isinstance(executable, str)
        or not executable
        or executable in (".", "..")
        or "/" in executable
        or "\\" in executable
    ):
        raise BundleError("Info.plist must name a valid CFBundleExecutable.")
    matching_executable = [entry for entry in entries if entry.filename == app + "/" + executable]
    if (
        len(matching_executable) != 1
        or matching_executable[0].is_dir()
        or matching_executable[0].file_size == 0
    ):
        raise BundleError("The main app executable is missing, empty, or duplicated.")
    if any(entry.flag_bits & 1 for entry in entries):
        raise BundleError("Encrypted IPA entries are not supported.")
    return app


def _same_file(first: Path, second: Path) -> bool:
    if first.resolve() == second.resolve():
        return True
    try:
        return first.samefile(second)
    except FileNotFoundError:
        return False


def bundle_ipa(input_ipa: Path, afs_path: Path, output_ipa: Path, *, force: bool = False) -> Path:
    """Write a new IPA atomically; existing signatures must be redone afterwards."""
    input_ipa, afs_path, output_ipa = map(Path, (input_ipa, afs_path, output_ipa))
    if _same_file(input_ipa, output_ipa):
        raise BundleError("Input and output IPA paths must be different.")
    if _same_file(afs_path, output_ipa):
        raise BundleError("The output path must not replace the original AFS archive.")
    if output_ipa.exists() and not force:
        raise BundleError("Output already exists. Choose a new path or pass --force to replace it.")
    if not output_ipa.parent.is_dir():
        raise BundleError("The output directory does not exist.")

    afs_size, expected_digest = validate_afs(afs_path)
    temporary: Path | None = None
    try:
        with zipfile.ZipFile(input_ipa, "r") as source:
            app = _main_app(source)
            target = app + "/game-data/SF33RD.AFS"
            with tempfile.NamedTemporaryFile(
                prefix="." + output_ipa.name + ".", suffix=".tmp", dir=output_ipa.parent, delete=False
            ) as pending:
                temporary = Path(pending.name)
            with zipfile.ZipFile(temporary, "w", allowZip64=True) as destination:
                destination.comment = source.comment
                for entry in source.infolist():
                    relative = entry.filename.removeprefix(app + "/")
                    parts = relative.split("/", 1)
                    if entry.filename.startswith(app + "/") and parts[0].casefold() == "resources":
                        # A root Resources directory changes Apple's bundle-layout
                        # detection. Remove the legacy AFS and empty directory.
                        if len(parts) == 1 or parts[1] in ("", "SF33RD.AFS"):
                            continue
                        raise BundleError("The IPA contains other files in a reserved Resources folder. Rebuild it first.")
                    # Remove every old target entry, including duplicate ZIP entries.
                    if entry.filename == target:
                        continue
                    metadata = copy.copy(entry)
                    with source.open(entry, "r") as original, destination.open(
                        metadata, "w", force_zip64=entry.file_size >= zipfile.ZIP64_LIMIT
                    ) as copied:
                        shutil.copyfileobj(original, copied, length=CHUNK_SIZE)

                metadata = zipfile.ZipInfo(target)
                metadata.compress_type = zipfile.ZIP_DEFLATED
                metadata.create_system = 3
                metadata.external_attr = 0o100644 << 16
                metadata.file_size = afs_size
                digest = hashlib.sha256()
                copied_size = 0
                with afs_path.open("rb") as original, destination.open(
                    metadata, "w", force_zip64=afs_size >= zipfile.ZIP64_LIMIT
                ) as copied:
                    while chunk := original.read(CHUNK_SIZE):
                        copied.write(chunk)
                        digest.update(chunk)
                        copied_size += len(chunk)
                if copied_size != afs_size or digest.hexdigest() != expected_digest:
                    raise BundleError("The AFS file changed while copying. No output IPA was published.")

        with temporary.open("rb+") as completed:
            os.fsync(completed.fileno())
        if force:
            os.replace(temporary, output_ipa)
        else:
            # A same-directory hard link publishes the complete file atomically
            # and fails if someone created the output after our initial check.
            # os.replace alone would silently overwrite that file on POSIX.
            try:
                os.link(temporary, output_ipa)
            except FileExistsError as error:
                raise BundleError("Output already exists. Choose a new path or pass --force.") from error
            except OSError as error:
                raise BundleError(
                    "Could not publish the output without overwrite protection. The output filesystem may not "
                    "support hard links (for example, FAT/exFAT). Choose an internal drive or use --force "
                    "to allow atomic replacement of the output path. " + str(error)
                ) from error
        return output_ipa
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Embed your extracted SF33RD.AFS in an IPA locally, before signing with a sideloading tool."
    )
    parser.add_argument("input_ipa", type=Path, metavar="INPUT.ipa", help="existing unsigned or preexisting IPA")
    parser.add_argument("afs_path", type=Path, metavar="SF33RD.AFS", help="extracted PS2 archive, not an ISO or 7z file")
    parser.add_argument("--output", type=Path, required=True, metavar="RESULT.ipa", help="new IPA to create")
    parser.add_argument("--force", action="store_true", help="replace an existing output IPA")
    args = parser.parse_args(argv)
    try:
        result = bundle_ipa(args.input_ipa, args.afs_path, args.output, force=args.force)
    except (BundleError, OSError, zipfile.BadZipFile, RuntimeError, NotImplementedError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    print(f"Created: {result}")
    print("Sign this output IPA with Sideloadly or your sideloading tool before installing it.")
    print("This tool does not sign the app; any previous app signature is no longer valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
