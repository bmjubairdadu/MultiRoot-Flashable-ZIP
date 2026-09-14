#!/bin/sh
# FolkPatch direct-flash installer (POSIX sh, recovery compatible).
# No bashisms: no 'function', no '[[', no '=='.
# Env from update-binary: BBBIN, INSTALLER. Args: $1 api, $2 fd, $3 zip.
OUTFD="$2"
ZIPFILE="$3"
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

# kptools needs Android linker + bionic libs from the real system.
# Recovery /system is a stub; mount real system + APEX, then run kptools directly.
# Universal: slot-aware system lookup (current SLOT first), vendor fallback,
# and apexd-style flattened APEX search so non-A/B, A/B, Virtual-A/B and
# dynamic-partition recoveries all resolve linker64.
SYS_OK=0
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
      # super-partition devices: system may be a logical volume listing only
      if [ -d /system_root/system ] || [ -d /system_root/bin ]; then SYS_OK=1; break; fi
    fi
  done
fi
SYSROOT=""
if [ -f /system_root/system/build.prop ]; then SYSROOT="/system_root/system"; else SYSROOT="/system_root"; fi
# Vendor libs (some kptools builds need them); mount read-only, best effort.
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
# Flattened APEX fallback (Android 10+ may ship deapexer-style dirs).
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
if [ ! -x /system/bin/linker64 ]; then ui_print "- WARNING: linker64 not found - kptools may fail"; fi
# Late fallback: if kptools still cannot run (RC 127), retry after bind-mounting
# vendor libs into /system/lib64 view.
KP_NEEDS_VENDOR_FALLBACK=0

kp_run() {
  LD_LIBRARY_PATH="$LD_DIRS" "$KPTOOLS" "$@"
  _rc=$?
  if [ $_rc -eq 127 ]; then
    ui_print "- ERROR: kptools missing libraries (RC 127)"
    ui_print "- Try mounting /system and /vendor manually"
  fi
  return $_rc
}
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

# Gzip fallback (kptools repack shells out to it)
if ! command -v gzip >/dev/null 2>&1; then
  if [ "$BB_OK" = "1" ] && "$BB" gzip --help >/dev/null 2>&1; then
    mkdir -p "$WORK/bin" 2>/dev/null
    ln -sf "$BB" "$WORK/bin/gzip" 2>/dev/null
    PATH="$WORK/bin:$PATH"
  else
    ui_print "- WARNING: gzip missing, repack may fail"
  fi
fi

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

