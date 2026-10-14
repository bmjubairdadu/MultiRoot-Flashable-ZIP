#!/usr/bin/env python3
"""Build MultiRoot recovery ZIPs: KernelPatch root + Magisk root, zero backups.

One installer ZIP patches the boot kernel with KernelPatch 0.13.8 (so the
FolkPatch and APatch manager apps can both manage root) and optionally the
ramdisk with Magisk 30.6 (so the Magisk app manages root too). One
uninstaller ZIP reverses everything live - no backup file is ever created,
used, or kept.

No binaries are committed. The build reads everything from three OFFICIAL
APKs placed next to this repo (missing ones are downloaded from their
official GitHub releases and SHA-256 verified):

  FolkPatch.apk    - LyraVoid/FolkPatch   (busybox, kptools, kpimg, daemons)
  APatch.apk       - bmax121/APatch       (manager APK for sdcard)
  Magisk-v30.6.apk - topjohnwu/Magisk     (magiskboot, magiskinit, payload)

Usage:
    python tools/build.py [--out dist] [--tag v2.0]
"""
import argparse
import hashlib
import os
import sys
import urllib.request
import zipfile

FOLKPATCH_URL = "https://github.com/LyraVoid/FolkPatch/releases/download/kp0.13.8/FolkPatch_115032_5.0_on_main-release.apk"
FOLKPATCH_SHA256 = "0b1671fe42a565a4fb8a573ac9b480febe11189380f96c83ccbe29fdfd375890"
APATCH_URL = "https://github.com/bmax121/APatch/releases/download/11224/APatch_11224_9a63e0f_HEAD-release-signed.apk"
APATCH_SHA256 = "f1986f9a9c3b2b2d5ca09aa6b9ef24226fef662f8faf5677ce1447ffcae68590"
MAGISK_URL = "https://github.com/topjohnwu/Magisk/releases/download/v30.6/Magisk-v30.6.apk"
MAGISK_SHA256 = "f1ffc3c9a5614c251ba6bada308163acc3c3d844cf01d33f55a8bc151adc34ce"

MAGISK_VER = "30.6"
KP_VER = "0.13.8"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def lf(path):
    with open(path, "rb") as f:
        return f.read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(url, path, expected_sha):
    """Use the local APK if its SHA-256 matches; otherwise download + verify."""
    name = os.path.basename(path)
    if os.path.exists(path):
        digest = sha256_file(path)
        if digest == expected_sha:
            print("OK  %s (local, sha256 verified)" % name)
            return path
        print("!!  %s hash mismatch - re-downloading official release" % name)
        os.remove(path)
    print("...  downloading %s" % url)
    urllib.request.urlretrieve(url, path)
    digest = sha256_file(path)
    if digest != expected_sha:
        print("FATAL: %s sha256 mismatch:\n  got      %s\n  expected %s" % (name, digest, expected_sha))
        sys.exit(1)
    print("OK  %s (downloaded, sha256 verified)" % name)
    return path


def w(z, name, data, mode=0o644):
    zi = zipfile.ZipInfo(name)
    zi.external_attr = (mode & 0xFFFF) << 16
    zi.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(zi, data)


