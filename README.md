# FolkPatch Flashable ZIP

**FolkPatch v10.2 / KernelPatch 0.13.8** — Recovery-flashable root for ARM64 Android devices.

Supported methods:
- **Recovery Installer** — flash ZIP and get root immediately on reboot (recommended)
- **Boot Patcher** — patch a stock boot.img file, flash via fastboot (advanced)
- **Uninstaller** — restore stock kernel, remove root daemon

---

## Requirements

| Requirement | Notes |
|---|---|
| ARM64 Android device | Required |
| Unlocked bootloader | Required for fastboot method |
| Custom recovery (TWRP, OrangeFox, etc.) | Required for flashing ZIPs |
| `CONFIG_KALLSYMS=y` in kernel | Required — if missing, root will NOT work |
| Battery ≥ 50% | Recommended |
| Android 8.0+ | Required |

---

## Files in each release

| File | Purpose |
|---|---|
| `FolkPatch-v10.2-kp0.13.8-Recovery-Installer.zip` | Flash in recovery for instant root |
| `FolkPatch-v10.2-kp0.13.8-Boot-Patcher.zip` | Patch a stock boot.img (no auto-flash) |
| `FolkPatch-v10.2-kp0.13.8-Uninstaller.zip` | Restore stock / unroot |
| `FolkPatch.apk` | Official Manager APK (bundled inside ZIPs too) |
| `SHA256SUMS.txt` | Checksums for verification |

---

## Method 1 — Recovery Installer (recommended)

1. Copy the Installer ZIP to your sdcard.
2. Boot into recovery → flash `FolkPatch-v10.2-kp0.13.8-Recovery-Installer.zip`.
3. The installer will:
   - Detect your boot partition automatically
   - Save a stock backup to sdcard (`FolkPatch-Backup/`)
   - Patch the kernel with a real superkey
   - Install the root daemon (`/data/adb/apd`)
   - Copy the Manager APK to sdcard
4. Reboot the device.
5. Install `FolkPatch-Manager.apk` from your sdcard (the official APK bundled in the ZIP — do not use any other APK source).
6. Open the app — it should show **Installed / Active**. No key entry is required. Allow Superuser on first prompt.

> **No root after flashing?** Check the recovery log for `ROOT ACTIVE on current slot`. If not present, the flash did not reach the partition (wrong target or write-protected). Try the Uninstaller, reboot, and flash again.

> **Already have the Manager installed?** Uninstall the old version first, then install the official APK from the ZIP. A different APK signature will cause authentication to fail.

---

## Method 2 — Boot Patcher + fastboot (advanced)

1. Extract your stock `boot.img` from your firmware package.
2. Place it on sdcard named `FolkPatch-stock-boot.img`.
3. Flash `FolkPatch-v10.2-kp0.13.8-Boot-Patcher.zip` in recovery.
   - This does **not** touch any partition.
   - Output: `FolkPatch-patched-boot.img` on sdcard, and `FolkPatch-key.txt`.
4. On your PC:
   ```sh
   fastboot flash boot FolkPatch-patched-boot.img
   # On A/B devices, also flash the other slot:
   fastboot flash boot_b FolkPatch-patched-boot.img
   ```
5. Reboot → install Manager APK → verify with Root Checker.

---

## Uninstall / Restore

Flash `FolkPatch-v10.2-kp0.13.8-Uninstaller.zip` in recovery.

- If a stock backup exists in `FolkPatch-Backup/`, it is restored automatically.
- If no backup is found, the installer performs a live kernel unpatch (`kptools -u`).
- The root daemon (`/data/adb/apd`, `ap/`, `fp/`) is removed from `/data/adb`.

---

## How it works

| Component | Role |
|---|---|
| `META-INF/.../update-binary` | Magisk-style bootstrap: selects installer script by ZIP filename, bootstraps BusyBox, mounts Android runtime |
| `scripts/InstallFP.sh` | Reads live boot partition → backs up → unpack → patch with real superkey → repack → flash → install daemon |
| `scripts/PatchOnly.sh` | Same pipeline on a stock image file; no partition writes |
| `scripts/UninstallFP.sh` | Restores backup or live-unpatches, removes daemon files |
| `assets/kpimg` | KernelPatch core image (embedded into the patched kernel) |
| `lib/arm64-v8a/libkptools.so` | KernelPatch CLI tool for pack/unpack/patch/verify |
| `lib/arm64-v8a/libbusybox.so` | BusyBox for recovery shell utilities |

**Why system + APEX must be mounted in recovery:**  
The `kptools` binary links against Android's Bionic libc (`/system/bin/linker64`, `/apex/com.android.runtime/lib64/bionic/`). In recovery these paths are either absent or dangling symlinks because `/apex` is not mounted. The scripts mount the real system partition and APEX before running `kptools`, then restore the environment afterward.

**Superkey:**  
The kernel is patched with a real `Ap...` superkey (not a zeroed keyless key). The Manager APK uses app-signature authentication — no key entry screen is shown. The key is saved to `FolkPatch-key.txt` on sdcard for reference.

---

## Build from source

No binaries are committed to this repository. The build script downloads the official FolkPatch APK and constructs the ZIPs:

```sh
python tools/build.py
# outputs: dist/FolkPatch-v10.2-kp0.13.8-*.zip + SHA256SUMS.txt
```

Pushing a `v*` tag triggers the GitHub Actions workflow which runs the same build and attaches the ZIPs to the release automatically.

---

## Credits & license

- **FolkPatch** by [LyraVoid](https://github.com/LyraVoid/FolkPatch),
  based on **KernelPatch** by [bmax121](https://github.com/bmax121/KernelPatch).
  Binaries (`kpimg`, `kptools`, `busybox`) and the Manager APK come from the
  official upstream release.
- Installer scripts (`META-INF/…/update-binary`, `scripts/*.sh`) are original
  work, licensed **GPL-3.0** (see [LICENSE](LICENSE)) to match the upstream project.
- This is a community repackaging project, not affiliated with LyraVoid.
  If you find this useful, please star the [upstream repo](https://github.com/LyraVoid/FolkPatch).