ui_print "****************************"
ui_print " FolkPatch Recovery Installer"
ui_print " v1.0 / KP-0.13.8"
ui_print " Universal boot-only patcher"
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
# (defined BEFORE first use: hidden-slot detection below calls find_block)
find_block() {
  _b="$1"
  for p in "/dev/block/by-name/$_b" "/dev/block/bootdevice/by-name/$_b"; do
    if [ -e "$p" ]; then echo "$p"; return 0; fi
  done
  for _m in /dev/block/platform/*/by-name/"$_b" /dev/block/platform/*/*/by-name/"$_b"; do
    if [ -e "$_m" ]; then echo "$_m"; return 0; fi
  done
  # mapper/super devices (dynamic partitions): boot is real, but keep generic.
  for _dm in /dev/block/mapper/"$_b"; do
    if [ -e "$_dm" ]; then echo "$_dm"; return 0; fi
  done
  _dev=$(find /dev/block -iname "$_b" 2>/dev/null | head -n 1)
  if [ -n "$_dev" ]; then echo "$_dev"; return 0; fi
  # sysfs uevent fallback (official util_functions.sh rule): match PARTNAME.
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

# Detect A/B slot: cmdline -> bootconfig (newer devices) -> getprop ->
# fstab/mount (active-slot symlinks) -> hidden-A/B probe.
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

# Detect hidden A/B (some recoveries like OrangeFox hide the slot).
# Prefer the ACTIVE slot from recovery fstab/mounts; else probe partitions.
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

# Official rule: kernel ALWAYS lives in boot (old and new devices).
# init_boot / vendor_boot hold ramdisk only — flashing them = no root.
# Boot-only target: never touch init_boot / vendor_boot.
TARGET=""
TARGET_KIND="boot"
for _n in boot kern-a android_boot kernel bootimg lnx; do
  T=$(find_part "$_n")
  if [ -n "$T" ]; then
    TARGET="$T"
    TARGET_KIND="boot"
    break
  fi
done
if [ -n "$TARGET" ]; then
  ui_print "- Target: $TARGET_KIND ($TARGET)"
else
  ui_print "- Available partitions:"
  ls /dev/block/by-name 2>/dev/null | while IFS= read -r _p || [ -n "$_p" ]; do ui_print "  $_p"; done
  abort "No boot partition found. Use Boot-Patcher ZIP + fastboot instead."
fi

# Superkey = fixed default "su" (same as the DOCUMENTED manual method:
#   kptools -p --image kernel --skey "su" --kpimg kpimg-android --out kernel
# and the app itself: APApplication.superKey = "su", doPatch default "su").
# Why NOT keyless: with no -s/-S, kptools stores nothing; at boot the kernel
# generates a RANDOM superkey (predata.c) that the app can never guess, so
# every supercall returns -EPERM and the app shows "not installed".
# Why NOT custom (-S ApXXX): the app sends "su", hash mismatches the baked
# key -> same -EPERM. Plaintext "su" matches on first compare. No key file:
# the key is a constant, nothing to save or reuse.
ui_print "- Auth mode: default superkey 'su' (no key entry needed)"

# Backup directory
BKDIR=""
for d in /sdcard/FolkPatch-Backup /data/media/0/FolkPatch-Backup /external_sd/FolkPatch-Backup; do
  if mkdir -p "$d" 2>/dev/null; then
    if [ -d "$d" ]; then BKDIR="$d"; break; fi
  fi
done
if [ -z "$BKDIR" ]; then
  BKDIR="$WORK/backup"
  mkdir -p "$BKDIR" 2>/dev/null
fi
ui_print "- Backup dir: $BKDIR"

# Battery warning
_BAT=""
for _b in /sys/class/power_supply/battery/capacity /sys/class/power_supply/Battery/capacity; do
  if [ -f "$_b" ]; then _BAT=$(cat "$_b" 2>/dev/null | tr -d ' \t\r\n'); break; fi
done
case "$_BAT" in
  ''|*[!0-9]*) ;;
  *) if [ "$_BAT" -lt 25 ]; then ui_print "- WARNING: battery ${_BAT}% - charge above 50% before flashing!"; fi ;;
esac

# Try to use stock backup if available for a clean patch
CLEAN_SOURCE=0
if [ -s "$BKDIR/stock-$TARGET_KIND$SLOT.img" ]; then
  ui_print "- Using existing stock backup for clean patch"
  run_cp -f "$BKDIR/stock-$TARGET_KIND$SLOT.img" "$WORK/boot.img" 2>/dev/null && CLEAN_SOURCE=1
fi

if [ "$CLEAN_SOURCE" = "0" ]; then
  ui_print "- Reading boot partition ..."
  run_dd "if=$TARGET" of="$WORK/boot.img" bs=1048576 2>"$WORK/dd_read.log" || abort "cannot read $TARGET"
fi
if [ ! -s "$WORK/boot.img" ]; then abort "read produced empty boot.img"; fi
_RSZ=$(wc -c < "$WORK/boot.img" 2>/dev/null | tr -d ' \t\r\n')
if [ -n "$_RSZ" ] && [ "$_RSZ" != "0" ] && [ "$_RSZ" -lt 4194304 ]; then
  abort "read only $_RSZ bytes (too small for boot.img) - wrong partition?"
fi

# Unpack
ui_print "- Unpacking boot image ..."
kp_run unpack boot.img >"$WORK/unpack.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  print_file "$WORK/unpack.log"
  abort "unpack failed ($RC)"
