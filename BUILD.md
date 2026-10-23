# Building

`scripts/setup-openwrt.sh` assembles vanilla OpenWrt master (pinned commit)
with the `overlay/` port files and builds it. The vendor CFE RAM binary is
extracted from your stock firmware image — it is **not** distributed here.

```sh
scripts/setup-openwrt.sh FW_EA9300_1.1.9.183697_prod.img
```

Incremental rebuilds: re-run `make -j$(nproc) REVISION=$(scripts/getver.sh)`
inside the tree (or just re-run the setup script — it is idempotent).

Optional: bake per-unit WiFi calibration into the image instead of relying
on the boot-time regeneration (see `scripts/fetch-caldata.sh`):

```sh
EA9300_CALDATA=caldata.txt scripts/setup-openwrt.sh FW_EA9300_*.img
```

## On macOS / Docker

OpenWrt requires a case-sensitive filesystem, so build inside a Linux
container with the tree in a named volume (not a bind mount):

```sh
docker volume create openwrt-build
# populate + run … see git history of this file for the full session,
# or simply:
docker run -d --name owbuild -v openwrt-build:/build ubuntu:24.04 sleep infinity
docker exec owbuild sh -c 'apt-get update && apt-get install -y build-essential \
  clang flex bison g++ gawk gcc gettext git libncurses-dev libssl-dev python3 \
  python3-setuptools rsync unzip zlib1g-dev file wget curl xz-utils swig \
  libelf-dev python3-pyelftools'
# then copy this repo in and run scripts/setup-openwrt.sh inside the container
```

## Known build quirks (all pre-solved in this repo)

1. **`FORCE_UNSAFE_CONFIGURE=1`** — host `tar` refuses to configure as root.
2. **`scripts/getver.sh` needs git metadata** — with a tarball tree the
   version becomes `~unknown` and `apk` rejects the package version. Clone
   (the setup script does) or commit locally.
3. **`tools/firmware-utils` `bcm4908kernel.c` uses `char` for `getopt()`** —
   on ARM64 Linux hosts plain `char` is unsigned, EOF becomes 255 and the
   tool spins at 100% CPU forever. Patched in
   `overlay/tools/firmware-utils/patches/`.
4. On non-x86 hosts, anything that spawns `qemu` will fail — not needed
   for this target.

## Validation

```sh
B=openwrt/bin/targets/bcm4908/generic/openwrt-bcm4908-generic-linksys_ea9300-squashfs.bin
staging_dir/host/bin/bcm4908img info -i $B
staging_dir/host/bin/bcm4908img bootfs -i $B ls   # 1-openwrt, 94908.dtb, cferam.001, vmlinux.lz
```

`bootfs offset: 0x0`, `rootfs offset: 0x400000`, valid checksum. Then see
[FLASHING.md](FLASHING.md).
