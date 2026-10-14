#!/bin/sh
# =====================================================================
# MultiRoot direct-flash installer (POSIX sh, recovery compatible).
# One flash, any root manager:
#   - KernelPatch root (kpimg 0.13.8) -> FolkPatch / APatch managers
#   - Magisk 30.6 ramdisk root        -> Magisk manager
# Modes: create /sdcard/root-mode.txt with one word before flashing:
#   all    (default) = KernelPatch + Magisk
#   kpatch           = KernelPatch only (FolkPatch / APatch managers)
#   magisk           = Magisk only (Magisk manager)
# NO backup files are created anywhere: read boot -> patch in tmpfs ->
# flash -> verify readback -> delete every temp file. Direct flash only.
# No bashisms: no 'function', no '[[', no '=='.
# Env from update-binary: BBBIN, INSTALLER. Args: $1 api, $2 fd, $3 zip.
# =====================================================================
OUTFD="$2"
ZIPFILE="$3"
BB="$BBBIN"
if [ -z "$BB" ]; then BB="busybox"; fi
WORK="$INSTALLER"
if [ -z "$WORK" ]; then WORK="/dev/tmp/multiroot"; fi
KP_VER="0.13.8"
MAGISK_VER="30.6"
INST_VER="2.0"

KPTOOLS=""
for k in "$WORK/lib/arm64-v8a/libkptools.so" "$WORK/kptools" "$WORK/assets/kptools"; do
  if [ -f "$k" ]; then
    chmod 755 "$k" 2>/dev/null
    KPTOOLS="$k"
    break
  fi
done
KPIMG="$WORK/assets/kpimg"
MAGDIR="$WORK/assets/magisk"
MAGISKBOOT="$MAGDIR/magiskboot"

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

# Bionic binaries (kptools / magiskboot) need the real Android linker +
# libc from the actual system. Recovery /system is a stub; mount the real
# system + APEX runtime first, then run the tools, restore afterwards.
# Universal: slot-aware system lookup, vendor fallback, flattened APEX so
# non-A/B, A/B, Virtual-A/B and dynamic-partition recoveries all work.
if [ -f /system_root/system/build.prop ] || [ -f /system_root/build.prop ]; then
  SYS_OK=1
else
  mkdir -p /system_root 2>/dev/null
  for _p in /dev/block/bootdevice/by-name/system"$SLOT" /dev/block/by-name/system"$SLOT" \
             /dev/block/bootdevice/by-name/system /dev/block/by-name/system \
             /dev/block/bootdevice/by-name/system_a /dev/block/by-name/system_a \
             /dev/block/mapper/system"$SLOT" /dev/block/mapper/system; do
    if [ -e "$_p" ]; then
      mount -o ro "$_p" /system_root 2>/dev/null
      if [ -f /system_root/system/build.prop ] || [ -f /system_root/build.prop ]; then SYS_OK=1; break; fi
      if [ -d /system_root/system ] || [ -d /system_root/bin ]; then SYS_OK=1; break; fi
    fi
  done
fi
SYSROOT=""
if [ -f /system_root/system/build.prop ]; then SYSROOT="/system_root/system"; else SYSROOT="/system_root"; fi
mkdir -p /vendor_lib 2>/dev/null
for _v in /dev/block/bootdevice/by-name/vendor"$SLOT" /dev/block/by-name/vendor \
           /dev/block/mapper/vendor"$SLOT" /dev/block/mapper/vendor; do
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
if [ ! -x /system/bin/linker64 ]; then
  mount -o bind "$SYSROOT" /system 2>/dev/null
fi
if [ ! -x /system/bin/linker64 ] && [ -f "$SYSROOT/bin/linker64" ]; then
  mkdir -p /system/bin 2>/dev/null
  rm -f /system/bin/linker64 2>/dev/null
  cp -f "$SYSROOT/bin/linker64" /system/bin/linker64 2>/dev/null
  chmod 755 /system/bin/linker64 2>/dev/null