fi
if [ ! -f kernel ]; then abort "unpack produced no kernel file"; fi

# Kernel checks
if ! kp_run -i kernel -f 2>/dev/null | run_grep -q "CONFIG_KALLSYMS=y"; then
  abort "kernel requires CONFIG_KALLSYMS=y (not enabled on this device)"
fi
ui_print "- Kernel: CONFIG_KALLSYMS=y OK"
if kp_run -i kernel -l 2>/dev/null | run_grep -qi "patched=true"; then
  ui_print "- NOTE: kernel already patched; re-patching with same key"
fi

# Save stock backup
if [ -s "$BKDIR/stock-$TARGET_KIND$SLOT.img" ]; then
  ui_print "- Keeping existing stock backup"
else
  run_cp -f "$WORK/boot.img" "$BKDIR/stock-$TARGET_KIND$SLOT.img" 2>/dev/null
fi
mkdir -p /data/FolkPatch-Backup 2>/dev/null
if [ ! -s "/data/FolkPatch-Backup/stock-$TARGET_KIND$SLOT.img" ]; then
  run_cp -f "$WORK/boot.img" "/data/FolkPatch-Backup/stock-$TARGET_KIND$SLOT.img" 2>/dev/null
fi
# Remove stale key files from old keyed ZIPs (the key is a fixed constant
# now; a leftover file only confuses).
for d in /sdcard /data/media/0 /data/media /external_sd "$BKDIR" /data/FolkPatch-Backup; do
  rm -f "$d/FolkPatch-key.txt" 2>/dev/null
done
ui_print "- Stock backup saved"
if run_cp -f "$WORK/boot.img" /data/boot.img 2>/dev/null; then
  : # silent
fi

# Stage kernel for patching
if [ -f kernel-origin ]; then rm -f kernel-origin 2>/dev/null; fi
mv kernel kernel-origin 2>/dev/null || abort "cannot stage kernel"

# Clean patch logic: Always try to unpatch before patching to avoid key injection failure
ui_print "- Checking for existing patches..."
kp_run -i kernel-origin -l > "$WORK/vorig.log" 2>&1
if grep -qi "patched=true" "$WORK/vorig.log"; then
  ui_print "- Existing patch found, cleaning kernel for fresh root..."
  kp_run -u -i kernel-origin -o kernel-clean >/dev/null 2>&1
  if [ -s kernel-clean ]; then
    mv -f kernel-clean kernel-origin
    ui_print "- Kernel cleaned successfully"
  else
    ui_print "- WARNING: Could not clean existing patch, continuing anyway"
  fi
fi

ui_print "- Patching kernel with default superkey ..."
# Documented manual method: -s "su". Plaintext compare succeeds with the
# app's key, so sc_ready("su") is true on first boot. (Keyless would leave
# the kernel with a random key; -S would hash-lock a key the app never sends.)
kp_run -p -i kernel-origin -k "$KPIMG" -s "su" -o kernel >"$WORK/patch.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  print_file "$WORK/patch.log"
  abort "patch failed ($RC)"
fi

# Verify patch
kp_run -i kernel -l >"$WORK/verify.log" 2>&1
if run_grep -qi "patched=false" "$WORK/verify.log"; then
  abort "patch verification failed (kernel still reports patched=false)"
fi
if run_grep -qi "patched=true" "$WORK/verify.log"; then
  ui_print "- Kernel patched OK (patched=true)"
else
  # Some kernels don't report patched=true immediately or kptools output differs
  if [ "$RC" -eq 0 ]; then
    ui_print "- Kernel patch command succeeded"
  else
    ui_print "- WARNING: verify log has no patched=true line"
  fi
fi
# Verify: superkey must read back as "su" (plaintext stored by -s).
# root_superkey zeroed is fine (no -S used); only patched=true matters
# besides the plaintext key.
_VL=$(run_grep -i "^superkey=" "$WORK/verify.log" 2>/dev/null | head -n 1)
if [ -n "$_VL" ]; then
  case "$_VL" in
    superkey=su*) ui_print "- Superkey OK: su" ;;
    *) abort "superkey mismatch ($_VL) - app sends 'su', root will NOT work!" ;;
  esac
