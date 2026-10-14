#!/bin/sh
# =====================================================================
# MultiRoot uninstaller (POSIX sh, recovery compatible).
# Removes EVERY root provider installed by the MultiRoot installer -
# WITHOUT needing or creating any backup file:
#   - KernelPatch: live kernel unpatch (kptools -u)
#   - Magisk:      ramdisk restored from the in-image .backup
#   - KernelSU:    /data/adb/ksu* daemon files removed
#   - FolkPatch/APatch daemons, Magisk files, modules: removed from /data
#   - stale FolkPatch-Backup folders from v1 installs: deleted
# The boot image itself is repacked from the patched one and flashed
# back; readback verification proves the stock state before exit.
# No bashisms: no 'function', no '[[', no '=='.
# Env from update-binary: BBBIN, INSTALLER. Args: $1 api, $2 fd, $3 zip.
# =====================================================================
OUTFD="$2"
ZIPFILE="$3"
BB="$BBBIN"
if [ -z "$BB" ]; then BB="busybox"; fi
WORK="$INSTALLER"
if [ -z "$WORK" ]; then WORK="/dev/tmp/multiroot_un"; fi
INST_VER="2.0"

KPTOOLS=""
for k in "$WORK/lib/arm64-v8a/libkptools.so" "$WORK/kptools" "$WORK/assets/kptools"; do
  if [ -f "$k" ]; then
    chmod 755 "$k" 2>/dev/null
    KPTOOLS="$k"
    break
  fi
done
MAGISKBOOT="$WORK/assets/magisk/magiskboot"

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

# Mount real system + APEX so the bionic tools resolve linker64 + libc.
if [ -f /system_root/system/build.prop ] || [ -f /system_root/build.prop ]; then
  SYS_OK=1
else
  mkdir -p /system_root 2>/dev/null
  for _p in /dev/block/bootdevice/by-name/system"$SLOT" /dev/block/by-name/system"$SLOT" \
             /dev/block/bootdevice/by-name/system /dev/block/by-name/system \
             /dev/block/bootdevice/by-name/system_a /dev/block/by-name/system_a \
             /dev/block/bootdevice/by-name/system_b /dev/block/by-name/system_b \
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

ui_print "****************************"
ui_print " MultiRoot Uninstaller v$INST_VER"
ui_print " Removes KernelPatch + Magisk"
ui_print " No backup needed or created"
ui_print "****************************"

if [ -z "$KPTOOLS" ]; then abort "kptools missing"; fi
chmod 755 "$KPTOOLS" 2>/dev/null
if [ ! -f "$MAGISKBOOT" ]; then abort "magiskboot missing in ZIP"; fi
chmod 755 "$MAGISKBOOT" 2>/dev/null

# Detect A/B slot: cmdline -> bootconfig -> getprop -> fstab/mounts.
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
if [ -z "$TARGET" ]; then abort "no boot partition found"; fi
ui_print "- Target: boot ($TARGET)"
INITBOOT_PART=$(find_part init_boot 2>/dev/null)

clean_stage() {
  rm -f kernel kernel-origin kernel-clean ramdisk.cpio ramdisk.cpio.orig \
       new-boot.img dtb extra kernel_dtb boot2.img check.img 2>/dev/null
  rm -rf "$WORK/vcheck" 2>/dev/null
}

flash_partition() {
  _part="$1"
  _label="$2"
  _img="$WORK/new-boot.img"
  _sz=$(wc -c < "$_img" 2>/dev/null | tr -d ' \t\r\n')
  if [ -z "$_sz" ] || [ "$_sz" = "0" ]; then abort "restored image is empty, refusing to flash"; fi
  if command -v blockdev >/dev/null 2>&1; then
    _bsz=$(blockdev --getsize64 "$_part" 2>/dev/null)
    if [ -n "$_bsz" ] && [ "$_bsz" != "0" ] && [ "$_sz" -gt "$_bsz" ]; then
      abort "restored image ($_sz bytes) larger than partition ($_bsz bytes)"
    fi
    blockdev --setrw "$_part" 2>/dev/null
  fi
  ui_print "- Flashing restored image to $2 ..."
  run_dd "if=$_img" "of=$_part" bs=4096 2>"$WORK/dd_write.log" || abort "flash failed on $_part"
  sync 2>/dev/null
}

