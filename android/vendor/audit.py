#!/usr/bin/env python3
"""Audit the final Android package's native machine type and segment layout."""
import hashlib
import io
import pathlib
import stat
import struct
import sys
import zipfile

apk, tree = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
abis={'arm64-v8a':183,'x86_64':62}
expected={'libpython.so','libpython.zip.so','libffmpeg.so','libffmpeg.zip.so','libffprobe.so','libqjs.so'}
counts={a:0 for a in abis}

def audit(buf, abi):
    assert buf[:6] == b'\x7fELF\x02\x01'
    assert struct.unpack_from('<H', buf, 18)[0] == abis[abi]
    if struct.unpack_from('<H',buf,16)[0] not in (2,3):
        # Relocatable build objects do not contain loadable segments.
        return
    ph,=struct.unpack_from('<Q',buf,32)
    stride,n=struct.unpack_from('<HH',buf,54)
    load=[]
    for i in range(n):
        record=struct.unpack_from('<II6Q',buf,ph+i*stride)
        if record[0]==1:
            off, vaddr, alignment=record[2],record[3],record[-1]
            assert alignment>=16384 and (off-vaddr)%16384==0, (abi,off,vaddr,alignment)
            load.append(record)
    assert load, abi
    counts[abi]+=1

with zipfile.ZipFile(apk) as z:
    assert z.testzip() is None
    for abi in abis:
        prefix=f'lib/{abi}/'
        assert {n[len(prefix):] for n in z.namelist() if n.startswith(prefix)}==expected
        for name in sorted(expected):
            buf=z.read(prefix+name)
            assert hashlib.sha256(buf).digest()==hashlib.sha256((tree / abi / name).read_bytes()).digest()
            if name.endswith('.zip.so'):
                with zipfile.ZipFile(io.BytesIO(buf)) as archive:
                    for member in archive.infolist():
                        if member.is_dir() or stat.S_ISLNK(member.external_attr>>16):
                            continue
                        with archive.open(member) as src:
                            if src.read(4)==b'\x7fELF':
                                audit(archive.read(member),abi)
            else:
                audit(buf,abi)
print('APK payloads match source archive. Loadable ELF objects with 16 KiB alignment:', counts)
