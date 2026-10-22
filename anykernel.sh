# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers
# Universal SM8250 Installer for Ki-kernel (boot + vendor_boot dtb)

## AnyKernel setup
# begin properties
properties() { '
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=munch
device.name2=alioth
device.name3=aliothin
device.name4=apollo
device.name5=apolloin
device.name6=lmi
supported.versions=
supported.patchlevels=
'; } # end properties

# shell variables
block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;
no_block_display=1

## Move kernel and dtb to home root before sourcing ak3-core.sh
if [ -f "$home/kernels/Image" ]; then
    mv -f $home/kernels/Image $home/Image;
fi;
if [ -f "$home/kernels/dtb" ]; then
    mv -f $home/kernels/dtb $home/dtb;
fi;

## AnyKernel methods (DO NOT CHANGE)
# import patching functions/variables - see for reference
. tools/ak3-core.sh;

find_prop() {
    local prop="$1";
    local val="";
    if [ -n "$(command -v getprop 2>/dev/null)" ]; then
        val="$(getprop "$prop" 2>/dev/null)";
    fi;
    if [ -z "$val" ]; then
        for f in /system/build.prop /system/system/build.prop /system_root/system/build.prop \
                 /system/etc/build.prop /vendor/build.prop /product/build.prop /system_ext/build.prop; do
            if [ -f "$f" ]; then
                val="$(file_getprop "$f" "$prop" 2>/dev/null)";
                [ -n "$val" ] && break;
            fi;
        done;
    fi;
    echo "$val";
}

hyperos_ver="$(find_prop "ro.mi.os.version.name")";
[ -z "$hyperos_ver" ] && hyperos_ver="$(find_prop "ro.mi.os.version.incremental")";
miui_ver="$(find_prop "ro.miui.ui.version.name")";
[ -z "$miui_ver" ] && miui_ver="$(find_prop "ro.miui.ui.version.code")";
miui_region="$(find_prop "ro.vendor.miui.build.region")";
[ -z "$miui_region" ] && miui_region="$(find_prop "ro.miui.build.region")";
userflavor="$(find_prop "ro.build.flavor")";
build_inc="$(find_prop "ro.build.version.incremental")";

if [ -n "$hyperos_ver" ] || echo "$build_inc" | grep -qiE '^OS[0-9]'; then
    os="hyperos";
    if [ -n "$hyperos_ver" ]; then
        os_string="Xiaomi HyperOS ($hyperos_ver)";
    else
        os_string="Xiaomi HyperOS ROM";
    fi;
elif [ -n "$miui_ver" ] || echo "$build_inc" | grep -qiE '^V[0-9]' || \
     case "$miui_region" in cn|in|ru|id|eu|tr|tw|gb|global|mx|jp|kr|lm|cl|mi) true;; *) false;; esac || \
     [ -d /system/priv-app/MiuiSystemUI -o -d /system_root/system/priv-app/MiuiSystemUI -o -d /system/system/priv-app/MiuiSystemUI ] || \
     [ -f /system/framework/miui.jar -o -f /system_root/system/framework/miui.jar ] || \
     [ -f /vendor/etc/device_features/munch.xml -o -f /product/etc/device_features/munch.xml ]; then
    os="miui";
    if [ -n "$miui_ver" ]; then
        os_string="Xiaomi MIUI ($miui_ver)";
    elif [ -n "$miui_region" ]; then
        os_string="Xiaomi MIUI/HyperOS (Region: $miui_region)";
    else
        os_string="Xiaomi MIUI ROM";
    fi;
elif case "$userflavor" in *missi*|*qssi*) true;; *) false;; esac; then
    os="miui";
    os_string="Xiaomi MIUI ROM";
elif case "$userflavor" in aospa*) true;; *) false;; esac; then
    os="aospa";
    os_string="Paranoid Android (AOSPA) ROM";
elif [ -n "$(find_prop "ro.build.version.oplusrom")" ] || [ -n "$(find_prop "ro.oplus.version.myos")" ] || \
     [ -n "$(find_prop "ro.build.version.opporom")" ] || [ -d /my_manifest -o -d /my_product -o -d /my_stock ]; then
    os="coloros";
    os_string="OPlus / ColorOS / OxygenOS ROM";
else
    os="aosp";
    os_string="AOSP ROM";
fi;
ui_print "  -> $os_string is detected!";

## AnyKernel boot install
ui_print "  -> Flashing Kernel Image to boot...";
split_boot;
flash_boot;
## end boot install

# Vendor boot install (flashes matching DTB for universal compatibility across all ROMs)
if [ -f "$home/vendor_boot-files/dtb" -o -f "$home/dtb" ]; then
    ui_print "  -> Flashing Device Tree (DTB) to vendor_boot...";
    block=vendor_boot;
    is_slot_device=auto;
    ramdisk_compression=auto;
    patch_vbmeta_flag=auto;

    # reset for vendor_boot patching
    reset_ak;

    split_boot;
    flash_boot;
    ui_print "  -> vendor_boot DTB patched successfully!";