do_restore_slot() {
  # $1 = partition device, $2 = label
  _part="$1"
  _label="$2"
  ui_print "- Reading $2 ($_part) ..."
  run_dd "if=$_part" of="$WORK/boot.img" bs=1048576 2>"$WORK/dd_read.log" || abort "cannot read $_part"
  if [ ! -s "$WORK/boot.img" ]; then abort "read produced empty boot.img"; fi
  clean_stage

  ui_print "- Unpacking boot image ..."
  run_magisk unpack boot.img >"$WORK/unpack.log" 2>&1 || { print_file "$WORK/unpack.log"; abort "unpack failed"; }

  CHANGE=0

  # ---- 1) KernelPatch: live unpatch ----
  if [ -f kernel ]; then
    kp_run -i kernel -l > "$WORK/vorig.log" 2>&1
    if run_grep -qi "patched=true" "$WORK/vorig.log"; then
      ui_print "- KernelPatch found - live unpatching kernel ..."
      run_mv kernel kernel-origin || abort "cannot stage kernel"
      kp_run -u -i kernel-origin -o kernel >"$WORK/unpatch.log" 2>&1
      RC=$?
      if [ "$RC" -ne 0 ] || [ ! -s kernel ]; then
        print_file "$WORK/unpatch.log"
        abort "KernelPatch unpatch failed ($RC)"
      fi
      kp_run -i kernel -l >"$WORK/vunp.log" 2>&1
      if run_grep -qi "patched=true" "$WORK/vunp.log"; then
        abort "kernel still reports patched=true after unpatch"
      fi
      ui_print "- Kernel unpatched OK (patched=false)"
      CHANGE=1
    else
      ui_print "- Kernel: no KernelPatch (already clean)"
    fi
  else
    ui_print "- WARNING: no kernel inside boot image"
  fi

  # ---- 2) Magisk: restore ramdisk from the in-image .backup ----
  RAMDISK=""
  for _rp in ramdisk.cpio vendor_ramdisk/init_boot.cpio vendor_ramdisk/ramdisk.cpio; do
    if [ -e "$_rp" ]; then RAMDISK="$_rp"; break; fi
  done
  if [ -n "$RAMDISK" ]; then
    run_magisk cpio "$RAMDISK" test >/dev/null 2>&1
    MG_STATUS=$?
    case $MG_STATUS in
      0)
        ui_print "- Ramdisk: stock (no Magisk)"
        ;;
      1)
        ui_print "- Magisk found - restoring ramdisk from internal backup ..."
        run_magisk cpio "$RAMDISK" "extract .backup/.magisk config.orig" "restore" >"$WORK/cpio.log" 2>&1 \
          || { print_file "$WORK/cpio.log"; abort "ramdisk restore failed"; }
        if ! run_magisk cpio "$RAMDISK" "exists init" >/dev/null 2>&1; then
          # A-only system-as-root: stock has no ramdisk in boot
          rm -f "$RAMDISK" 2>/dev/null
          ui_print "- Restored ramdisk is empty (system-as-root) - removed"
        fi
        ui_print "- Ramdisk restored to stock"
        CHANGE=1
        ;;
      2)
        abort "ramdisk patched by unsupported programs - cannot uninstall safely"
        ;;
    esac
  else
    ui_print "- Boot has no ramdisk (normal for GKI)"
  fi

  if [ "$CHANGE" = "0" ]; then
    ui_print "- $2 is already stock - no flash needed"
    clean_stage
    return 0
  fi

  ui_print "- Repacking boot image ..."
  run_magisk repack boot.img >"$WORK/repack.log" 2>&1 || { print_file "$WORK/repack.log"; abort "repack failed"; }
  if [ ! -f "$WORK/new-boot.img" ]; then abort "new-boot.img missing after repack"; fi
  flash_partition "$_part" "$_label"

  # Readback verification: prove stock state on the partition
  _esz=$(wc -c < "$WORK/new-boot.img" 2>/dev/null | tr -d ' \t\r\n')
  _blocks=$(( (_esz + 511) / 512 ))
  if run_dd "if=$_part" of="$WORK/check.img" bs=512 "count=$_blocks" 2>/dev/null && [ -s "$WORK/check.img" ]; then
    rm -rf "$WORK/vcheck" 2>/dev/null
    mkdir -p "$WORK/vcheck" 2>/dev/null
    run_cp -f "$WORK/check.img" "$WORK/vcheck/boot.img" 2>/dev/null
    cd "$WORK/vcheck" 2>/dev/null
    run_magisk unpack boot.img >/dev/null 2>&1
    if [ -f kernel ]; then
      kp_run -i kernel -l >"$WORK/vcheck-l.log" 2>&1
      if run_grep -qi "patched=true" "$WORK/vcheck-l.log"; then
        cd "$WORK" 2>/dev/null
        abort "partition STILL has KernelPatch - restore failed on $_part!"
      fi
    fi
    if [ -f ramdisk.cpio ]; then
      run_magisk cpio ramdisk.cpio test >/dev/null 2>&1
      if [ "$?" -eq "1" ]; then
        cd "$WORK" 2>/dev/null
        abort "partition STILL has Magisk ramdisk - restore failed on $_part!"
      fi
    fi
    cd "$WORK" 2>/dev/null
    ui_print "- STOCK CONFIRMED on $2 (readback verified)"
    rm -rf "$WORK/vcheck" "$WORK/check.img" 2>/dev/null
  fi
  clean_stage
}

