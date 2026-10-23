#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
Extract vendor binaries from a Linksys EA9300 stock firmware image.

The stock .img is a JFFS2-style bootfs (little endian) followed by a raw
UBI rootfs. This script:

  1. walks the bootfs and extracts every file (94908.dtb, cferam.NNN,
     vmlinux.lz ...),
  2. writes the CFE RAM binary as cferam.001 (the file CFE loads at boot
     and the only vendor binary the OpenWrt image needs), and
  3. optionally builds a CFE-writable stock rescue image (stock-ws.bin)
     by replacing the Linksys vendor tail with a standard BCM4908 tail.

Usage:
  extract-stock-files.py <stock .img> [--out-dir DIR] [--rescue FILE]

No vendor binaries are distributed with this project - run this against
the stock firmware image you download from Linksys.
"""

import argparse
import os
import re
import struct
import sys
import zlib

BCM4908_TAIL = struct.pack("<IIIII", 0, 0x00005732, 0x4908, 3, 2)
# crc32 filled in later; version WFI_VERSION, chip 0x4908,
# flash type NAND128, flags SUPPORTS_BTRM


def crc32_bcm(data: bytes) -> int:
    """CRC32 as computed by bcm4908img: init 0xffffffff, no final xor."""
    crc = 0xFFFFFFFF
    for b in data:
        crc = zlib.crc32(bytes([b]), crc) & 0xFFFFFFFF
    return crc ^ 0xFFFFFFFF  # zlib applies the final xor for us


def crc32_bcm_fast(data: bytes) -> int:
    return (zlib.crc32(data) ^ 0xFFFFFFFF) & 0xFFFFFFFF


def walk_bootfs(data: bytes):
    """Sequentially walk the bootfs, yielding ('dir', name) and
    ('data', bytes) events. Files are chunked into <=4096 byte inodes with
    interleaved directory pages (custom node types)."""
    off = 0
    files = []  # (name, bytearray)
    cur = None
    while off + 12 <= len(data):
        if data[off : off + 2] != b"\x85\x19":
            break
        nodetype = struct.unpack("<H", data[off + 2 : off + 4])[0]
        length = struct.unpack("<I", data[off + 4 : off + 8])[0]
        if length < 12 or off + length > len(data):
            break
        if nodetype == 0xE001:  # dirent (52-byte record, name embedded)
            m = re.search(rb"[\x20-\x7e]{3,32}\xff*", data[off + 12 : off + 52])
            name = "?"
            if m:
                name = m.group().rstrip(b"\xff").decode(errors="replace")
            if cur and cur[1]:
                files.append((cur[0], bytes(cur[1])))
            cur = (name, bytearray())
            off += 52
            continue
        if nodetype & 0xFF00 in (0x2000, 0x4000):  # directory page, skip
            off += length
            continue
        dsize = length - 68  # 12B header + 56B metadata + payload
        if cur is not None and dsize > 0:
            cur[1].extend(data[off + 0x44 : off + 0x44 + dsize])
        off += length
        if off % 4:
            off += 4 - off % 4
    if cur and cur[1]:
        files.append((cur[0], bytes(cur[1])))
    return files


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stock_image")
    ap.add_argument("--out-dir", default=".")
    ap.add_argument("--rescue", metavar="FILE",
                    help="also write a CFE-writable stock rescue image")
    args = ap.parse_args()

    data = open(args.stock_image, "rb").read()
    if data[:2] != b"\x85\x19":
        sys.exit("not a Linksys EA9300 stock image (no bootfs magic)")

    print(f"image: {len(data)} bytes")
    files = walk_bootfs(data)
    for name, blob in files:
        print(f"  bootfs file: {name!r:20} {len(blob)} bytes")

    # cferam.NNN: the ~350 KB CFE RAM binary (second file by convention,
    # identified by size since vendor dirent names can be truncated).
    cferam = next(
        (blob for _, blob in files if 256 * 1024 < len(blob) < 512 * 1024),
        None,
    )
    if not cferam:
        sys.exit("could not locate the CFE RAM binary (cferam)")

    os.makedirs(args.out_dir, exist_ok=True)
    out = os.path.join(args.out_dir, "cferam.001")
    open(out, "wb").write(cferam)
    print(f"wrote {out} ({len(cferam)} bytes)")

    if args.rescue:
        # factory image = bootfs content + 20B zeroed tail slot +
        # 253B Linksys vendor tail. Replace both tails with a standard
        # BCM4908 tail so CFE's 'ws' command accepts the image.
        content = data[:-273]
        tail = bytearray(BCM4908_TAIL)
        tail[0:4] = struct.pack("<I", crc32_bcm_fast(content))
        open(args.rescue, "wb").write(content + bytes(tail))
        print(f"wrote {args.rescue} ({len(content) + 20} bytes)")


if __name__ == "__main__":
    main()
