#!/bin/sh
# FolkPatch uninstaller / restore (POSIX sh, recovery compatible).
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
  ui_print "- Uninstall aborted."
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
if [ "$BB_OK" = "1" ]; then "$BB" chmod 755 "$KPTOOLS" 2>/dev/null; fi

ui_print "****************************"
ui_print " FolkPatch Uninstaller"
ui_print "****************************"

# Detect A/B slot
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
if [ -z "$SLOT" ] && command -v getprop >/dev/null 2>&1; then
  SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
  if [ -z "$SLOT" ]; then
    S=$(getprop ro.boot.slot 2>/dev/null)
    if [ -n "$S" ]; then SLOT="_$S"; fi
  fi
fi
if [ "$SLOT" = "normal" ]; then SLOT=""; fi
if [ -n "$SLOT" ]; then
  ui_print "- A/B slot: $SLOT"
else
  ui_print "- Slot: A-only"
fi

find_block() {
  _b="$1"
  for p in "/dev/block/by-name/$_b" "/dev/block/bootdevice/by-name/$_b"; do
    if [ -e "$p" ]; then echo "$p"; return 0; fi
  done
  for _m in /dev/block/platform/*/by-name/"$_b"; do
    if [ -e "$_m" ]; then echo "$_m"; return 0; fi
  done
  _dev=$(find /dev/block -iname "$_b" 2>/dev/null | head -n 1)
  if [ -n "$_dev" ]; then echo "$_dev"; return 0; fi
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
TARGET_KIND="boot"
for _n in init_boot vendor_boot boot kern-a android_boot kernel bootimg lnx; do
  T=$(find_part "$_n")
  if [ -n "$T" ]; then
    TARGET="$T"
    case "$_n" in
      init_boot*) TARGET_KIND="init_boot" ;;
      vendor_boot*) TARGET_KIND="vendor_boot" ;;
      *) TARGET_KIND="boot" ;;
    esac
    break
  fi
done
if [ -z "$TARGET" ]; then abort "no boot partition found"; fi
ui_print "- Target: $TARGET_KIND ($TARGET)"

# Find stock backup (prefer slot-matched backup)
BACKUP=""
for d in /data/FolkPatch-Backup /sdcard/FolkPatch-Backup /data/media/0/FolkPatch-Backup \
          /external_sd/FolkPatch-Backup /sdcard/Download/FolkPatch/BootBackups \
          /data/media/0/Download/FolkPatch/BootBackups; do
  for f in "$d/stock-$TARGET_KIND$SLOT.img" "$d/stock-$TARGET_KIND.img"; do
    if [ -s "$f" ]; then BACKUP="$f"; break; fi
  done
  if [ -n "$BACKUP" ]; then break; fi
done
if [ -z "$BACKUP" ]; then
  for d in /data/FolkPatch-Backup /sdcard/FolkPatch-Backup /data/media/0/FolkPatch-Backup \
            /external_sd/FolkPatch-Backup /data /sdcard /data/media/0 /external_sd; do
    for f in "$d/stock-$TARGET_KIND$SLOT.img" "$d/stock-$TARGET_KIND.img" "$d/boot.img" "$d/stock-boot.img"; do
      if [ -s "$f" ]; then BACKUP="$f"; break; fi
    done
    if [ -n "$BACKUP" ]; then break; fi
    if [ -d "$d" ]; then
      if [ "$BB_OK" = "1" ]; then
        LATEST=$("$BB" ls -t "$d" 2>/dev/null | "$BB" grep -i "stock.*\.img$" | "$BB" head -n 1)
      else
        LATEST=$(ls -t "$d" 2>/dev/null | grep -i "stock.*\.img$" | head -n 1)
      fi
      if [ -n "$LATEST" ] && [ -s "$d/$LATEST" ]; then BACKUP="$d/$LATEST"; break; fi
    fi
  done
fi

restore_target() {
  _bsz=""
  _isz=""
  if command -v blockdev >/dev/null 2>&1; then _bsz=$(blockdev --getsize64 "$1" 2>/dev/null); fi
  _isz=$(wc -c < "$BACKUP" 2>/dev/null | tr -d ' \t\r\n')
  if [ -n "$_bsz" ] && [ -n "$_isz" ] && [ "$_bsz" != "0" ] && [ "$_isz" -gt "$_bsz" ]; then
    abort "backup ($_isz bytes) is larger than partition ($_bsz bytes)"
  fi
  ui_print "- Restoring $1 from: $BACKUP"
  if [ "$BB_OK" = "1" ]; then
    "$BB" dd "if=$BACKUP" "of=$1" bs=4096 2>"$WORK/dd_restore.log" || abort "restore failed on $1"
  else
    dd "if=$BACKUP" "of=$1" bs=4096 2>"$WORK/dd_restore.log" || abort "restore failed on $1"
  fi
  sync 2>/dev/null
}

if [ -n "$BACKUP" ]; then
  ui_print "- Stock backup found: $BACKUP"
  restore_target "$TARGET"

  OTHER=""
  case "$SLOT" in
    _a) OTHER="_b" ;;
    _b) OTHER="_a" ;;
  esac
  if [ -n "$OTHER" ]; then
    _ob=""
    for d in /data/FolkPatch-Backup /sdcard/FolkPatch-Backup /data/media/0/FolkPatch-Backup \
              /external_sd/FolkPatch-Backup /sdcard/Download/FolkPatch/BootBackups \
              /data/media/0/Download/FolkPatch/BootBackups; do
      for f in "$d/stock-$TARGET_KIND$OTHER.img" "$d/stock-$TARGET_KIND.img"; do
        if [ -s "$f" ]; then _ob="$f"; break; fi
      done
      if [ -n "$_ob" ]; then break; fi
    done
    _op=$(find_block "$TARGET_KIND$OTHER")
    if [ -n "$_op" ] && [ "$_op" != "$TARGET" ]; then
      if [ -n "$_ob" ]; then
        _OLD="$BACKUP"
        BACKUP="$_ob"
        ui_print "- Restoring inactive slot ($TARGET_KIND$OTHER) ..."
        restore_target "$_op" || ui_print "- WARNING: inactive slot restore failed"
        BACKUP="$_OLD"
      else
        ui_print "- No backup found for inactive slot, leaving it"
      fi
    fi
  fi

  sync 2>/dev/null
  # Remove root daemon files to prevent ghost root after restore
  for _d in /data/adb/apd /data/adb/ap /data/adb/fp; do
    if [ -e "$_d" ]; then rm -rf "$_d" 2>/dev/null; fi
  done
  ui_print "- Root daemon removed"

  if [ -n "$OLD_LD_PRELOAD" ]; then export LD_PRELOAD="$OLD_LD_PRELOAD"; fi
  if [ -n "$OLD_LD_CONFIG" ]; then export LD_CONFIG_FILE="$OLD_LD_CONFIG"; fi

  ui_print "****************************"
  ui_print " Stock restored. Reboot to unroot."
  ui_print "****************************"
  exit 0
fi

# No backup found - live unpatch the current kernel
ui_print "- No stock backup found - live unpatching kernel ..."
run_dd "if=$TARGET" of="$WORK/boot.img" bs=1048576 2>"$WORK/dd_read.log" || abort "cannot read $TARGET"
kp_run unpack boot.img >"$WORK/unpack.log" 2>&1 || abort "unpack failed"
if [ ! -f kernel ]; then abort "no kernel after unpack"; fi
if kp_run -i kernel -l 2>/dev/null | run_grep -qi "patched=false"; then
  ui_print "- Kernel is already stock. Reboot."
  exit 0
fi
if [ "$BB_OK" = "1" ]; then "$BB" mv kernel kernel-origin 2>/dev/null || abort "cannot stage kernel"; else mv kernel kernel-origin 2>/dev/null || abort "cannot stage kernel"; fi
kp_run -u -i kernel-origin -o kernel >"$WORK/unpatch.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
  print_file "$WORK/unpatch.log"
  abort "unpatch failed ($RC)"
fi
kp_run repack boot.img >"$WORK/repack.log" 2>&1 || abort "repack failed"
if [ ! -f "$WORK/new-boot.img" ]; then abort "new-boot.img missing"; fi
if [ "$BB_OK" = "1" ]; then
  "$BB" dd "if=$WORK/new-boot.img" "of=$TARGET" bs=4096 2>"$WORK/dd_write.log" || abort "flash failed"
else
  dd "if=$WORK/new-boot.img" "of=$TARGET" bs=4096 2>"$WORK/dd_write.log" || abort "flash failed"
fi
sync 2>/dev/null
for _d in /data/adb/apd /data/adb/ap /data/adb/fp; do
  if [ -e "$_d" ]; then rm -rf "$_d" 2>/dev/null; fi
done

if [ -n "$OLD_LD_PRELOAD" ]; then export LD_PRELOAD="$OLD_LD_PRELOAD"; fi
if [ -n "$OLD_LD_CONFIG" ]; then export LD_CONFIG_FILE="$OLD_LD_CONFIG"; fi

ui_print "****************************"
ui_print " FolkPatch removed. Reboot."
ui_print "****************************"
exit 0
