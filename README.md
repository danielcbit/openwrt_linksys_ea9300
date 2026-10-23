# OpenWrt for the Linksys EA9300 (BCM4908)

Unofficial OpenWrt port for the **Linksys EA9300 Max-Stream AC4000 Tri-Band**
router — a Broadcom **BCM4908** (4× ARMv8 Brahma-B53 @ 1.8 GHz) device that
has never been supported by OpenWrt, DD-WRT or Tomato.

This repository contains everything needed to build and flash OpenWrt on it:
a patch/overlay series against vanilla OpenWrt master, scripts to extract the
few required vendor files from the stock firmware image, and scripts to pull
per-unit WiFi calibration data from the router itself.

> **Status: working on real hardware.** Boot, switch (LAN1-4 + WAN),
> USB 2.0/3.0, and all three WiFi radios with per-unit factory calibration.
> See [Status](#status) and [PORT_NOTES.md](PORT_NOTES.md) for details.

## Hardware

| Component | Detail |
|---|---|
| SoC | Broadcom BCM4908 — 4× Brahma-B53 (ARMv8, Cortex-A53 class) @ 1.8 GHz |
| RAM | 512 MB DDR3-1600 |
| Flash | 256 MB NAND (Winbond), dual firmware slots |
| Switch | 5-port GbE inside the SoC (SF2): WAN + LAN1-4 |
| WiFi | 3× BCM4366 (PCI devid 14e4:4365), 3×3 used of 4×4: 2× 5 GHz + 1× 2.4 GHz, on the SoC's own PCIe controllers |
| USB | 2× USB 3.0 |
| Serial | 4-pin header, 3.3 V TTL, 115200 8N1 |
| Boot | CFE (kept; the port reuses the stock CFE RAM stage) |

## How it works

The port reuses the device's own bootloader flow instead of replacing it:

1. CFE (stock, extracted from the factory update image) loads three files
   from a small JFFS2 "bootfs" partition: `cferam.000/001` (itself),
   `94908.dtb` (our device tree) and `vmlinux.lz` (our kernel, in
   Broadcom's wrapper format).
2. It then boots the kernel, which mounts the squashfs rootfs from the UBI
   image that follows in the same flash slot.

OpenWrt's `bcm4908` target produces exactly this image format, so the
resulting `.bin` can be written with CFE's own `ws` command over TFTP.

Main port pieces (see `overlay/`):

- **PCIe controllers** for BCM4908 in the SoC dtsi, plus two required
  `pcie-brcmstb` fixes (UBUS inbound `ACCESS_EN` and CPU_INTR1 unmasking)
  without which PCIe endpoints enumerate but cannot work. Patterned after
  the hardware-verified OpenWrt PR #24902 (Archer C2300 v1).
- **`bcm4908-linksys-ea9300.dts`** with the real flash layout (verified
  against `/proc/mtd` on hardware), WPS/Reset buttons, all three PCIe
  controllers, and dual firmware slots.
- **Boot-slot auto-detection**: the dual-slot layout has no boot parameter;
  a small patch to the bcm4908 partition parser picks the slot whose bootfs
  contains OpenWrt's `1-openwrt` marker, so the device boots OpenWrt no
  matter which slot CFE wrote.
- **WiFi calibration**: the factory radio/PA/regulatory data lives in the
  `devinfo` NAND partition. A preinit hook regenerates
  `/lib/firmware/brcm/brcmfmac4366c-pcie.linksys,ea9300.txt` from it at
  every boot, so each unit runs with its own calibration and MAC addresses.
- **mtdsplit fix**: `cfe_bootfs` must return `-ENOENT` (not `-EINVAL`) for
  the non-active slot, or the whole dual-slot layout fails to parse.
- **Host tool fix**: `firmware-utils`' `bcm4908kernel` uses `char` for a
  `getopt()` result — on ARM64 build hosts plain `char` is unsigned, EOF
  becomes 255 and the tool spins forever.

## Quick start

Prerequisites: a Linux host (or Docker), `git`, `python3`, the stock
firmware image `FW_EA9300_1.1.9.183697_prod.img` from
[Linksys](https://downloads.linksys.com/downloads/firmware/FW_EA9300_1.1.9.183697_prod.img)
(needed once, to extract the vendor CFE RAM binary), and optionally a
caldata file produced by [scripts/fetch-caldata.sh](scripts/fetch-caldata.sh)
(else the image regenerates it from the device at boot).

```sh
scripts/setup-openwrt.sh FW_EA9300_1.1.9.183697_prod.img
# … coffee …
# → openwrt/bin/targets/bcm4908/generic/openwrt-bcm4908-generic-linksys_ea9300-squashfs.bin
```

Details, including Docker usage and host-quirk notes:
[BUILD.md](BUILD.md).

## Flashing

Flashing happens from the CFE bootloader prompt over serial (3.3 V TTL,
115200 8N1) with `loadb n` (TFTP → RAM) + `ws` (RAM → the inactive flash
slot). The stock `.img` itself is rejected by `ws`; use `stock-ws.bin`
built by `extract-stock-files.py --rescue`.

Full procedure, slot layout, dual-boot switching and recovery:
[FLASHING.md](FLASHING.md).

## Status

| Component | State |
|---|---|
| Boot (CFE → OpenWrt kernel+DTB, either slot) | ✅ |
| NAND dual-slot layout, mtdsplit, UBI overlay | ✅ |
| Switch (LAN1-4 + WAN, 1 Gbps, DSA) | ✅ |
| USB 2.0 + USB 3.0 (2 ports) | ✅ |
| WiFi 3× BCM4366 (2.4 + 2× 5 GHz) via brcmfmac | ✅ with per-unit caldata |
| Buttons (Reset = GPIO30, WPS = GPIO29) | ✅ |
| LEDs | ❌ GPIOs not yet identified |
| Eth MAC addresses | ⚠️ set from devinfo at boot (hotplug), wifi from caldata |
| Known nits | `eth0` MTU message (DSA overhead, cosmetic); no CLM blob ("limited channels", DFS restricted); `uboot-envtools` noise |

## Repository layout

```
overlay/    everything applied onto vanilla OpenWrt master (target changes,
            kernel patches, board files)
scripts/    setup + vendor-file extraction + caldata extraction
FLASHING.md verified flashing / dual-boot / recovery procedure
BUILD.md    build instructions and host-quirk notes
PORT_NOTES.md  port internals, flash layout, known unknowns
```

`overlay/` is applied onto vanilla OpenWrt master at commit
`d014acb494001606ce78720e240892e840302a9d` (2026-10-22, kernel 6.18.55).
No vendor binaries or per-unit data are distributed here —
`scripts/extract-stock-files.py` pulls the CFE RAM binary out of the stock
image you provide, and `scripts/fetch-caldata.sh` pulls calibration out of
your device.

## Credits

- [Rafał Miłecki](https://github.com/zajec) — the OpenWrt `bcm4908` target,
  `bcm4908img`/`bcm4908kernel` tools, and most of the BCM4908 upstream
  drivers this port stands on.
- OpenWrt PR [#24902](https://github.com/openwrt/openwrt/pull/24902)
  (Anatoliy Shulika) — PCIe controller DTS and the two brcmstb fixes,
  hardware-verified on the Archer C2300 v1.
- The [OpenWrt](https://openwrt.org) project.

## License

Everything in this repository is GPLv2 — same as OpenWrt and the Linux
kernel components it builds on. See [LICENSE](LICENSE).