def build(outname, entries, rd):
    out = os.path.join(args.out, outname)
    z = zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9)
    seen = set()
    for name, data, mode in entries:
        if name in seen:
            print("FATAL: duplicate zip entry %s" % name)
            sys.exit(1)
        seen.add(name)
        w(z, name, data, mode)
    w(z, "README.txt", rd.encode("utf-8"), 0o644)
    z.close()
    print("->  %s (%d bytes)" % (outname, os.path.getsize(out)))
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"))
    ap.add_argument("--tag", default="v2.1", help="ZIP filename tag, e.g. v2.1")
    args = ap.parse_args()
    print("Building MultiRoot %s (KP %s + Magisk %s)" % (args.tag, KP_VER, MAGISK_VER))

    folk_path = fetch(FOLKPATCH_URL, os.path.join(ROOT, "FolkPatch.apk"), FOLKPATCH_SHA256)
    apatch_path = fetch(APATCH_URL, os.path.join(ROOT, "APatch.apk"), APATCH_SHA256)
    magisk_path = fetch(MAGISK_URL, os.path.join(ROOT, "Magisk-v30.6.apk"), MAGISK_SHA256)

    # --- payloads from the official FolkPatch APK (KernelPatch side) ---
    zf = zipfile.ZipFile(folk_path)
    bb = zf.read("lib/arm64-v8a/libbusybox.so")
    kt = zf.read("lib/arm64-v8a/libkptools.so")
    kpimg = zf.read("assets/kpimg")
    try:
        apd = zf.read("lib/arm64-v8a/libapd.so")
    except KeyError:
        apd = b""
    try:
        fpd = zf.read("assets/Service/fpd")
    except KeyError:
        fpd = b""
    try:
        rp = zf.read("lib/arm64-v8a/libresetprop.so")
    except KeyError:
        rp = b""
    zf.close()
    if not apd:
        print("WARNING: libapd.so missing in FolkPatch APK - instant-root daemon unavailable")
    with open(folk_path, "rb") as f:
        folk_apk = f.read()
    with open(apatch_path, "rb") as f:
        apatch_apk = f.read()

    # --- payloads from the official Magisk APK (ramdisk side) ---
    zm = zipfile.ZipFile(magisk_path)
    magiskboot = zm.read("lib/arm64-v8a/libmagiskboot.so")
    magiskinit = zm.read("lib/arm64-v8a/libmagiskinit.so")
    magiskbin = zm.read("lib/arm64-v8a/libmagisk.so")
    init_ld = zm.read("lib/arm64-v8a/libinit-ld.so")
    stub_apk = zm.read("assets/stub.apk")

    # 32-bit ARM (armeabi-v7a) support from official Magisk APK
    try:
        bb32 = zm.read("lib/armeabi-v7a/libbusybox.so")
        mb32 = zm.read("lib/armeabi-v7a/libmagiskboot.so")
        mi32 = zm.read("lib/armeabi-v7a/libmagiskinit.so")
        mbin32 = zm.read("lib/armeabi-v7a/libmagisk.so")
        ild32 = zm.read("lib/armeabi-v7a/libinit-ld.so")
    except KeyError:
        bb32 = mb32 = mi32 = mbin32 = ild32 = b""
    zm.close()

    with open(magisk_path, "rb") as f:
        magisk_apk = f.read()

    ub = lf(os.path.join(ROOT, "META-INF", "com", "google", "android", "update-binary"))
    us = lf(os.path.join(ROOT, "META-INF", "com", "google", "android", "updater-script"))
    inst = lf(os.path.join(ROOT, "assets", "InstallMultiRoot.sh"))
    un = lf(os.path.join(ROOT, "assets", "UninstallMultiRoot.sh"))

    rd_inst = (
        "MultiRoot v2.0 - Universal Recovery Installer (KernelPatch %s + Magisk %s)\n" % (KP_VER, MAGISK_VER) +
        "======================================================================\n"
        "Ekta flashable ZIP, jekono root manager kaj korbe:\n"
        "  - Magisk Manager    (sdcard e Magisk-Manager.apk)\n"
        "  - FolkPatch Manager (sdcard e FolkPatch-Manager.apk)\n"
        "  - APatch Manager    (sdcard e APatch-Manager.apk)\n"
        "  - KernelSU / Next   (je kono APK install kore su access pabe)\n"
        "\n"
        "Flash korar por phone reboot kore sdcard theke je kono ekta manager\n"
        "install korlei shob app root / superuser access pabe.\n"
        "\n"
        "Kivabe flash korbe:\n"
        "  1. Ei ZIP phone er storage / sdcard e copy koro\n"
        "  2. Custom recovery (TWRP/OrangeFox) -> Install -> ZIP select koro\n"
        "  3. Reboot -> sdcard theke manager app install koro\n"
        "\n"
        "Mode change (optional): sdcard e 'root-mode.txt' banao, first line:\n"
        "  all    = KernelPatch + Magisk (default, universal root)\n"
        "  kpatch = shudhu KernelPatch (FolkPatch/APatch manager)\n"
        "  magisk = shudhu Magisk (Magisk manager)\n"
        "\n"
        "Universal: ARM64 + 32-bit ARM, Android 6.0 theke Android 15+.\n"
        "NO backup file toiri hoy na - direct flash.\n"
        "Bootloop hole MultiRoot Uninstaller ZIP flash koro.\n"
    )

    rd_un = (
        "MultiRoot v2.0 - Uninstaller\n"
        "============================\n"
        "KernelPatch + Magisk + sob root file remove kore stock boot ferot\n"
        "anbe. Kono backup file lagbe na (live kernel unpatch + Magisk-er\n"
        "in-image ramdisk restore). Manager app gulo Android settings theke\n"
        "nijei uninstall koro.\n"
        "\n"
        "Flash: Recovery -> Install -> ei ZIP -> reboot.\n"
    )

    common = [
        ("META-INF/com/google/android/update-binary", ub, 0o755),
        ("META-INF/com/google/android/updater-script", us, 0o644),
        ("busybox", bb, 0o755),
        ("lib/arm64-v8a/libbusybox.so", bb, 0o755),
        ("lib/arm64-v8a/libkptools.so", kt, 0o755),
    ]
    if bb32:
        common.append(("lib/armeabi-v7a/libbusybox.so", bb32, 0o755))
        common.append(("busybox32", bb32, 0o755))

    inst_entries = list(common) + [
        ("assets/kpimg", kpimg, 0o755),
        ("assets/InstallMultiRoot.sh", inst, 0o755),
        ("assets/magisk/magiskboot", magiskboot, 0o755),
        ("assets/magisk/magiskinit", magiskinit, 0o644),
        ("assets/magisk/magisk", magiskbin, 0o755),
        ("assets/magisk/init-ld", init_ld, 0o644),
        ("assets/magisk/stub.apk", stub_apk, 0o644),
        ("assets/magisk/arm64-v8a/magiskboot", magiskboot, 0o755),
        ("assets/magisk/arm64-v8a/magiskinit", magiskinit, 0o644),
        ("assets/magisk/arm64-v8a/magisk", magiskbin, 0o755),
        ("assets/magisk/arm64-v8a/init-ld", init_ld, 0o644),
        ("FolkPatch.apk", folk_apk, 0o644),
        ("APatch.apk", apatch_apk, 0o644),
        ("Magisk.apk", magisk_apk, 0o644),
    ]
    if mb32:
        inst_entries.extend([
            ("assets/magisk/armeabi-v7a/magiskboot", mb32, 0o755),
            ("assets/magisk/armeabi-v7a/magiskinit", mi32, 0o644),
            ("assets/magisk/armeabi-v7a/magisk", mbin32, 0o755),
            ("assets/magisk/armeabi-v7a/init-ld", ild32, 0o644),
        ])
    if apd:
        inst_entries.append(("assets/apd", apd, 0o755))
    if fpd:
        inst_entries.append(("assets/fpd", fpd, 0o755))
    if rp:
        inst_entries.append(("assets/resetprop", rp, 0o755))

    un_entries = list(common) + [
        ("assets/UninstallMultiRoot.sh", un, 0o755),
        ("assets/magisk/magiskboot", magiskboot, 0o755),
        ("assets/magisk/arm64-v8a/magiskboot", magiskboot, 0o755),
    ]
    if mb32:
        un_entries.append(("assets/magisk/armeabi-v7a/magiskboot", mb32, 0o755))

    os.makedirs(args.out, exist_ok=True)
    outs = []
    outs.append(build("MultiRoot-%s-Recovery-Installer.zip" % args.tag, inst_entries, rd_inst))
    outs.append(build("MultiRoot-%s-Uninstaller.zip" % args.tag, un_entries, rd_un))

    sums = os.path.join(args.out, "SHA256SUMS.txt")
    with open(sums, "w", newline="\n") as f:
        for o in outs:
            f.write("%s  %s\n" % (sha256_file(o), os.path.basename(o)))
    print("DONE -> %s" % args.out)
