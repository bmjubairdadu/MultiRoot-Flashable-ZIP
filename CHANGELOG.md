# Changelog

All notable changes to this project are documented here.
Versioning: `vX.Y` — installer version (embedded: KernelPatch 0.13.8,
Magisk 30.6).

## [v2.0] — 2026-10-14 — MultiRoot: ekta zip, jekono root manager

### Added
- ✨ Magisk 30.6 ramdisk root ekhon installer er bhitorei — ek flash e
  KernelPatch (FolkPatch/APatch manager) + Magisk (Magisk app) dui root-i active.
- ✨ Mode select: sdcard e `root-mode.txt` (`all` default / `kpatch` / `magisk`).
- ✨ Android 13+ GKI support: boot e ramdisk na thakle Magisk `init_boot` e patch hoy.
- ✨ APatch-Manager.apk (official 11224) o sdcard e copy hoy — FolkPatch o APatch
  dui manager-i KP 0.13.8 kernel manage korte pare.

### Changed
- 🔥 **Zero backup policy:** ar kono backup file toiri hoy na —
  `FolkPatch-Backup/`, `/data/FolkPatch-Backup`, `ori.img`, flash-report,
  patched-image copy sob BAD. Direct read → patch (tmpfs) → flash → verify → temp clean.
- 🔥 Uninstaller ekhon **backup charai** kaj kore: KernelPatch live-unpatch
  (`kptools -u`) + Magisk in-image `.backup` restore + init_boot restore.
- 🔥 Uninstaller ekhon FolkPatch/APatch daemon + Magisk files + KSU leftover +
  purano backup folder sob clean kore.
- 🔄 Boot-Patcher ZIP bad (ekhon shudhu Recovery-Installer + Uninstaller).
- 🔄 Kernel unpack/repack ekhon official Magisk `magiskboot` diye hoy (age kptools).
- 🔄 Manager APK gulo tmpfs e extract hoy na — ZIP theke sorasori sdcard e stream hoy.

### Compatibility
- Slot detection, real-system/APEX mount dance, CONFIG_KALLSYMS check,
  on-partition readback verify — v1 er proven pipeline ta intact.
- Re-flash idempotent: age theke KP/Magisk patch thakle age clean kore fresh patch.

## [v1.0-kp0.13.8] — 2026-09-14 — First stable release ✅

Device-verified on Xiaomi Mi A2 Lite (`daisy`, A/B slot `_b`, Android 11,
OrangeFox R11.1): flash → reboot → Manager shows **Installed / Active**.

### Added
- ✨ Recovery Installer: live `boot` backup → patch → flash → daemon
  install → on-partition verify (`ROOT ACTIVE`), both A/B slots patched.
- ✨ Boot Patcher: patch a stock `boot.img` on sdcard, no partition writes
  (fastboot Plan B included).
- ✨ Uninstaller: restore stock backup or live-unpatch, remove daemon.
- ✨ `FolkPatch-flash-report.txt` on sdcard after every install.
- ✨ Professional repo: issue/PR templates, contributing guide, security
  policy, CI-built releases with SHA-256 checksums.

### Compatibility
- Universal slot detection (cmdline → bootconfig → getprop → recovery
  fstab → partition probe) for A-only, A/B, and Virtual A/B devices.
- Universal runtime mount (slot-aware system + vendor fallback + flattened
  APEX) so `kptools` runs in TWRP, OrangeFox, and Lineage recoveries —
  including `adb sideload`.
- Boot-only targeting: the kernel always lives in `boot`; `init_boot` /
  `vendor_boot` are never flashed.
- Auth: kernel patched with the documented default superkey; the Manager
  (`me.yuki.folk`) authenticates by APK signature — no key entry needed.
