### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Ki-kernel AOSP for SM8250 (munch)

### AnyKernel setup
properties() { '
kernel.string=Ki-kernel
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

# Pick kernel Image (Advanced Multi-Stage ROM Detection)
if [ -f "$AKHOME/kernels/miui/Image" ] && [ -f "$AKHOME/kernels/aosp/Image" ]; then
    IS_MIUI=0;
    IS_AOSP=0;
    ROM_TYPE="";
    ROM_DETAIL="";

    # 1. Check for manual override flags
    if [ -f /tmp/aosp ] || [ -f /sdcard/aosp ] || [ -f /data/aosp ]; then
        IS_AOSP=1;
        ROM_TYPE="AOSP (Manual Override)";
    elif [ -f /tmp/miui ] || [ -f /sdcard/miui ] || [ -f /data/miui ]; then
        IS_MIUI=1;
        ROM_TYPE="MIUI / HyperOS (Manual Override)";
    fi;

    # 2. Check live getprop if available (flashed from booted Android via ksud / FK Kernel Manager)
    if [ "$IS_AOSP" -eq 0 ] && [ "$IS_MIUI" -eq 0 ]; then
        if command -v getprop >/dev/null 2>&1; then
            OS_NAME=$(getprop ro.mi.os.version.name 2>/dev/null);
            MIUI_NAME=$(getprop ro.miui.ui.version.name 2>/dev/null);
            BUILD_INC=$(getprop ro.build.version.incremental 2>/dev/null);
            SYS_NAME=$(getprop ro.product.system.name 2>/dev/null);
            SYS_MODEL=$(getprop ro.product.system.model 2>/dev/null);

            if [ -n "$OS_NAME" ] || echo "$BUILD_INC" | grep -q -E "^OS[0-9]"; then
                IS_MIUI=1;
                ROM_TYPE="Xiaomi HyperOS";
                ROM_DETAIL="${OS_NAME:-$BUILD_INC}";
            elif [ -n "$MIUI_NAME" ] || echo "$BUILD_INC" | grep -q -E "^V[0-9]"; then
                IS_MIUI=1;
                ROM_TYPE="Xiaomi MIUI";
                ROM_DETAIL="${MIUI_NAME:-$BUILD_INC}";
            elif [ -n "$SYS_NAME" ] || [ -n "$SYS_MODEL" ]; then
                IS_AOSP=1;
                ROM_TYPE="AOSP / Custom ROM";
                ROM_DETAIL="${SYS_NAME:-$SYS_MODEL}";
            fi;
        fi;
    fi;

    # 3. Recovery inspection with dynamic partition & A/B slot resolution
    if [ "$IS_AOSP" -eq 0 ] && [ "$IS_MIUI" -eq 0 ]; then
        # Detect active slot
        SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null);
        [ -z "$SLOT" ] && SLOT=$(grep -o 'androidboot\.slot_suffix=[^ ]*' /proc/cmdline 2>/dev/null | cut -d= -f2);

        # Mount system partition if not already mounted
        SYSTEM_MOUNTED=0;
        if [ ! -f /system/build.prop ] && [ ! -f /system/system/build.prop ] && [ ! -f /system_root/system/build.prop ]; then
            mkdir -p /s_chk 2>/dev/null;
            for dev in "/dev/block/mapper/system$SLOT" "/dev/block/mapper/system" \
                       "/dev/block/bootdevice/by-name/system$SLOT" "/dev/block/bootdevice/by-name/system"; do
                if [ -b "$dev" ]; then
                    mount -o ro "$dev" /s_chk 2>/dev/null && { SYSTEM_MOUNTED=1; break; };
                fi;
            done;
        fi;

        # Mount product partition if available for HyperOS detection
        PRODUCT_MOUNTED=0;
        if [ ! -f /product/build.prop ] && [ ! -f /product/etc/build.prop ]; then
            mkdir -p /p_chk 2>/dev/null;
            for dev in "/dev/block/mapper/product$SLOT" "/dev/block/mapper/product" \
                       "/dev/block/bootdevice/by-name/product$SLOT" "/dev/block/bootdevice/by-name/product"; do
                if [ -b "$dev" ]; then
                    mount -o ro "$dev" /p_chk 2>/dev/null && { PRODUCT_MOUNTED=1; break; };
                fi;
            done;
        fi;

        # Check distinctive Xiaomi-exclusive hardware feature files (100% reliable)
        FEATURE_FILES="/s_chk/system/etc/device_features/munch.xml /s_chk/etc/device_features/munch.xml \
                       /system_root/system/etc/device_features/munch.xml /system/etc/device_features/munch.xml \
                       /p_chk/etc/device_features/munch.xml /product/etc/device_features/munch.xml";
        for f in $FEATURE_FILES; do
            if [ -f "$f" ]; then
                IS_MIUI=1;
                ROM_TYPE="Xiaomi MIUI / HyperOS (device_features verified)";
                break;
            fi;
        done;

        # Check Xiaomi proprietary app structures
        if [ "$IS_MIUI" -eq 0 ]; then
            MIUI_DIRS="/s_chk/system/priv-app/MiuiSystemUI /s_chk/priv-app/MiuiSystemUI \
                       /system_root/system/priv-app/MiuiSystemUI /system/priv-app/MiuiSystemUI \
                       /p_chk/priv-app/MiuiSystemUI /product/priv-app/MiuiSystemUI \
                       /s_chk/system/framework/miui.jar /system_root/system/framework/miui.jar";
            for d in $MIUI_DIRS; do
                if [ -e "$d" ]; then
                    IS_MIUI=1;
                    ROM_TYPE="Xiaomi MIUI / HyperOS (framework verified)";
                    break;
                fi;
            done;
        fi;

        # Parse build.prop files across all standard partitions
        PROP_LIST="/system_root/system/build.prop /system/system/build.prop /system/build.prop /system/etc/build.prop \
                   /s_chk/system/build.prop /s_chk/build.prop /s_chk/etc/build.prop \
                   /p_chk/etc/build.prop /p_chk/build.prop /product/etc/build.prop /product/build.prop \
                   /vendor/build.prop /vendor/etc/build.prop";

        # Check HyperOS / MIUI signature props (including E404 region detection)
        if [ "$IS_MIUI" -eq 0 ]; then
            for prop in $PROP_LIST; do
                if [ -f "$prop" ]; then
                    HOS_VAL=$(grep -E "^ro\.mi\.os\.version\.name=" "$prop" 2>/dev/null | head -n 1 | cut -d= -f2);
                    MIUI_VAL=$(grep -E "^ro\.miui\.ui\.version\.name=" "$prop" 2>/dev/null | head -n 1 | cut -d= -f2);
                    INC_VAL=$(grep -E "^ro\.build\.version\.incremental=" "$prop" 2>/dev/null | head -n 1 | cut -d= -f2);
                    REGION_VAL=$(grep -E "^ro\.(vendor\.)?miui\.build\.region=" "$prop" 2>/dev/null | head -n 1 | cut -d= -f2);

                    if [ -n "$HOS_VAL" ] || echo "$INC_VAL" | grep -q -E "^OS[0-9]"; then
                        IS_MIUI=1;
                        ROM_TYPE="Xiaomi HyperOS";
                        ROM_DETAIL="${HOS_VAL:-$INC_VAL}";
                        break;
                    elif [ -n "$MIUI_VAL" ] || echo "$INC_VAL" | grep -q -E "^V[0-9]"; then
                        IS_MIUI=1;
                        ROM_TYPE="Xiaomi MIUI";
                        ROM_DETAIL="${MIUI_VAL:-$INC_VAL}";
                        break;
                    elif case "$REGION_VAL" in cn|in|ru|id|eu|tr|tw|gb|global|mx|jp|kr|lm|cl|mi) true;; *) false;; esac; then
                        IS_MIUI=1;
                        ROM_TYPE="Xiaomi MIUI / HyperOS";
                        ROM_DETAIL="Region: $REGION_VAL";
                        break;
                    fi;
                fi;
            done;
        fi;

        # Check distinctive AOSP / Custom ROM signature props
        if [ "$IS_MIUI" -eq 0 ]; then
            for prop in $PROP_LIST; do
                if [ -f "$prop" ]; then
                    AOSP_MATCH=$(grep -i -E "lineage|crdroid|evolution|pixel|arrow|havoc|aosp|corvus|spark|matrixx|rising|cherish|derp|paranoid|hentai|superior|axion|yaap|voltage|elixir" "$prop" 2>/dev/null | head -n 1);
                    if [ -n "$AOSP_MATCH" ]; then
                        IS_AOSP=1;
                        ROM_TYPE="AOSP / Custom ROM";
                        break;
                    fi;
                fi;
            done;
        fi;

        # Clean up temporary inspection mounts
        [ "$SYSTEM_MOUNTED" -eq 1 ] && { umount /s_chk 2>/dev/null; rm -rf /s_chk 2>/dev/null; };
        [ "$PRODUCT_MOUNTED" -eq 1 ] && { umount /p_chk 2>/dev/null; rm -rf /p_chk 2>/dev/null; };
    fi;

    # Apply selected kernel Image and matching DTB
    ui_print "--------------------------------------";
    if [ "$IS_MIUI" -eq 1 ] && [ "$IS_AOSP" -eq 0 ]; then
        if [ -n "$ROM_DETAIL" ]; then
            ui_print "  -> ROM Detected : $ROM_TYPE ($ROM_DETAIL)";
        else
            ui_print "  -> ROM Detected : ${ROM_TYPE:-Xiaomi MIUI / HyperOS}";
        fi;
        ui_print "  -> Kernel Target: MIUI / HyperOS variant";
        cp -f "$AKHOME/kernels/miui/Image" "$AKHOME/Image";
        [ -f "$AKHOME/kernels/miui/dtb" ] && cp -f "$AKHOME/kernels/miui/dtb" "$AKHOME/dtb_vendor";
    else
        if [ -n "$ROM_DETAIL" ]; then
            ui_print "  -> ROM Detected : ${ROM_TYPE:-AOSP / Custom ROM} ($ROM_DETAIL)";
        else
            ui_print "  -> ROM Detected : ${ROM_TYPE:-AOSP / Custom ROM}";
        fi;
        ui_print "  -> Kernel Target: AOSP variant";
        cp -f "$AKHOME/kernels/aosp/Image" "$AKHOME/Image";
        [ -f "$AKHOME/kernels/aosp/dtb" ] && cp -f "$AKHOME/kernels/aosp/dtb" "$AKHOME/dtb_vendor";
    fi;
    ui_print "--------------------------------------";
