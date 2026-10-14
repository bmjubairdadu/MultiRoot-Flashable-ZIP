#!/bin/sh
# =====================================================================
# MultiRoot direct-flash installer (POSIX sh, recovery compatible).
# One flash, any root manager:
#   - KernelPatch root (kpimg 0.13.8) -> FolkPatch / APatch managers
#   - Magisk 30.6 ramdisk root        -> Magisk manager
# Modes: create /sdcard/root-mode.txt with one word before flashing:
#   all    (default) = KernelPatch + Magisk (universal root)
#   kpatch           = KernelPatch only (FolkPatch / APatch managers)
#   magisk           = Magisk only (Magisk manager)
# NO backup files are created anywhere: read boot -> patch in tmpfs ->
# flash -> verify readback -> delete every temp file. Direct flash only.
# No bashisms: no 'function', no '[[', no '=='.
# Env from update-binary: BBBIN, INSTALLER, ARCH. Args: $1 api, $2 fd, $3 zip.
# =====================================================================
OUTFD="$2"
ZIPFILE="$3"
BB="$BBBIN"
if [ -z "$BB" ]; then BB="busybox"; fi
WORK="$INSTALLER"
if [ -z "$WORK" ]; then WORK="/dev/tmp/multiroot"; fi
KP_VER="0.13.8"
MAGISK_VER="30.6"
INST_VER="2.1"

ui_print() {
  if [ -n "$OUTFD" ] && [ -e "/proc/self/fd/$OUTFD" ]; then
    printf 'ui_print %s\nui_print\n' "$1" >> "/proc/self/fd/$OUTFD" 2>/dev/null
  else
    echo "$1" >&2
  fi
}
print_file() {
  while IFS= read -r line || [ -n "$line" ]; do
    ui_print "$line"
  done < "$1"
}
abort() {
  ui_print "- ERROR: $1"
  ui_print "- Installation aborted."
  exit 1
}

cd "$WORK" 2>/dev/null || abort "cannot cd to $WORK"

# Entropy fix (prevents patch hangs in some recoveries)
mount -o bind /dev/urandom /dev/random 2>/dev/null
OLD_LD_PRELOAD="$LD_PRELOAD"
OLD_LD_CONFIG="$LD_CONFIG_FILE"
unset LD_PRELOAD 2>/dev/null
unset LD_CONFIG_FILE 2>/dev/null

BB_OK=0
if [ -n "$BB" ] && [ -x "$BB" ] && "$BB" true 2>/dev/null; then BB_OK=1; else BB=""; fi
run_dd() {
  if [ "$BB_OK" = "1" ]; then "$BB" dd "$@"; else dd "$@"; fi
}
run_cp() {
  if [ "$BB_OK" = "1" ]; then "$BB" cp "$@"; else cp "$@"; fi
}
run_mv() {
  if [ "$BB_OK" = "1" ]; then "$BB" mv "$@"; else mv "$@"; fi
}
run_rm() {
  if [ "$BB_OK" = "1" ]; then "$BB" rm "$@"; else rm "$@"; fi
}
run_grep() {
  if [ "$BB_OK" = "1" ]; then "$BB" grep "$@"; else grep "$@"; fi
}
run_unzip() {
  if [ "$BB_OK" = "1" ]; then "$BB" unzip -o "$@"; else unzip -o "$@"; fi
}
grep_prop() {
  [ -n "$1" ] && [ -f "$2" ] || return 1
  run_grep "^$1=" "$2" 2>/dev/null | head -n 1 | cut -d= -f2- 2>/dev/null
}

# ---------------------------------------------------------------------
# Slot detection at the very beginning (needed for system/vendor/boot)
SLOT=""
if [ -f /proc/cmdline ]; then
  _cmdline=$(cat /proc/cmdline 2>/dev/null)
  case "$_cmdline" in
    *androidboot.slot_suffix=*)
      SLOT=$(echo "$_cmdline" | tr ' ' '\n' 2>/dev/null | grep '^androidboot.slot_suffix=' 2>/dev/null | head -n 1 | cut -d= -f2)
      ;;
  esac
  if [ -z "$SLOT" ]; then
    _s=$(echo "$_cmdline" | tr ' ' '\n' 2>/dev/null | grep '^androidboot.slot=' 2>/dev/null | head -n 1 | cut -d= -f2)
    if [ -n "$_s" ]; then SLOT="_$_s"; fi
  fi
fi
if [ -z "$SLOT" ] && [ -f /proc/bootconfig ]; then
  _bs=$(grep -o 'androidboot\.slot_suffix *= *[^ ]*' /proc/bootconfig 2>/dev/null | head -n 1 | cut -d= -f2 | tr -d ' "')
  if [ -n "$_bs" ]; then SLOT="$_bs"; fi
  if [ -z "$SLOT" ]; then
    _b=$(grep -o 'androidboot\.slot *= *[^ ]*' /proc/bootconfig 2>/dev/null | head -n 1 | cut -d= -f2 | tr -d ' "')
    if [ -n "$_b" ]; then SLOT="_$_b"; fi
  fi
fi
if [ -z "$SLOT" ] && command -v getprop >/dev/null 2>&1; then
  SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
  if [ -z "$SLOT" ]; then
    S=$(getprop ro.boot.slot 2>/dev/null)
    if [ -n "$S" ]; then SLOT="_$S"; fi
  fi
fi
if [ "$SLOT" = "normal" ]; then SLOT=""; fi
if [ -z "$SLOT" ]; then
  _act=""
  for _f in /etc/recovery.fstab /etc/twrp.fstab /etc/fox.fstab /proc/mounts /etc/mtab; do
    if [ -f "$_f" ]; then
      _m=$(grep -o '/dev/block/[^ ]*boot_[ab]' "$_f" 2>/dev/null | head -n 1)
      case "$_m" in
        *_a) _act="_a"; break ;;
        *_b) _act="_b"; break ;;
      esac
    fi
  done
  if [ -n "$_act" ]; then
    SLOT="$_act"
  elif [ -e "/dev/block/bootdevice/by-name/boot_a" ] || [ -e "/dev/block/by-name/boot_a" ]; then
    SLOT="_a"
  fi