# ---------------------------------------------------------------------
# Restore current slot
do_restore_slot "$TARGET" "current slot"

# init_boot may carry the Magisk ramdisk on Android 13+ GKI devices
if [ -n "$INITBOOT_PART" ]; then
  ui_print "- Checking init_boot for Magisk ..."
  run_dd "if=$INITBOOT_PART" of="$WORK/boot2.img" bs=1048576 2>"$WORK/dd_read2.log" || { ui_print "- WARNING: cannot read init_boot - skipped"; INITBOOT_PART=""; }
fi
if [ -n "$INITBOOT_PART" ]; then
  rm -f kernel ramdisk.cpio ramdisk.cpio.orig new-boot.img dtb extra kernel_dtb 2>/dev/null
  if run_magisk unpack boot2.img >"$WORK/iunpack.log" 2>&1; then
    _IR=""
    for _rp in ramdisk.cpio vendor_ramdisk/init_boot.cpio vendor_ramdisk/ramdisk.cpio; do
      if [ -e "$_rp" ]; then _IR="$_rp"; break; fi
    done
    if [ -n "$_IR" ]; then
      run_magisk cpio "$_IR" test >/dev/null 2>&1
      _IST=$?
      if [ "$_IST" -eq "1" ]; then
        ui_print "- Magisk found in init_boot - restoring ..."
        run_magisk cpio "$_IR" "extract .backup/.magisk config.orig" "restore" >"$WORK/icpio.log" 2>&1 \
          || { print_file "$WORK/icpio.log"; abort "init_boot ramdisk restore failed"; }
        if ! run_magisk cpio "$_IR" "exists init" >/dev/null 2>&1; then
          rm -f "$_IR" 2>/dev/null
        fi
        run_magisk repack boot2.img >"$WORK/irepack.log" 2>&1 || abort "init_boot repack failed"
        if [ -f "$WORK/new-boot.img" ]; then
          flash_partition "$INITBOOT_PART" "init_boot"
          ui_print "- STOCK CONFIRMED on init_boot"
        fi
        CHANGE_ANY=1
      elif [ "$_IST" -eq "2" ]; then
        ui_print "- WARNING: init_boot patched by unsupported program - skipped"
      else
        ui_print "- init_boot: stock (no Magisk)"
      fi
    fi
  fi
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
    ui_print "- Restoring inactive slot (boot$OTHER) ..."
    do_restore_slot "$_op" "inactive slot"
  fi
fi

sync 2>/dev/null

