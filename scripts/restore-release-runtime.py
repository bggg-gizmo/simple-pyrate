#!/usr/bin/env python3
"""Restore the verified release components omitted from Git."""
from pathlib import Path, PurePosixPath
import hashlib
import shutil
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text(encoding="ascii").strip()
WINDOWS = f"Simple-Pyrate-{VERSION}-Windows"
ANDROID = f"Simple-Pyrate-{VERSION}-Android-Source"


def allowed(relative, archive):
    if archive == WINDOWS:
        return relative.startswith(("runtime/windows-x64/", "runtime/windows-arm64/"))
    return relative.startswith("vendor/native/") or relative in (
        "assets/runtime/yt-dlp", "brand-source/Gold-Pirate-Ship-Original.png"
    )


def digest(stream):
    hasher = hashlib.sha256()
    for piece in iter(lambda: stream.read(1024 * 1024), b""):
        hasher.update(piece)
    return hasher.hexdigest()


def restore(archive):
    base = archive.stem
    if archive.name not in (WINDOWS + ".zip", ANDROID + ".zip"):
        raise ValueError("Choose the matching Windows release ZIP or Android source release ZIP.")
    sums = dict(line.split(maxsplit=1)[::-1] for line in (ROOT / "SHA256SUMS.txt").read_text().splitlines() if line.strip())
    with archive.open("rb") as payload:
        if digest(payload) != sums.get(archive.name):
            raise ValueError("Archive SHA-256 does not match this checkout.")
    destination = ROOT if base == WINDOWS else ROOT / "android"
    selected = {}
    with zipfile.ZipFile(archive) as bundle:
        for entry in bundle.infolist():
            name = PurePosixPath(entry.filename)
            if entry.is_dir() or not name.parts or name.parts[0] != base:
                continue
            relative = name.relative_to(base).as_posix()
            if not allowed(relative, base):
                continue
            if ".." in name.parts or "\\" in relative or relative in selected:
                raise ValueError("Invalid runtime member in release ZIP.")
            target = destination / relative
            if target.is_symlink() or not target.resolve().is_relative_to(destination):
                raise ValueError(f"Unsafe output path: {target}")
            if target.exists():
                with target.open("rb") as existing, bundle.open(entry) as bundled:
                    if digest(existing) != digest(bundled):
                        raise ValueError(f"Remove or back up the different existing file first: {target}")
            selected[relative] = (entry, target)
        if not selected:
            raise ValueError("No runtime files found in archive.")
        for entry, target in selected.values():
            if target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            stage = None
            try:
                with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output, bundle.open(entry) as source:
                    stage = Path(output.name)
                    shutil.copyfileobj(source, output, 1024 * 1024)
                mode = (entry.external_attr >> 16) & 0o777
                if mode:
                    stage.chmod(mode)
                stage.replace(target)
            finally:
                if stage is not None:
                    stage.unlink(missing_ok=True)
    print(f"Verified and restored {len(selected)} files for {base}.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/restore-release-runtime.py RELEASE_ZIP")
    try:
        restore(Path(sys.argv[1]))
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        raise SystemExit(str(exc))