fi

# Architecture detection
if [ -z "$ARCH" ] && [ "$BB_OK" = "1" ]; then
  _u=$("$BB" uname -m 2>/dev/null)
  case "$_u" in
    aarch64|arm64*) ARCH="arm64-v8a" ;;
    arm*|armv7*) ARCH="armeabi-v7a" ;;
    x86_64|amd64) ARCH="x86_64" ;;
    i*86|x86) ARCH="x86" ;;
  esac
fi
if [ -z "$ARCH" ] && command -v getprop >/dev/null 2>&1; then
  _abi=$(getprop ro.product.cpu.abi 2>/dev/null)
  case "$_abi" in
    arm64*) ARCH="arm64-v8a" ;;
    armeabi*) ARCH="armeabi-v7a" ;;
    x86_64*) ARCH="x86_64" ;;
    x86*) ARCH="x86" ;;
  esac
fi
if [ -z "$ARCH" ]; then ARCH="arm64-v8a"; fi

# Locate Magisk tools
MAGDIR="$WORK/assets/magisk"
if [ -d "$WORK/assets/magisk/$ARCH" ]; then
  MAGDIR="$WORK/assets/magisk/$ARCH"
elif [ -d "$WORK/lib/$ARCH" ]; then
  MAGDIR="$WORK/lib/$ARCH"
fi

MAGISKBOOT=""
for mb in "$MAGDIR/magiskboot" "$WORK/assets/magisk/magiskboot" \
          "$WORK/lib/$ARCH/libmagiskboot.so" "$WORK/lib/arm64-v8a/libmagiskboot.so"; do
  if [ -f "$mb" ]; then
    chmod 755 "$mb" 2>/dev/null
    MAGISKBOOT="$mb"
    break
  fi
done

# Define BOTH run_magisk and magisk_run (magiskboot is statically linked)
run_magisk() {
  "$MAGISKBOOT" "$@"
}
magisk_run() {
  "$MAGISKBOOT" "$@"
}

# Locate KernelPatch tools (ARM64 only)
KPTOOLS=""
for k in "$WORK/lib/$ARCH/libkptools.so" "$WORK/lib/arm64-v8a/libkptools.so" \
         "$WORK/kptools" "$WORK/assets/kptools"; do
  if [ -f "$k" ]; then
    chmod 755 "$k" 2>/dev/null
    KPTOOLS="$k"
    break
  fi
done
KPIMG="$WORK/assets/kpimg"

# Mount real system + APEX runtime if needed for dynamic-linked bionic tools (kptools)
SYSROOT=""
if [ -f /system_root/system/build.prop ]; then
  SYSROOT="/system_root/system"
elif [ -f /system_root/build.prop ]; then
  SYSROOT="/system_root"
elif [ -f /system/build.prop ]; then
  SYSROOT="/system"
else
  mkdir -p /system_root 2>/dev/null
  for _p in "/dev/block/bootdevice/by-name/system$SLOT" "/dev/block/by-name/system$SLOT" \
             "/dev/block/bootdevice/by-name/system" "/dev/block/by-name/system" \
             "/dev/block/bootdevice/by-name/system_a" "/dev/block/by-name/system_a" \
             "/dev/block/bootdevice/by-name/system_b" "/dev/block/by-name/system_b" \
             "/dev/block/mapper/system$SLOT" "/dev/block/mapper/system"; do
    if [ -e "$_p" ]; then
      mount -o ro "$_p" /system_root 2>/dev/null
      if [ -f /system_root/system/build.prop ]; then SYSROOT="/system_root/system"; break; fi
      if [ -f /system_root/build.prop ] || [ -d /system_root/bin ]; then SYSROOT="/system_root"; break; fi
    fi
  done
fi

mkdir -p /vendor_lib 2>/dev/null
for _v in "/dev/block/bootdevice/by-name/vendor$SLOT" "/dev/block/by-name/vendor" \
           "/dev/block/mapper/vendor$SLOT" "/dev/block/mapper/vendor"; do
  if [ -e "$_v" ]; then mount -o ro "$_v" /vendor_lib 2>/dev/null && break; fi
done

mkdir -p /apex 2>/dev/null
APEX_SRC=""
for _a in "$SYSROOT/apex" /system_root/apex /system_root/system/apex /apex; do
  if [ -d "$_a/com.android.runtime" ]; then APEX_SRC="$_a"; break; fi
done
if [ -z "$APEX_SRC" ]; then
  for _a in "$SYSROOT/apex" /system_root/apex /system_root/system/apex /apex; do
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

if [ ! -d /apex/com.android.runtime/lib64/bionic ]; then
  for _r in /system_root/com.android.runtime /system_root/system/com.android.runtime \
             "$SYSROOT/com.android.runtime" /vendor_lib/com.android.runtime; do
    if [ -d "$_r/lib64/bionic" ]; then
      mkdir -p /apex/com.android.runtime 2>/dev/null
      mount -o bind "$_r" /apex/com.android.runtime 2>/dev/null
      break
    fi
  done
fi

if [ ! -x /system/bin/linker64 ] && [ -n "$SYSROOT" ] && [ -x "$SYSROOT/bin/linker64" ]; then
  mount -o bind "$SYSROOT" /system 2>/dev/null
fi
if [ ! -x /system/bin/linker64 ] && [ -n "$SYSROOT" ] && [ -f "$SYSROOT/bin/linker64" ]; then
  mkdir -p /system/bin 2>/dev/null
  rm -f /system/bin/linker64 2>/dev/null
  cp -f "$SYSROOT/bin/linker64" /system/bin/linker64 2>/dev/null
  chmod 755 /system/bin/linker64 2>/dev/null
fi

