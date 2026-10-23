#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Extract per-unit WiFi calibration data for the Linksys EA9300 and format
# it as a brcmfmac NVRAM file.
#
# The unit's factory data (sromrev-13 radio blocks for all three BCM4366
# radios, devpath entries, per-radio MAC addresses, regulatory settings)
# lives in the "devinfo" NAND partition as NUL-separated key=value pairs.
#
# Usage:
#   on the router:      fetch-caldata.sh                 (reads devinfo mtd)
#   from a dump file:   fetch-caldata.sh <dump-file>
#
# Output on stdout: brcmfmac4366c-pcie.linksys,ea9300.txt content.
# Bake it into an image at openwrt/files/lib/firmware/brcm/ or rely on the
# preinit hook (81_linksys_ea9300_nvram) which regenerates it at every boot.

set -e

FILE=""
if [ -n "$1" ]; then
	FILE="$1"                       # offline: parse a devinfo dump
else
	# on-device: locate the devinfo partition (fallback: nvram)
	mtd=""
	for part in devinfo nvram; do
		mtd="$(sed -n "s/^\\(mtd[0-9]*\\):.* $part\$/\\1/p" /proc/mtd)"
		[ -n "$mtd" ] && break
	done
	[ -n "$mtd" ] || { echo "no devinfo/nvram partition found" >&2; exit 1; }
	FILE="/dev/$mtd"
fi

tr '\0' '\n' < "$FILE" 2>/dev/null | awk -F= '
	/^(devpath[0-9]+|[0-9]+:|et0macaddr|boardnum|boardtype|boardflags|boardrev)/ { print }
'
