# zettnas-unraid

**Run Unraid on a Zettlab NAS — from a USB stick prepared on Windows to a stable system that never shuts down, with both the CPU and HDD fans controlled.**

> Tested on a **Zettlab D6 Ultra** (Intel Core Ultra 5 125H) with **Unraid 7.3.4**. Other Zettlab models (D4 / D6 / D8) are probably similar but are **untested**.
>
> 🇳🇱 Nederlandse versie: [README.nl.md](README.nl.md)

> ⚠️ **Disclaimer:** use at your own risk. The fan script writes directly to physical memory (`/dev/mem`) to talk to the embedded controller. Wrong values or addresses on a different board could cause hangs or overheating. No warranty — see [LICENSE](LICENSE).

## Why this is needed

Out of the box, Unraid on a Zettlab has two problems:

1. **It beeps and hard-reboots after a few minutes.** ZettOS feeds a hardware watchdog timer. Unraid's kernel has no driver for it (no ACPI WDAT table, no `iTCO_wdt`/`wdat_wdt`), so the watchdog fires. → Disable it in the BIOS.
2. **It overheats and shuts down (often within ~1 minute under load).** The fans are on the embedded controller (EC), not on standard hwmon PWM. Under Unraid the CPU fan stays **off** in EC "auto" mode. → Use the script in this repo.

## Contents

