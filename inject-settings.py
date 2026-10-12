#!/usr/bin/env python3
"""Inject a settings shim into the zip appended to BPT's rti.linux.

The HMRC binary is an ELF interpreter with a zip of frozen Python 2
modules concatenated (offsets adjusted to be absolute from the file
start, AppImage-style). We take the ELF prefix up to the first local
file header, rebuild the archive with one extra member, and write
prefix+zip back in place. The extra member is a Python 2 settings
module that imports the stock settings and relaxes ALLOWED_HOSTS (BPT
hardcodes ALLOWED_HOSTS = ['127.0.0.1'], so it 400s any request whose
Host header is not loopback -- e.g. when BPT_BIND is a tailscale or
LAN address).

usage: inject-settings.py RTI_LINUX MEMBER_NAME SHIM_FILE
"""
import io
import struct
import sys
import zipfile

LOCAL_SIG = b"PK\x03\x04"
EOCD_SIG = b"PK\x05\x06"


def die(msg):
    sys.exit("inject-settings: %s" % msg)


def main():
    if len(sys.argv) != 4:
        die("usage: inject-settings.py RTI_LINUX MEMBER_NAME SHIM_FILE")
    rti_path, member, shim_path = sys.argv[1:4]

    with open(rti_path, "rb") as f:
        data = f.read()

    eocd = data.rfind(EOCD_SIG)
    if eocd < 0:
        die("no zip End Of Central Directory record in %s" % rti_path)
    comment_len = struct.unpack_from("<H", data, eocd + 20)[0]
    if eocd + 22 + comment_len != len(data):
        die("unexpected trailing bytes after EOCD")

    prefix_len = data.find(LOCAL_SIG)
    if prefix_len < 0:
        die("no local file header in %s" % rti_path)

    src = zipfile.ZipFile(io.BytesIO(data))
    out = io.BytesIO()
    dst = zipfile.ZipFile(out, "w")
    for info in src.infolist():
        ni = zipfile.ZipInfo(info.filename, info.date_time)
        ni.compress_type = info.compress_type
        ni.external_attr = info.external_attr
        ni.create_system = info.create_system
        dst.writestr(ni, src.read(info))
    with open(shim_path, "rb") as f:
        shim = f.read()
    ni = zipfile.ZipInfo(member, (2020, 1, 1, 0, 0, 0))
    ni.compress_type = zipfile.ZIP_DEFLATED
    ni.external_attr = 0o100644 << 16
    dst.writestr(ni, shim)
    dst.close()

    with open(rti_path, "wb") as f:
        f.write(data[:prefix_len] + out.getvalue())
    print("injected %s (%d bytes) into %s; prefix %d bytes"
          % (member, len(shim), rti_path, prefix_len))


if __name__ == "__main__":
    main()
