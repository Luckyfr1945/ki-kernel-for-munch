### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Ki-kernel AOSP for SM8250 (munch)

### AnyKernel setup
properties() { '
kernel.string=Ki-kernel AOSP SM8250 (munch)
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=munch
device.name2=munchin
device.name3=alioth
device.name4=aliothin
device.name5=apollo
device.name6=apolloin
device.name7=lmi
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
NO_BLOCK_DISPLAY=1;

. tools/ak3-core.sh;

ui_print " ";
ui_print "  ********************************";
ui_print "  *          Ki-Kernel           *";
ui_print "  *         SM8250 munch         *";
ui_print "  ********************************";
ui_print " ";

# Pick kernel Image & DTB
if [ -f "$AKHOME/kernels/miui/Image" ]; then
    ui_print "- Target: MIUI / HyperOS";
    cp -f "$AKHOME/kernels/miui/Image" "$AKHOME/Image";
    [ -f "$AKHOME/kernels/miui/dtb" ] && cp -f "$AKHOME/kernels/miui/dtb" "$AKHOME/dtb";
elif [ -f "$AKHOME/kernels/aosp/Image" ]; then
    ui_print "- Target: AOSP";
    cp -f "$AKHOME/kernels/aosp/Image" "$AKHOME/Image";
    [ -f "$AKHOME/kernels/aosp/dtb" ] && cp -f "$AKHOME/kernels/aosp/dtb" "$AKHOME/dtb";
elif [ -f "$AKHOME/kernels/Image" ]; then
    cp -f "$AKHOME/kernels/Image" "$AKHOME/Image";
    [ -f "$AKHOME/kernels/dtb" ] && cp -f "$AKHOME/kernels/dtb" "$AKHOME/dtb";
fi;

# DO NOT touch DTBO (Preserve panel/touch calibration from ROM)
rm -f "$AKHOME/dtbo.img" "$AKHOME/dtbo" 2>/dev/null;

# 1. Flash Kernel Image to boot partition
ui_print "- Flashing kernel to boot...";
dump_boot;

# Early ADB & USB Debugging injection (Android 11 - 17)
ui_print "- Injecting Early ADB & USB Debugging...";
patch_cmdline "androidboot.debuggable" "androidboot.debuggable=1";
patch_cmdline "androidboot.adb" "androidboot.adb=1";
patch_cmdline "androidboot.usbconfig" "androidboot.usbconfig=adb";

for prop in default.prop prop.default system/etc/prop.default; do
    if [ -f "$RAMDISK/$prop" ]; then
        patch_prop "$RAMDISK/$prop" "ro.debuggable" "1";
        patch_prop "$RAMDISK/$prop" "ro.adb.secure" "0";
        patch_prop "$RAMDISK/$prop" "persist.sys.usb.config" "adb";
        patch_prop "$RAMDISK/$prop" "sys.usb.config" "adb";
    fi;
done;

if [ -d "$RAMDISK" ]; then
    cat << 'EOF' > "$RAMDISK/init.early_adb.rc"
on early-init
    setprop ro.debuggable 1
    setprop ro.adb.secure 0
    setprop persist.sys.usb.config adb
    setprop sys.usb.config adb

on post-fs
    setprop persist.sys.usb.config adb
    setprop sys.usb.config adb
    start adbd

on property:sys.boot_completed=1
    setprop persist.sys.usb.config adb
    setprop sys.usb.config adb
    start adbd
EOF
    chmod 644 "$RAMDISK/init.early_adb.rc" 2>/dev/null;
    if [ -f "$RAMDISK/init.rc" ] && ! grep -q "init.early_adb.rc" "$RAMDISK/init.rc"; then
        sed -i '1s;^;import /init.early_adb.rc\n;' "$RAMDISK/init.rc";
    fi;

    # Ki-Profile Control Service for Root and Non-Root (Shizuku / ADB)
    cat << 'EOF' > "$RAMDISK/init.ki_profile.rc"
on boot
    chmod 0666 /sys/kernel/ki_profile/mode
    chmod 0666 /sys/kernel/ki_profile/thermal_throttle
    chmod 0666 /sys/kernel/ki_profile/spoof_version
    chmod 0444 /sys/kernel/ki_profile/current_profile
    chmod 0444 /sys/kernel/ki_profile/available_modes
    chown system system /sys/kernel/ki_profile/mode
    chown system system /sys/kernel/ki_profile/thermal_throttle
    chown system system /sys/kernel/ki_profile/spoof_version

# Enable kernel version spoof ONLY after full boot — prevents bootreceiver/recovery
# from seeing the 5.15 string during early init and triggering a recovery loop.
on property:sys.boot_completed=1
    write /sys/kernel/ki_profile/spoof_version 1

on property:persist.ki.profile=0
    write /sys/kernel/ki_profile/mode 0

on property:persist.ki.profile=1
    write /sys/kernel/ki_profile/mode 1

on property:persist.ki.profile=2
    write /sys/kernel/ki_profile/mode 2

on property:persist.ki.thermal=0
    write /sys/kernel/ki_profile/thermal_throttle 0

on property:persist.ki.thermal=1
    write /sys/kernel/ki_profile/thermal_throttle 1
EOF
    chmod 644 "$RAMDISK/init.ki_profile.rc" 2>/dev/null;
    if [ -f "$RAMDISK/init.rc" ] && ! grep -q "init.ki_profile.rc" "$RAMDISK/init.rc"; then
        sed -i '1s;^;import /init.ki_profile.rc\n;' "$RAMDISK/init.rc";
    fi;
fi;

write_boot;

# 2. Flash DTB to vendor_boot partition (Standard SM8250 AOSP)
vendor_boot_block="";
for dev in /dev/block/bootdevice/by-name/vendor_boot \
           /dev/block/by-name/vendor_boot; do
    if [ -e "${dev}${SLOT}" ] || [ -e "$dev" ]; then
        vendor_boot_block="$dev";
        break;
    fi;
done;

if [ -n "$vendor_boot_block" ]; then
    ui_print "- Flashing dtb to vendor_boot...";
    BLOCK=$vendor_boot_block;
    IS_SLOT_DEVICE=auto;
    RAMDISK_COMPRESSION=auto;
    PATCH_VBMETA_FLAG=auto;

    reset_ak;
    if [ -f "$AKHOME/kernels/miui/dtb" ]; then
        cp -f "$AKHOME/kernels/miui/dtb" "$AKHOME/dtb";
    elif [ -f "$AKHOME/kernels/aosp/dtb" ]; then
        cp -f "$AKHOME/kernels/aosp/dtb" "$AKHOME/dtb";
    elif [ -f "$AKHOME/kernels/dtb" ]; then
        cp -f "$AKHOME/kernels/dtb" "$AKHOME/dtb";
    fi;
    dump_boot;
    write_boot;
else
    ui_print "- Warning: vendor_boot partition not found, skipping dtb";
fi;

# Setup NKM Bypass permissions and profiles on boot (if Magisk / KernelSU exists)
if [ -d /data/adb ]; then
    rm -f /data/adb/post-fs-data.d/00_early_adb.sh;
    cat << 'EOF' > /data/adb/service.d/00_nkm_bypass.sh
#!/system/bin/sh
if [ -x /data/adb/ksu/bin/ksud ]; then
    /data/adb/ksu/bin/ksud sepolicy patch "allow untrusted_app vendor_sysfs_battery_supply dir { search read getattr open }" 2>/dev/null
    /data/adb/ksu/bin/ksud sepolicy patch "allow untrusted_app vendor_sysfs_battery_supply file { read getattr open }" 2>/dev/null
    /data/adb/ksu/bin/ksud sepolicy patch "allow untrusted_app_all vendor_sysfs_battery_supply dir { search read getattr open }" 2>/dev/null
    /data/adb/ksu/bin/ksud sepolicy patch "allow untrusted_app_all vendor_sysfs_battery_supply file { read getattr open }" 2>/dev/null
    /data/adb/ksu/bin/ksud sepolicy patch "allow system_app sysfs_ro file { read open getattr }" 2>/dev/null
    /data/adb/ksu/bin/ksud sepolicy patch "allow hal_displayfeature_xiaomi_default vendor_default_prop property_service set" 2>/dev/null
    /data/adb/ksu/bin/ksud sepolicy patch "allow platform_app vendor_display_prop file { read open getattr }" 2>/dev/null
    /data/adb/ksu/bin/ksud sepolicy patch "allow vendor_hal_perf_default system_server dir search" 2>/dev/null
fi

chmod 664 /sys/class/power_supply/battery/input_suspend 2>/dev/null
chmod 664 /sys/class/power_supply/battery/bypass_charging 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_limit_current 2>/dev/null
chmod 644 /sys/class/power_supply/battery/battery_health 2>/dev/null
chmod 644 /sys/class/power_supply/battery/battery_cycle_count 2>/dev/null
chmod 664 /sys/class/power_supply/battery/battery_charging_enabled 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_enabled 2>/dev/null

chmod 666 /dev/ntsync 2>/dev/null
chmod 666 /sys/kernel/ki_profile/mode 2>/dev/null
chmod 666 /sys/kernel/ki_profile/thermal_throttle 2>/dev/null
chmod 666 /sys/kernel/ki_profile/spoof_version 2>/dev/null
chmod 666 /sys/kernel/dyn_fsync/* 2>/dev/null
chmod 666 /sys/kernel/gpu/* 2>/dev/null
chmod 666 /sys/touchpanel/double_tap 2>/dev/null
chmod 666 /sys/touchpanel/reversed_keys 2>/dev/null

chmod 664 /sys/class/power_supply/battery/screen_on_fast_charge 2>/dev/null
chmod 664 /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null
echo 1 > /sys/class/power_supply/battery/screen_on_fast_charge 2>/dev/null
echo 1 > /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null
EOF
    chmod 755 /data/adb/service.d/00_nkm_bypass.sh
fi;

ui_print " ";
ui_print "- Done! Reboot to system.";
ui_print " ";
