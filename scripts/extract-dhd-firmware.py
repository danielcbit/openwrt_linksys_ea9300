#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
Extract the BCM4366C0 WiFi firmware from a Linksys EA9300 stock firmware.

Why: the stock firmware ships a Broadcom "dhd" build of the 4366c0 firmware
(version 10.10.122.20) whose embedded CLM data enables the full channel set
(including UNII-3, 149-165) on both 5 GHz radios. The generic
brcmfmac4366c-pcie.bin from linux-firmware carries a restricted CLM, so the
high-band radio refuses channels >= 149 and the second 5 GHz interface
cannot be used.

The firmware image is embedded (uncompressed) inside the stock kernel
module lib/modules/4.1.27/dhd.ko. It is a standard brcmfmac PCIe firmware
container: it starts with a small header (first word 0x00f23eb8) and ends
with the version banner ("4366c0-roml... Version: ... FWID ...") followed
by a 4-byte trailer.

Usage:
  extract-dhd-firmware.py <stock .img|dhd.ko|extracted-rootfs-dir> [--out FILE]

Defaults to writing brcmfmac4366c-pcie.bin in the current directory.
Requires ubireader_extract_files when given a .img (pip install ubireader).
No vendor binaries are distributed with this project.
"""

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

FW_MAGIC = bytes.fromhex("00f23eb8")
BANNER = b"4366c0-roml"
DHD_REL = "lib/modules/4.1.27/dhd.ko"


def find_dhd(path: str) -> str:
    if os.path.isfile(path) and path.endswith("dhd.ko"):
        return path
    if os.path.isfile(path):
        tmp = tempfile.mkdtemp(prefix="ea9300-stock-")
        print(f"extracting rootfs from {path} ...", file=sys.stderr)
        try:
            subprocess.run(["ubireader_extract_files", "-o", tmp, path],
                           check=True)
        except FileNotFoundError:
            sys.exit("ubireader_extract_files not found (pip install ubireader)")
        path = tmp
    for root, _dirs, files in os.walk(path):
        if "dhd.ko" in files and root.replace("\\", "/").endswith("4.1.27"):
            return os.path.join(root, "dhd.ko")
    sys.exit("dhd.ko not found")


def carve(data: bytes) -> bytes:
    banner = data.find(BANNER)
    if banner < 0:
        sys.exit("firmware banner not found in dhd.ko")
    # The image begins with a 64-byte preamble that contains the 32-byte
    # header block twice; pick the first copy of that pair.
    start = -1
    pos = 0
    while True:
        i = data.find(FW_MAGIC, pos)
        if i < 0 or i > banner:
            break
        if data[i:i + 32] == data[i + 32:i + 64]:
            start = i
            break
        pos = i + 1
    if start < 0:
        sys.exit("firmware header not found before the banner")
    end = data.find(b"\n\x00", banner)
    if end < 0:
        sys.exit("firmware trailer not found")
    end += 4
    blob = data[start:end]
    if b"CLM DATA" not in blob or b"Version:" not in blob:
        sys.exit("carved blob does not look like brcmfmac firmware")
    if not 500_000 < len(blob) < 4_000_000:
        sys.exit(f"unexpected firmware size {len(blob)}")
    return blob


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stock", help="stock .img, dhd.ko or extracted rootfs dir")
    ap.add_argument("--out", default="brcmfmac4366c-pcie.bin")
    args = ap.parse_args()

    dhd = find_dhd(args.stock)
    with open(dhd, "rb") as f:
        data = f.read()
    blob = carve(data)
    with open(args.out, "wb") as f:
        f.write(blob)
    m = re.search(rb"Version: ([^ ]+) .*?FWID ([0-9a-f]+)", blob)
    ver = m.group(1).decode() if m else "?"
    fwid = m.group(2).decode() if m else "?"
    print(f"wrote {args.out}: {len(blob)} bytes, firmware {ver}, FWID {fwid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
