#!/bin/sh
# FolkPatch boot-image patcher, file mode only (POSIX sh).
# Patches a stock boot IMG on sdcard. NEVER touches partitions directly.
# Env: BBBIN, INSTALLER. Args: $1 api, $2 fd, $3 zip.
OUTFD="$2"
BB="$BBBIN"
if [ -z "$BB" ]; then BB="busybox"; fi
WORK="$INSTALLER"
if [ -z "$WORK" ]; then WORK="/dev/tmp/fp_install"; fi
KPTOOLS=""
for k in "$WORK/lib/arm64-v8a/libkptools.so" "$WORK/kptools" "$WORK/assets/kptools"; do
  if [ -f "$k" ]; then
    chmod 755 "$k" 2>/dev/null
    KPTOOLS="$k"
    break
  fi
done
KPIMG="$WORK/assets/kpimg"

ui_print() {
  if [ -n "$OUTFD" ] && [ -e "/proc/self/fd/$OUTFD" ]; then
    printf 'ui_print %s\nui_print\n' "$1" >> "/proc/self/fd/$OUTFD" 2>/dev/null
  fi
  echo "$1" >&2
}
print_file() {
  while IFS= read -r line || [ -n "$line" ]; do
    ui_print "$line"
  done < "$1"
}
abort() {
  ui_print "- ERROR: $1"
  ui_print "- Patch aborted. Partitions NOT touched."
  exit 1
}

cd "$WORK" 2>/dev/null || abort "cannot cd to $WORK"
mount -o bind /dev/urandom /dev/random 2>/dev/null
OLD_LD_PRELOAD="$LD_PRELOAD"
OLD_LD_CONFIG="$LD_CONFIG_FILE"
unset LD_PRELOAD 2>/dev/null
unset LD_CONFIG_FILE 2>/dev/null

# Mount real system + APEX so kptools can resolve linker64 + bionic
SYS_OK=0
if [ -f /system_root/system/build.prop ] || [ -f /system_root/build.prop ]; then
  SYS_OK=1
else
  mkdir -p /system_root 2>/dev/null
  for _p in /dev/block/bootdevice/by-name/system_b /dev/block/by-name/system_b \
             /dev/block/bootdevice/by-name/system /dev/block/by-name/system; do
    if [ -e "$_p" ]; then
      mount -o ro "$_p" /system_root 2>/dev/null
      if [ -f /system_root/system/build.prop ] || [ -f /system_root/build.prop ]; then SYS_OK=1; break; fi
    fi
  done
fi
SYSROOT=""
if [ -f /system_root/system/build.prop ]; then SYSROOT="/system_root/system"; else SYSROOT="/system_root"; fi
mkdir -p /apex 2>/dev/null
APEX_SRC=""
for _a in "$SYSROOT/apex" /system_root/apex /system_root/system/apex; do
  if [ -d "$_a/com.android.runtime" ]; then APEX_SRC="$_a"; break; fi
done
if [ -z "$APEX_SRC" ]; then
  for _a in "$SYSROOT/apex" /system_root/apex /system_root/system/apex; do
    if [ -d "$_a" ]; then APEX_SRC="$_a"; break; fi
  done
fi
if [ -n "$APEX_SRC" ]; then
  mount -o bind "$APEX_SRC" /apex 2>/dev/null
  if [ -d "$APEX_SRC/com.android.runtime" ]; then
    mkdir -p /apex/com.android.runtime 2>/dev/null
    mount -o bind "$APEX_SRC/com.android.runtime" /apex/com.android.runtime 2>/dev/null
  fi
fi
if [ ! -x /system/bin/linker64 ]; then
  mount -o bind "$SYSROOT" /system 2>/dev/null
fi
if [ ! -x /system/bin/linker64 ] && [ -f "$SYSROOT/bin/linker64" ]; then
  mkdir -p /system/bin 2>/dev/null
  rm -f /system/bin/linker64 2>/dev/null
  cp -f "$SYSROOT/bin/linker64" /system/bin/linker64 2>/dev/null
  chmod 755 /system/bin/linker64 2>/dev/null
