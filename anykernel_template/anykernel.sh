### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Ki-kernel AOSP for SM8250 (munch)

### AnyKernel setup
properties() { '
kernel.string=Ki-kernel Universal SM8250 (AOSP / MIUI / HyperOS)
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

# Pick kernel Image
if [ -f "$AKHOME/kernels/miui/Image" ] && [ -f "$AKHOME/kernels/aosp/Image" ]; then
    IS_MIUI=0;
    IS_AOSP=0;

    # Check for manual override flags
    if [ -f /tmp/aosp ] || [ -f /sdcard/aosp ] || [ -f /data/aosp ]; then
        IS_AOSP=1;
    elif [ -f /tmp/miui ] || [ -f /sdcard/miui ] || [ -f /data/miui ]; then
        IS_MIUI=1;
    fi;

    # 0. Check live getprop if available (flashed from booted Android via ksud / FK Kernel Manager)
    if [ "$IS_AOSP" -eq 0 ] && [ "$IS_MIUI" -eq 0 ]; then
        if command -v getprop >/dev/null 2>&1; then
            SYSTEM_NAME=$(getprop ro.product.system.name 2>/dev/null);
            MIUI_NAME=$(getprop ro.miui.ui.version.name 2>/dev/null);
            OS_NAME=$(getprop ro.mi.os.version.name 2>/dev/null);
            BUILD_INC=$(getprop ro.build.version.incremental 2>/dev/null);
            if [ -n "$MIUI_NAME" ] || [ -n "$OS_NAME" ] || echo "$BUILD_INC" | grep -q -E "^V[0-9]|^OS[0-9]"; then
                IS_MIUI=1;
            elif [ -n "$SYSTEM_NAME" ]; then
                IS_AOSP=1;
            fi;
        fi;
    fi;

    # 1. If in recovery, inspect mounted system or try mounting system
    if [ "$IS_AOSP" -eq 0 ] && [ "$IS_MIUI" -eq 0 ]; then
        SYSTEM_MOUNTED=0;
        if [ ! -f /system/build.prop ] && [ ! -f /system/system/build.prop ] && [ ! -f /system_root/system/build.prop ]; then
            mkdir -p /s_chk 2>/dev/null;
            mount -o ro /dev/block/mapper/system /s_chk 2>/dev/null || mount -o ro /dev/block/bootdevice/by-name/system /s_chk 2>/dev/null;
            [ -f /s_chk/build.prop ] || [ -f /s_chk/system/build.prop ] && SYSTEM_MOUNTED=1;
        fi;

        PROP_LIST="/system_root/system/build.prop /system/system/build.prop /system/build.prop /system/etc/build.prop /s_chk/system/build.prop /s_chk/build.prop /product/etc/build.prop";

        # Check for distinct AOSP / Custom ROM indicators
        for prop in $PROP_LIST; do
            if [ -f "$prop" ]; then
                if grep -q -i -E "lineage|crdroid|evolution|pixel|arrow|havoc|aosp|corvus|spark|matrixx|rising|cherish|derp|paranoid|hentai|superior|axion" "$prop" 2>/dev/null; then
                    IS_AOSP=1;
                    break;
                fi;
            fi;
        done;

        # Check for official MIUI / HyperOS system versioning
        if [ "$IS_AOSP" -eq 0 ]; then
            for prop in $PROP_LIST; do
                if [ -f "$prop" ]; then
                    if grep -q -E "^ro\.miui\.ui\.version|^ro\.mi\.os\.version|^ro\.build\.version\.incremental=V[0-9]|^ro\.build\.version\.incremental=OS[0-9]" "$prop" 2>/dev/null; then
                        IS_MIUI=1;
                        break;
                    fi;
                fi;
            done;
        fi;

        if [ "$SYSTEM_MOUNTED" -eq 1 ]; then
            umount /s_chk 2>/dev/null;
            rm -rf /s_chk 2>/dev/null;
        fi;
    fi;

    # Apply selected kernel Image and DTB
    if [ "$IS_MIUI" -eq 1 ] && [ "$IS_AOSP" -eq 0 ]; then
        ui_print "- Detected: MIUI / HyperOS ROM";
        cp -f "$AKHOME/kernels/miui/Image" "$AKHOME/Image";
        [ -f "$AKHOME/kernels/miui/dtb" ] && cp -f "$AKHOME/kernels/miui/dtb" "$AKHOME/dtb_vendor";
    else
        ui_print "- Detected: AOSP / Custom ROM";
        cp -f "$AKHOME/kernels/aosp/Image" "$AKHOME/Image";
        [ -f "$AKHOME/kernels/aosp/dtb" ] && cp -f "$AKHOME/kernels/aosp/dtb" "$AKHOME/dtb_vendor";
    fi;
elif [ -f "$AKHOME/kernels/miui/Image" ]; then
    ui_print "- Target: MIUI / HyperOS";
    cp -f "$AKHOME/kernels/miui/Image" "$AKHOME/Image";
    [ -f "$AKHOME/kernels/miui/dtb" ] && cp -f "$AKHOME/kernels/miui/dtb" "$AKHOME/dtb_vendor";
elif [ -f "$AKHOME/kernels/aosp/Image" ]; then
    ui_print "- Target: AOSP";
    cp -f "$AKHOME/kernels/aosp/Image" "$AKHOME/Image";
    [ -f "$AKHOME/kernels/aosp/dtb" ] && cp -f "$AKHOME/kernels/aosp/dtb" "$AKHOME/dtb_vendor";
elif [ -f "$AKHOME/kernels/Image" ]; then
    cp -f "$AKHOME/kernels/Image" "$AKHOME/Image";
    [ -f "$AKHOME/kernels/dtb" ] && cp -f "$AKHOME/kernels/dtb" "$AKHOME/dtb_vendor";
fi;

# DO NOT touch DTBO (preserve panel/touch drivers from ROM)
rm -f "$AKHOME/dtb" "$AKHOME/dtbo.img" "$AKHOME/dtbo" 2>/dev/null;

# 1. Flash Kernel Image to boot partition (preserve original ramdisk xattrs/SELinux intact)
ui_print "- Flashing kernel to boot...";
split_boot;
flash_boot;

# 2. Flash DTB to vendor_boot partition (Extreme UV + OC 683 MHz GPU table)
if [ -f "$AKHOME/dtb_vendor" ]; then
    ui_print "- Flashing dtb to vendor_boot...";
    BLOCK=vendor_boot;
    reset_ak;
    rm -f "$AKHOME/Image";
    cp -f "$AKHOME/dtb_vendor" "$AKHOME/dtb";
    split_boot;
    flash_boot;
    rm -f "$AKHOME/dtb" "$AKHOME/dtb_vendor";
fi;

# Setup NKM Bypass permissions and profiles on boot (if Magisk / KernelSU exists)
if [ -d /data/adb ]; then
    rm -f /data/adb/post-fs-data.d/00_early_adb.sh;
    cat << 'EOF' > /data/adb/service.d/00_nkm_bypass.sh
#!/system/bin/sh
KSUD_BIN=""
if [ -x /data/adb/ksud ]; then
    KSUD_BIN="/data/adb/ksud"
elif [ -x /data/adb/ksu/bin/ksud ]; then
    KSUD_BIN="/data/adb/ksu/bin/ksud"
fi

if [ -n "$KSUD_BIN" ]; then
    $KSUD_BIN sepolicy patch "allow untrusted_app vendor_sysfs_battery_supply dir { search read getattr open }" 2>/dev/null
    $KSUD_BIN sepolicy patch "allow untrusted_app vendor_sysfs_battery_supply file { read getattr open }" 2>/dev/null
    $KSUD_BIN sepolicy patch "allow untrusted_app_all vendor_sysfs_battery_supply dir { search read getattr open }" 2>/dev/null
    $KSUD_BIN sepolicy patch "allow untrusted_app_all vendor_sysfs_battery_supply file { read getattr open }" 2>/dev/null
    $KSUD_BIN sepolicy patch "allow system_app sysfs_ro file { read open getattr }" 2>/dev/null
    $KSUD_BIN sepolicy patch "allow hal_displayfeature_xiaomi_default vendor_default_prop property_service set" 2>/dev/null
    $KSUD_BIN sepolicy patch "allow platform_app vendor_display_prop file { read open getattr }" 2>/dev/null
    $KSUD_BIN sepolicy patch "allow vendor_hal_perf_default system_server dir search" 2>/dev/null
fi

chmod 664 /sys/class/power_supply/battery/input_suspend 2>/dev/null
chmod 664 /sys/class/power_supply/battery/bypass_charging 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_limit_current 2>/dev/null
chmod 644 /sys/class/power_supply/battery/battery_health 2>/dev/null
chmod 644 /sys/class/power_supply/battery/battery_cycle_count 2>/dev/null
chmod 664 /sys/class/power_supply/battery/battery_charging_enabled 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_enabled 2>/dev/null

chmod 666 /dev/ntsync 2>/dev/null
chmod 666 /sys/devices/platform/kcal_ctrl.0/* 2>/dev/null
chmod 666 /sys/kernel/ki_profile/mode 2>/dev/null
chmod 666 /sys/kernel/ki_profile/thermal_throttle 2>/dev/null
chmod 666 /sys/kernel/ki_profile/spoof_version 2>/dev/null
chmod 666 /sys/kernel/ki_profile/screen_off_battery 2>/dev/null
chmod 666 /sys/kernel/ki_profile/active_profile 2>/dev/null
chmod 666 /sys/kernel/dyn_fsync/* 2>/dev/null
chmod 666 /sys/kernel/gpu/* 2>/dev/null
chmod 666 /sys/touchpanel/double_tap 2>/dev/null
chmod 666 /sys/touchpanel/reversed_keys 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/dimming 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/dc_dimming 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/disp_param 2>/dev/null
chmod 666 /sys/devices/virtual/mi_display/disp_feature/disp-DSI-*/disp_param 2>/dev/null
chmod 666 /sys/devices/virtual/mi_display/disp_feature/disp-DSI-*/dimming 2>/dev/null
chmod 666 /sys/block/zram0/comp_algorithm 2>/dev/null

chmod 666 /sys/class/power_supply/battery/screen_on_fast_charge 2>/dev/null
chmod 666 /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null
echo 1 > /sys/class/power_supply/battery/screen_on_fast_charge 2>/dev/null
echo 1 > /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null

chmod 666 /sys/class/power_supply/battery/force_fast_charge 2>/dev/null
chmod 666 /sys/kernel/fast_charge/force_fast_charge 2>/dev/null
echo 1 > /sys/class/power_supply/battery/force_fast_charge 2>/dev/null
echo 1 > /sys/kernel/fast_charge/force_fast_charge 2>/dev/null

echo 150 > /proc/sys/vm/swappiness 2>/dev/null
chmod 666 /sys/class/misc/boeffla_wakelock_blocker/* 2>/dev/null
echo "wlan_pno_wl;wlan_extscan_wl;wlan_wow_wl;netmgr_wl;" > /sys/class/misc/boeffla_wakelock_blocker/wakelock_blocker 2>/dev/null

# LMKD Tuning (Anti-Kill Multitasking & PSI Memory Retention)
setprop sys.lmk.kill_heaviest_task false 2>/dev/null
setprop ro.lmk.psi_partial_stall_ms 180 2>/dev/null
setprop ro.lmk.thrashing_limit 50 2>/dev/null

for q in /sys/block/*/queue/scheduler; do
    if [ -f "$q" ]; then
        echo maple > "$q" 2>/dev/null
    fi
done
EOF
    chmod 755 /data/adb/service.d/00_nkm_bypass.sh
fi;

ui_print " ";
ui_print "- Done! Reboot to system.";
ui_print " ";