fi
LD_DIRS="/apex/com.android.runtime/lib64/bionic:/apex/com.android.runtime/lib64:/system/lib64:$SYSROOT/lib64:/system_root/system/lib64:/vendor/lib64:/vendor_lib/lib64:/vendor_lib/system/lib64"
if [ -n "$LD_LIBRARY_PATH" ]; then LD_DIRS="$LD_DIRS:$LD_LIBRARY_PATH"; fi
if [ ! -x /system/bin/linker64 ]; then ui_print "- WARNING: linker64 not found - patch tools may fail"; fi

kp_run() {
  LD_LIBRARY_PATH="$LD_DIRS" "$KPTOOLS" "$@"
  _rc=$?
  if [ $_rc -eq 127 ]; then
    ui_print "- ERROR: kptools missing libraries (RC 127)"
  fi
  return $_rc
}
magisk_run() {
  LD_LIBRARY_PATH="$LD_DIRS" "$MAGISKBOOT" "$@"
}

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

ui_print "****************************"
ui_print " MultiRoot Recovery Installer"
ui_print " v$INST_VER: KernelPatch $KP_VER + Magisk $MAGISK_VER"
ui_print " One flash - any root manager"
ui_print " No backup files - direct flash"
ui_print "****************************"

ABI=""
if command -v getprop >/dev/null 2>&1; then
  ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
fi
case "$ABI" in
  *arm64*)
    ui_print "- CPU: $ABI"
    ;;
  *)
    if [ -n "$ABI" ]; then ui_print "- WARNING: CPU reports $ABI (requires ARM64)"; fi
    ;;
esac

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

# Detect A/B slot: cmdline -> bootconfig -> getprop -> fstab/mount ->
# hidden-A/B probe.
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
    ui_print "- A/B slot from recovery config: $SLOT (both slots will be patched)"
  elif find_block "boot_a" >/dev/null 2>&1 || find_block "boot_b" >/dev/null 2>&1; then
    SLOT="_a"
    ui_print "- A/B slot hidden by recovery; defaulting to _a (both slots will be patched)"
  fi
fi
if [ -n "$SLOT" ]; then
  ui_print "- A/B slot: $SLOT"
else
  ui_print "- Slot: A-only"
fi

# Kernel ALWAYS lives in boot (official rule). init_boot holds the GKI
# ramdisk on Android 13+ and is only used for the Magisk part when boot
# has no ramdisk. vendor_boot is never touched.
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
  all)    ui_print "- Mode: ALL (KernelPatch + Magisk - every manager works)" ;;
  kpatch) ui_print "- Mode: KPATCH (FolkPatch / APatch managers only)" ;;
  magisk) ui_print "- Mode: MAGISK (Magisk manager only)" ;;
esac

# Tool validation depends on the selected mode.
if [ "$MODE" != "magisk" ]; then
  if [ -z "$KPTOOLS" ]; then abort "kptools missing"; fi
  chmod 755 "$KPTOOLS" 2>/dev/null
  if [ "$BB_OK" = "1" ]; then "$BB" chmod 755 "$KPTOOLS" 2>/dev/null; fi
  if [ ! -x "$KPTOOLS" ]; then
    if [ -f "$KPTOOLS" ]; then
      ui_print "- WARNING: exec bit not sticking, trying anyway"
    else
      abort "kptools missing"
    fi
  fi
  if [ ! -f "$KPIMG" ]; then abort "kpimg missing"; fi
fi
if [ "$MODE" != "kpatch" ]; then
  if [ ! -f "$MAGISKBOOT" ]; then abort "magiskboot missing in ZIP (assets/magisk/)"; fi
  chmod 755 "$MAGISKBOOT" 2>/dev/null
fi

# Battery warning
_BAT=""
for _b in /sys/class/power_supply/battery/capacity /sys/class/power_supply/Battery/capacity; do
  if [ -f "$_b" ]; then _BAT=$(cat "$_b" 2>/dev/null | tr -d ' \t\r\n'); break; fi