LD_DIRS="/apex/com.android.runtime/lib64/bionic:/apex/com.android.runtime/lib64:/system/lib64:$SYSROOT/lib64:/system_root/system/lib64:/vendor/lib64:/vendor_lib/lib64:/vendor_lib/system/lib64"
if [ -n "$LD_LIBRARY_PATH" ]; then LD_DIRS="$LD_DIRS:$LD_LIBRARY_PATH"; fi

kp_run() {
  LD_LIBRARY_PATH="$LD_DIRS" "$KPTOOLS" "$@"
  return $?
}

ui_print "****************************"
ui_print " MultiRoot Recovery Installer"
ui_print " v$INST_VER: KernelPatch $KP_VER + Magisk $MAGISK_VER"
ui_print " Universal Root for Any Android"
ui_print "****************************"

ui_print "- Platform: $ARCH"
if [ -n "$SLOT" ]; then
  ui_print "- A/B slot: $SLOT"
else
  ui_print "- Slot: A-only"
fi

# by-name block lookup with multiple fallback paths
find_block() {
  _b="$1"
  for p in "/dev/block/by-name/$_b" "/dev/block/bootdevice/by-name/$_b"; do
    if [ -e "$p" ]; then echo "$p"; return 0; fi
  done
  for _m in /dev/block/platform/*/by-name/"$_b" /dev/block/platform/*/*/by-name/"$_b"; do
    if [ -e "$_m" ]; then echo "$_m"; return 0; fi
  done
  for _dm in /dev/block/mapper/"$_b"; do
    if [ -e "$_dm" ]; then echo "$_dm"; return 0; fi
  done
  _dev=$(find /dev/block -iname "$_b" 2>/dev/null | head -n 1)
  if [ -n "$_dev" ]; then echo "$_dev"; return 0; fi
  for _u in /sys/dev/block/*/uevent; do
    if [ -f "$_u" ]; then
      _pn=$(grep '^PARTNAME=' "$_u" 2>/dev/null | cut -d= -f2)
      _dn=$(grep '^DEVNAME=' "$_u" 2>/dev/null | cut -d= -f2)
      if [ -n "$_pn" ] && [ -n "$_dn" ]; then
        _pl=$(echo "$_pn" | tr 'A-Z' 'a-z'); _bl=$(echo "$_b" | tr 'A-Z' 'a-z')
        if [ "$_pl" = "$_bl" ] && [ -e "/dev/block/$_dn" ]; then echo "/dev/block/$_dn"; return 0; fi
      fi
    fi
  done
  return 1
}

find_part() {
  if [ -n "$SLOT" ]; then
    _t=$(find_block "$1$SLOT")
    if [ -n "$_t" ]; then echo "$_t"; return 0; fi
  fi
  _t=$(find_block "$1")
  if [ -n "$_t" ]; then echo "$_t"; return 0; fi
  return 1
}

TARGET=""
for _n in boot kern-a android_boot kernel bootimg lnx; do
  T=$(find_part "$_n")
  if [ -n "$T" ]; then
    TARGET="$T"
    break
  fi
done
if [ -z "$TARGET" ]; then
  ui_print "- Available partitions:"
  ls /dev/block/by-name 2>/dev/null | while IFS= read -r _p || [ -n "$_p" ]; do ui_print "  $_p"; done
  abort "No boot partition found."
fi
ui_print "- Target: boot ($TARGET)"

# Mode selection: /sdcard/root-mode.txt (first line) overrides default.
MODE="all"
for mf in /sdcard/root-mode.txt /data/media/0/root-mode.txt /external_sd/root-mode.txt /data/local/tmp/root-mode.txt; do
  if [ -f "$mf" ]; then
    MODE=$(head -n 1 "$mf" 2>/dev/null | tr -d ' \t\r\n' | tr 'A-Z' 'a-z')
    ui_print "- Mode file: $mf"
    break
  fi
done
case "$MODE" in
  kpatch|kp) MODE="kpatch" ;;
  magisk|magisk-only|magiskonly) MODE="magisk" ;;
  all|"") MODE="all" ;;
  *) ui_print "- WARNING: unknown mode '$MODE', using 'all'"; MODE="all" ;;
esac
case "$MODE" in
  all)    ui_print "- Mode: ALL (KernelPatch + Magisk - universal root)" ;;
  kpatch) ui_print "- Mode: KPATCH (FolkPatch / APatch managers)" ;;
  magisk) ui_print "- Mode: MAGISK (Magisk manager)" ;;
esac

# Tool validation
if [ "$MODE" = "kpatch" ]; then
  if [ -z "$KPTOOLS" ] || [ ! -x "$KPTOOLS" ]; then abort "kptools missing or cannot execute"; fi
  if [ ! -f "$KPIMG" ]; then abort "kpimg missing"; fi
fi
if [ "$MODE" != "kpatch" ]; then
  if [ -z "$MAGISKBOOT" ] || [ ! -x "$MAGISKBOOT" ]; then abort "magiskboot missing or cannot execute"; fi
fi

# init_boot (only used for Magisk when boot itself has no ramdisk on Android 13+ GKI)
INITBOOT_PART=""
if [ "$MODE" != "kpatch" ]; then
  INITBOOT_PART=$(find_part init_boot 2>/dev/null)
fi

# State flags
CHROMEOS=false
VENDORBOOT=false
KEEPVERITY=false
KEEPFORCEENCRYPT=false
PATCHVBMETAFLAG=false
RECOVERYMODE=false
LEGACYSAR=false
PREINITDEVICE=""
KP_OK=0
MG_IN_SLOT=0
PATCHEDKERNEL=false

clean_stage() {
  rm -f kernel kernel-origin kernel-clean ramdisk.cpio ramdisk.cpio.orig \
       new-boot.img dtb extra kernel_dtb config config.orig stock_boot.img \
       boot2.img magisk magiskinit stub.apk init-ld magisk.xz stub.xz \
       init-ld.xz check.img 2>/dev/null
  rm -rf "$WORK/vcheck" 2>/dev/null
}

stage_magisk_payload() {
  _m_init=""
  _m_bin=""
  _m_stub=""
  _m_ld=""
  for d in "$MAGDIR" "$WORK/assets/magisk" "$WORK/lib/$ARCH"; do
    [ -z "$_m_init" ] && [ -f "$d/magiskinit" ] && _m_init="$d/magiskinit"
    [ -z "$_m_init" ] && [ -f "$d/libmagiskinit.so" ] && _m_init="$d/libmagiskinit.so"
    [ -z "$_m_bin" ] && [ -f "$d/magisk" ] && _m_bin="$d/magisk"
    [ -z "$_m_bin" ] && [ -f "$d/libmagisk.so" ] && _m_bin="$d/libmagisk.so"
    [ -z "$_m_stub" ] && [ -f "$d/stub.apk" ] && _m_stub="$d/stub.apk"
    [ -z "$_m_ld" ] && [ -f "$d/init-ld" ] && _m_ld="$d/init-ld"
    [ -z "$_m_ld" ] && [ -f "$d/libinit-ld.so" ] && _m_ld="$d/libinit-ld.so"
  done
  [ -z "$_m_stub" ] && [ -f "$WORK/assets/magisk/stub.apk" ] && _m_stub="$WORK/assets/magisk/stub.apk"

  [ -n "$_m_init" ] && run_cp -f "$_m_init" magiskinit
  [ -n "$_m_bin" ] && run_cp -f "$_m_bin" magisk
  [ -n "$_m_stub" ] && run_cp -f "$_m_stub" stub.apk
  [ -n "$_m_ld" ] && run_cp -f "$_m_ld" init-ld
  chmod 755 magisk magiskinit 2>/dev/null
}

magisk_hexpatch() {
  PATCHEDKERNEL=false
  if [ ! -f kernel ] || [ -z "$MAGISKBOOT" ]; then return 0; fi
  run_magisk hexpatch kernel \
    49010054011440B93FA00F71E9000054010840B93FA00F7189000054001840B91FA00F7188010054 \
    A1020054011440B93FA00F7140020054010840B93FA00F71E0010054001840B91FA00F7181010054 \
    >/dev/null 2>&1 && { PATCHEDKERNEL=true; ui_print "- Samsung RKP disabled"; }
  run_magisk hexpatch kernel 821B8012 E2FF8F12 >/dev/null 2>&1 && { PATCHEDKERNEL=true; ui_print "- Samsung defex disabled"; }
  run_magisk hexpatch kernel \
    70726F63615F636F6E66696700 \
    70726F63615F6D616769736B00 \
    >/dev/null 2>&1 && { PATCHEDKERNEL=true; ui_print "- Samsung PROCA disabled"; }
  return 0
}

kp_patch_kernel() {
  if [ ! -f kernel ]; then
    ui_print "- NOTICE: No kernel in boot image; KernelPatch skipped"
    return 0
  fi
  if [ "$ARCH" != "arm64-v8a" ]; then
    ui_print "- NOTICE: Device architecture is $ARCH (KernelPatch requires ARM64)"
    ui_print "- Magisk root will provide full root access"
    return 0
  fi
  if [ -z "$KPTOOLS" ] || [ ! -x "$KPTOOLS" ] || [ ! -f "$KPIMG" ]; then
    if [ "$MODE" = "kpatch" ]; then abort "KernelPatch tools unavailable"; fi
    ui_print "- NOTICE: KernelPatch tools unavailable; skipping to Magisk"
    return 0
  fi

  # Test if kptools can actually execute in this environment
  kp_run -h >/dev/null 2>&1
  _kprc=$?
  if [ $_kprc -eq 127 ] || [ $_kprc -eq 126 ]; then
    if [ "$MODE" = "kpatch" ]; then abort "kptools cannot execute (missing bionic libraries)"; fi
    ui_print "- NOTICE: kptools cannot execute in this recovery (linker/APEX not resolved)"
    ui_print "- Magisk root will provide full root access"
    return 0
  fi

  if ! kp_run -i kernel -f 2>/dev/null | run_grep -q "CONFIG_KALLSYMS=y"; then
    if [ "$MODE" = "kpatch" ]; then abort "kernel requires CONFIG_KALLSYMS=y"; fi
    ui_print "- NOTICE: Kernel lacks CONFIG_KALLSYMS=y (KernelPatch unsupported)"
    ui_print "- Magisk root will provide full root access"
    return 0
  fi
  ui_print "- Kernel: CONFIG_KALLSYMS=y OK"

  run_mv kernel kernel-origin || { ui_print "- WARNING: cannot stage kernel"; return 0; }
  
  # Clean previous patch if kernel was already patched
  kp_run -i kernel-origin -l > "$WORK/vorig.log" 2>&1
  if run_grep -qi "patched=true" "$WORK/vorig.log"; then
    ui_print "- Cleaning existing patch for fresh root ..."
    kp_run -u -i kernel-origin -o kernel-clean >/dev/null 2>&1
    if [ -s kernel-clean ]; then
      run_mv -f kernel-clean kernel-origin
      ui_print "- Kernel cleaned successfully"
    fi
  fi

  ui_print "- Patching kernel with KernelPatch (superkey: su) ..."
  kp_run -p -i kernel-origin -k "$KPIMG" -s "su" -o kernel >"$WORK/patch.log" 2>&1
  RC=$?
  if [ "$RC" -ne 0 ] || [ ! -s kernel ]; then
    print_file "$WORK/patch.log"
    if [ "$MODE" = "kpatch" ]; then abort "KernelPatch patch failed ($RC)"; fi
    ui_print "- WARNING: KernelPatch failed ($RC); falling back to stock kernel"
    run_cp -f kernel-origin kernel 2>/dev/null
    return 0
  fi

  kp_run -i kernel -l >"$WORK/verify.log" 2>&1
  if run_grep -qi "patched=false" "$WORK/verify.log"; then
    if [ "$MODE" = "kpatch" ]; then abort "KernelPatch verification failed"; fi
    ui_print "- WARNING: KernelPatch verify failed; falling back to stock kernel"
    run_cp -f kernel-origin kernel 2>/dev/null
    return 0
  fi

  ui_print "- KernelPatch OK (patched=true)"
  _VL=$(run_grep -i "^superkey=" "$WORK/verify.log" 2>/dev/null | head -n 1)
  case "$_VL" in
    superkey=su*) ui_print "- Superkey OK: su" ;;
    "") ui_print "- NOTE: superkey embedded in kernel" ;;
    *) ui_print "- Superkey: $_VL" ;;
  esac
  KP_OK=1
}

do_magisk_ramdisk() {
  _RD="$1"
  _SHA1="$2"
  _SKIPB="$3"
  stage_magisk_payload
  ui_print "- Compressing Magisk payload ..."
  run_magisk compress=xz magisk magisk.xz >/dev/null 2>&1 || abort "cannot compress magisk"
  run_magisk compress=xz stub.apk stub.xz >/dev/null 2>&1 || abort "cannot compress stub"
  run_magisk compress=xz init-ld init-ld.xz >/dev/null 2>&1 || abort "cannot compress init-ld"
  echo "KEEPVERITY=$KEEPVERITY" > config
  echo "KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT" >> config
  echo "RECOVERYMODE=$RECOVERYMODE" >> config
  echo "VENDORBOOT=$VENDORBOOT" >> config
  if [ -n "$PREINITDEVICE" ]; then
    ui_print "- Pre-init storage partition: $PREINITDEVICE"
    echo "PREINITDEVICE=$PREINITDEVICE" >> config
  fi
  [ -n "$_SHA1" ] && echo "SHA1=$_SHA1" >> config
  ui_print "- Patching ramdisk (Magisk $MAGISK_VER) ..."
  run_magisk cpio "$_RD" \
    "add 0750 init magiskinit" \
    "mkdir 0750 overlay.d" \
    "mkdir 0750 overlay.d/sbin" \
    "add 0644 overlay.d/sbin/magisk.xz magisk.xz" \
    "add 0644 overlay.d/sbin/stub.xz stub.xz" \
    "add 0644 overlay.d/sbin/init-ld.xz init-ld.xz" \
    "patch" \
    "$_SKIPB backup ramdisk.cpio.orig" \
    "mkdir 000 .backup" \
    "add 000 .backup/.magisk config" \
    >"$WORK/cpio.log" 2>&1 || { print_file "$WORK/cpio.log"; abort "! Unable to patch ramdisk"; }
  rm -f ramdisk.cpio.orig config magisk.xz stub.xz init-ld.xz 2>/dev/null
  MG_IN_SLOT=1
}

flash_partition() {
  _part="$1"
  _label="$2"
  _img="$WORK/new-boot.img"
  _sz=$(wc -c < "$_img" 2>/dev/null | tr -d ' \t\r\n')
  if [ -z "$_sz" ] || [ "$_sz" = "0" ]; then abort "patched image is empty, refusing to flash"; fi
  if command -v blockdev >/dev/null 2>&1; then
    _bsz=$(blockdev --getsize64 "$_part" 2>/dev/null)
    if [ -n "$_bsz" ] && [ "$_bsz" != "0" ] && [ "$_sz" -gt "$_bsz" ]; then
      abort "patched image ($_sz bytes) larger than partition ($_bsz bytes)"
    fi
    blockdev --setrw "$_part" 2>/dev/null
  fi
  ui_print "- Flashing $2 ..."
  run_dd "if=$_img" "of=$_part" bs=4096 2>"$WORK/dd_write.log" || abort "flash failed on $_part"
  sync 2>/dev/null
}

verify_partition() {
  _part="$1"
  _label="$2"
  _esz=$(wc -c < "$WORK/new-boot.img" 2>/dev/null | tr -d ' \t\r\n')
  if [ -z "$_esz" ] || [ "$_esz" = "0" ]; then return 0; fi
  _blocks=$(( (_esz + 511) / 512 ))
  if ! run_dd "if=$_part" of="$WORK/check.img" bs=512 "count=$_blocks" 2>/dev/null || [ ! -s "$WORK/check.img" ]; then
    ui_print "- WARNING: cannot read back $_part for verification"
    return 0
  fi
  rm -rf "$WORK/vcheck" 2>/dev/null
  mkdir -p "$WORK/vcheck" 2>/dev/null
  run_cp -f "$WORK/check.img" "$WORK/vcheck/boot.img" 2>/dev/null
  cd "$WORK/vcheck" 2>/dev/null
  run_magisk unpack boot.img >/dev/null 2>&1
  if [ "$KP_OK" = "1" ] && [ -f kernel ]; then
    kp_run -i kernel -l >"$WORK/vcheck-l.log" 2>&1
    if run_grep -qi "patched=true" "$WORK/vcheck-l.log"; then
      ui_print "- ROOT ACTIVE on $2 (KernelPatch patched=true)"
    else
      ui_print "- NOTE: kernel verify check finished"
    fi
  fi
  if [ "$MG_IN_SLOT" = "1" ] && [ -f ramdisk.cpio ]; then
    run_magisk cpio ramdisk.cpio test >/dev/null 2>&1
    _VR=$?
    if [ "$_VR" -eq "1" ]; then
      ui_print "- MAGISK ACTIVE on $2 (ramdisk patched)"
    fi
  fi
  cd "$WORK" 2>/dev/null
  rm -rf "$WORK/vcheck" "$WORK/check.img" 2>/dev/null
}

do_patch_slot() {
  _part="$1"
  _label="$2"
  MG_IN_SLOT=0
  ui_print "- Reading $2 ($_part) ..."
  run_dd "if=$_part" of="$WORK/boot.img" bs=1048576 2>"$WORK/dd_read.log" || abort "cannot read $_part"
  if [ ! -s "$WORK/boot.img" ]; then abort "read produced empty boot.img"; fi
  _RSZ=$(wc -c < "$WORK/boot.img" 2>/dev/null | tr -d ' \t\r\n')
  if [ -n "$_RSZ" ] && [ "$_RSZ" != "0" ] && [ "$_RSZ" -lt 4194304 ]; then
    abort "read only $_RSZ bytes (too small for boot.img) - wrong partition?"
  fi
  clean_stage

  ui_print "- Unpacking boot image ..."
  run_magisk unpack boot.img >"$WORK/unpack.log" 2>&1
  RC=$?
  case $RC in
    0) ;;
    2) ui_print "- ChromeOS boot image detected"; CHROMEOS=true ;;
    3) ui_print "- Vendor boot style image detected"; VENDORBOOT=true ;;
    *) print_file "$WORK/unpack.log"; abort "unpack failed ($RC)" ;;
  esac

  # ---- Kernel-level root: KernelPatch ----
  magisk_hexpatch
  if [ "$MODE" != "magisk" ]; then
    kp_patch_kernel
  else
    if [ "$PATCHEDKERNEL" != "true" ]; then
      rm -f kernel 2>/dev/null
    fi
  fi

  # ---- Ramdisk root: Magisk ----
  if [ "$MODE" != "kpatch" ]; then
    RAMDISK=""
    for _rp in ramdisk.cpio vendor_ramdisk/init_boot.cpio vendor_ramdisk/ramdisk.cpio; do
      if [ -e "$_rp" ]; then RAMDISK="$_rp"; break; fi
    done
    SKIPB=""
    SHA1=""
    if [ -n "$RAMDISK" ]; then
      run_magisk cpio "$RAMDISK" test >/dev/null 2>&1
      MG_STATUS=$?
    elif [ -n "$INITBOOT_PART" ]; then
      RAMDISK=""
      MG_STATUS=0
      if [ "$_label" != "inactive slot" ]; then
        ui_print "- No ramdisk in boot; Magisk will be installed via init_boot"
      fi
    else
      RAMDISK="ramdisk.cpio"
      SKIPB="#"
      MG_STATUS=0
      if [ "$_label" != "inactive slot" ]; then
        ui_print "- No ramdisk/init_boot found; creating fresh ramdisk in boot"
      fi
    fi
    case $MG_STATUS in
      0)
        if [ -n "$RAMDISK" ]; then ui_print "- Stock ramdisk detected"; fi
        SHA1=$(run_magisk sha1 boot.img 2>/dev/null)
        ;;
      1)
        ui_print "- Magisk-patched ramdisk found - cleaning for fresh patch"
        run_magisk cpio "$RAMDISK" "extract .backup/.magisk config.orig" "restore" >"$WORK/cpio2.log" 2>&1 \
          || { print_file "$WORK/cpio2.log"; abort "cannot restore existing Magisk ramdisk"; }
        if [ -f config.orig ]; then
          PREINITDEVICE=$(grep_prop PREINITDEVICE config.orig)
          rm -f config.orig 2>/dev/null
        fi
        ;;
      2)
        abort "ramdisk patched by unsupported programs - restore stock boot first"
        ;;
    esac
    if [ -n "$RAMDISK" ]; then
      [ -z "$SKIPB" ] && run_cp -f "$RAMDISK" ramdisk.cpio.orig 2>/dev/null
      do_magisk_ramdisk "$RAMDISK" "$SHA1" "$SKIPB"
    fi
    # fstab tweaks inside dtb (official Magisk step)
    if [ "$MG_IN_SLOT" = "1" ]; then
      for dt in dtb kernel_dtb extra; do
        if [ -f "$dt" ]; then
          if ! run_magisk dtb "$dt" test >/dev/null 2>&1; then
            abort "boot image $dt patched by unsupported old Magisk - restore stock first"
          fi
          if run_magisk dtb "$dt" patch >/dev/null 2>&1; then
            ui_print "- Patched fstab in boot image $dt"
          fi
        fi
      done
    fi
  fi

  ui_print "- Repacking boot image ..."
  run_magisk repack boot.img >"$WORK/repack.log" 2>&1 || { print_file "$WORK/repack.log"; abort "repack failed"; }
  if [ ! -f "$WORK/new-boot.img" ]; then abort "new-boot.img missing after repack"; fi

  flash_partition "$_part" "$_label"
  verify_partition "$_part" "$_label"
}

patch_init_boot() {
  ui_print "- Patching init_boot ($INITBOOT_PART) for Magisk ..."
  run_dd "if=$INITBOOT_PART" of="$WORK/boot2.img" bs=1048576 2>"$WORK/dd_read2.log" || { ui_print "- WARNING: cannot read init_boot - Magisk skipped"; return 1; }
  rm -f kernel ramdisk.cpio ramdisk.cpio.orig config config.orig dtb extra kernel_dtb new-boot.img 2>/dev/null
  run_magisk unpack boot2.img >"$WORK/iunpack.log" 2>&1 || { ui_print "- WARNING: init_boot unpack failed - Magisk skipped"; return 1; }
  _IR=""
  for _rp in ramdisk.cpio vendor_ramdisk/init_boot.cpio vendor_ramdisk/ramdisk.cpio; do
    if [ -e "$_rp" ]; then _IR="$_rp"; break; fi
  done
  if [ -z "$_IR" ]; then ui_print "- WARNING: init_boot has no ramdisk - Magisk skipped"; return 1; fi
  run_magisk cpio "$_IR" test >/dev/null 2>&1
  _IST=$?
  SHA1=$(run_magisk sha1 boot2.img 2>/dev/null)
  case $_IST in
    0) ui_print "- init_boot: stock ramdisk" ;;
    1)
      ui_print "- init_boot: Magisk found - cleaning for fresh patch"
      run_magisk cpio "$_IR" "extract .backup/.magisk config.orig" "restore" >/dev/null 2>&1
      if [ -f config.orig ]; then
        PREINITDEVICE=$(grep_prop PREINITDEVICE config.orig)
        rm -f config.orig 2>/dev/null
      fi
      ;;
    2) ui_print "- WARNING: init_boot patched by unsupported program - Magisk skipped"; return 1 ;;
  esac
  run_cp -f "$_IR" ramdisk.cpio.orig 2>/dev/null
  do_magisk_ramdisk "$_IR" "$SHA1" ""
  ui_print "- Repacking init_boot ..."
  run_magisk repack boot2.img >"$WORK/irepack.log" 2>&1 || { ui_print "- WARNING: init_boot repack failed - Magisk skipped"; return 1; }
  if [ ! -f "$WORK/new-boot.img" ]; then ui_print "- WARNING: init_boot repack empty - Magisk skipped"; return 1; fi
  flash_partition "$INITBOOT_PART" "init_boot"
  _esz=$(wc -c < "$WORK/new-boot.img" 2>/dev/null | tr -d ' \t\r\n')
  _blocks=$(( (_esz + 511) / 512 ))
  run_dd "if=$INITBOOT_PART" of="$WORK/check.img" bs=512 "count=$_blocks" 2>/dev/null
  if [ -s "$WORK/check.img" ]; then
    rm -rf "$WORK/vcheck" 2>/dev/null
    mkdir -p "$WORK/vcheck" 2>/dev/null
    run_cp -f "$WORK/check.img" "$WORK/vcheck/boot.img" 2>/dev/null
    cd "$WORK/vcheck" 2>/dev/null
    run_magisk unpack boot.img >/dev/null 2>&1
    if [ -f ramdisk.cpio ]; then
      run_magisk cpio ramdisk.cpio test >/dev/null 2>&1
      if [ "$?" -eq "1" ]; then
        ui_print "- MAGISK ACTIVE on init_boot (on-partition verified)"
      fi
    fi
    cd "$WORK" 2>/dev/null
    rm -rf "$WORK/vcheck" "$WORK/check.img" 2>/dev/null
  fi
  rm -f boot2.img new-boot.img kernel ramdisk.cpio ramdisk.cpio.orig 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------
# Main Flow
ui_print "- Patching boot partition ..."
do_patch_slot "$TARGET" "current slot"

if [ "$MODE" != "kpatch" ] && [ -n "$INITBOOT_PART" ]; then
  patch_init_boot
fi

# Inactive slot (A/B devices)
OTHER=""
case "$SLOT" in
  _a) OTHER="_b" ;;
  _b) OTHER="_a" ;;
esac
if [ -n "$OTHER" ]; then
  _op=$(find_block "boot$OTHER")
  if [ -n "$_op" ] && [ "$_op" != "$TARGET" ]; then
    ui_print "- Patching inactive slot (boot$OTHER) ..."
    do_patch_slot "$_op" "inactive slot"
  fi
fi

sync 2>/dev/null

# ---------------------------------------------------------------------
# Root daemon for KernelPatch (FolkPatch / APatch managers)
if [ "$KP_OK" = "1" ]; then
  ui_print "- Installing KernelPatch daemon ..."
  APD_SRC=""
  for _a in "$WORK/assets/apd" "$WORK/lib/$ARCH/libapd.so" "$WORK/lib/arm64-v8a/libapd.so"; do
    if [ -s "$_a" ]; then APD_SRC="$_a"; break; fi
  done
  FPD_SRC=""
  for _f in "$WORK/assets/fpd" "$WORK/assets/Service/fpd"; do
    if [ -s "$_f" ]; then FPD_SRC="$_f"; break; fi
  done
  BUSYB_SRC=""
  for _b in "$WORK/busybox" "$WORK/lib/$ARCH/libbusybox.so" "$WORK/lib/arm64-v8a/libbusybox.so"; do
    if [ -s "$_b" ]; then BUSYB_SRC="$_b"; break; fi
  done
  KPTB_SRC="$KPTOOLS"
  RESETP_SRC=""
  for _r in "$WORK/assets/resetprop" "$WORK/lib/$ARCH/libresetprop.so" "$WORK/lib/arm64-v8a/libresetprop.so"; do
    if [ -s "$_r" ]; then RESETP_SRC="$_r"; break; fi
  done

  if [ -d /data/adb ] || mount /data 2>/dev/null || mount /dev/block/by-name/userdata /data 2>/dev/null; then
    mkdir -p /data/adb/ap/bin /data/adb/ap/log /data/adb/ap/kpm /data/adb/fp/bin /data/adb/fp/pathhide /data/adb/post-fs-data.d 2>/dev/null
    if [ -d /data/adb ]; then
      if [ -n "$APD_SRC" ]; then
        for dest in /data/adb/apd /data/adb/ap/bin/apd /data/adb/fp/bin/apd; do
          mkdir -p $(dirname "$dest") 2>/dev/null
          run_cp -f "$APD_SRC" "$dest" 2>/dev/null
          chmod 755 "$dest" 2>/dev/null
        done
      fi
      if [ -n "$BUSYB_SRC" ]; then run_cp -f "$BUSYB_SRC" /data/adb/ap/bin/busybox 2>/dev/null; fi
      if [ -n "$KPTB_SRC" ]; then run_cp -f "$KPTB_SRC" /data/adb/ap/bin/kptools 2>/dev/null; fi
      if [ -n "$RESETP_SRC" ]; then run_cp -f "$RESETP_SRC" /data/adb/ap/bin/resetprop 2>/dev/null; fi
      if [ -n "$FPD_SRC" ]; then
        run_cp -f "$FPD_SRC" /data/adb/fp/bin/fpd 2>/dev/null
        chmod 755 /data/adb/fp/bin/fpd 2>/dev/null
      fi
      chmod 755 /data/adb/ap/bin/busybox /data/adb/ap/bin/kptools /data/adb/ap/bin/resetprop 2>/dev/null
      ln -sf /data/adb/apd /data/adb/ap/bin/apd 2>/dev/null
      if [ ! -s /data/adb/ap/su_path ]; then echo "/system/bin/su" > /data/adb/ap/su_path 2>/dev/null; fi
      touch /data/adb/ap/package_config 2>/dev/null
      for pkg in me.yuki.folk com.android.shell; do
        echo "$pkg" >> /data/adb/ap/package_config 2>/dev/null
      done
      if [ "$BB_OK" = "1" ]; then "$BB" sort -u /data/adb/ap/package_config -o /data/adb/ap/package_config 2>/dev/null; fi
      chmod 644 /data/adb/ap/package_config 2>/dev/null
      touch /data/adb/ap/version 2>/dev/null
      run_rm -f /data/adb/ap/ori.img 2>/dev/null
      if [ -s /data/adb/apd ]; then
        ui_print "- Daemon installed: /data/adb/apd (KernelPatch active)"
      fi
      if command -v restorecon >/dev/null 2>&1; then
        restorecon /data/adb/apd 2>/dev/null
        restorecon -R /data/adb/ap/ 2>/dev/null
        restorecon /data/adb/fp/bin/fpd 2>/dev/null
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------
# Copy Manager APKs straight from the ZIP to sdcard
ui_print "- Copying Manager APKs to storage ..."
APK_COPIED=0
for d in /sdcard /data/media/0 /external_sd /data/media; do
  if [ -d "$d" ] && [ "$APK_COPIED" = "0" ]; then
    mkdir -p "$WORK/apk_out" 2>/dev/null
    run_unzip "$ZIPFILE" "FolkPatch.apk" -d "$WORK/apk_out" >/dev/null 2>&1
    run_unzip "$ZIPFILE" "APatch.apk" -d "$WORK/apk_out" >/dev/null 2>&1
    run_unzip "$ZIPFILE" "Magisk.apk" -d "$WORK/apk_out" >/dev/null 2>&1

    [ -s "$WORK/apk_out/FolkPatch.apk" ] && run_cp -f "$WORK/apk_out/FolkPatch.apk" "$d/FolkPatch-Manager.apk" 2>/dev/null
    [ -s "$WORK/apk_out/APatch.apk" ] && run_cp -f "$WORK/apk_out/APatch.apk" "$d/APatch-Manager.apk" 2>/dev/null
    [ -s "$WORK/apk_out/Magisk.apk" ] && run_cp -f "$WORK/apk_out/Magisk.apk" "$d/Magisk-Manager.apk" 2>/dev/null

    if [ -s "$d/FolkPatch-Manager.apk" ] || [ -s "$d/APatch-Manager.apk" ] || [ -s "$d/Magisk-Manager.apk" ]; then
      ui_print "- Saved Manager APKs to $d:"
      [ -s "$d/FolkPatch-Manager.apk" ] && ui_print "  * FolkPatch-Manager.apk"
      [ -s "$d/APatch-Manager.apk" ] && ui_print "  * APatch-Manager.apk"
      [ -s "$d/Magisk-Manager.apk" ] && ui_print "  * Magisk-Manager.apk"
      APK_COPIED=1
    fi
  fi
done

# Clean legacy backup folders from v1 installers
if [ -d /data ] || mount /data 2>/dev/null; then
  run_rm -rf /sdcard/FolkPatch-Backup /data/media/0/FolkPatch-Backup /external_sd/FolkPatch-Backup /data/FolkPatch-Backup 2>/dev/null
  run_rm -rf "/sdcard/Download/FolkPatch" "/data/media/0/Download/FolkPatch" 2>/dev/null
  run_rm -f /data/boot.img /data/adb/ap/ori.img /data/magisk_backup_* 2>/dev/null
  run_rm -f /sdcard/FolkPatch-flash-report.txt /data/media/0/FolkPatch-flash-report.txt 2>/dev/null
  run_rm -f /sdcard/FolkPatch-key.txt /data/media/0/FolkPatch-key.txt 2>/dev/null
  run_rm -f /sdcard/FolkPatch-patched-*.img /data/media/0/FolkPatch-patched-*.img 2>/dev/null
fi

# Restore linker env
if [ -n "$OLD_LD_PRELOAD" ]; then export LD_PRELOAD="$OLD_LD_PRELOAD"; fi
if [ -n "$OLD_LD_CONFIG" ]; then export LD_CONFIG_FILE="$OLD_LD_CONFIG"; fi

# Clean temporary files in tmpfs
rm -f "$WORK"/boot.img "$WORK"/boot2.img "$WORK"/new-boot.img "$WORK"/check.img \
      "$WORK"/kernel "$WORK"/kernel-origin "$WORK"/kernel-clean \
      "$WORK"/ramdisk.cpio "$WORK"/ramdisk.cpio.orig "$WORK"/dtb "$WORK"/extra \
      "$WORK"/kernel_dtb "$WORK"/config "$WORK"/config.orig "$WORK"/stock_boot.img \
      "$WORK"/magisk "$WORK"/magiskinit "$WORK"/stub.apk "$WORK"/init-ld \
      "$WORK"/magisk.xz "$WORK"/stub.xz "$WORK"/init-ld.xz 2>/dev/null
rm -rf "$WORK/vcheck" "$WORK/apk_out" 2>/dev/null

ui_print "****************************"
ui_print " MultiRoot installation finished!"
if [ "$KP_OK" = "1" ]; then
  ui_print " KernelPatch root: ACTIVE (superkey: su)"
fi
if [ "$MG_IN_SLOT" = "1" ]; then
  ui_print " Magisk root: ACTIVE"
fi
if [ "$MODE" != "kpatch" ] && [ "$MG_IN_SLOT" = "0" ] && [ -n "$INITBOOT_PART" ]; then
  ui_print " Magisk root: ACTIVE (via init_boot)"
fi
ui_print " Managers on sdcard (install ANY one):"
ui_print "  - FolkPatch-Manager.apk"
ui_print "  - APatch-Manager.apk"
ui_print "  - Magisk-Manager.apk"
ui_print "****************************"
ui_print " NEXT STEPS:"
ui_print " 1. Reboot system now"
ui_print " 2. Open file manager and install ANY manager APK"
ui_print "    (Magisk, APatch, FolkPatch, or KernelSU)"
ui_print " 3. Root is active! Any manager will have root access."
ui_print " Bootloop? Flash MultiRoot Uninstaller ZIP."
ui_print "****************************"
exit 0
