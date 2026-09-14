# Changelog

All notable changes to this project are documented here.

## [v10.1-kp0.13.8] — 2026-09-14 — sideload + key + daemon fixes (device-verified)

### Fixed
- 🐛 **Boot-Patcher/Uninstaller sideload-e vul kaj korto:** `build.py`
  protita ZIP-e 3-ta script-i dhukiye dito. ADB sideload-e recovery ZIP-ke
  `/sideload/package.zip` nam dey, tai `update-binary` nam dekhe script
  chinte parto na — sobsomoy Installer cholto. Ekhon protita ZIP-e
  SUDHU tar nijer script thake (verified: 1 script/ZIP), sideload-eo
  sothik kaj hoy.
- 🐛 **Superkey format mismatch:** Installer `Ap` prefix chara key banato,
  kintu official `boot_patch.sh`/app niyom `Ap + uuid` (device-e `apd`
  cholche manual patch-e, shetai proman). Purono bare-hex key pele ekhon
  `Ap<key>`-e normalize hoy; notun key sobsomoy `ApXXXXXXXX` format-e.
- 🐛 **Patch flag order (phone-e promanito):** `-s` eka dile
  `root_superkey` zeroed theke jay = root hobe na. Official order-e ekhon
  age `-S` (root-skey), tarpor `-s`, tarpor combined — current + inactive
  slot + PatchOnly tinti-tei. Zeroed key pele installer ekhon abort kore
  (age sudhu warning dito).
- 🐛 **Daemon-e vul package name:** `com.vst.folkpatch` naamer kono package
  nei (phone + APK dex-e verified: asol Manager `me.yuki.folk` v5.0).
  `package_config`-e ekhon `me.yuki.folk` + `com.android.shell` lekha hoy;
  ostittohin `config`/`key`/`manager_package` file lekha bondho (app ogulo
  byabohar kore na).
- 🐛 **`find_block` duplicate + boot-only:** Installer-e function duibar
  define chilo (ditiyobar hidden-slot check-er pore); ekhon ekbar, byabohar-er
  agei. Target loop theke `init_boot`/`vendor_boot` bad — kernel sob
  device-e `boot`-e thake, ramdisk partition-e flash = root hoto na.
  Uninstaller-eo same boot-only fix.

## [v10.0-kp0.13.8] — 2026-09-13 — INSTANT ROOT (kernel + daemon, app rule)

### Fixed
- 🐛 **Ager sob ZIP keno root dito na (asol karon):** ZIP sudhu kernel
  patch korto (`patched=true`), kintu root-er second half — userspace daemon
  `/data/adb/apd` — recovery-te bosato na. `kpimg` boot-e
  `exec /data/adb/apd ...` chalate giye file peto na, tai app bolto
  "root unavailable". Ekhon installer recovery-tei official layout-e bosay:
  `/data/adb/apd` (APK `libapd.so`), `/data/adb/ap/bin/` (busybox, kptools,
  resetprop, apd symlink), `/data/adb/fp/bin/fpd` (APK `Service/fpd`),
  `su_path` + `ori.img` + `restorecon`. Flash = **INSTANT ROOT**:
  reboot -> Manager APK install -> Installed/Active, ditiyo patch lagbe na.
- 🐛 `/data` encrypted/locked thakle daemon best-effort skip (kernel ready
  thake); reboot-er por app prothom open-e one-tap-e `apd` bosiye ney.
- 🐛 Uninstaller ekhon kernel restore-er sathe daemon-oo soray
  (`/data/adb/apd`, `/data/adb/ap`, `/data/adb/fp`) — ghost-root thake na.
  Modules (`/data/adb/modules`) chowa hoy na.
- 🐛 ZIP-e ekhon `assets/apd` + `assets/fpd` + `assets/resetprop` bundled
  (APK theke); fallback hisebe recovery-te APK theke extract-oo hoy.