1. [Requirements](#1-requirements)
2. [BIOS settings (F2 / F12)](#2-bios-settings)
3. [Choose what to do with the internal SSD](#3-internal-ssd-options)
4. [Hardware gotchas](#4-hardware-gotchas)
5. [Install and array setup](#5-install-and-array-setup)
6. [Fan control](#6-fan-control)
7. [Verification checklist](#7-verification-checklist)
8. [Troubleshooting](#8-troubleshooting)
9. [Optional extras](#9-optional-extras)
10. [Credits](#credits)

## 1. Requirements

- **A USB stick** (8–32 GB, USB 2.0/3.0, with a unique GUID). Some sticks are **not detected at boot** by the Zettlab firmware. A **SanDisk Cruzer Fit** worked; the first stick tried did not. If you see *"boot device not found"*, try another stick.
- **Unraid USB Creator** on Windows (from unraid.net), or the manual method (FAT32, label `UNRAID`, extract the zip, run `make_bootable.bat` as administrator).
- An Unraid **trial or license key**. Keys are tied to the stick's GUID, so pick a stick you will keep.
- A monitor + keyboard (HDMI/USB) for the BIOS steps.
- A small screwdriver if you open the case to swap the NVMe.

In the USB Creator: choose the Unraid version (7.3.x), select the stick, optionally set a hostname and static IP, and write.

## 2. BIOS settings

Power on and press **F2** repeatedly to enter the BIOS. Change:

| Setting | Value | Why |
|---|---|---|
| **Secure Boot** | **Disabled** | Unraid's bootloader is not signed for Secure Boot |
| **Watchdog Timer (WDT)** | **Disabled** | **Critical.** Otherwise beep + hard reboot after a few minutes (no driver in Unraid to feed it) |
| **HDD power on sequence** | **Enabled** | Staggered spin-up; avoids power peaks / disks not detected |
| **Boot order** | **USB first** | So it boots Unraid without intervention |

Save and exit (usually F10).

**F12** at power-on opens the **one-time boot menu**: use it to pick the USB stick for the first boot or when testing.

> The WDT step comes from the excellent [henryxwong/zettlab-ubuntu](https://github.com/henryxwong/zettlab-ubuntu) guide.

## 3. Internal SSD options

The unit ships with ZettOS on an internal NVMe SSD.

- **Option A (recommended): keep ZettOS as a fallback.** Remove the original SSD, store it safely, and install a spare NVMe to use as Unraid **cache** (appdata, Docker, VMs). You can always go back to ZettOS by swapping it back and changing the boot order.
- **Option B: reuse the original SSD.** Wipe it in Unraid and use it as cache. ZettOS is gone unless you have a backup image.

### ⚠️ Watch out: Unraid 7.x "internal boot"

The Unraid 7.x installer may offer **internal boot**, which puts the boot files on the NVMe as a ZFS pool named `flash`. If you want normal **USB boot**, choose **USB**.

**Recovery if it already happened** (⚠️ `wipefs` **destroys all data** on that NVMe — double-check the device name):

1. Copy `/boot/config` to the USB stick's `config` folder (from the running system or another PC).
2. On the USB stick, delete `config/pools/boot.cfg`.
3. Boot from USB (F12).
4. In a terminal:
   ```bash
   zpool export flash
   wipefs -a /dev/nvme0n1    # DESTRUCTIVE — verify with lsblk first
   ```
5. Now assign the NVMe as a normal cache pool.

## 4. Hardware gotchas

- **No HDDs visible after opening the case?** The **SATA bridge board cable** came loose. Reconnect it firmly.
- **A disk shows "missing" after moving the unit?** Check `dmesg | grep -i "link down"`. A `SATA link down` means the disk is not seated: power down, reseat the disk in its bay, check the bridge cable, boot again. **Do not start the array** until all disks are back.

## 5. Install and array setup

1. Boot from USB, open `http://tower.local` (or the IP shown on screen), set the root password, and start the trial.
2. **Identify disks by serial number**, not by device letter — the USB stick becomes `sda`, so letters shift.
3. Assign **1 parity** (must be ≥ the largest data disk) and the rest as **data** disks. Assign the NVMe as **cache**.
4. Start the array and **format** the new disks. The first parity sync takes many hours; data is not protected until it finishes.
5. **Settings → Docker**: use **directory** mode (not a docker.img).
6. Shares: `appdata` and `system` (and `domains`) → **Cache only**. Data shares → cache → array with Mover.

Recommended afterwards: Fix Common Problems, flash backup, notifications, a monthly parity check (write corrections off), spin-down (30–60 min), and the **Appdata Backup** plugin (to a `backups` share on the array).

## 6. Fan control

### How the fans work

The fans are driven by the **embedded controller** via MMIO, accessed through `/dev/mem`:

| | Offset from `0xFE0B0456` |
|---|---|
| Disk fan 1 RPM (16-bit big-endian) | `+0` |
| Disk fan 1 PWM | `+2` |
| Disk fan 2 RPM | `+3` |
| Disk fan 2 PWM | `+5` |
| CPU fan RPM | `+6` |
| CPU fan PWM | `+8` |

- PWM range is **0–183** (183 = 100%). `0` = EC auto.
- On EC auto the **CPU fan stays off** under Unraid, so the script drives it from `coretemp`.
- Disk fans follow the hottest HDD (SMART attribute 194/190; standby disks are not woken).
- On exit (kill, shutdown) the script sets **all fans to full speed** as a fail-safe.
- Standard hwmon tools — **FanCtrl Plus, Dynamix AutoFan, it87/nct6775 drivers** — **do not work** on this board. Don't install them alongside this script.

### Install

From the Unraid terminal (or copy the file onto the flash share):

```bash
wget -O /boot/config/zettlab-fans.sh https://raw.githubusercontent.com/rubenbolink/zettnas-unraid/main/zettlab-fans.sh
echo 'nohup bash /boot/config/zettlab-fans.sh >/dev/null 2>&1 &' >> /boot/config/go
nohup bash /boot/config/zettlab-fans.sh >/dev/null 2>&1 &
```

Check it:

```bash
cat /var/log/zettlab-fans.log
# 2026-10-24 21:00:00 hdd=41C cpu=50C disk_pwm=113 cpu_pwm=90
```

### Tuning

Defaults (top of the script):

```bash
D_MIN=70;  D_MAX=183; T_LO=35; T_HI=48; T_PANIC=55   # disk fans vs hottest HDD (°C)
C_MIN=90;  C_MAX=183; C_LO=50; C_HI=80               # CPU fan vs coretemp (°C)
INTERVAL=10                                          # seconds
```

Linear curve between `*_LO` → `*_MIN` and `*_HI` → `*_MAX`; above `T_PANIC` disk fans go to max. After editing:

```bash
pkill -f zettlab-fans.sh
nohup bash /boot/config/zettlab-fans.sh >/dev/null 2>&1 &
```

### Testing

[`fan-test.sh`](fan-test.sh) reads RPMs and can set a fixed PWM for all fans:

```bash
pkill -f zettlab-fans.sh      # stop the controller first
bash fan-test.sh              # read
bash fan-test.sh 120          # set all fans to 120/183, then read
```

> RPM reads work on the D6 Ultra (e.g. `1901 1879 2933`). A reading of `0` means that fan is stopped — for example the CPU fan left on EC auto (PWM 0).

## 7. Verification checklist

- [ ] Uptime keeps increasing past 10–15 minutes without beeps (WDT off)
- [ ] `cat /var/log/zettlab-fans.log` updates every 10 s
- [ ] CPU fan audibly spins; CPU temp stays well below 80 °C under load
- [ ] HDDs stay below ~45 °C during parity sync
- [ ] All disks present by serial; no `SATA link down` in `dmesg`
- [ ] After a reboot, the fan script starts automatically (check `ps aux | grep zettlab-fans`)

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Beeps, then hard reboot after a few minutes | Hardware watchdog (WDT) | BIOS (F2) → disable Watchdog Timer |
| Shuts down from overheating after ~1 minute | Fans not controlled | Install `zettlab-fans.sh` |
| CPU fan doesn't spin | EC auto mode keeps it off | Make sure the script is running |
| No HDDs visible | SATA bridge cable loose | Reconnect the bridge board cable |
| Disk missing / `SATA link down` | Disk not seated after moving | Power down, reseat disk |
| "Boot device not found" | Stick not supported by firmware | Try another stick (SanDisk Cruzer Fit worked) |
| Boots from NVMe instead of USB | 7.x internal boot chosen | See [section 3](#️-watch-out-unraid-7x-internal-boot) |

## 9. Optional extras

- **Intel iGPU for Ollama:** use the official `ollama/ollama` image, add device `/dev/dri`, and set `OLLAMA_VULKAN=1` and `OLLAMA_IGPU_ENABLE=1`.
- **Tailscale:** with the Tailscale plugin, add the Tailscale interface under *Settings → Management Access* (listen interfaces) so SSH/WebGUI are reachable over the tailnet; restart sshd afterwards.
- **UPS via a Synology:** install the **NUT** plugin, mode *Netclient*, remote = your Synology's IP, UPS name `ups`, user `monuser`, password `secret` (Synology default). Enable the network UPS server on the Synology and allow the Unraid IP.

## Credits

- [henryxwong/zettlab-ubuntu](https://github.com/henryxwong/zettlab-ubuntu) — Ubuntu on Zettlab, including the watchdog BIOS step
- [haveacry/zettlab-d8-fans](https://github.com/haveacry/zettlab-d8-fans) — kernel module documenting the EC fan registers on the D8
- [fr0styx/zettnas-toolkit](https://github.com/fr0styx/zettnas-toolkit) — ZettNAS Toolkit

Contributions and reports for other Zettlab models are welcome — open an issue or PR.
