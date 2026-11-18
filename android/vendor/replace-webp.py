#!/usr/bin/env python3
"""Replace the five 4 KiB-aligned WebP files with same-SONAME 16 KiB builds."""
import pathlib
import struct
import sys
import zipfile

old, webp, out = map(pathlib.Path, sys.argv[1:4])
names = ('libsharpyuv.so','libwebp.so','libwebpdecoder.so','libwebpdemux.so','libwebpmux.so')
replacement = {f'usr/lib/{n}': (webp/n).read_bytes() for n in names}

def architecture(b):
    if b[:4] != b'\x7fELF' or b[4:6] != b'\x02\x01':
        raise ValueError('Unexpected vendor executable')
    off, = struct.unpack_from('<Q', b, 32)
    size, num = struct.unpack_from('<HH', b, 54)
    for i in range(num):
        record = struct.unpack_from('<II6Q', b, off + size*i)
        if record[0] == 1 and (record[-1] < 16384 or (record[2] - record[3]) % 16384 != 0):
            raise ValueError('Vendor executable is not 16 KiB aligned')
    return struct.unpack_from('<H', b, 18)[0]

with zipfile.ZipFile(old) as source, zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as dest:
    assert set(replacement) <= set(source.namelist())
    for info in source.infolist():
        original = source.read(info)
        data = replacement.get(info.filename, original)
        if info.filename in replacement:
            assert architecture(data) == struct.unpack_from('<H', original, 18)[0]
        dest.writestr(info, data, compress_type=info.compress_type, compresslevel=6)
