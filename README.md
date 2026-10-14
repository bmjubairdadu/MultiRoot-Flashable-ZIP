# MultiRoot Flashable ZIP

**One recovery-flashable ZIP installs KernelPatch + Magisk root — then whichever root manager app you install (FolkPatch, APatch, or Magisk) manages it.** Flash in TWRP/OrangeFox, reboot, done. Ships with a matching **Uninstaller ZIP** that removes everything **without needing or creating a single backup file**.

> **TL;DR:** KernelPatch `0.13.8` kernel patch (→ **FolkPatch** + **APatch** managers) + Magisk `30.6` ramdisk patch (→ **Magisk** app) — two root providers active from one flash. See the [KSU section](#about-kernelsu-managers) for KernelSU support status.

[![Build ZIPs](https://github.com/bmjubairdadu/MultiRoot-Flashable-ZIP/actions/workflows/build.yml/badge.svg)](https://github.com/bmjubairdadu/MultiRoot-Flashable-ZIP/actions/workflows/build.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

---

## Which file do I need?

| File | Use it when… |
|---|---|
| `MultiRoot-v2.1-Recovery-Installer.zip` | You want root: flash in recovery, reboot, done ✅ |
| `MultiRoot-v2.1-Uninstaller.zip` | You want to unroot: no backup needed |
| `SHA256SUMS.txt` | Verify downloads before flashing |

All three official manager APKs (`me.yuki.folk` FolkPatch + APatch + Magisk Manager) are bundled **inside** the ZIP — the installer copies them to sdcard for you automatically.

---

## Requirements

| Requirement | Notes |
|---|---|
| Android device (Android 6.0 to 15+) | Supported (ARM64 & 32-bit ARM) |
| Custom recovery (TWRP / OrangeFox / Lineage) | Required — `adb sideload` works too |
| `CONFIG_KALLSYMS=y` in the kernel | Optional — Enables KernelPatch (FolkPatch/APatch); if missing, Magisk provides full universal root |
| Unlocked bootloader | Required |
| Battery ≥ 50% | Recommended |

Works on A-only, A/B, and Virtual A/B devices. The kernel always lives in the **`boot`** partition — `vendor_boot` is never touched.

---

## How to flash

1. Copy the ZIP to your sdcard / storage.
2. Recovery → **Install** → select the ZIP (or `adb sideload` it).
3. The installer will:
   - Detect the boot partition and slot automatically
   - Unpack the boot image and patch the kernel with **KernelPatch** (superkey: `su`, if supported)
   - Patch the ramdisk with **Magisk** (on Android 13+ GKI devices where boot has no ramdisk, Magisk goes to `init_boot` instead)
   - Clean any existing patch first, so re-flashing is always safe
   - Flash directly → verify by reading the partition back → print `ROOT ACTIVE` / `MAGISK ACTIVE`
   - Copy `FolkPatch-Manager.apk`, `APatch-Manager.apk`, and `Magisk-Manager.apk` to sdcard
4. Reboot → install **any one** manager:
   - `Magisk-Manager.apk` (sdcard) → manages Magisk root, grants superuser to all apps
   - `FolkPatch-Manager.apk` (sdcard) → shows Installed/Active
   - `APatch-Manager.apk` (sdcard) → manages the KernelPatch kernel
   - KernelSU app / other root managers → gets root permission via `su`
5. Grant Superuser per app inside whichever manager you use.

### Mode selection (optional)

Default mode is **all** (KernelPatch + Magisk together). Want only one? Create `root-mode.txt` on sdcard with a single word:

| Mode | What gets installed |
|---|---|
| `all` (default) | KernelPatch + Magisk — both active |
| `kpatch` | KernelPatch only — FolkPatch / APatch managers |
| `magisk` | Magisk only — Magisk app |

Then re-flash the same ZIP: the installer cleans the old patch and applies the new mode. `/data/media/0/root-mode.txt` and `/external_sd/root-mode.txt` work as fallbacks.

---

## Uninstall / unroot

Flash `MultiRoot-v2.0-Uninstaller.zip` in recovery. It:

- **KernelPatch** → live kernel unpatch via `kptools -u` (no backup required)
- **Magisk** → restores the ramdisk from the internal `.backup` stored inside the patched boot image itself
- Restores the Magisk ramdisk in `init_boot` too, if present
- Removes every root file from `/data`: FolkPatch/APatch daemon (`/data/adb/ap*`, `/data/adb/fp`), Magisk (`/data/adb/magisk*`, modules, post-fs-data.d, service.d), KernelSU (`/data/adb/ksu*`), plus any old `FolkPatch-Backup` folders and flash reports
- Verifies by reading the partition back and prints `STOCK CONFIRMED`

Uninstall the manager **apps** manually from Android settings afterwards.

---

## About KernelSU managers

**KernelSU / KernelSU Next / SukiSU managers do not work with this ZIP**, because:

- The KernelSU family needs its code compiled into the kernel, and that requires **a prebuilt kernel/LKM matching your exact kernel version (KMI)** — impossible to bundle in a universal ZIP.
- Want KSU anyway? The KSU-Next/SukiSU manager app can install its own LKM/GKI image for your device from its "Install" page — that is a separate step.
- The **Uninstaller still cleans KernelSU** `/data/adb` leftovers for you.

One flash gives you FolkPatch + APatch + Magisk — three manager families can be active at once. Using one manager as your primary is still recommended (see FAQ).

---

## Backup policy: not a single backup file is created

The old v1 installer created `FolkPatch-Backup/` folders, `ori.img`, and flash reports. **None of that exists anymore** — and stale files from v1 are deleted when you flash the installer or uninstaller:

- No `stock-*.img` / `boot.img` copies are written to sdcard or `/data`
- All patch work happens in `/tmp` (RAM/tmpfs) and is deleted at the end
- Magisk uninstall relies on the `.backup` **inside the boot image itself** — not on any external file
- If you want a stock `boot.img` copy for extra safety, keep one yourself from your firmware package — this ZIP will not.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No `ROOT ACTIVE` in the recovery log | The flash didn't reach the partition — flash the Uninstaller and retry |
| Manager shows "Not installed" | Install the APK from the ZIP (sdcard copy), reboot, open again |
| `kernel requires CONFIG_KALLSYMS=y` | This kernel cannot be patched — root is impossible on it |
| `new-boot.img missing` / repack failed | ZIP damaged — re-download and verify SHA-256 |
| Bootloop | Flash the MultiRoot Uninstaller ZIP (or `fastboot flash boot` your stock boot.img) |
| `su: not found` in adb shell | Normal — FolkPatch/APatch have no `/system/bin/su`; grant per-app inside the manager |
| Both KP and Magisk installed — which `su` wins? | Both daemons run; which `su` appears in a terminal depends on boot-time mount order. Per-app grants follow the manager you granted in |

---

## FAQ

**Is this official?**
No — a community repackaging. FolkPatch: [LyraVoid](https://github.com/LyraVoid/FolkPatch), KernelPatch: [bmax121](https://github.com/bmax121/KernelPatch), APatch: [bmax121/APatch](https://github.com/bmax121/APatch), Magisk: [topjohnwu/Magisk](https://github.com/topjohnwu/Magisk). All binaries come from the official upstream releases and are SHA-256 verified at build time; the installer scripts are original work from this repo (GPL-3.0).

**Do I need to enter a superkey?**
No. The kernel is patched with the fixed superkey `su`; the FolkPatch/APatch managers authenticate by APK signature. There is no key screen.

**Can I install all three manager apps?**
Yes — but using one as your primary is recommended. With both Magisk and KP active, one daemon owns `/system/bin/su` depending on mount order; each daemon still handles the apps you granted in its own manager.

**Will it trip Play Integrity / SafetyNet?**
Root inherently affects attestation — use Shamiko/SUSFS-style hiding modules and the manager's denylist. No guarantees.

**Does `adb sideload` work?**
Yes — each ZIP contains exactly one script, so dispatch works under sideload too.

---

## How it works

| Component | Role |
|---|---|
| `META-INF/.../update-binary` | Recovery bootstrap: busybox setup, picks the script by ZIP name |
| `assets/InstallMultiRoot.sh` | Read boot → unpack (magiskboot) → Samsung hexpatches → KernelPatch kernel patch → Magisk ramdisk patch → repack → flash → readback verify → daemon → sdcard APKs → temp cleanup |
| `assets/UninstallMultiRoot.sh` | Read boot → live KP unpatch → Magisk in-image restore → repack → flash → verify → /data root-file cleanup |
| `assets/kpimg` | KernelPatch core (0.13.8) embedded into the kernel |
| `lib/arm64-v8a/libkptools.so` | KernelPatch CLI (patch/unpatch/verify) |
| `assets/magisk/*` | Official Magisk 30.6 payload (magiskboot, magiskinit, magisk, init-ld, stub) |
| `FolkPatch.apk` / `APatch.apk` | Official manager APKs — copied to sdcard after flashing |

`kptools` and `magiskboot` are bionic-linked, so the scripts mount the real system + APEX runtime in recovery, run the tools, then restore the environment.

## Build from source

No binaries are committed. The build extracts everything from the three official APKs (SHA-256 verified) and packs both ZIPs:

```sh
python tools/build.py --tag v2.0
# output: dist/MultiRoot-v2.0-Recovery-Installer.zip
#         dist/MultiRoot-v2.0-Uninstaller.zip
#         dist/SHA256SUMS.txt
```

Pushing a `v*` tag makes GitHub Actions build and attach the ZIPs to a release automatically.

## Credits & license

- **FolkPatch** by [LyraVoid](https://github.com/LyraVoid/FolkPatch), **KernelPatch** by [bmax121](https://github.com/bmax121/KernelPatch), **APatch** by [bmax121](https://github.com/bmax121/APatch), **Magisk** by [topjohnwu](https://github.com/topjohnwu/Magisk) — binaries from official releases, under their own licenses.
- Installer/uninstaller scripts + build system: original work in this repo, **GPL-3.0** ([LICENSE](LICENSE)).
- Community project — not affiliated with LyraVoid / bmax121 / topjohnwu.