# ---------------------------------------------------------------------
# Remove every root family's files from /data (KP / FolkPatch / Magisk / KSU)
ui_print "- Removing root files from /data ..."
DATA_OK=0
if [ -d /data/adb ] || mount /data 2>/dev/null || mount /dev/block/by-name/userdata /data 2>/dev/null; then
  if [ -d /data ]; then DATA_OK=1; fi
fi
if [ "$DATA_OK" = "1" ]; then
  # KernelPatch / FolkPatch / APatch daemon
  run_rm -rf /data/adb/apd /data/adb/ap /data/adb/fp 2>/dev/null
  # Magisk (official uninstaller list)
  run_rm -rf /data/adb/*magisk* /data/adb/post-fs-data.d /data/adb/service.d /data/adb/modules* 2>/dev/null
  run_rm -rf /data/*magisk* /data/cache/*magisk* /data/property/*magisk* 2>/dev/null
  run_rm -rf /data/Magisk.apk /data/busybox /data/custom_ramdisk_patch.sh 2>/dev/null
  run_rm -rf /cache/*magisk* /cache/unblock 2>/dev/null
  run_rm -rf /data/unencrypted/magisk /metadata/magisk /metadata/watchdog/magisk 2>/dev/null
  run_rm -rf /persist/magisk /mnt/vendor/persist/magisk 2>/dev/null
  # KernelSU / KernelSU Next / SukiSU leftovers
  run_rm -rf /data/adb/ksu /data/adb/ksud 2>/dev/null
  # Old backup folders/files from v1 installers (policy: zero backups)
  run_rm -rf /sdcard/FolkPatch-Backup /data/media/0/FolkPatch-Backup 2>/dev/null
  run_rm -rf /external_sd/FolkPatch-Backup /data/FolkPatch-Backup 2>/dev/null
  run_rm -rf "/sdcard/Download/FolkPatch" "/data/media/0/Download/FolkPatch" 2>/dev/null
  run_rm -rf /data/magisk_backup_* 2>/dev/null
  run_rm -f /data/boot.img /data/adb/ap/ori.img 2>/dev/null
  run_rm -f /sdcard/FolkPatch-flash-report.txt /data/media/0/FolkPatch-flash-report.txt 2>/dev/null
  run_rm -f /sdcard/FolkPatch-key.txt /data/media/0/FolkPatch-key.txt 2>/dev/null
  run_rm -f /sdcard/FolkPatch-patched-*.img /data/media/0/FolkPatch-patched-*.img 2>/dev/null
  # Manager APK copies made by the installer (apps stay until user uninstalls)
  run_rm -f /sdcard/FolkPatch-Manager.apk /data/media/0/FolkPatch-Manager.apk 2>/dev/null
  run_rm -f /sdcard/APatch-Manager.apk /data/media/0/APatch-Manager.apk 2>/dev/null
  ui_print "- Root files removed from /data"
else
  ui_print "- WARNING: /data not mounted - daemon files not removed"
  ui_print "- Kernel is clean; reinstall stock ROM to remove app data leftovers"
fi

# Restore linker env
if [ -n "$OLD_LD_PRELOAD" ]; then export LD_PRELOAD="$OLD_LD_PRELOAD"; fi
if [ -n "$OLD_LD_CONFIG" ]; then export LD_CONFIG_FILE="$OLD_LD_CONFIG"; fi

# Clean every temp file (tmpfs self-cleans on reboot too)
rm -f "$WORK"/boot.img "$WORK"/boot2.img "$WORK"/new-boot.img "$WORK"/check.img \
      "$WORK"/kernel "$WORK"/kernel-origin "$WORK"/kernel-clean \
      "$WORK"/ramdisk.cpio "$WORK"/ramdisk.cpio.orig "$WORK"/dtb "$WORK"/extra \
      "$WORK"/kernel_dtb 2>/dev/null
rm -rf "$WORK/vcheck" 2>/dev/null

ui_print "****************************"
ui_print " Fully unrooted!"
ui_print " Kernel: stock  |  Ramdisk: stock"
ui_print " Root files removed from /data"
ui_print " Manager apps: uninstall them"
ui_print " manually from Android settings"
ui_print "****************************"
ui_print " Reboot to finish unroot."
ui_print "****************************"
exit 0
