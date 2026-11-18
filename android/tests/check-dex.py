#!/usr/bin/env python3
"""Check APK DEX names, versions and binary integrity."""
import hashlib
import re
import struct
import sys
import zipfile
import zlib


def check(apk, min_api):
    maximum_dex = 35
    for api, version in ((24, 37), (26, 38), (28, 39), (30, 40)):
        if min_api >= api:
            maximum_dex = version
    with zipfile.ZipFile(apk) as package:
        corrupt = package.testzip()
        if corrupt is not None:
            raise ValueError(f"Bad ZIP CRC for {corrupt}")
        names = [name for name in package.namelist() if re.fullmatch(r"classes(?:[0-9]+)?\.dex", name)]
        expected = ["classes.dex"] + [f"classes{i}.dex" for i in range(2, len(names) + 1)]
        if not names or sorted(names) != sorted(expected):
            raise ValueError(f"Missing, duplicate or non-contiguous root DEX files: {names}")
        for name in expected:
            data = package.read(name)
            version = re.fullmatch(rb"dex\n(035|037|038|039|040)\x00", data[:8])
            if len(data) < 0x70 or version is None:
                raise ValueError(f"Invalid DEX header in {name}")
            if int(version.group(1)) > maximum_dex:
                raise ValueError(f"{name} DEX {version.group(1).decode()} exceeds minimum API {min_api} support")
            if struct.unpack_from("<I", data, 8)[0] != zlib.adler32(data[12:]):
                raise ValueError(f"Bad DEX Adler-32 in {name}")
            if data[12:32] != hashlib.sha1(data[32:]).digest():
                raise ValueError(f"Bad DEX SHA-1 in {name}")
            if struct.unpack_from("<III", data, 32) != (len(data), 0x70, 0x12345678):
                raise ValueError(f"Invalid DEX size, header size or endianness in {name}")
            map_offset, = struct.unpack_from("<I", data, 52)
            count, class_offset, data_size, data_offset = struct.unpack_from("<IIII", data, 96)
            if not count or not 0x70 <= class_offset < len(data) or class_offset + count * 32 > len(data):
                raise ValueError(f"Invalid class definitions in {name}")
            if not 0x70 <= data_offset <= map_offset <= len(data) - 4 or data_offset + data_size > len(data):
                raise ValueError(f"Invalid map or data section in {name}")
            print(f"{name}: DEX {version.group(1).decode()}, {count} classes, CRC and header digests verified")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: check-dex.py APK MIN_API")
    try:
        check(sys.argv[1], int(sys.argv[2]))
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        raise SystemExit(str(exc))

