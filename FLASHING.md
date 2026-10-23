# Flashing the Linksys EA9300 — verified procedure

This is the procedure validated on real hardware (2026-10). The EA9300's
CFE has **no web recovery UI** and holding reset at power-on does
nothing at the CFE level — flashing is done over **serial + TFTP**.

## Requirements

- Serial console: 3.3 V TTL, 115200 8N1 (4-pin header)
- PC on a LAN port with static IP `192.168.1.254/24`
- TFTP server serving the files (e.g. `tftp-now serve -root <dir> -port 69 -verbose`)
- Router CFE network config: board 192.168.1.1, host 192.168.1.254 (factory)

## CFE basics

- Press any key during the boot countdown (`Boot delay: 3` set via `c`) to get the `CFE>` prompt.
- **Do not run a TFTP server during normal reboots**: with `Run from flash/host/tftp = c`,
  CFE tries to TFTP-load `94908.dtb`/`ramdisk`/`vmlinux_rd_boot` at every boot.
  A `ramdisk` reply injects `root=/dev/ram0` into the kernel cmdline and panics OpenWrt.
- Flashing uses `loadb n` (TFTP → RAM) followed by `ws` (RAM → inactive flash slot).
  **Type the `ws` arguments by hand** — pasting long arguments over serial can
  corrupt them (the source of several `ws` crashes during bring-up).
- `ws` always writes the **inactive** slot; CFE then boots it as "latest".

## Flash OpenWrt

```
CFE> loadb n 0x02000000 192.168.1.254:openwrt.bin
CFE> ws 0x02000000 <size-from-loadb-output>
```
Stop the TFTP server, then `reset`. OpenWrt: 192.168.1.1 (root, no password).

## Restore / install stock

The stock `.img` must be re-tailed: it carries a Linksys vendor tail
instead of the 20-byte BCM4908 tail CFE's `ws` validates. `stock-ws.bin`
is the factory 1.1.9 image with a proper tail (built with
`bcm4908img create -f <img minus 273 tail bytes>`):

```
CFE> loadb n 0x02000000 192.168.1.254:stock-ws.bin
CFE> ws 0x02000000 43646999
```

## Dual boot

| Slot | Offset | Contents (current) |
|---|---|---|
| A ("previous"/backup) | 0x100000 | whichever was flashed last-but-one |
| B ("latest"/firmware) | 0x5080000 | whichever was flashed last |

- CFE boots the slot with the highest boot-tracker value ("latest");
  after a failed boot it fails over to the other slot.
- `CFE> c` → `Boot image (0=latest, 1=previous)` overrides the choice.
  Flip it to switch between stock and OpenWrt without reflashing.
- Our kernel auto-detects the OpenWrt slot (`1-openwrt` bootfs marker),
  so either slot boots either firmware correctly.

## Arranging a specific dual-boot layout

`ws` always writes the **inactive** slot and makes it "latest" + boots it,
so the **last** file flashed ends up as the default OS. To get
`A = OpenWrt (latest)`, `B = stock (previous)`:

1. Booted from OpenWrt (B): flash **stock** → lands on A, boots stock.
   `loadb n 0x02000000 192.168.1.254:stock-ws.bin` + `ws 0x02000000 43646999`
2. Booted from stock (A): flash **OpenWrt** → lands on B, boots OpenWrt.
   `loadb n 0x02000000 192.168.1.254:openwrt.bin` + `ws 0x02000000 9961492`
3. Booted from OpenWrt (B): flash **OpenWrt again** → lands on A, boots
   OpenWrt from A. (Same commands as step 2.)

Between steps: stop the TFTP server, `reset`, verify which slot booted
from the address/kernel-banner lines, then start the server again for
the next step. Note: rewriting a slot wipes that slot's `rootfs_data`
(overlay/config) — redo password/country/SSIDs after the final flash.

## First-boot checklist (OpenWrt)

```
passwd
# LuCI → Network → Wireless: set country (factory blob is Q2/906) + SSIDs
dmesg | grep -iE "brcmfmac"     # expect 3x BCM43666 firmware 10.28.2 attach
ip link                          # lan1-4, wan, wlan0-2
```

Known cosmetic issues: LED GPIOs unmapped; `eth0` MTU message (DSA
overhead, harmless); `fw_env.config` noise from uboot-envtools (harmless);
no CLM blob shipped ("limited channels" — DFS channels may be restricted).
