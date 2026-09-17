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
     [ -d /system/priv-app/MiuiSystemUI -o -d /system_root/system/priv-app/MiuiSystemUI -o -d /system/system/priv-app/MiuiSystemUI ] || \
     [ -f /system/framework/miui.jar -o -f /system_root/system/framework/miui.jar ]; then
    os="miui";
    if [ -n "$miui_ver" ]; then
        os_string="Xiaomi MIUI ($miui_ver)";
    else
        os_string="Xiaomi MIUI ROM";
    fi;
elif case "$userflavor" in *missi*|*qssi*) true;; *) false;; esac; then
    os="miui";
    os_string="Xiaomi MIUI ROM";
elif case "$userflavor" in aospa*) true;; *) false;; esac; then
    os="aospa";
    os_string="Paranoid Android (AOSPA) ROM";
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

# Setup bypass charging permissions and SELinux compatibility for NKM & battery managers
if [ -d /data/adb/service.d ]; then
    cat << 'EOF' > /data/adb/service.d/00_nkm_bypass.sh
#!/system/bin/sh
/data/adb/ksu/bin/ksud sepolicy patch "allow untrusted_app vendor_sysfs_battery_supply dir { search read getattr open }" 2>/dev/null
/data/adb/ksu/bin/ksud sepolicy patch "allow untrusted_app vendor_sysfs_battery_supply file { read getattr open }" 2>/dev/null
/data/adb/ksu/bin/ksud sepolicy patch "allow untrusted_app_all vendor_sysfs_battery_supply dir { search read getattr open }" 2>/dev/null
/data/adb/ksu/bin/ksud sepolicy patch "allow untrusted_app_all vendor_sysfs_battery_supply file { read getattr open }" 2>/dev/null
chmod 664 /sys/class/power_supply/battery/input_suspend 2>/dev/null
chmod 664 /sys/class/power_supply/battery/bypass_charging 2>/dev/null
chmod 664 /sys/class/power_supply/battery/battery_charging_enabled 2>/dev/null
chmod 664 /sys/class/power_supply/battery/charging_enabled 2>/dev/null
EOF
    chmod 755 /data/adb/service.d/00_nkm_bypass.sh
    ui_print "  -> Bypass charging NKM support configured!";
fi;