elif [ -f "$AKHOME/kernels/miui/Image" ]; then
    ui_print "  -> Target: MIUI / HyperOS";
    cp -f "$AKHOME/kernels/miui/Image" "$AKHOME/Image";
    [ -f "$AKHOME/kernels/miui/dtb" ] && cp -f "$AKHOME/kernels/miui/dtb" "$AKHOME/dtb_vendor";
elif [ -f "$AKHOME/kernels/aosp/Image" ]; then
    ui_print "  -> Target: AOSP";
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
    mkdir -p /data/adb/service.d /data/adb/post-fs-data.d;
    rm -f /data/adb/post-fs-data.d/00_early_adb.sh;

    # Early boot storage scheduler tuning (runs before zygote)
    cat << 'EOF_MAPLE' > /data/adb/post-fs-data.d/00_maple.sh
#!/system/bin/sh
for q in /sys/block/sd*/queue/scheduler /sys/block/*/queue/scheduler; do
    [ -f "$q" ] && echo maple > "$q" 2>/dev/null
done
EOF_MAPLE
    chmod 755 /data/adb/post-fs-data.d/00_maple.sh

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
chmod 666 /sys/kernel/mm/lru_gen/* 2>/dev/null
chmod 666 /proc/mglru 2>/dev/null
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

# Fast charge nodes permission (allow NKM / Kernel Manager to control toggles without overriding to ON on boot)
chmod 666 /sys/class/power_supply/battery/screen_on_fast_charge 2>/dev/null
chmod 666 /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null
chmod 666 /sys/class/power_supply/battery/force_fast_charge 2>/dev/null
chmod 666 /sys/kernel/fast_charge/force_fast_charge 2>/dev/null
chmod 666 /sys/class/power_supply/usb/pd_authentication 2>/dev/null
chmod 666 /sys/class/power_supply/battery/fastcharge_mode 2>/dev/null
chmod 666 /sys/class/power_supply/bms/fastcharge_mode 2>/dev/null
chmod 666 /sys/class/power_supply/bms/authentic 2>/dev/null

echo 80 > /proc/sys/vm/swappiness 2>/dev/null
echo 80 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
chmod 666 /sys/class/misc/boeffla_wakelock_blocker/* 2>/dev/null
echo "wlan_pno_wl;wlan_extscan_wl;" > /sys/class/misc/boeffla_wakelock_blocker/wakelock_blocker 2>/dev/null

# LMKD Tuning (Anti-Kill Multitasking: kill single heaviest only on true OOM, prevent cache purge)
setprop sys.lmk.kill_heaviest_task true 2>/dev/null
setprop ro.lmk.kill_heaviest_task true 2>/dev/null
setprop ro.lmk.psi_partial_stall_ms 250 2>/dev/null
setprop ro.lmk.thrashing_limit 100 2>/dev/null

for q in /sys/block/*/queue/scheduler; do
    if [ -f "$q" ]; then
        echo maple > "$q" 2>/dev/null
    fi
done

# Ensure CPU idle floors allow full power saving when idle
echo 300000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 2>/dev/null

# Auto-enable MGLRU (override ROM init.rc 0 disable)
echo 1 > /proc/mglru 2>/dev/null
EOF
    chmod 755 /data/adb/service.d/00_nkm_bypass.sh
fi;

ui_print " ";
ui_print "- Done! Reboot to system.";
ui_print " ";
ui_print "- Enjoy this kernel feature.";