done
case "$_BAT" in
  ''|*[!0-9]*) ;;
  *) if [ "$_BAT" -lt 25 ]; then ui_print "- WARNING: battery ${_BAT}% - charge above 50% first!"; fi ;;
esac

# init_boot (only used for Magisk when boot itself has no ramdisk)
INITBOOT_PART=""
if [ "$MODE" != "kpatch" ]; then
  INITBOOT_PART=$(find_part init_boot 2>/dev/null)
fi

# ---------------------------------------------------------------------
# State flags shared by the patch pipeline
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
  run_cp -f "$MAGDIR/magiskinit" magiskinit || abort "magiskinit missing in ZIP"
  run_cp -f "$MAGDIR/magisk" magisk || abort "magisk binary missing in ZIP"
  run_cp -f "$MAGDIR/stub.apk" stub.apk || abort "stub.apk missing in ZIP"
  run_cp -f "$MAGDIR/init-ld" init-ld || abort "init-ld missing in ZIP"
}

# Samsung kernel protections (official Magisk hexpatches). Patterns only
# match on Samsung kernels - harmless everywhere else. They also unblock
# KernelPatch on Samsung (RKP/DEFEX block patched kernels).
magisk_hexpatch() {
  PATCHEDKERNEL=false
  if [ ! -f kernel ] || [ ! -f "$MAGISKBOOT" ]; then return 0; fi
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
  if [ ! -f kernel ]; then abort "no kernel inside boot image - KernelPatch impossible"; fi
  if ! kp_run -i kernel -f 2>/dev/null | run_grep -q "CONFIG_KALLSYMS=y"; then
    abort "kernel requires CONFIG_KALLSYMS=y (not enabled on this device)"
  fi
  ui_print "- Kernel: CONFIG_KALLSYMS=y OK"
  if kp_run -i kernel -l 2>/dev/null | run_grep -qi "patched=true"; then
    ui_print "- NOTE: kernel already KernelPatch-ed"
  fi
  run_mv kernel kernel-origin || abort "cannot stage kernel"
  # Clean any previous KP patch first so the kernel is patched exactly once.
  kp_run -i kernel-origin -l > "$WORK/vorig.log" 2>&1
  if run_grep -qi "patched=true" "$WORK/vorig.log"; then
    ui_print "- Cleaning existing patch for fresh root ..."
    kp_run -u -i kernel-origin -o kernel-clean >/dev/null 2>&1
    if [ -s kernel-clean ]; then
      run_mv -f kernel-clean kernel-origin
      ui_print "- Kernel cleaned successfully"
    else
      ui_print "- WARNING: could not clean existing patch, continuing anyway"
    fi
  fi
  ui_print "- Patching kernel with KernelPatch (superkey: su) ..."
  kp_run -p -i kernel-origin -k "$KPIMG" -s "su" -o kernel >"$WORK/patch.log" 2>&1
  RC=$?
  if [ "$RC" -ne 0 ]; then
    print_file "$WORK/patch.log"
    abort "KernelPatch patch failed ($RC)"
  fi
  kp_run -i kernel -l >"$WORK/verify.log" 2>&1
  if run_grep -qi "patched=false" "$WORK/verify.log"; then
    abort "KernelPatch verification failed (kernel still reports patched=false)"
  fi
  ui_print "- KernelPatch OK (patched=true)"
  _VL=$(run_grep -i "^superkey=" "$WORK/verify.log" 2>/dev/null | head -n 1)
  case "$_VL" in
    superkey=su*) ui_print "- Superkey OK: su" ;;
    "") ui_print "- NOTE: no superkey line in verify output" ;;
    *) abort "superkey mismatch ($_VL) - root would NOT work" ;;
  esac
  KP_OK=1
}