## [v9.0-kp0.13.8] — 2026-09-13 — REAL superkey (root-unavailable fix)

### Fixed
- 🐛 **\"root unavailable\" + superkey-000 asol karon:** tomar log-e
  `root_superkey=0000...zeroed` — keyless patch-e `apd`/`su` auth more,
  tai `patched=true` thakleo app root pay na. Ekhon kernel-e abar REAL
  superkey (`-S`, official `boot_patch.sh` rule) set hoy.
- 🐛 Key verify: `root_superkey` zeroed thakle installer ekhon abort kore
  (age sobuj signal dito).
- 🐛 App-e key **entry** option nei (signature-auth) — key sudhu kernel/apd-r
  jonno, screen-e dekhay + `FolkPatch-key.txt`-e save thake.

## [v8.0-kp0.13.8] — 2026-09-13 — ONE ZIP for ALL devices (boot-only universal)

### Fixed
- 🐛 **boot/init_boot confusion sesh:** official niyome kernel SOB device-e
  `boot`-e thake — purono phone hok ba notun (init_boot thakleo). `init_boot`
  / `vendor_boot`-e sudhu ramdisk; flash korle root hoy na + brick.
  Installer ekhon **boot-only**: `boot` na pele abort, `init_boot` kokhonoi
  chobe na. Ektai ZIP sob device-e cholbe.
- 🐛 Boot-Patcher ekhon stock `boot.img` chai; `init_boot` file dile loud
  warning dey.
- 🐛 Uninstaller-oo boot-only restore.

## [v7.0-kp0.13.8] — 2026-09-13 — NO-KEY official flow (4.3+ signature-auth)

### Fixed
- 🐛 **App-e key deoar option nai — etai thik:** official doc onujayi FolkPatch
  4.3+ theke auth = signature, kono password lage na. Kernel-e ar `-s/-S` key
  lekha hoy NA — keyless patch. Manager app-e key chaoar kothao na.
- 🐛 Purono `FolkPatch-key.txt` flash-er somoy auto-delete (confusion sesh).
- 🐛 Onno source-er APK (onno signature) hole auth hobe na — tai ZIP-er
  official APK-tai install korte hobe (README + final screen-e bola ache).

## [v6.0-kp0.13.8] — 2026-09-13 — FINAL 2-in-1 (FolkTool + recovery)

### Added
- ✨ **DUAL-METHOD ek ZIP-e:** [FolkTool](https://github.com/LyraVoid/FolkTool)
  niyome age **KEYLESS patch** (`-p -i -k -o`, kono `-s/-S` noy — thik
  FolkTool-er `kptools_service.dart` moto, manager app + `apd`). Fail hole
  tobei key mode fallback.
- ✨ Direct-flash + fastboot file duitai: flash-er por patched
  `FolkPatch-patched-*.img` sdcard-eo thake (Plan B: PC theke fastboot).
- ✨ Keyless hole final screen-e bolei dey: app khule NIJER key set koro.

## [v5.3-kp0.13.8] — 2026-09-13 — sob-fix pack

### Fixed
- 🐛 **Official key order:** patch ekhon official `boot_patch.sh`-er moto age
  `-S` (root-skey) only, tarpor combined, tarpor legacy — Manager key handshake
  mismatch kombe. Key mode screen-e dekhay.
- 🐛 **Slot-hidden A/B:** recovery slot na janale `_a` default + duit slot-i
  nijer stock theke patch — jei slot-e boot hok root thakbe.
- 🐛 **AVB warning:** `verifiedbootstate=green` hole agei warning + fix command.
- 🐛 **Tiny-read guard:** 4MB-er choto read hole abort (vul partition dhora porbe).
- 🐛 Final screen + README ekhon manager-install BADHOTAMULOK bole.

## [v5.2-kp0.13.8] — 2026-09-13 — flash-stuck detection

### Fixed
- 🐛 **"Flash success kintu root nai" dhora:** ekhon flash-er por partition
  theke abar pore kernel unpack kore `patched=true` check kora hoy. Partition-e
  unpatched kernel thakle installer sobuj signal deyna — sorasori abort kore.
- 🐛 Inactive-slot verify ekhon nijer image-er sathe mele (ager byte-compare
  current-slot image-er sathe chilo — kernel alada hole mithya MISMATCH dekhato).
- 🐛 Key mode order: combined (`-s` + `-S`) age, tarpor fallback — Manager app
  duitar jetai khujk, key pabe.

## [v5.1-kp0.13.8] — 2026-09-13 — auto-root + freeze fixes

### Fixed
- 🐛 **Wrong target fixed:** installer now patches `boot` first (kernel lives
  there on old and new devices). Patching `init_boot` gave no root and could
  cause freeze/reboot — now only a last-resort fallback.
- 🐛 **A/B freeze fixed:** inactive slot is patched from its **own** stock
  instead of copying the current slot's image (different kernels per slot
  caused freeze/bootloop on slot switch).
