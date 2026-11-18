#!/usr/bin/env python3
"""Add both complete Android-native runtime sets before APK alignment."""
from pathlib import Path
import sys
import zipfile

ABIS = ("arm64-v8a", "x86_64")
BINARIES = ("libpython.so", "libpython.zip.so", "libqjs.so", "libffmpeg.so", "libffmpeg.zip.so", "libffprobe.so")


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: package.py UNSIGNED_APK ANDROID_NATIVE_DIR")
    unsigned, native = map(Path, sys.argv[1:])
    entries = [(native / abi / name, f"lib/{abi}/{name}") for abi in ABIS for name in BINARIES]
    for source, entry in entries:
        if not source.is_file():
            raise SystemExit(f"Missing {entry}: {source}")
    with zipfile.ZipFile(unsigned, "a") as apk:
        existing = set(apk.namelist())
        for _, entry in entries:
            if entry in existing:
                raise SystemExit(f"Duplicate APK entry: {entry}")
        for source, entry in entries:
            apk.write(source, entry, compress_type=zipfile.ZIP_STORED)


if __name__ == "__main__":
    main()