else
  ui_print "- WARNING: no superkey line in verify log"
  print_file "$WORK/verify.log"
fi

if ! kp_run -i kernel-origin -f 2>/dev/null | run_grep -q "CONFIG_KALLSYMS_ALL=y"; then
  ui_print "- WARNING: CONFIG_KALLSYMS_ALL not enabled - keep your stock backup"
fi

# Repack
ui_print "- Repacking boot image ..."
kp_run repack boot.img >"$WORK/repack.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  print_file "$WORK/repack.log"
  abort "repack failed ($RC)"
fi
if [ ! -f "$WORK/new-boot.img" ]; then abort "new-boot.img missing after repack"; fi

# Flash target partition
flash_target() {
  _img="$WORK/new-boot.img"
  _part="$1"
  _sz=$(wc -c < "$_img" 2>/dev/null | tr -d ' \t\r\n')
  if [ -z "$_sz" ] || [ "$_sz" = "0" ]; then abort "patched image is empty, refusing to flash"; fi
  if command -v blockdev >/dev/null 2>&1; then
    _bsz=$(blockdev --getsize64 "$_part" 2>/dev/null)
    if [ -n "$_bsz" ] && [ "$_bsz" != "0" ] && [ "$_sz" -gt "$_bsz" ]; then
      abort "patched image ($_sz bytes) is larger than partition ($_bsz bytes)"
    fi
    blockdev --setrw "$_part" 2>/dev/null
  fi
  ui_print "- Flashing $1 ..."
  if [ "$BB_OK" = "1" ]; then
    "$BB" dd "if=$_img" "of=$1" bs=4096 2>"$WORK/dd_write.log" || abort "flash failed on $1 - restore stock image manually!"
  else
    dd "if=$_img" "of=$1" bs=4096 2>"$WORK/dd_write.log" || abort "flash failed on $1 - restore stock image manually!"
  fi
  sync 2>/dev/null
}

flash_target "$TARGET"
run_cp -f "$WORK/new-boot.img" "$WORK/new-boot-current.img" 2>/dev/null

# Patch inactive slot (A/B devices only) using its own stock kernel
OTHER=""
INACTIVE_FLASHED=""
case "$SLOT" in
  _a) OTHER="_b" ;;
  _b) OTHER="_a" ;;
esac
if [ -n "$OTHER" ]; then
  _op=$(find_block "$TARGET_KIND$OTHER")
  if [ -n "$_op" ] && [ "$_op" != "$TARGET" ]; then
    ui_print "- Patching inactive slot ($TARGET_KIND$OTHER) ..."
    if run_dd "if=$_op" of="$WORK/obot.img" bs=1048576 2>"$WORK/dd_oread.log" && [ -s "$WORK/obot.img" ]; then
      rm -f kernel kernel-origin new-boot.img 2>/dev/null
      run_cp -f "$WORK/obot.img" "$WORK/boot.img" 2>/dev/null
      if kp_run unpack boot.img >"$WORK/ounpack.log" 2>&1 && [ -f kernel ]; then
        mv kernel kernel-origin 2>/dev/null
        # Same fixed key as current slot.
        if kp_run -p -i kernel-origin -k "$KPIMG" -s "su" -o kernel >"$WORK/opatch.log" 2>&1; then _orc=0; else _orc=$?; fi
        if [ "$_orc" -eq 0 ] && kp_run repack boot.img >"$WORK/orepack.log" 2>&1 && [ -f "$WORK/new-boot.img" ]; then
          run_cp -f "$WORK/new-boot.img" "$WORK/new-boot-inactive.img" 2>/dev/null
          _osz=$(wc -c < "$WORK/new-boot.img" 2>/dev/null | tr -d ' \t\r\n')
          if [ "$BB_OK" = "1" ]; then "$BB" dd "if=$WORK/new-boot.img" "of=$_op" bs=4096 2>"$WORK/dd_write2.log"; else dd "if=$WORK/new-boot.img" "of=$_op" bs=4096 2>"$WORK/dd_write2.log"; fi
          sync 2>/dev/null
          if [ "$?" -eq 0 ]; then
            ui_print "- Inactive slot patched OK"
            INACTIVE_FLASHED="$_op"
          else
            ui_print "- WARNING: inactive slot flash failed (current slot still patched)"
          fi
        else
          ui_print "- WARNING: inactive slot patch failed, skipping"
        fi
      else
        ui_print "- WARNING: inactive slot unpack failed, skipping"
      fi
      rm -f kernel kernel-origin 2>/dev/null
    else
      ui_print "- WARNING: cannot read inactive slot, skipping"
    fi
  fi
