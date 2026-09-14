# Contributing to FolkPatch Flashable ZIP

Thanks for your interest! This project repackages the official
[FolkPatch](https://github.com/LyraVoid/FolkPatch) manager (by LyraVoid,
based on [KernelPatch](https://github.com/bmax121/KernelPatch) by bmax121)
as recovery-flashable ZIPs. The installer scripts in `assets/` and
`META-INF/` are original work (GPL-3.0); all binaries and the manager APK
come from the official upstream release and are **never** committed.

## Ground rules

- **No binaries in git.** `FolkPatch.apk`, `dist/`, `*.zip`, `fp_install/`,
  and `*.log` files are git-ignored. The build downloads/uses a local
  official APK and extracts what it needs.
- **POSIX shell only.** Recovery `sh` has no bashisms: no `function`,
  no `[[ ]]`, no `==`. Test every change with `sh -n` and, if possible,
  on a real device via `adb shell sh -n`.
- **One script per ZIP.** `tools/build.py` packs exactly one installer
  script per ZIP so ADB sideload (`/sideload/package.zip`) dispatches
  correctly. Never bundle all `*.sh` files into every ZIP.
- **boot-only.** FolkPatch patches the `kernel`, which always lives in
  the `boot` partition. Never add `init_boot`/`vendor_boot` as a flash
  target — flashing them cannot give root and can brick booting.
- **Superkey `su`.** The kernel is patched with `-s "su"` (the documented
  manual method and the app's own default). Do not introduce custom or
  random keys: the manager authenticates with `"su"` + APK signature.

## Development setup

```sh
# 1. Place the official FolkPatch APK next to the repo (same version as APK_URL in tools/build.py)
# 2. Build all three ZIPs locally
python tools/build.py --tag v1.0-kp0.13.8
# 3. Outputs land in dist/ (git-ignored): 3 ZIPs + SHA256SUMS.txt
```

## Testing checklist (before opening a PR)

- [ ] `python tools/build.py --tag vX.Y-kpA.B.C` succeeds, APK sha256 OK.
- [ ] Each ZIP contains exactly **one** `assets/*.sh` script.
- [ ] `sh -n` passes on all changed shell scripts (ideally via `adb shell`).
- [ ] Installer prints `ROOT ACTIVE on current slot` in recovery log.
- [ ] Manager app (`me.yuki.folk`) shows Installed after reboot.
- [ ] Uninstaller restores the stock backup and removes `/data/adb/apd`.

## Release process

1. Update `CHANGELOG.md` (new version section on top).
2. Commit everything except ignored build outputs.
3. Tag `vX.Y-kpA.B.C` and push tag — GitHub Actions builds the ZIPs
   and attaches them to the release automatically.

## Reporting issues

Please include: device model, Android version, recovery name/version,
the recovery log lines (`Target:` / `Flashing` / `ROOT ACTIVE`), and
`FolkPatch-flash-report.txt` from sdcard if present. Never attach
`boot.img` backups containing personal data.
