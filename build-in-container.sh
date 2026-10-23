#!/bin/sh
# Build script: runs INSIDE the Linux container
set -e
cd /build

echo "== Installing build deps"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	build-essential clang flex bison g++ gawk gcc gettext git \
	libncurses-dev libssl-dev python3 python3-setuptools python3-dev \
	rsync unzip zlib1g-dev file wget curl xz-utils ca-certificates \
	swig libelf-dev python3-pyelftools ccache time >/dev/null

echo "== Feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "== Config"
cat > .config <<'EOF'
CONFIG_TARGET_bcm4908=y
CONFIG_TARGET_bcm4908_generic=y
CONFIG_TARGET_bcm4908_generic_DEVICE_linksys_ea9300=y
CONFIG_PACKAGE_luci=y
EOF
make defconfig

echo "== Download"
make -j"$(nproc)" download

echo "== Build"
make -j"$(nproc)" V=s 2>&1 | tee /build/build.log | tail -n 5