fi

# Cleanup and restore current slot image
rm -f "$WORK/boot.img" "$WORK/obot.img" 2>/dev/null
if [ -f "$WORK/new-boot-current.img" ]; then
  run_cp -f "$WORK/new-boot-current.img" "$WORK/new-boot.img" 2>/dev/null
fi

# On-partition verification (decisive check)
verify_slot() {
  _exp="$3"
  if [ -z "$_exp" ]; then _exp="$WORK/new-boot.img"; fi
  _esz=$(wc -c < "$_exp" 2>/dev/null | tr -d ' \t\r\n')
  if [ -z "$_esz" ] || [ "$_esz" = "0" ]; then return 0; fi
  _blocks=$(( ($_esz + 511) / 512 ))
  if ! run_dd "if=$1" of="$WORK/check.img" bs=512 "count=$_blocks" 2>/dev/null || [ ! -s "$WORK/check.img" ]; then
    abort "Cannot read back $2 ($1) - flash may have failed!"
  fi
  rm -rf "$WORK/vcheck" 2>/dev/null
  mkdir -p "$WORK/vcheck" 2>/dev/null
  run_cp -f "$WORK/check.img" "$WORK/vcheck/boot.img" 2>/dev/null
  cd "$WORK/vcheck" 2>/dev/null
  if kp_run unpack boot.img >"$WORK/vcheck.log" 2>&1 && [ -f kernel ]; then
    kp_run -i kernel -l >"$WORK/vcheck-l.log" 2>&1
    cd "$WORK" 2>/dev/null
    if run_grep -qi "patched=false" "$WORK/vcheck-l.log"; then
      rm -rf "$WORK/vcheck" "$WORK/check.img" 2>/dev/null
      abort "Partition holds UNPATCHED kernel! Flash failed on $1 - restore stock image."
    fi
    if run_grep -qi "patched=true" "$WORK/vcheck-l.log"; then
      ui_print "- ROOT ACTIVE on $2 (on-partition: patched=true)"
    else
      ui_print "- WARNING: on-partition verify unclear for $2"
      print_file "$WORK/vcheck-l.log"
    fi
  else
    cd "$WORK" 2>/dev/null
    ui_print "- WARNING: cannot unpack $2 readback"
  fi
  rm -rf "$WORK/vcheck" "$WORK/check.img" 2>/dev/null
}
ui_print "- Verifying on-partition ..."
verify_slot "$TARGET" "current slot" "$WORK/new-boot.img"
if [ -n "$INACTIVE_FLASHED" ] && [ -f "$WORK/new-boot-inactive.img" ]; then
  verify_slot "$INACTIVE_FLASHED" "inactive slot" "$WORK/new-boot-inactive.img"
fi
sync 2>/dev/null