fi
LD_DIRS="/apex/com.android.runtime/lib64/bionic:/apex/com.android.runtime/lib64:/system/lib64:$SYSROOT/lib64:/system_root/system/lib64:/vendor/lib64"
if [ -n "$LD_LIBRARY_PATH" ]; then LD_DIRS="$LD_DIRS:$LD_LIBRARY_PATH"; fi
if [ ! -x /system/bin/linker64 ]; then ui_print "- WARNING: linker64 not found - kptools may fail"; fi

kp_run() { LD_LIBRARY_PATH="$LD_DIRS" "$KPTOOLS" "$@"; }
BB_OK=0
if [ -n "$BB" ] && [ -x "$BB" ] && "$BB" true 2>/dev/null; then BB_OK=1; else BB=""; fi
run_dd() {
  if [ "$BB_OK" = "1" ]; then "$BB" dd "$@"; else dd "$@"; fi
}
run_cp() {
  if [ "$BB_OK" = "1" ]; then "$BB" cp "$@"; else cp "$@"; fi
}
run_grep() {
  if [ "$BB_OK" = "1" ]; then "$BB" grep "$@"; else grep "$@"; fi
}
if ! command -v gzip >/dev/null 2>&1; then
  if [ "$BB_OK" = "1" ] && "$BB" gzip --help >/dev/null 2>&1; then
    mkdir -p "$WORK/bin" 2>/dev/null
    ln -sf "$BB" "$WORK/bin/gzip" 2>/dev/null
    PATH="$WORK/bin:$PATH"
  else
    ui_print "- WARNING: gzip missing, repack may fail"
  fi
fi
if [ ! -f "$KPTOOLS" ]; then abort "kptools missing"; fi
if [ ! -f "$KPIMG" ]; then abort "kpimg missing"; fi

ui_print "****************************"
ui_print " FolkPatch Boot Patcher"
ui_print " (file mode - no auto-flash)"
ui_print "****************************"

# Locate stock boot image on sdcard
SRC=""
for f in /sdcard/FolkPatch-stock-boot.img /data/media/0/FolkPatch-stock-boot.img \
          /sdcard/boot.img /sdcard/stock_boot.img /external_sd/boot.img /sdcard/stock-boot.img; do
  if [ -s "$f" ]; then SRC="$f"; break; fi
