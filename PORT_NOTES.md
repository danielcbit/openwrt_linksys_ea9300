# Port notes — Linksys EA9300 OpenWrt

Internals of the port: what was done, what was verified on hardware, and
what is still open. For flashing see [FLASHING.md](FLASHING.md), for
building see [BUILD.md](BUILD.md).

## Verified on hardware

- CFE v1.1.1 (Base 5.2_02HNDrc17), BCM4908_A0, 512 MB DDR3-1600,
  Winbond 256 MB NAND (BCH-4, 128 KiB blocks), board id `EA9300`.
- CFE network boot: at power-on it TFTP-requests `94908.dtb`,
  `ramdisk` and `vmlinux_rd_boot` from the host IP (192.168.1.254) before
  falling back to flash. **A served `ramdisk` file injects
  `root=/dev/ram0` into the kernel cmdline and panics OpenWrt** — keep no
  TFTP server running for normal boots.
- Kernel load: CFE decompresses the `vmlinux.lz` (BRCM wrapper header,
  load/entry 0x80000) — exactly the format OpenWrt's `bcm4908lzma` +
  `bcm4908kernel` produce.
- All three PCIe controllers link at 5.0 GT/s; endpoints at
  `0000:01:00.0`, `0001:01:00.0`, `0002:01:00.0` (BCM43666, PCI devid
  14e4:4365). Radio map: PCIE0 = 2.4 GHz (devpath `pcie/1/1`),
  PCIE1 = 5 GHz (`pcie/2/1`), PCIE2 = 5 GHz (`pcie/3/1`).
- SF2 switch: 4 GPHYs (lan1-4) + wan on internal phy12; 1 Gbps verified.
- USB: EHCI/OHCI (2 ports) + xHCI (2 ports) all enumerate.
- Buttons: **WPS = GPIO 29, Reset = GPIO 30**, both active-low (from the
  stock bdutil registration).

## Flash layout (verified from a real unit's /proc/mtd)

| Region | Offset | Size |
|---|---|---|
| nvram (CFE bootline) | 0x0000000 | 1 MiB |
| slot A | 0x0100000 | 79.5 MiB |
| slot B | 0x5080000 | 79.5 MiB |
| — bootfs (per slot) | slot start | 4.125 MiB |
| — rootfs (per slot) | +0x420000 | 75 MiB |
| devinfo | 0xa000000 | 8 MiB |
| sysdiag | 0xa800000 | 2 MiB |
| syscfg | 0xaa00000 | 76 MiB |
| crash | 0xf600000 | 1 MiB |
| data | 0xf700000 | 8 MiB |

Per-unit factory data (full sromrev-13 calibration for all three radios,
per-radio MACs, `et0macaddr`, regulatory `Q2/906`) lives in the **devinfo**
partition — not in nvram. `scripts/fetch-caldata.sh` and the preinit hook
read it and generate the brcmfmac NVRAM file.

## Boot slot selection (reverse-engineered)

CFE keeps a per-slot boot-tracker ("BT") sequence number inside each
slot's bootfs and boots the slot with the highest value; after a failed
boot it fails over to the other slot. `ws` always writes **slot A**
(0x100000) and refreshes its tracker, making it "latest".

Because there is no boot parameter naming the active slot, the port's
kernel patch (`321-mtd-parsers-ofpart-bcm4908-openwrt-slot-autodetect`)
scans both slots for OpenWrt's `1-openwrt` bootfs marker and names the
matching one `firmware` — the device boots OpenWrt from either slot no
matter what CFE's tracker says.

## WiFi radio mapping (reverse-engineered 2026-10)

All three BCM4366 cores are dual-band capable but each has a band-specific
RF path, and the devinfo blocks are NOT in Linux PCI order. The stock
firmware's syscfg (`wl*_mac_addr`, `wl*_available_channels`) is the source
of truth:

| devinfo block | stock wl | MAC | band | Linux phy |
|---|---|---|---|---|
| 1 | wl0 | ...BD | 2.4 GHz (1-11) | phy1 |
| 2 | wl1 | ...BE | 5 GHz 36-48 | phy2 |
| 3 | wl2 | ...BF | 5 GHz 149-165 | phy0 |

brcmfmac's v2 NVRAM prefixes are `pcie/<linux-domain+1>/1/`, so the preinit
hook maps block 3 -> pcie/1/1 (phy0), block 1 -> pcie/2/1 (phy1), block 2 ->
pcie/3/1 (phy2). Getting this wrong makes radios disappear or transmit into
the wrong band's filter (observed: -90 dBm instead of -39 dBm).

The high-band radio (phy0, channels 149-165) needs firmware with full
CLM data: the linux-firmware build (10.28.2) refuses channels >= 149
(`Set Channel failed ... -52`) regardless of NVRAM ccode/regrev or the host
country.

- The stock Linksys dhd.ko embeds a 4366c0 firmware (10.10.122.20, 2017)
  *with* the CLM (`scripts/extract-dhd-firmware.py` can carve it), but it
  is not usable with brcmfmac 6.x: DHCP replies and other unicast data
  frames to stations are silently dropped and links flap.
- `scripts/fetch-wifi-firmware.sh` downloads a hash-pinned 2021 build
  (10.10.122.303, FWID 01-ccd91e51, from codeberg.org/floe/
  broadcom-4366c-firmware) that has the CLM and works with brcmfmac 6.x.
  With it all three radios come up (5-2 on 149, 5-1 on 48, 2.4 on 6) and
  DHCP/data traffic works on both bands.

## Known open items

1. **LED GPIOs** — rear switch-port LEDs are mapped and implemented in the
   DTS (LED engine positions 0/2/4/6/10/17/18/19/21/26). Front panel mostly
   mapped (Internet=GPIO12, WPS=GPIO14, logo=pin15, USB=GPIO22/23); the
   front Ethernet logo LED is still unmapped. Full details and probing
   notes in `research/led-map.md`.
2. **`eth0` MTU** — DSA asks the conduit for 1504 (1500 + overhead) and
   the driver rejects it (`error -22`). Cosmetic; traffic works.
3. **No CLM blob** — brcmfmac reports "limited channels"; DFS channels
   may be restricted. A `brcmfmac4366c-pcie.clm_blob` would fix it if one
   surfaces. Note: with `CONFIG_FW_LOADER_USER_HELPER` enabled a missing
   blob becomes a fatal 0-byte file for one racing probe — the target
   config disables the user-helper (keep it that way).
4. **CLM/regulatory** — factory regdomain is `Q2/906`; set your real
   country in OpenWrt wireless settings.
5. **Boot slot tracker** — CFE failover can flip to the other slot after
   a panic; `c` → `Boot image 0/1` at the CFE prompt pins the choice.
   No OS-side confirmation of successful boot is implemented yet.
6. **Bootfs size** — the slot's bootfs partition is 4.125 MiB and the
   image pads it to 4 MiB (cferam 347 KB + vmlinux.lz ~3.7 MB + DTB). If
   a future kernel outgrows it, bump the LZMA dictionary
   (`bcm4908lzma` -d22 → -d25) or trim the kernel config.
