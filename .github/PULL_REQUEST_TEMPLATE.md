# Pull Request

## What changed and why

<!-- One paragraph: problem on which device/recovery, root cause, fix approach. -->

## Testing

- [ ] `python tools/build.py --tag vX.Y-kpA.B.C` succeeds, APK sha256 OK
- [ ] One `assets/*.sh` per ZIP (sideload dispatch intact)
- [ ] `sh -n` passes on changed scripts
- [ ] Recovery log shows `ROOT ACTIVE on current slot`
- [ ] Manager app shows Installed after reboot
- [ ] Uninstaller restores stock + removes daemon

## Checklist

- [ ] POSIX sh only (no bashisms)
- [ ] boot-only (no `init_boot`/`vendor_boot` flash targets)
- [ ] Superkey stays `"su"` (no custom/random keys)
- [ ] CHANGELOG.md updated
- [ ] No binaries, logs, or backups committed (`git status` clean of junk)
