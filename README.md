# MultiRoot Flashable ZIP

**Ekta recovery-flashable ZIP → FolkPatch, APatch ba Magisk — jekono root manager app install korle oitai root manage korbe.** Flash in TWRP/OrangeFox, reboot, done. Plus ekta **Uninstaller ZIP** jeta **kono backup file charai** sob root live-remove kore.

> **Short e:** KernelPatch `0.13.8` kernel patch (→ FolkPatch + APatch manager) + Magisk `30.6` ramdisk patch (→ Magisk app) — dui root provider ek sathe, ek ZIP e. KSU manager er jonyo nicher "KSU" section dekho.

[![Build ZIPs](https://github.com/bmjubairdadu/MultiRoot-Flashable-ZIP/actions/workflows/build.yml/badge.svg)](https://github.com/bmjubairdadu/MultiRoot-Flashable-ZIP/actions/workflows/build.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

---

## Kon file tar jonno?

| File | Use |
|---|---|
| `MultiRoot-v2.0-Recovery-Installer.zip` | Root chao? Recovery te flash koro, reboot dao ✅ |
| `MultiRoot-v2.0-Uninstaller.zip` | Unroot chao? Flash koro — backup lagbe na |
| `SHA256SUMS.txt` | Download verify korar jonno |

ZIP er bhitore official Manager APK (`me.yuki.folk`) + APatch manager ache — flash sesh e sdcard e copy hoye jabe.

---

## Requirements

| Requirement | Note |
|---|---|
| ARM64 Android, Android 8.0+ | Required |
| Custom recovery (TWRP/OrangeFox/Lineage) | Required — adb sideload o chole |
| `CONFIG_KALLSYMS=y` kernel | Required (installer nijei check kore) |
| Unlocked bootloader | Required |
| Battery 50%+ | Recommended |

A-only, A/B, Virtual A/B sob device e kaj kore. Kernel sob somoy `boot` partition e thake — `vendor_boot` kono din dhora hoy na.

---

## Flash korar niyom

1. ZIP ta sdcard e copy koro.
2. Recovery → **Install** → ZIP select (ba `adb sideload`).
3. Installer ekta ekta kore:
   - Boot partition + slot detect kore
   - Kernel unpack kore **KernelPatch** diye patch kore (superkey: `su`)
   - Ramdisk e **Magisk** patch kore (boot e ramdisk na thakle Android 13+ GKI device e Magisk jay `init_boot` e)
   - Ek unpatch/clean check: age theke patch thakle age clean kore fresh patch kore
   - Direct flash → readback verify → `ROOT ACTIVE` / `MAGISK ACTIVE` print
   - FolkPatch-Manager.apk + APatch-Manager.apk sdcard e copy
4. Reboot → **jekono ekta** manager install koro:
   - `FolkPatch-Manager.apk` (sdcard) → Installed/Active dekhabe, superkey lagbe na
   - `APatch-Manager.apk` (sdcard) → same KernelPatch kernel manage kore
   - Magisk app (GitHub/Play) → Magisk root manage korbe
5. Je app ke root dibe, sei manager er Superuser page theke allow koro.

### Mode change (optional)

Default mode **all** (KernelPatch + Magisk dui root-i). Ekmatro ekta chao? Sdcard e `root-mode.txt` banao, first line e ekta word:

| Mode | Ki hoy |
|---|---|
| `all` (default) | KernelPatch + Magisk dui root-i active |
| `kpatch` | Shudhu KernelPatch — FolkPatch/APatch manager |
| `magisk` | Shudhu Magisk — Magisk app |

Tarpor ekai ZIP abar flash koro — installer age purano patch clean kore notun mode boshiye dey. File er jaygay `/data/media/0/root-mode.txt`, `/external_sd/root-mode.txt` o chole.

---

## Uninstall / unroot

Recovery te `MultiRoot-v2.0-Uninstaller.zip` flash koro. Etar kaj:

- **KernelPatch** → `kptools -u` diye kernel live-unpatch (backup charai)
- **Magisk** → boot image er bhitore thaka internal `.backup` theke ramdisk restore
- **init_boot** e Magisk thakle setao restore hoy
- `/data` theke sob root file remove: FolkPatch/APatch daemon (`/data/adb/ap*`, `/data/adb/fp`), Magisk (`/data/adb/magisk*`, modules, post-fs-data.d, service.d), KSU (`/data/adb/ksu*`), purano `FolkPatch-Backup` folder, flash-report — sob
- Readback verify kore `STOCK CONFIRMED` print kore

Manager **app** gulo Android settings → Apps theke nijei uninstall korte hobe.

---

## KSU manager niye sotti kotha

**KernelSU / KernelSU Next / SukiSU manager ei ZIP er sathe kaj kore na.** Karon:

- KernelSU family er root provider kernel er bhitore KSU code compile kore lage, ar seta **proti kernel version (KMI) er alada prebuilt kernel/LKM** chay — universal ZIP e rakha possible na.
- KSU chao? KSU-Next/SukiSU manager app nijer "Install" page theke tomiyer device er jonno LKM/GKI image niye nije boot patch korte pare — seta alada step.
- Tobe ei ZIP er **Uninstaller** KSU er `/data/adb` file gulo o clean kore dey.

Ek flash e FolkPatch + APatch + Magisk — ei tinta manager family ek SATHE active thakte pare. Tobe ek user ekbare ekta manager primarily use korai best (niche FAQ dekho).

---

## Backup policy: ektao backup file toiri hoy na

Purano v1 installer `FolkPatch-Backup/` folder, `ori.img`, flash-report file baniyeto. **Ekhon ar kichui toiri hoy na** — ar age toiri kora gulo o installer/uninstaller flash korle delete hoye jay:

- Kono `stock-*.img` / `boot.img` copy sdcard ba /data te jay na
- Patch kaj sob `/tmp` (RAM/tmpfs) e hoy, sesh e delete hoy
- Magisk uninstall er jonno boot image er **bhitorei** `.backup` use hoy — alada file na
- Jodi nijer hate ekta stock `boot.img` rakte chao (extra safety hisebe), firmware package theke nijei rakhun — ei ZIP kichu rakhbe na

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Recovery log e `ROOT ACTIVE` nai | Flash partition e pouchay ni — Uninstaller flash kore abar try koro |
| Manager "Not installed" dekhay | ZIP er APK ta install koro (sdcard er copy), reboot dao, abar open koro |
| `kernel requires CONFIG_KALLSYMS=y` | Ei kernel patch kora somvob na — root impossible |
| `new-boot.img missing` / repack fail | ZIP damaged — abar download koro, SHA256 verify koro |
| Bootloop | MultiRoot Uninstaller ZIP flash koro (ba fastboot e stock boot.img) |
| `su: not found` (adb shell) | Normal — FolkPatch/APatch e `/system/bin/su` nai; manager app theke per-app grant koro |
| Magisk + KP dujtai thakle `su` konta? | Dui daemon-i active thake; terminal e `su` kon daemon er seta boot e mount order er upor depend kore — je manager theke grant korbe sei daemon er policy follow korbe |

---

## FAQ

**Ki eta official FolkPatch/APatch/Magisk?**
Na — community repackaging. FolkPatch: [LyraVoid](https://github.com/LyraVoid/FolkPatch), KernelPatch: [bmax121](https://github.com/bmax121/KernelPatch), APatch: [bmax121/APatch](https://github.com/bmax121/APatch), Magisk: [topjohnwu/Magisk](https://github.com/topjohnwu/Magisk). Binary gulo official upstream release theke ashe (build time e SHA-256 verify hoy); installer script gulo ei repo-r original kaj (GPL-3.0).

**Superkey dite hobe?**
Na. Kernel default superkey `su` diye patch kora thake — FolkPatch/APatch manager APK signature diye authenticate kore. Key screen nai.

**Ek sathe 3 ta manager app install korte pari?**
Pari — kintu recommendation: jeita primarily use korbe seta rakho. Magisk + KP ek sathe thakle `/system/bin/su` binary ekjon peye jay (mount order), tobe dui daemon-i chole ar duitar nijer nijer granted app der root dey.

**Play Integrity / SafetyNet?**
Root diye attestation kharap hoy — Shamiko/SUSFS-type hide module + manager er denylist use koro. Guarantee nai.

**adb sideload?**
Hae — prottek ZIP e ekta script ache, sideload e o thik moto dispatch hoy.

---

## Kivabe kaj kore

| Component | Role |
|---|---|
| `META-INF/.../update-binary` | Recovery bootstrap: busybox setup, ZIP name diye script select |
| `assets/InstallMultiRoot.sh` | boot read → unpack (magiskboot) → Samsung hexpatch → KernelPatch kernel patch → Magisk ramdisk patch → repack → flash → readback verify → daemon → sdcard APK → temp clean |
| `assets/UninstallMultiRoot.sh` | boot read → KP live-unpatch → Magisk in-image restore → repack → flash → verify → /data root-file clean |
| `assets/kpimg` | KernelPatch core (0.13.8) — kernel er bhitore boshe root dey |
| `lib/arm64-v8a/libkptools.so` | KernelPatch CLI (patch/unpatch/verify) |
| `assets/magisk/*` | Official Magisk 30.6 payload (magiskboot, magiskinit, magisk, init-ld, stub) |
| `FolkPatch.apk` / `APatch.apk` | Official manager APK — sdcard e copy hoy |

`kptools`/`magiskboot` bionic-linked, tai script recovery te real system + APEX mount kore binary gulo chalay, sesh e environment restore kore.

## Build from source

Kono binary commit kora nei. Build 3 ta official APK theke sob binary ber kore (SHA-256 verified) 2 ta ZIP banay:

```sh
python tools/build.py --tag v2.0
# output: dist/MultiRoot-v2.0-Recovery-Installer.zip
#         dist/MultiRoot-v2.0-Uninstaller.zip
#         dist/SHA256SUMS.txt
```

`v*` tag push korle GitHub Actions ekai build kore release e attach kore.

## Credits & license

- **FolkPatch** by [LyraVoid](https://github.com/LyraVoid/FolkPatch), **KernelPatch** by [bmax121](https://github.com/bmax121/KernelPatch), **APatch** by [bmax121](https://github.com/bmax121/APatch), **Magisk** by [topjohnwu](https://github.com/topjohnwu/Magisk) — binary gulo official release theke, nijer nijer license e (GPL).
- Installer/uninstaller script + build system: ei repo-r original kaj, **GPL-3.0** ([LICENSE](LICENSE)).
- Community project — LyraVoid/bmax121/topjohnwu er sathe affiliated na.
