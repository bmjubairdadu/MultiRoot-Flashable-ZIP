# Changelog

All notable changes to this project are documented here.
Versioning: `vX.Y-kpA.B.C` where `X.Y` is this installer and `A.B.C`
is the embedded KernelPatch.

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