do_magisk_ramdisk() {
  # $1 = ramdisk path, $2 = SHA1 (may be empty), $3 = skip-backup ("#" or "")
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
  # The in-image .backup (inside the cpio) is the ONLY "backup" that exists:
  # it lives inside boot.img itself and powers backup-free uninstall later.
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
    abort "cannot read back $_part - flash may have failed!"
  fi
  rm -rf "$WORK/vcheck" 2>/dev/null
  mkdir -p "$WORK/vcheck" 2>/dev/null
  run_cp -f "$WORK/check.img" "$WORK/vcheck/boot.img" 2>/dev/null
  cd "$WORK/vcheck" 2>/dev/null
  run_magisk unpack boot.img >/dev/null 2>&1
  if [ "$KP_OK" = "1" ] && [ -f kernel ]; then
    kp_run -i kernel -l >"$WORK/vcheck-l.log" 2>&1
    if run_grep -qi "patched=false" "$WORK/vcheck-l.log"; then
      cd "$WORK" 2>/dev/null
      abort "partition holds UNPATCHED kernel! Flash failed on $_part."
    fi
    ui_print "- ROOT ACTIVE on $2 (on-partition: KernelPatch patched=true)"
  fi
  if [ "$MG_IN_SLOT" = "1" ] && [ -f ramdisk.cpio ]; then
    run_magisk cpio ramdisk.cpio test >/dev/null 2>&1
    _VR=$?
    if [ "$_VR" -eq "1" ]; then
      ui_print "- MAGISK ACTIVE on $2 (on-partition: ramdisk patched)"
    else
      cd "$WORK" 2>/dev/null
      abort "partition ramdisk is NOT Magisk-patched! Flash failed on $_part."
    fi
  fi
  cd "$WORK" 2>/dev/null
  rm -rf "$WORK/vcheck" "$WORK/check.img" 2>/dev/null
}