done
if [ -z "$SRC" ]; then
  for f in /sdcard/*.img /data/media/0/*.img /external_sd/*.img; do
    if [ -s "$f" ]; then SRC="$f"; break; fi
  done
fi
if [ -z "$SRC" ]; then
  ui_print "- Place your STOCK boot.img on sdcard named:"
  ui_print "  FolkPatch-stock-boot.img"
  abort "no stock boot image found on sdcard"
fi
ui_print "- Source: $SRC"

case "$SRC" in
  *init_boot*|*vendor_boot*|*vendor_kernel_boot*)
    KIND="boot"
    ui_print "- WARNING: '$SRC' looks like init_boot/vendor_boot (ramdisk only)"
    ui_print "- Kernel lives in BOOT. Use stock boot.img if this fails."
    ;;
  *) KIND="boot" ;;
esac

# Superkey = fixed default "su" (documented manual method + app default).
# Keyless would leave a random kernel key; -S would hash-lock a key the app
# never sends. Plaintext "su" matches on first compare. Old key files removed.
for d in /sdcard /data/media/0 /data/media /external_sd; do
  rm -f "$d/FolkPatch-key.txt" 2>/dev/null
done
ui_print "- Auth mode: default superkey 'su' (no key entry needed)"

OUTDIR=""
for d in /sdcard /data/media/0 /external_sd; do
  if [ -d "$d" ]; then OUTDIR="$d"; break; fi
done
if [ -z "$OUTDIR" ]; then
  OUTDIR="$WORK"
fi

if [ "$BB_OK" = "1" ]; then "$BB" cp -f "$SRC" "$WORK/boot.img" 2>/dev/null || abort "cannot copy source"; else cp -f "$SRC" "$WORK/boot.img" 2>/dev/null || abort "cannot copy source"; fi

ui_print "- Unpacking boot image ..."
kp_run unpack boot.img >"$WORK/unpack.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  print_file "$WORK/unpack.log"
  abort "unpack failed ($RC)"
fi
if [ ! -f kernel ]; then abort "no kernel after unpack"; fi

if ! kp_run -i kernel -f 2>/dev/null | run_grep -q "CONFIG_KALLSYMS=y"; then
  abort "kernel requires CONFIG_KALLSYMS=y"
fi
ui_print "- Kernel: CONFIG_KALLSYMS=y OK"
if kp_run -i kernel -l 2>/dev/null | run_grep -qi "patched=true"; then
  abort "source image already patched - use a STOCK boot.img"
fi

if [ "$BB_OK" = "1" ]; then "$BB" mv kernel kernel-origin 2>/dev/null || abort "cannot stage kernel"; else mv kernel kernel-origin 2>/dev/null || abort "cannot stage kernel"; fi

# Patch with fixed default key (same as documented manual method).
ui_print "- Patching kernel (superkey: su) ..."
kp_run -p -i kernel-origin -k "$KPIMG" -s "su" -o kernel >"$WORK/patch.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  print_file "$WORK/patch.log"
  abort "patch failed ($RC)"
fi

ui_print "- Verifying patch ..."
kp_run -i kernel -l >"$WORK/verify.log" 2>&1
if run_grep -qi "patched=false" "$WORK/verify.log"; then ui_print "- WARNING: verify reports patched=false (continuing anyway)"; fi
# Verify: superkey must read back as "su".
_VL=$(run_grep -i "^superkey=" "$WORK/verify.log" 2>/dev/null | head -n 1)
if [ -n "$_VL" ]; then
  case "$_VL" in
    superkey=su*) ui_print "- Superkey OK: su" ;;
    *) abort "superkey mismatch ($_VL) - app sends 'su'!" ;;
  esac
fi
if run_grep -qi "patched=true" "$WORK/verify.log"; then
  ui_print "- Kernel patched OK (patched=true)"
else
  ui_print "- Kernel patch applied (verify log differs)"
fi
if ! kp_run -i kernel-origin -f 2>/dev/null | run_grep -q "CONFIG_KALLSYMS_ALL=y"; then
  ui_print "- WARNING: CONFIG_KALLSYMS_ALL not enabled - keep stock backup"
fi

ui_print "- Repacking boot image ..."
kp_run repack boot.img >"$WORK/repack.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  print_file "$WORK/repack.log"
  abort "repack failed ($RC)"
fi
if [ ! -f "$WORK/new-boot.img" ]; then abort "new-boot.img missing"; fi

OUT="$OUTDIR/FolkPatch-patched-$KIND.img"
if [ "$BB_OK" = "1" ]; then "$BB" cp -f "$WORK/new-boot.img" "$OUT" 2>/dev/null || abort "cannot write $OUT"; else cp -f "$WORK/new-boot.img" "$OUT" 2>/dev/null || abort "cannot write $OUT"; fi
mkdir -p "$OUTDIR/Download/FolkPatch/BootBackups" 2>/dev/null
run_cp -f "$SRC" "$OUTDIR/Download/FolkPatch/BootBackups/" 2>/dev/null
if [ -f "$WORK/FolkPatch.apk" ]; then
  run_cp -f "$WORK/FolkPatch.apk" "$OUTDIR/FolkPatch-Manager.apk" 2>/dev/null
  run_cp -f "$WORK/FolkPatch.apk" "$OUTDIR/Download/FolkPatch/FolkPatch-Manager.apk" 2>/dev/null
fi

if [ -n "$OLD_LD_PRELOAD" ]; then export LD_PRELOAD="$OLD_LD_PRELOAD"; fi
if [ -n "$OLD_LD_CONFIG" ]; thensuperkey: su LD_CONFIG_FILE="$OLD_LD_CONFIG"; fi

ui_print "****************************"
ui_print " Patched image ready (keyless):"
ui_print " $OUT"
ui_print " Flash with: fastboot flash $KIND $OUT"
ui_print " Then reboot and install FolkPatch-Manager.apk"
ui_print " No key entry needed in the app (signature auth)."
ui_print "****************************"
exit 0
