#!/usr/bin/env python3
"""Build Magisk-style FolkPatch recovery ZIPs from the official APK.

Downloads nothing by default: uses FolkPatch.apk placed next to this repo
(see APK_URL below), extracts busybox/kptools/kpimg, packs 3 ZIPs + SHA256SUMS.

Usage:
    python tools/build.py [--apk PATH] [--out dist] [--version 1.0] [--kp 0.13.8]
    python tools/build.py --tag v1.0-kp0.13.8   # tag drives ZIP filenames
"""
import argparse
import hashlib
import os
import re
import sys
import urllib.request
import zipfile

APK_URL = "https://github.com/LyraVoid/FolkPatch/releases/download/kp0.13.8/FolkPatch_115032_5.0_on_main-release.apk"
APK_SHA256 = "0b1671fe42a565a4fb8a573ac9b480febe11189380f96c83ccbe29fdfd375890"

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


def w(z, name, data, mode=0o644):
    zi = zipfile.ZipInfo(name)
    zi.external_attr = (mode & 0xFFFF) << 16
    zi.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(zi, data)


def build(outname, script_name, script_data, ub, us, rd, bb, kt, kp, apk, extra=None):
    out = os.path.join(args.out, outname)
    z = zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9)
    zi = zipfile.ZipInfo("META-INF/com/google/android/update-binary")
    zi.external_attr = (0o755 & 0xFFFF) << 16
    zi.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(zi, ub)
    zi2 = zipfile.ZipInfo("META-INF/com/google/android/updater-script")
    zi2.external_attr = (0o644 & 0xFFFF) << 16
    zi2.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(zi2, us)
    w(z, "busybox", bb, 0o755)
    w(z, "lib/arm64-v8a/libbusybox.so", bb, 0o755)
    w(z, "lib/arm64-v8a/libkptools.so", kt, 0o755)
    for name, data in (extra or []):
        w(z, name, data, 0o755)
    w(z, "assets/" + script_name, script_data, 0o755)
    # Also include assets folder contents (apd, fpd, resetprop, kpimg).
    # CRITICAL: pack ONLY the selected installer script. Packing all *.sh
    # files breaks ADB sideload: recovery renames the ZIP to
    # /sideload/package.zip, so update-binary cannot pick a script by ZIP
    # filename and always falls back to InstallFP.sh (wrong ZIP = no root /
    # wrong action). One script per ZIP keeps sideload working.
    assets_dir = os.path.join(ROOT, "assets")
    if os.path.isdir(assets_dir):
        for root, dirs, files in os.walk(assets_dir):
            for fname in files:
                if fname.endswith(".sh"):
                    continue  # selected script already added above; skip others
                fpath = os.path.join(root, fname)
                arcname = os.path.relpath(fpath, ROOT)
                with open(fpath, "rb") as f:
                    w(z, arcname, f.read(), 0o755)
    w(z, "FolkPatch.apk", apk, 0o644)
    w(z, "README.txt", rd, 0o644)
    z.close()
    print(outname, os.path.getsize(out))
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", default=os.path.join(ROOT, "FolkPatch.apk"))
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"))
    ap.add_argument("--version", default="1.0")
    ap.add_argument("--kp", default="0.13.8")
    ap.add_argument("--tag", default="",
                    help="Release tag like v1.0-kp0.13.8; drives ZIP names + README.txt")
    args = ap.parse_args()

    if args.tag:
        m = re.match(r"^v(.+?)-[kK][pP](.+)$", args.tag.strip())
        if m:
            args.version, args.kp = m.group(1), m.group(2)
            print("Tag %s -> version=%s kp=%s" % (args.tag, args.version, args.kp))
        else:
            print("WARNING: --tag %s not like v<ver>-kp<kp>, using --version/--kp" % args.tag)
        tag = args.tag.lstrip("v")
        tag = "v" + tag
    else:
        tag = "v%s-KP%s" % (args.version, args.kp)
    print("Building: %s" % tag)

    apk_path = args.apk
    if not os.path.exists(apk_path):
        print("APK not found at %s, downloading official release..." % apk_path)
        print("URL: %s" % APK_URL)
        urllib.request.urlretrieve(APK_URL, apk_path)
    digest = sha256_file(apk_path)
    if digest != APK_SHA256:
        print("WARNING: APK sha256 mismatch:\n  got      %s\n  expected %s" % (digest, APK_SHA256))
        print("Continuing anyway (upstream may have re-uploaded).")
    else:
        print("APK sha256 OK")

    ub = lf(os.path.join(ROOT, "META-INF", "com", "google", "android", "update-binary"))
    us = lf(os.path.join(ROOT, "META-INF", "com", "google", "android", "updater-script"))
    inst = lf(os.path.join(ROOT, "assets", "InstallFP.sh"))
    patch = lf(os.path.join(ROOT, "assets", "PatchOnly.sh"))
    un = lf(os.path.join(ROOT, "assets", "UninstallFP.sh"))

    rd_lines = [
        "FolkPatch v%s (KP-%s) - Magisk-style Recovery ZIPs" % (args.version, args.kp),
        "See https://github.com/bmjubairdadu/FolkPatch-Flashable-ZIP for guide.",
        "1) *-Recovery-Installer.zip = direct flash boot from recovery.",
        "2) *-Boot-Patcher.zip = patch stock img on sdcard (safe, no auto-flash).",
        "3) *-Uninstaller.zip = restore stock backup or live-unpatch.",
        "Needs ARM64 + CONFIG_KALLSYMS=y. Keep stock backup. GPL-3.0.",
    ]
    rd = ("\n".join(rd_lines) + "\n").encode()

    za = zipfile.ZipFile(apk_path)
    bb = za.read("lib/arm64-v8a/libbusybox.so")
    kt = za.read("lib/arm64-v8a/libkptools.so")
    kp = za.read("assets/kpimg")
    # Instant-root daemon files (app rule): libapd.so -> /data/adb/apd,
    # Service/fpd -> /data/adb/fp/bin/fpd, resetprop -> /data/adb/ap/bin/.
    try:
        apd = za.read("lib/arm64-v8a/libapd.so")
    except KeyError:
        apd = b""
    try:
        fpd = za.read("assets/Service/fpd")
    except KeyError:
        fpd = b""
    try:
        rp = za.read("lib/arm64-v8a/libresetprop.so")
    except KeyError:
        rp = b""
    za.close()
    extra = []
    if apd:
        extra.append(("assets/apd", apd))
    if fpd:
        extra.append(("assets/fpd", fpd))
    if rp:
        extra.append(("assets/resetprop", rp))
    if not apd:
        print("WARNING: libapd.so missing in APK - instant-root daemon unavailable")
    with open(apk_path, "rb") as f:
        apk = f.read()

    os.makedirs(args.out, exist_ok=True)
    outs = []
    outs.append(build("FolkPatch-%s-Recovery-Installer.zip" % tag, "InstallFP.sh", inst, ub, us, rd, bb, kt, kp, apk, extra))
    outs.append(build("FolkPatch-%s-Boot-Patcher.zip" % tag, "PatchOnly.sh", patch, ub, us, rd, bb, kt, kp, apk, extra))
    outs.append(build("FolkPatch-%s-Uninstaller.zip" % tag, "UninstallFP.sh", un, ub, us, rd, bb, kt, kp, apk))

    with open(os.path.join(args.out, "SHA256SUMS.txt"), "w") as f:
        for o in outs:
            f.write("%s  %s\n" % (sha256_file(o), os.path.basename(o)))
    print("DONE ->", args.out)