do_patch_slot() {
  # $1 = partition device, $2 = label
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

  # ---- Kernel-level root: KernelPatch (FolkPatch / APatch managers) ----
  magisk_hexpatch
  if [ "$MODE" != "magisk" ]; then
    kp_patch_kernel
  else
    if [ "$PATCHEDKERNEL" != "true" ]; then
      rm -f kernel 2>/dev/null
    fi
  fi

  # ---- Ramdisk root: Magisk (Magisk manager) ----
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
      # Android 13+ GKI: ramdisk lives in init_boot, patched separately.
      RAMDISK=""
      MG_STATUS=0
      if [ "$_label" != "inactive slot" ]; then
        ui_print "- No ramdisk in boot; Magisk will be installed via init_boot"
      fi
    else
      # Legacy SAR / rare GKI: create a fresh ramdisk inside boot.
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
  # Magisk-only path for Android 13+ GKI devices (ramdisk in init_boot).
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
      else
        cd "$WORK" 2>/dev/null
        abort "init_boot ramdisk NOT patched - flash failed!"
      fi
    fi
    cd "$WORK" 2>/dev/null
    rm -rf "$WORK/vcheck" "$WORK/check.img" 2>/dev/null
  fi
  rm -f boot2.img new-boot.img kernel ramdisk.cpio ramdisk.cpio.orig 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------
# Main flow
ui_print "- Patching current slot ..."
do_patch_slot "$TARGET" "current slot"

# Magisk via init_boot when the boot image has no ramdisk (Android 13+ GKI)
if [ "$MODE" != "kpatch" ] && [ -n "$INITBOOT_PART" ]; then
  patch_init_boot
fi

# Inactive slot (A/B devices): patch with the same pipeline
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
    if [ "$MODE" != "kpatch" ] && [ "$MG_IN_SLOT" = "0" ] && [ -n "$INITBOOT_PART" ]; then
      ui_print "- NOTE: inactive slot got KernelPatch only"
      ui_print "-       (its Magisk ramdisk lives in init_boot)"
    fi
  fi
fi

sync 2>/dev/null

# ---------------------------------------------------------------------
# Root daemon (KernelPatch apd) for instant FolkPatch / APatch root
if [ "$MODE" != "magisk" ]; then
  ui_print "- Installing KernelPatch daemon ..."
  APD_SRC=""
  for _a in "$WORK/assets/apd" "$WORK/lib/arm64-v8a/libapd.so"; do
    if [ -s "$_a" ]; then APD_SRC="$_a"; break; fi
  done
  FPD_SRC=""
  for _f in "$WORK/assets/fpd" "$WORK/assets/Service/fpd"; do
    if [ -s "$_f" ]; then FPD_SRC="$_f"; break; fi
  done
  BUSYB_SRC=""
  for _b in "$WORK/busybox" "$WORK/lib/arm64-v8a/libbusybox.so"; do
    if [ -s "$_b" ]; then BUSYB_SRC="$_b"; break; fi
  done
  KPTB_SRC="$KPTOOLS"
  RESETP_SRC=""
  for _r in "$WORK/assets/resetprop" "$WORK/lib/arm64-v8a/libresetprop.so"; do
    if [ -s "$_r" ]; then RESETP_SRC="$_r"; break; fi
  done
  if [ -d /data/adb ] || mount /data 2>/dev/null || mount /dev/block/by-name/userdata /data 2>/dev/null; then
    mkdir -p /data/adb/ap/bin /data/adb/ap/log /data/adb/ap/kpm /data/adb/fp/bin /data/adb/fp/pathhide /data/adb/post-fs-data.d 2>/dev/null
    DAEMON_OK=0
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
        if [ "$BB_OK" = "1" ]; then "$BB" chmod 755 /data/adb/fp/bin/fpd 2>/dev/null; fi
      fi
      chmod 755 /data/adb/ap/bin/busybox /data/adb/ap/bin/kptools /data/adb/ap/bin/resetprop 2>/dev/null
      ln -sf /data/adb/apd /data/adb/ap/bin/apd 2>/dev/null
      # su_path: app writes LEGACY path (/system/bin/su) when empty; do the same.
      if [ ! -s /data/adb/ap/su_path ]; then echo "/system/bin/su" > /data/adb/ap/su_path 2>/dev/null; fi
      # Pre-authorize the official Manager package (me.yuki.folk) + shell.
      touch /data/adb/ap/package_config 2>/dev/null
      for pkg in me.yuki.folk com.android.shell; do
        echo "$pkg" >> /data/adb/ap/package_config 2>/dev/null
      done
      if [ "$BB_OK" = "1" ]; then "$BB" sort -u /data/adb/ap/package_config -o /data/adb/ap/package_config 2>/dev/null; fi
      chmod 644 /data/adb/ap/package_config 2>/dev/null
      touch /data/adb/ap/version 2>/dev/null
      # NO backup images are stored (no ori.img) - policy: zero backup files.
      run_rm -f /data/adb/ap/ori.img 2>/dev/null
      if [ -s /data/adb/apd ]; then
        DAEMON_OK=1
        ui_print "- Daemon installed: /data/adb/apd (INSTANT ROOT on reboot)"
      else
        ui_print "- WARNING: /data not writable (encrypted?) - daemon skipped"
        ui_print "- Kernel is patched; open the Manager APK after reboot"
      fi
      if command -v restorecon >/dev/null 2>&1; then
        restorecon /data/adb/apd 2>/dev/null
        restorecon -R /data/adb/ap/ 2>/dev/null
        restorecon /data/adb/fp/bin/fpd 2>/dev/null
      fi
    fi
  else
    ui_print "- WARNING: /data not mounted - daemon skipped"
    ui_print "- Kernel is patched; open the Manager APK after reboot"
  fi
fi

# ---------------------------------------------------------------------
# Manager APKs straight from the ZIP to sdcard (apps to install, NOT backups)
ui_print "- Copying Manager APKs to sdcard ..."
APK_COPIED=0
for d in /sdcard /data/media/0 /external_sd; do
  if [ -d "$d" ] && [ "$APK_COPIED" = "0" ]; then
    mkdir -p "$WORK/apk_out" 2>/dev/null
    run_unzip "$ZIPFILE" "FolkPatch.apk" -d "$WORK/apk_out" >/dev/null 2>&1
    run_unzip "$ZIPFILE" "APatch.apk" -d "$WORK/apk_out" >/dev/null 2>&1
    if [ -s "$WORK/apk_out/FolkPatch.apk" ] && [ -s "$WORK/apk_out/APatch.apk" ]; then
      run_cp -f "$WORK/apk_out/FolkPatch.apk" "$d/FolkPatch-Manager.apk" 2>/dev/null
      run_cp -f "$WORK/apk_out/APatch.apk" "$d/APatch-Manager.apk" 2>/dev/null
      if [ -s "$d/FolkPatch-Manager.apk" ] && [ -s "$d/APatch-Manager.apk" ]; then
        ui_print "- Saved: FolkPatch-Manager.apk + APatch-Manager.apk"
        APK_COPIED=1
      fi
    fi
  fi
done
if [ "$APK_COPIED" = "0" ]; then
  ui_print "- WARNING: could not copy Manager APKs (sdcard busy?)"
fi

# Remove stale backup folders/files from older installer versions
# (policy: this project creates and keeps NO backup files anywhere).
if [ -d /data ] || mount /data 2>/dev/null; then
  run_rm -rf /sdcard/FolkPatch-Backup /data/media/0/FolkPatch-Backup /external_sd/FolkPatch-Backup /data/FolkPatch-Backup 2>/dev/null
  run_rm -rf "/sdcard/Download/FolkPatch" "/data/media/0/Download/FolkPatch" 2>/dev/null
  run_rm -f /data/boot.img /data/adb/ap/ori.img /data/magisk_backup_* 2>/dev/null
  run_rm -f /sdcard/FolkPatch-flash-report.txt /data/media/0/FolkPatch-flash-report.txt 2>/dev/null
  run_rm -f /sdcard/FolkPatch-key.txt /data/media/0/FolkPatch-key.txt 2>/dev/null
  run_rm -f /sdcard/FolkPatch-patched-*.img /data/media/0/FolkPatch-patched-*.img 2>/dev/null
fi

# ---------------------------------------------------------------------
# Restore linker env
if [ -n "$OLD_LD_PRELOAD" ]; then export LD_PRELOAD="$OLD_LD_PRELOAD"; fi
if [ -n "$OLD_LD_CONFIG" ]; then export LD_CONFIG_FILE="$OLD_LD_CONFIG"; fi

# Clean every temp image/payload file (tmpfs self-cleans on reboot too)
rm -f "$WORK"/boot.img "$WORK"/boot2.img "$WORK"/new-boot.img "$WORK"/check.img \
      "$WORK"/kernel "$WORK"/kernel-origin "$WORK"/kernel-clean \
      "$WORK"/ramdisk.cpio "$WORK"/ramdisk.cpio.orig "$WORK"/dtb "$WORK"/extra \
      "$WORK"/kernel_dtb "$WORK"/config "$WORK"/config.orig "$WORK"/stock_boot.img \
      "$WORK"/magisk "$WORK"/magiskinit "$WORK"/stub.apk "$WORK"/init-ld \
      "$WORK"/magisk.xz "$WORK"/stub.xz "$WORK"/init-ld.xz 2>/dev/null
rm -rf "$WORK/vcheck" "$WORK/apk_out" 2>/dev/null

ui_print "****************************"
ui_print " MultiRoot installed! v$INST_VER"
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
ui_print "  - Magisk app v$MAGISK_VER+ (GitHub/Play)"
ui_print " NO backup files were created."
ui_print "****************************"
ui_print " NEXT STEPS:"
ui_print " 1. Reboot device"
ui_print " 2. Install any ONE manager app from sdcard"
ui_print "    (FolkPatch / APatch) or Magisk app"
ui_print " 3. Open it - it should show Installed/Active"
ui_print " 4. Grant Superuser per app when asked"
ui_print " Bootloop? Flash the MultiRoot Uninstaller ZIP."
ui_print "****************************"
exit 0
