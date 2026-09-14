# Security Policy

## Supported versions

Only the latest release is supported. Older tags remain visible for
reference but receive no fixes — please re-flash the newest
`Recovery-Installer` ZIP before reporting an issue.

| Version | Supported |
| ------- | --------- |
| Latest `vX.Y-kpA.B.C` release | ✅ |
| Older tags | ❌ |

## What this project is

A community repackaging of the official
[FolkPatch](https://github.com/LyraVoid/FolkPatch) manager as
recovery-flashable ZIPs. No binaries are committed: release ZIPs are built
by GitHub Actions from the official upstream APK, and every build prints
the APK SHA-256 so you can verify what you flash.

- Verify downloads with `SHA256SUMS.txt` before flashing.
- The installer always keeps a stock `boot` backup
  (`FolkPatch-Backup/stock-boot_?.img`) — keep a copy off-device.

## Reporting a vulnerability

**Do not open a public issue for security problems.** Instead, open a
[private security advisory](https://github.com/bmjubairdadu/FolkPatch-Flashable-ZIP/security/advisories/new)
or contact the repository owner directly.

Please include: affected version/tag, device + recovery details, steps to
reproduce, and (if safe) the relevant recovery-log lines. We aim to
acknowledge within 72 hours and will credit reporters in the fix release
unless anonymity is requested.

## Scope notes

- Rooting inherently bypasses Android security boundaries (unlocked
  bootloader, custom recovery, patched kernel). Only flash on devices
  you own, with a known-good stock `boot.img` backup.
- Upstream vulnerabilities in FolkPatch/KernelPatch themselves should
  also be reported to [LyraVoid/FolkPatch](https://github.com/LyraVoid/FolkPatch/security)
  and [bmax121/KernelPatch](https://github.com/bmax121/KernelPatch/security).
