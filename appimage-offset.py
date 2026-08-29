#!/usr/bin/env python3

import struct
import sys


def squashfs_offset(path):
    with open(path, "rb") as fh:
        ident = fh.read(16)
        if ident[:4] != b"\x7fELF":
            raise SystemExit(f"{path}: not an ELF file")
        if ident[4] != 2:
            raise SystemExit(f"{path}: not ELF64")
        end = "<" if ident[5] == 1 else ">"

        fh.seek(0x28)
        (e_shoff,) = struct.unpack(end + "Q", fh.read(8))
        fh.seek(0x3A)
        e_shentsize, e_shnum = struct.unpack(end + "HH", fh.read(4))

    if not e_shoff or not e_shnum:
        raise SystemExit(f"{path}: no section headers")
    return e_shoff + e_shnum * e_shentsize


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: appimage-offset.py <AppImage>")
    path = sys.argv[1]
    offset = squashfs_offset(path)

    with open(path, "rb") as fh:
        fh.seek(offset)
        magic = fh.read(4)
    if magic not in (b"hsqs", b"sqsh"):
        raise SystemExit(f"{path}: no squashfs magic at offset {offset}, found {magic!r}")
    print(offset)


if __name__ == "__main__":
    main()
