# FolkPatch Flashable ZIP

**Recovery-flashable root (FolkPatch v1.0 / KernelPatch 0.13.8) for ARM64 Android — flash in TWRP/OrangeFox, reboot rooted.**

Flash the Installer ZIP in custom recovery and get root immediately on reboot — no PC, no fastboot, no manual patching. Also included: a safe Boot Patcher (patch a stock `boot.img` without touching partitions) and an Uninstaller (restore stock kernel, remove root).

> **Keywords:** FolkPatch recovery flashable zip, FolkPatch TWRP install, KernelPatch root zip, FolkPatch OrangeFox sideload, `me.yuki.folk` manager, APatch alternative root, root without PC, boot.img patcher, KernelPatch 0.13.8.

[![Build ZIPs](https://github.com/bmjubairdadu/FolkPatch-Flashable-ZIP/actions/workflows/build.yml/badge.svg)](https://github.com/bmjubairdadu/FolkPatch-Flashable-ZIP/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/bmjubairdadu/FolkPatch-Flashable-ZIP)](https://github.com/bmjubairdadu/FolkPatch-Flashable-ZIP/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

---

## Which file do I need?

| File | Use it when… |
|---|---|
| `FolkPatch-v1.0-kp0.13.8-Recovery-Installer.zip` | You want root now: flash in recovery, reboot, done ✅ |
| `FolkPatch-v1.0-kp0.13.8-Boot-Patcher.zip` | You prefer fastboot: patch a stock `boot.img` on sdcard, flash from PC |
| `FolkPatch-v1.0-kp0.13.8-Uninstaller.zip` | You want to unroot: restores the stock kernel backup |
| `SHA256SUMS.txt` | Verify downloads before flashing |

All three ZIPs (plus checksums) are attached to every
[release](https://github.com/bmjubairdadu/FolkPatch-Flashable-ZIP/releases/latest).
The official Manager APK (`me.yuki.folk`) is bundled **inside** each ZIP —
always install that copy, never a random APK.

---

## Requirements

| Requirement | Notes |
|---|---|
| ARM64 Android device, Android 8.0+ | Required |
| Custom recovery (TWRP, OrangeFox, …) | Required for flashing ZIPs |
| `CONFIG_KALLSYMS=y` in the kernel | Required — without it root cannot work |
| Unlocked bootloader | Only needed for the fastboot method |
| Battery ≥ 50% | Recommended |

Works on A-only, A/B, and Virtual A/B devices. The kernel always lives in
the **`boot`** partition — this project never touches `init_boot` or
`vendor_boot` (flashing those cannot give root and can break booting).

---

## Method 1 — Recovery Installer (recommended, no PC)

1. Copy `FolkPatch-v1.0-kp0.13.8-Recovery-Installer.zip` to sdcard.
2. Boot into recovery → **Install** → select the ZIP (or `adb sideload` it).
3. The installer will:
   - Detect your current boot partition and slot automatically
   - Save a stock backup to `FolkPatch-Backup/` (keep a copy off-device!)
   - Patch the kernel and install the root daemon (`/data/adb/apd`)
   - Copy the Manager APK to sdcard
   - Verify the flashed partition reads back as patched (`ROOT ACTIVE`)
4. Reboot → install `FolkPatch-Manager.apk` from sdcard.
5. Open the app → **Installed / Active**. Grant Superuser per app when asked.

> **How do I know the flash really worked?** The recovery log must contain
> `ROOT ACTIVE on current slot`. A copy is also saved to sdcard as
> `FolkPatch-flash-report.txt` — attach it when asking for help.

---

## Method 2 — Boot Patcher + fastboot (advanced)

1. Get your stock `boot.img` (firmware package or `adb pull /dev/block/by-name/boot`).
2. Put it on sdcard as `FolkPatch-stock-boot.img`.
3. Flash `FolkPatch-v1.0-kp0.13.8-Boot-Patcher.zip` in recovery.
   - Touches **no** partition. Output: `FolkPatch-patched-boot.img` on sdcard.
4. From PC:
   ```sh
   fastboot flash boot FolkPatch-patched-boot.img
   # A/B devices: flash the other slot too
   fastboot flash boot_a FolkPatch-patched-boot.img
   fastboot flash boot_b FolkPatch-patched-boot.img
   fastboot reboot
   ```
5. Install the Manager APK → verify with a root checker.

---

## Uninstall / unroot

Flash `FolkPatch-v1.0-kp0.13.8-Uninstaller.zip` in recovery. It restores the
stock backup if found, otherwise live-unpatches the kernel, and always
removes the root daemon (`/data/adb/apd`, `ap/`, `fp/`).

---

## Troubleshooting (read before opening an issue)

| Symptom | Most likely cause → fix |
|---|---|
| No `ROOT ACTIVE` in recovery log | Flash didn't reach the partition (wrong target / write-protected). Flash the Uninstaller, reboot, flash again. |
| App shows “Not installed” but `apd` runs | Manager APK signature mismatch — uninstall it, install `FolkPatch-Manager.apk` from the ZIP, **reboot**, open the app again. |
| `kernel requires CONFIG_KALLSYMS=y` | Your kernel can't be patched — root is impossible on this kernel. |
| `new-boot.img missing` / repack failed | Missing `gzip` in recovery or corrupt download — re-download, verify SHA-256. |
| Bootloop after flash | Restore: flash the Uninstaller ZIP, or fastboot-flash your stock `boot.img`. |
| `su: not found` in `adb shell` | Normal — FolkPatch has no `/system/bin/su`. Grant root per app inside the Manager (Superuser page). |

Still stuck? Open a [bug report](.github/ISSUE_TEMPLATE/bug_report.yml) with
device model, Android version, recovery name/version, the recovery-log lines,
and `FolkPatch-flash-report.txt`.

---

## FAQ

**Is this official?**
No — a community repackaging. FolkPatch is by
[LyraVoid](https://github.com/LyraVoid/FolkPatch), based on KernelPatch by
[bmax121](https://github.com/bmax121/KernelPatch). Binaries and the manager
APK come from the official upstream release; only the installer scripts here
are original work (GPL-3.0). Please star the upstream repo.

**Do I need to enter a superkey?**
No. The kernel is patched with the default key and the manager authenticates
by APK signature. There is no key screen — anyone asking for your key is a scam.

**Magisk vs KernelSU vs FolkPatch?**
Magisk patches the ramdisk (`boot`/`init_boot`); KernelSU needs GKI/LKM builds;
FolkPatch (KernelPatch-based) patches the `kernel` inside `boot` directly and
works on kernels 3.18–6.15 with `CONFIG_KALLSYMS=y`, including many older devices.

**Will it trip SafetyNet / Play Integrity?**
Root inherently affects attestation. Use Shamiko/similar hiding modules and
check the [FolkPatch docs](https://fp.mysqil.com/) — no guarantees.

**Can I use it with `adb sideload`?**
Yes — Lineage-style recoveries included. Each ZIP contains exactly one script,
so sideload (`/sideload/package.zip`) dispatches to the right installer.

---

## How it works

| Component | Role |
|---|---|
| `META-INF/.../update-binary` | Recovery bootstrap: picks the script by ZIP filename, sets up BusyBox + runtime |
| `assets/InstallFP.sh` | Live partition → backup → unpack → patch → repack → flash → daemon → verify |
| `assets/PatchOnly.sh` | Same pipeline on a stock image file; writes nothing to partitions |
| `assets/UninstallFP.sh` | Restores backup or live-unpatches; removes daemon files |
| `assets/kpimg` | KernelPatch core image embedded into the patched kernel |
| `lib/arm64-v8a/libkptools.so` | KernelPatch CLI (unpack/patch/verify/repack) |
| `lib/arm64-v8a/libbusybox.so` | Unix tools for recovery shell |

`kptools` links against Android's Bionic libc, so the scripts mount the real
system partition and APEX runtime before running it, then restore the
environment afterward.

---

## Build from source

No binaries are committed. The build extracts everything from the official APK:

```sh
python tools/build.py --tag v1.0-kp0.13.8
# outputs: dist/*.zip + SHA256SUMS.txt (all git-ignored)
```

Pushing a `v*` tag runs the same build in GitHub Actions and attaches the
ZIPs to the release. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

---

## Versioning

`vX.Y-kpA.B.C` — `X.Y` is this installer, `A.B.C` is the embedded KernelPatch.
Only the latest release is supported ([security policy](SECURITY.md)).

---

## Credits & license

- **FolkPatch** by [LyraVoid](https://github.com/LyraVoid/FolkPatch),
  based on **KernelPatch** by [bmax121](https://github.com/bmax121/KernelPatch).
  Binaries (`kpimg`, `kptools`, `busybox`) and the Manager APK come from the
  official upstream release.
- Installer scripts (`META-INF/…/update-binary`, `assets/*.sh`) are original
  work, licensed **GPL-3.0** (see [LICENSE](LICENSE)).
- Community project, not affiliated with LyraVoid.
