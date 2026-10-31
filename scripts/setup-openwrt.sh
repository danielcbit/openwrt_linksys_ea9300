#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Assemble and build the OpenWrt tree for the Linksys EA9300.
#
# Usage:
#   setup-openwrt.sh <path-to-stock-firmware.img> [out-dir]
#
# The stock image is required once, to extract the CFE RAM binary
# (cferam.001) - a vendor binary that is not distributed with this
# repository. Everything else comes from vanilla OpenWrt plus overlay/.

set -e

STOCK_IMG="$1"
OUT_DIR="${2:-openwrt}"
OWRT_REPO="https://github.com/openwrt/openwrt.git"
OWRT_COMMIT="d014acb494001606ce78720e240892e840302a9d"   # master, 2026-10-22 (kernel 6.18.55)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[ -n "$STOCK_IMG" ] && [ -f "$STOCK_IMG" ] || {
	echo "usage: $0 <stock-firmware.img> [out-dir]" >&2
	exit 1
}

# 1. vanilla OpenWrt at the tested commit
if [ ! -d "$OUT_DIR" ]; then
	git init -q "$OUT_DIR"
	git -C "$OUT_DIR" remote add origin "$OWRT_REPO"
	git -C "$OUT_DIR" fetch -q --depth 1 origin "$OWRT_COMMIT"
	git -C "$OUT_DIR" checkout -q FETCH_HEAD
fi
git config --global --add safe.directory "$(cd "$OUT_DIR" && pwd)"

# 2. port overlay (target changes, patches, board files)
cp -a "$SCRIPT_DIR/../overlay/." "$OUT_DIR"/

# 3. vendor CFE RAM binary (extracted from the stock image, gitignored)
mkdir -p "$OUT_DIR/target/linux/bcm4908/image/linksys_ea9300"
if [ ! -f "$OUT_DIR/target/linux/bcm4908/image/linksys_ea9300/cferam.001" ]; then
	python3 "$SCRIPT_DIR/extract-stock-files.py" "$STOCK_IMG" \
		--out-dir "$OUT_DIR/target/linux/bcm4908/image/linksys_ea9300"
fi

# 4. optional: bake per-unit WiFi calibration data (else the preinit hook
#    regenerates it from the devinfo partition at every boot)
if [ -n "$EA9300_CALDATA" ] && [ -f "$EA9300_CALDATA" ]; then
	mkdir -p "$OUT_DIR/files/lib/firmware/brcm"
	cp "$EA9300_CALDATA" \
	   "$OUT_DIR/files/lib/firmware/brcm/brcmfmac4366c-pcie.linksys,ea9300.txt"
	echo "baked caldata from $EA9300_CALDATA"
fi

# 4b. BCM4366C0 firmware with full-channel CLM data. The linux-firmware
#     build refuses UNII-3 (149-165), which disables the high-band 5 GHz
#     radio; the stock Linksys dhd build has the CLM but is too old for
#     brcmfmac 6.x. fetch-wifi-firmware.sh downloads a hash-pinned 2021
#     build that works.
"$SCRIPT_DIR/fetch-wifi-firmware.sh" "$OUT_DIR/files/lib/firmware/brcm"

cd "$OUT_DIR"

# 5. feeds + config
./scripts/feeds update -a
./scripts/feeds install -a
cat > .config <<'EOF'
CONFIG_TARGET_bcm4908=y
CONFIG_TARGET_bcm4908_generic=y
CONFIG_TARGET_bcm4908_generic_DEVICE_linksys_ea9300=y
CONFIG_PACKAGE_luci=y
EOF
make defconfig

# 6. build (see BUILD.md for the known host-quirks)
make -j"$(nproc)" download
make -j"$(nproc)" REVISION="$(scripts/getver.sh)" FORCE_UNSAFE_CONFIGURE=1

echo
echo "image: $OUT_DIR/bin/targets/bcm4908/generic/openwrt-bcm4908-generic-linksys_ea9300-squashfs.bin"