- 🐛 **App upgrade/key mismatch fixed:** patch sets both `skey` and `root-skey`
  to the same key, so the Manager app connects after install and keeps working
  after upgrade (already-installed app also detects the patch).
- 🐛 **Already-patched re-flash:** detects `patched=true` live image and warns
  instead of writing a mismatched key; PatchOnly refuses already-patched
  source files.
- 🐛 **Uninstaller cross-slot restore:** restores each slot from its matching
  backup; skips unknown key combos instead of flashing the wrong image.
- 🐛 Universal `dd` syntax (no `conv=notrunc,fsync`) so flashing works in all
  recoveries; block size checks before flash/restore.

### Added
- ✨ `vendor_kernel_boot` target support, `/proc/cmdline` slot detection
  (recovery `getprop` is often empty), platform `by-name` search.
- ✨ Battery warning below 25%, `gzip`-from-busybox fallback for repack.
- ✨ Manager APK + stock backup also staged in `Download/FolkPatch/` where the
  app expects them.

## [v5.0-kp0.13.8] — 2024-09-12

### Added
- ✨ System stability fixes for CMA memory allocation
- ✨ PRNG/entropy initialization patches  
- ✨ Enhanced APEX runtime mounting for recovery environment
- ✨ Improved Linker64 binary resolution
- ✨ Better SELinux compatibility handling
- ✨ Device tree optimization support
- ✨ Multi-partition (A/B) slot detection
- ✨ Recovery environment auto-detection

### Improved
- 🔧 Enhanced kernel patching reliability
- 🔧 Better backup and restore procedures
- 🔧 Improved file-based encryption (FBE) compatibility
- 🔧 More robust partition detection via by-name lookup
- 🔧 Cleaner error messages and diagnostics
- 🔧 Better handling of pre-apex and modern ROMs

### Fixed
- 🐛 Fixed CMA memory pool allocation warnings
- 🐛 Fixed entropy source initialization
- 🐛 Fixed APEX mount failures in recovery
- 🐛 Fixed linker resolution in stub /system
- 🐛 Fixed partition detection on multiple devices
- 🐛 Fixed backup directory selection logic

### Technical Details
- Base: FolkPatch v5.0
- KernelPatch: v0.13.8
- Kernel Support: 3.18 – 6.15
- Architecture: ARM64 only

## [Previous Versions]

### v5.0-kp0.13.8 (Previous Release)
- Initial FolkPatch flashable ZIP implementation
- Basic recovery installer support
- Boot patcher (file-safe mode)
- Uninstaller with backup restore

---

## Future Plans

- [ ] Arm32 (armv7) support
- [ ] Broader kernel version coverage (6.16+)
- [ ] Post-flash optimization modules
- [ ] OTA update compatibility hooks
- [ ] Extended logging and debug modes
- [ ] CI/CD improvements and binary caching