fi;
## end vendor_boot install

# Setup NKM Bypass permissions and profiles on boot (if Magisk / KernelSU exists)
if [ -d /data/adb ]; then
    mkdir -p /data/adb/service.d /data/adb/post-fs-data.d;
    rm -f /data/adb/post-fs-data.d/00_early_adb.sh 2>/dev/null;
    rm -f /data/adb/post-fs-data.d/00_maple.sh 2>/dev/null;

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

# Battery & charging sysfs permissions
chmod 664 /sys/class/power_supply/battery/input_suspend 2>/dev/null
chmod 664 /sys/class/power_supply/battery/bypass_charging 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_limit_current 2>/dev/null
chmod 644 /sys/class/power_supply/battery/battery_health 2>/dev/null
chmod 644 /sys/class/power_supply/battery/battery_cycle_count 2>/dev/null
chmod 664 /sys/class/power_supply/battery/battery_charging_enabled 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_enabled 2>/dev/null

# Kernel tweak nodes permissions (controlled by user via Ki-Kernel Settings module)
chmod 666 /dev/ntsync 2>/dev/null
chmod 666 /sys/devices/platform/kcal_ctrl.0/* 2>/dev/null
chmod 666 /sys/kernel/ki_profile/* 2>/dev/null
chmod 666 /proc/ki_profile 2>/dev/null
chmod 666 /sys/kernel/mm/lru_gen/* 2>/dev/null
chmod 666 /proc/mglru 2>/dev/null
chmod 666 /proc/bypass_charging 2>/dev/null
chmod 666 /sys/kernel/dyn_fsync/* 2>/dev/null
chmod 666 /sys/module/sync/parameters/fsync_enabled 2>/dev/null
chmod 666 /sys/kernel/gpu/* 2>/dev/null
chmod 666 /sys/touchpanel/double_tap 2>/dev/null
chmod 666 /sys/touchpanel/reversed_keys 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/dimming 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/dc_dimming 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/disp_param 2>/dev/null
chmod 666 /sys/devices/platform/soc/soc:qcom,dsi-display-primary/* 2>/dev/null
chmod 666 /sys/devices/virtual/mi_display/disp_feature/disp-DSI-*/disp_param 2>/dev/null
chmod 666 /sys/devices/virtual/mi_display/disp_feature/disp-DSI-*/dimming 2>/dev/null
chmod 666 /sys/block/zram0/comp_algorithm 2>/dev/null

# Fast charge nodes permission
chmod 666 /sys/class/power_supply/battery/screen_on_fast_charge 2>/dev/null
chmod 666 /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null
chmod 666 /sys/class/power_supply/battery/force_fast_charge 2>/dev/null
chmod 666 /sys/kernel/fast_charge/force_fast_charge 2>/dev/null
chmod 666 /sys/class/power_supply/usb/pd_authentication 2>/dev/null
chmod 666 /sys/class/power_supply/battery/fastcharge_mode 2>/dev/null
chmod 666 /sys/class/power_supply/bms/fastcharge_mode 2>/dev/null
chmod 666 /sys/class/power_supply/bms/authentic 2>/dev/null

# Wakelock blocker permissions
chmod 666 /sys/kernel/wakelock_blocker/* 2>/dev/null
chmod 666 /sys/class/misc/boeffla_wakelock_blocker/* 2>/dev/null
chmod 666 /sys/devices/virtual/misc/boeffla_wakelock_blocker/* 2>/dev/null

# OPlus / ColorOS / OxygenOS stub & project nodes permissions
chmod 644 /proc/oplusVersion/* 2>/dev/null
chmod 644 /proc/oplus_charger/* 2>/dev/null
chmod 666 /proc/theiaPwkReport 2>/dev/null
chmod 666 /proc/bootprof 2>/dev/null
chmod 666 /proc/storage/buf_log 2>/dev/null
chmod 666 /proc/oplus_storage/io_metrics/forever/* 2>/dev/null
chmod 666 /proc/oplus_scheduler/sched_assist/* 2>/dev/null
chmod 666 /proc/oplus_scheduler/sched_assist/audio/* 2>/dev/null
chmod 666 /proc/oplus_frame_boost/* 2>/dev/null
chmod 666 /proc/oplus_binder/* 2>/dev/null
chmod 666 /proc/sys/fbg/* 2>/dev/null
chmod 666 /proc/oplus_afs_config/afs_config 2>/dev/null
chmod 666 /proc/oplus_mem/memory_monitor 2>/dev/null
chmod 666 /proc/devinfo/lcd* 2>/dev/null
chmod 666 /sys/class/oplus_chg/*/* 2>/dev/null

EOF
    chmod 755 /data/adb/service.d/00_nkm_bypass.sh
    ui_print "  -> NKM and Ki-Kernel permissions configured!";
fi;