# Install root daemon (apd) to /data/adb - required for instant root after reboot
ui_print "- Installing root daemon ..."
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
# Fallback: extract from bundled APK
need_apk_extract=0
if [ -z "$APD_SRC" ]; then need_apk_extract=1; fi
if [ -z "$FPD_SRC" ]; then need_apk_extract=1; fi
if [ -z "$RESETP_SRC" ]; then need_apk_extract=1; fi
if [ "$need_apk_extract" = "1" ] && [ -s "$WORK/FolkPatch.apk" ]; then
  mkdir -p "$WORK/apklib" 2>/dev/null
  if [ "$BB_OK" = "1" ]; then
    "$BB" unzip -o -q "$WORK/FolkPatch.apk" "lib/arm64-v8a/libapd.so" "lib/arm64-v8a/libresetprop.so" "assets/Service/fpd" -d "$WORK/apklib" 2>/dev/null
  else
    unzip -o -q "$WORK/FolkPatch.apk" "lib/arm64-v8a/libapd.so" "lib/arm64-v8a/libresetprop.so" "assets/Service/fpd" -d "$WORK/apklib" 2>/dev/null
  fi
  if [ -z "$APD_SRC" ] && [ -s "$WORK/apklib/lib/arm64-v8a/libapd.so" ]; then APD_SRC="$WORK/apklib/lib/arm64-v8a/libapd.so"; fi
  if [ -z "$RESETP_SRC" ] && [ -s "$WORK/apklib/lib/arm64-v8a/libresetprop.so" ]; then RESETP_SRC="$WORK/apklib/lib/arm64-v8a/libresetprop.so"; fi
  if [ -z "$FPD_SRC" ] && [ -s "$WORK/apklib/assets/Service/fpd" ]; then FPD_SRC="$WORK/apklib/assets/Service/fpd"; fi
fi
mkdir -p /data/adb/ap/bin /data/adb/ap/log /data/adb/ap/kpm /data/adb/fp/bin /data/adb/fp/pathhide /data/adb/post-fs-data.d 2>/dev/null
if [ ! -d /data/adb ]; then
  ui_print "- /data/adb not found, attempting to mount /data..."
  mount /data 2>/dev/null
  mount /dev/block/by-name/userdata /data 2>/dev/null
fi
mkdir -p /data/adb/ap/bin /data/adb/ap/log /data/adb/ap/kpm /data/adb/fp/bin /data/adb/fp/pathhide /data/adb/post-fs-data.d 2>/dev/null
DAEMON_OK=0
if [ -d /data/adb ]; then
  if [ -n "$APD_SRC" ]; then
    # Copy to multiple locations for better compatibility with different kernels
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
  # Pre-authorize the real Manager package (verified: me.yuki.folk v5.0 on
  # device + in APK dex) and shell so root works right after reboot.
  touch /data/adb/ap/package_config 2>/dev/null
  for pc in /data/adb/ap/package_config; do
    mkdir -p "$(dirname "$pc")" 2>/dev/null
    for pkg in me.yuki.folk com.android.shell; do
      echo "$pkg" >> "$pc" 2>/dev/null
    done
    if [ "$BB_OK" = "1" ]; then "$BB" sort -u "$pc" -o "$pc" 2>/dev/null; fi
    chmod 644 "$pc" 2>/dev/null
  done

  touch /data/adb/ap/version 2>/dev/null
  if [ -s "$BKDIR/stock-$TARGET_KIND$SLOT.img" ]; then
    run_cp -f "$BKDIR/stock-$TARGET_KIND$SLOT.img" /data/adb/ap/ori.img 2>/dev/null
  fi
  # magiskpolicy --live --magisk: the app runs this after installing (it only
  # exists bundled as a stub-less call; recovery has no libmagiskpolicy.so in
  # this APK, so apply via the installed apd if present, else warn).
  if [ -s /data/adb/ap/bin/magiskpolicy ] || [ -s /data/adb/apd ]; then
    ui_print "- Daemon binaries staged (policy applied by app on first boot)"
  else
    ui_print "- WARNING: apd copy failed - daemon install incomplete"
  fi
  if command -v restorecon >/dev/null 2>&1; then
    restorecon /data/adb/apd 2>/dev/null
    restorecon -R /data/adb/ap/ 2>/dev/null
    restorecon /data/adb/fp/bin/fpd 2>/dev/null
  fi
  if [ -s /data/adb/apd ]; then
    DAEMON_OK=1
    ui_print "- Daemon installed: /data/adb/apd"
  else
    ui_print "- WARNING: /data not writable (encrypted?) - daemon skipped"
    ui_print "- Kernel is patched; open the Manager APK after reboot to install daemon"
  fi
