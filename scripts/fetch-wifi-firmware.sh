#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fetch a BCM4366C0 PCIe firmware build that carries full-channel CLM data.
#
# The brcmfmac4366c-pcie.bin shipped in linux-firmware (10.28.2, 2018) has a
# restricted CLM: channels >= 149 (UNII-3) are refused, so the EA9300's
# high-band 5 GHz radio (Linux phy0) cannot be used. The stock Linksys dhd
# build has the CLM but is too old (10.10.122.20, 2017) to work with
# brcmfmac 6.x - unicast data frames to stations are dropped and links flap.
#
# The 2021 build below (10.10.122.303, FWID 01-ccd91e51, extracted from an
# Asus router firmware) has the CLM and works with brcmfmac 6.x: all three
# radios come up and DHCP/data traffic works on both bands.
#
# Source: https://codeberg.org/floe/broadcom-4366c-firmware
#         (file brcmfmac4366c-pcie.bin.bf1a3b)
#
# Usage: fetch-wifi-firmware.sh [output-dir]
#   default output dir: files/lib/firmware/brcm (relative to cwd)
#
# Only a hash-pinned download is performed; the blob is not distributed
# with this project.

set -e

URL="https://codeberg.org/floe/broadcom-4366c-firmware/raw/branch/main/brcmfmac4366c-pcie.bin.bf1a3b"
SHA256="38e313a62cbd9bf70d717d1b14cd82165e3e684eefd389ecd16641f719d64d2b"
DEST="${1:-files/lib/firmware/brcm}"

mkdir -p "$DEST"
OUT="$DEST/brcmfmac4366c-pcie.bin"

if [ -f "$OUT" ] && [ "$(sha256sum "$OUT" | cut -d' ' -f1)" = "$SHA256" ]; then
	echo "wifi firmware already present in $OUT"
	exit 0
fi

TMP="$OUT.tmp"
echo "downloading BCM4366C0 firmware (10.10.122.303) ..."
if command -v curl >/dev/null 2>&1; then
	curl -sfL -o "$TMP" "$URL"
else
	wget -q -O "$TMP" "$URL"
fi

GOT="$(sha256sum "$TMP" | cut -d' ' -f1)"
if [ "$GOT" != "$SHA256" ]; then
	rm -f "$TMP"
	echo "checksum mismatch: got $GOT, expected $SHA256" >&2
	exit 1
fi
mv "$TMP" "$OUT"
echo "installed $OUT"
