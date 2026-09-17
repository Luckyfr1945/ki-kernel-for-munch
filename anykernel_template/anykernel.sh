# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers
# Universal SM8250 Direct Auto Installer for Ki-kernel

## AnyKernel setup
# begin properties
properties() { '
kernel.string=Ki-kernel Universal SM8250
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
'; } # end properties

# shell variables
block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;
no_block_display=1;

[ "$home" ] || home=$PWD;

## AnyKernel methods (DO NOT CHANGE)
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

ui_print " ";
ui_print "==============================";
ui_print "  Ki-kernel Universal SM8250  ";
ui_print "==============================";

# 1. Deteksi ROM Otomatis
hyperos_ver="$(find_prop "ro.mi.os.version.name")";
[ -z "$hyperos_ver" ] && hyperos_ver="$(find_prop "ro.mi.os.version.incremental")";
miui_ver="$(find_prop "ro.miui.ui.version.name")";
[ -z "$miui_ver" ] && miui_ver="$(find_prop "ro.miui.ui.version.code")";
build_inc="$(find_prop "ro.build.version.incremental")";

if [ -n "$hyperos_ver" ] || echo "$build_inc" | grep -qiE '^OS[0-9]'; then
    ROM_SHORT="HyperOS ($hyperos_ver)";
    ROM_CHOICE="miui";
elif [ -n "$miui_ver" ] || echo "$build_inc" | grep -qiE '^V[0-9]' || \
     [ -d /system/priv-app/MiuiSystemUI -o -d /system_root/system/priv-app/MiuiSystemUI ] || \
     [ -f /system/framework/miui.jar -o -f /system_root/system/framework/miui.jar ]; then
    ROM_SHORT="MIUI ($miui_ver)";
    ROM_CHOICE="miui";
else
    ROM_SHORT="AOSP / Custom ROM";
    ROM_CHOICE="aosp";
fi;

ui_print "* Device   : POCO F4 (munch)";
ui_print "* ROM      : $ROM_SHORT";
ui_print "* GPU      : 150MHz - 683MHz (OC + Underclock)";
ui_print "* Charging : Screen-On Fast Charge (Aktif)";
ui_print "------------------------------";

## Move kernel Image
if [ -f "$home/kernels/Image" ]; then
    mv -f "$home/kernels/Image" "$home/Image";
fi;

## Pilih DTB Extreme (150 - 683MHz OC + UV)
if [ -f "$home/dtbs/dtb_extreme" ]; then
    ui_print "-> Memasang DTB Optimal (150 - 683MHz OC + UV)...";
    cp -f "$home/dtbs/dtb_extreme" "$home/dtb";
elif [ -f "$home/dtbs/dtb_stock" ]; then
    ui_print "-> Memasang DTB Stock (305 - 670MHz)...";
    cp -f "$home/dtbs/dtb_stock" "$home/dtb";
elif [ -f "$home/kernels/dtb" ]; then
    mv -f "$home/kernels/dtb" "$home/dtb";
fi;

## AnyKernel boot install
ui_print "-> Flashing Kernel Image ke boot...";
split_boot;
flash_boot;
## end boot install

## Vendor boot install (flashes matching DTB ke vendor_boot)
if [ -f "$home/dtb" ]; then
    ui_print "-> Flashing Device Tree ke vendor_boot...";
    cp -f "$home/dtb" "$home/chosen_dtb";
    block=vendor_boot;
    is_slot_device=auto;
    ramdisk_compression=auto;
    patch_vbmeta_flag=auto;

    reset_ak;
    cp -f "$home/chosen_dtb" "$home/dtb";
    split_boot;
    flash_boot;
    rm -f "$home/chosen_dtb";
    ui_print "-> vendor_boot DTB berhasil diperbarui!";
fi;
## end vendor_boot install

# Setup NKM Bypass permissions, HyperOS fixes, and Fast Charge config on boot
if [ -d /data/adb/service.d ]; then
    cat << 'EOF' > /data/adb/service.d/00_nkm_bypass.sh
#!/system/bin/sh
# KernelSU SELinux live patches
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

# Bypass charging & current limit sysfs permissions
chmod 664 /sys/class/power_supply/battery/input_suspend 2>/dev/null
chmod 664 /sys/class/power_supply/battery/bypass_charging 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_limit_current 2>/dev/null
chmod 644 /sys/class/power_supply/battery/battery_health 2>/dev/null
chmod 644 /sys/class/power_supply/battery/battery_cycle_count 2>/dev/null
chmod 664 /sys/class/power_supply/battery/battery_charging_enabled 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_enabled 2>/dev/null

# Ki-kernel profile node permissions
chmod 666 /sys/kernel/ki_profile/mode 2>/dev/null
chmod 666 /sys/kernel/ki_profile/thermal_throttle 2>/dev/null

# Double Tap to Wake (DT2W) node permissions for AOSP
chmod 666 /sys/touchpanel/double_tap 2>/dev/null
chmod 666 /sys/touchpanel/reversed_keys 2>/dev/null

# Fast charge sysfs permissions and configuration
chmod 664 /sys/class/power_supply/battery/screen_on_fast_charge 2>/dev/null
chmod 664 /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null
chmod 664 /sys/class/power_supply/battery/force_fast_charge 2>/dev/null
chmod 664 /sys/kernel/fast_charge/force_fast_charge 2>/dev/null

echo 1 > /sys/class/power_supply/battery/screen_on_fast_charge 2>/dev/null
echo 1 > /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null

# Fix N0Kontzzz Manager FGS crash on Android 14/15 if installed
if pm list packages 2>/dev/null | grep -q id.nkz.nokontzzzmanager; then
    pm disable id.nkz.nokontzzzmanager/.service.BootRestoreService 2>/dev/null
fi

# UFS 3.1 storage read-ahead 1024KB for instant WuWa texture/mesh asset streaming
for q in /sys/block/sd*/queue; do
    echo 1024 > "$q/read_ahead_kb" 2>/dev/null
    echo 0 > "$q/add_random" 2>/dev/null
    echo 0 > "$q/iostats" 2>/dev/null
    echo 256 > "$q/nr_requests" 2>/dev/null
done

# VM Memory tuning to prevent traversal stutter / ZRAM churn
echo 80 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
echo 40 > /proc/sys/vm/swappiness 2>/dev/null
echo 15 > /proc/sys/vm/dirty_ratio 2>/dev/null
echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null

# Instant APK installation fix
setprop pm.dexopt.install quicken

EOF
    chmod 755 /data/adb/service.d/00_nkm_bypass.sh
fi;

ui_print " ";
ui_print "==============================";
ui_print " Ki-kernel Berhasil Terpasang!";
ui_print " Silakan Reboot System.";
ui_print "==============================";