else
  ui_print "- WARNING: /data not mounted - daemon skipped"
  ui_print "- Kernel is patched; open the Manager APK after reboot to install daemon"
fi

# Copy Manager APK to sdcard
if [ -f "$WORK/FolkPatch.apk" ]; then
  for d in /sdcard /data/media/0 /external_sd; do
    if [ -d "$d" ]; then
      run_cp -f "$WORK/FolkPatch.apk" "$d/FolkPatch-Manager.apk" 2>/dev/null
      mkdir -p "$d/Download/FolkPatch/BootBackups" 2>/dev/null
      run_cp -f "$WORK/FolkPatch.apk" "$d/Download/FolkPatch/FolkPatch-Manager.apk" 2>/dev/null
      if [ -f "$BKDIR/stock-$TARGET_KIND$SLOT.img" ]; then
        run_cp -f "$BKDIR/stock-$TARGET_KIND$SLOT.img" "$d/Download/FolkPatch/BootBackups/" 2>/dev/null
      fi
    fi
  done
  ui_print "- Manager APK saved to sdcard: FolkPatch-Manager.apk"
fi

# Restore linker env
if [ -n "$OLD_LD_PRELOAD" ]; then export LD_PRELOAD="$OLD_LD_PRELOAD"; fi
if [ -n "$OLD_LD_CONFIG" ]; then export LD_CONFIG_FILE="$OLD_LD_CONFIG"; fi

# Also save patched image to sdcard (Plan B: fastboot)
if [ -f "$WORK/new-boot.img" ]; then
  for d in /sdcard /data/media/0 /data/media /external_sd; do
    if [ -d "$d" ]; then
      run_cp -f "$WORK/new-boot.img" "$d/FolkPatch-patched-$TARGET_KIND.img" 2>/dev/null
    fi
  done
fi

ui_print "****************************"
ui_print " FolkPatch installed! (superkey: su)"
ui_print " Stock backup: $BKDIR/stock-$TARGET_KIND$SLOT.img"
if [ "$DAEMON_OK" = "1" ]; then
  ui_print " Daemon: /data/adb/apd installed - INSTANT ROOT on reboot"
else
  ui_print " Daemon: /data was locked - open Manager APK after reboot"
fi
ui_print "****************************"
ui_print " NEXT STEPS:"
ui_print " 1. Reboot device"
ui_print " 2. Install FolkPatch-Manager.apk from sdcard"
ui_print "    (use the official APK from this ZIP only)"
ui_print " 3. Open app - it should show Installed/Active"
ui_print "    No key entry needed. Allow Superuser on first use."
ui_print " 4. Verify with Root Checker app"
ui_print " Plan B (PC): fastboot flash $TARGET_KIND FolkPatch-patched-$TARGET_KIND.img"
ui_print " Bootloop? Flash Uninstaller ZIP or restore stock backup."
ui_print "****************************"
# Persistent flash report on sdcard (survives reboot; user can send it).
{
  echo "FolkPatch v10.3 flash report"
  echo "date: $(date 2>/dev/null)"
  echo "target: $TARGET_KIND ($TARGET)"
  echo "slot: $SLOT"
  echo "superkey: su"
  echo "daemon: $DAEMON_OK"
  echo "backup: $BKDIR/stock-$TARGET_KIND$SLOT.img"
  echo "inactive: ${INACTIVE_FLASHED:-none}"
} > "$BKDIR/FolkPatch-flash-report.txt" 2>/dev/null
for d in /sdcard /data/media/0 /data/media /external_sd; do
  if [ -d "$d" ]; then cp -f "$BKDIR/FolkPatch-flash-report.txt" "$d/FolkPatch-flash-report.txt" 2>/dev/null; fi
done
exit 0
