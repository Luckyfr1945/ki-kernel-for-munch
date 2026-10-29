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
patch_vbmeta_flag=auto;
NO_BLOCK_DISPLAY=1;

. tools/ak3-core.sh;

ui_print " ";
ui_print "  ===========================================";
ui_print "  |         Ki-Kernel v1.6.0 | munch        |";
ui_print "  |                                         |";
ui_print "  ===========================================";
ui_print " ";

# Pick kernel Image (E404 ROM Detection)
if [ -f "$AKHOME/kernels/miui/Image" ] || [ -f "$AKHOME/kernels/aosp/Image" ] || [ -f "$AKHOME/kernels/coloros/Image" ]; then
    IS_MIUI=0;
    IS_AOSP=0;
    IS_OPLUS=0;
    ROM_TYPE="";
    ROM_DETAIL="";

    # 1. Check for manual override flags
    if [ -f /tmp/aosp ] || [ -f /sdcard/aosp ] || [ -f /data/aosp ]; then
        IS_AOSP=1;
        ROM_TYPE="AOSP (Manual Override)";
    elif [ -f /tmp/miui ] || [ -f /tmp/hyperos ] || [ -f /sdcard/miui ] || [ -f /sdcard/hyperos ] || [ -f /data/miui ]; then
        IS_MIUI=1;
        ROM_TYPE="MIUI / HyperOS (Manual Override)";
    elif [ -f /tmp/oplus ] || [ -f /tmp/oos ] || [ -f /tmp/coloros ] || \
         [ -f /sdcard/oplus ] || [ -f /sdcard/coloros ] || [ -f /sdcard/oos ] || \
         [ -f /sdcard/Download/oplus ] || [ -f /sdcard/Download/coloros ] || \
         [ -f /data/oplus ] || [ -f /data/coloros ]; then
        IS_OPLUS=1;
        ROM_TYPE="ColorOS / OxygenOS (Manual Override)";
    fi;

    # 2. Single-variant package check
    if [ "$IS_AOSP" -eq 0 ] && [ "$IS_MIUI" -eq 0 ] && [ "$IS_OPLUS" -eq 0 ]; then
        if [ ! -f "$AKHOME/kernels/miui/Image" ] && [ -f "$AKHOME/kernels/aosp/Image" ]; then
            IS_AOSP=1;
            ROM_TYPE="AOSP / Custom ROM (Single-variant target)";
        elif [ -f "$AKHOME/kernels/miui/Image" ] && [ ! -f "$AKHOME/kernels/aosp/Image" ]; then
            IS_MIUI=1;
            ROM_TYPE="Xiaomi MIUI / HyperOS (Single-variant target)";
        elif [ -f "$AKHOME/kernels/coloros/Image" ] && [ ! -f "$AKHOME/kernels/aosp/Image" ] && [ ! -f "$AKHOME/kernels/miui/Image" ]; then
            IS_OPLUS=1;
            ROM_TYPE="ColorOS / OxygenOS (Single-variant target)";
        fi;
    fi;

    # 3. Auto Configuration ROM Detection
    if [ "$IS_AOSP" -eq 0 ] && [ "$IS_MIUI" -eq 0 ] && [ "$IS_OPLUS" -eq 0 ]; then
        # Mount system, vendor, product, and my_product if available in recovery
        mount -o ro /system_root 2>/dev/null || mount /system_root 2>/dev/null || mount -o ro /system 2>/dev/null || mount /system 2>/dev/null;
        mount -o ro /vendor 2>/dev/null || mount /vendor 2>/dev/null;
        mount -o ro /product 2>/dev/null || mount /product 2>/dev/null;
        mount -o ro /my_product 2>/dev/null || mount /my_product 2>/dev/null;

        # Oplus / ColorOS / OxygenOS Port ROM detection
        # Must check BEFORE MIUI because ColorOS ports on Xiaomi devices retain stock Xiaomi vendor props!
        oplus=0;

        # 1. Check recovery / system props
        sys_fp="$(getprop ro.system.build.fingerprint 2>/dev/null)";
        [ -z "$sys_fp" ] && sys_fp="$(getprop ro.build.fingerprint 2>/dev/null)";
        case "$sys_fp" in
            *oplus*|*coloros*|*oxygen*|*realme*|*oppo*) oplus=1 ;;
        esac;

        # 2. Check getprop dump for any oplus / coloros indicators
        if [ "$oplus" -eq 0 ]; then
            if getprop 2>/dev/null | grep -iqE "oplus|coloros|oxygen|my_product"; then
                oplus=1;
            fi;
        fi;

        # 3. Check filesystem markers in system_root / root / vendor / data
        if [ "$oplus" -eq 0 ]; then
            if [ -d /system_root/my_product ] || [ -d /my_product ] || \
               [ -d /system_root/my_manifest ] || [ -d /system_root/my_heytap ] || \
               [ -d /system_root/my_bigball ] || [ -d /system_root/my_reserve ] || \
               [ -f /vendor/OemPorts10T.prop ] || [ -f /vendor/etc/init/OemPorts10T.rc ] || \
               [ -f /vendor/OemPorts.prop ] || [ -f /vendor/etc/init/OemPorts.rc ] || \
               [ -d /data/data/com.oplus.safecenter ] || [ -d /data/data/com.coloros.phonemanager ] || \
               [ -d /data/data/oplus ] || [ -f /data/oplusbootstats ] || [ -d /data/oplus_lib ] || \
               [ -d /data/data/com.oplus.camera ] || [ -d /data/persist_log/oplusreserve ] || \
               [ -d /vendor/oplus ] || [ -d /vendor/euclid/oplus ] || \
               grep -iqE "coloros|oplus|oxygen|realme" /system_root/system/build.prop 2>/dev/null || \
               grep -iqE "coloros|oplus|oxygen|realme" /system/build.prop 2>/dev/null || \
               grep -iqE "coloros|oplus|oxygen|realme" /system_root/my_product/build.prop 2>/dev/null || \
               grep -iqE "coloros|oplus" /vendor/build.prop 2>/dev/null; then
                oplus=1;
            fi;
        fi;

        if [ "$oplus" -eq 1 ]; then
            ui_print "--> Oplus Port ROM detected, configuring...";
            IS_OPLUS=1;
            ROM_TYPE="OPlus Port (ColorOS / OxygenOS / RealmeUI)";
            ROM_DETAIL="ColorOS / OxygenOS / RealmeUI";
        else
            # MIUI / HyperOS region detection (E404 method)
            miprops="$(file_getprop /vendor/build.prop "ro.vendor.miui.build.region" 2>/dev/null)";
            if [ -z "$miprops" ]; then
                miprops="$(file_getprop /product/etc/build.prop "ro.miui.build.region" 2>/dev/null)";
            fi;
            if [ -z "$miprops" ]; then
                miprops="$(getprop ro.vendor.miui.build.region 2>/dev/null)";
            fi;
            if [ -z "$miprops" ]; then
                miprops="$(getprop ro.miui.build.region 2>/dev/null)";
            fi;

            case "$miprops" in
                cn|in|ru|id|eu|tr|tw|gb|global|mx|jp|kr|lm|cl|mi)
                    ui_print "--> Miui/HyperOS ROM detected, configuring...";
                    IS_MIUI=1;
                    ROM_TYPE="Xiaomi MIUI / HyperOS";
                    ROM_DETAIL="Region: $miprops";
                    ;;
                *)
                    ui_print "--> AOSP/CLO ROM detected, configuring...";
                    IS_AOSP=1;
                    ROM_TYPE="AOSP / Custom ROM";
                    ;;
            esac;
        fi;
    fi;


    # Apply selected kernel Image and matching DTB
    ui_print "-------------------------------------------";
    if [ "$IS_OPLUS" -eq 1 ]; then
        ui_print "- Detected ROM : ColorOS / OxygenOS Port";
        [ -n "$ROM_DETAIL" ] && ui_print "  Profile      : $ROM_DETAIL";
        ui_print "- Target Kernel: ColorOS / OPlus";
        rom_arg="rom_port";
        if [ -f "$AKHOME/kernels/coloros/Image" ]; then
            cp -f "$AKHOME/kernels/coloros/Image" "$AKHOME/Image";
            [ -f "$AKHOME/kernels/coloros/dtb" ] && cp -f "$AKHOME/kernels/coloros/dtb" "$AKHOME/dtb_vendor";
        else
            cp -f "$AKHOME/kernels/miui/Image" "$AKHOME/Image";
            [ -f "$AKHOME/kernels/miui/dtb" ] && cp -f "$AKHOME/kernels/miui/dtb" "$AKHOME/dtb_vendor";
        fi;
    elif [ "$IS_MIUI" -eq 1 ] && [ "$IS_AOSP" -eq 0 ]; then
        if [ -f "$AKHOME/kernels/miui/Image" ]; then
            rom_arg="rom_oem";
            ui_print "- Detected ROM : ${ROM_TYPE:-MIUI / HyperOS}";
            [ -n "$ROM_DETAIL" ] && ui_print "  Profile      : $ROM_DETAIL";
            ui_print "- Target Kernel: MIUI / HyperOS";
            cp -f "$AKHOME/kernels/miui/Image" "$AKHOME/Image";
            [ -f "$AKHOME/kernels/miui/dtb" ] && cp -f "$AKHOME/kernels/miui/dtb" "$AKHOME/dtb_vendor";
        else
            abort "! Wrong package: this zip is AOSP only.";
        fi;
    elif [ "$IS_AOSP" -eq 1 ]; then
        if [ -f "$AKHOME/kernels/aosp/Image" ]; then
            rom_arg="rom_aosp";
            ui_print "- Detected ROM : AOSP / Custom ROM";
            [ -n "$ROM_DETAIL" ] && ui_print "  Profile      : $ROM_DETAIL";
            ui_print "- Target Kernel: AOSP";
            cp -f "$AKHOME/kernels/aosp/Image" "$AKHOME/Image";
            [ -f "$AKHOME/kernels/aosp/dtb" ] && cp -f "$AKHOME/kernels/aosp/dtb" "$AKHOME/dtb_vendor";
        else
            abort "! Wrong package: this zip is MIUI only.";
        fi;
    fi;
    ui_print "-------------------------------------------";
elif [ -f "$AKHOME/kernels/Image" ]; then
    rom_arg="rom_port";
    cp -f "$AKHOME/kernels/Image" "$AKHOME/Image";
    [ -f "$AKHOME/kernels/dtb" ] && cp -f "$AKHOME/kernels/dtb" "$AKHOME/dtb_vendor";
elif [ -f "$AKHOME/Image" ]; then
    rom_arg="${rom_arg:-rom_port}";
    [ -f "$AKHOME/kernels/dtb" ] && cp -f "$AKHOME/kernels/dtb" "$AKHOME/dtb_vendor";
fi;

# ----------------------------------------------------
# Interactive GPU & Voltage Profile Selector
# (Runs BEFORE flashing boot or vendor_boot)
# ----------------------------------------------------
CHOSEN_DTB="";

if [ -f "$AKHOME/dtb_oc" ] && [ -f "$AKHOME/dtb_stock" ]; then
    IS_RECOVERY=0;
    if [ "$BOOTMODE" = "false" ] || [ -z "$BOOTMODE" ] || [ -d /twres ] || [ -d /sbin ] || [ -f /sbin/recovery ] || grep -q "recovery" /proc/cmdline 2>/dev/null; then
        IS_RECOVERY=1;
    fi;

    TIMEOUT_CMD="";
    if command -v timeout >/dev/null 2>&1; then
        TIMEOUT_CMD="timeout";
    elif [ -x "$AKHOME/tools/busybox" ] && "$AKHOME/tools/busybox" timeout --help >/dev/null 2>&1; then
        TIMEOUT_CMD="$AKHOME/tools/busybox timeout";
    elif command -v busybox >/dev/null 2>&1 && busybox timeout --help >/dev/null 2>&1; then
        TIMEOUT_CMD="busybox timeout";
    fi;

    GETEVENT_CMD="";
    if command -v getevent >/dev/null 2>&1; then
        GETEVENT_CMD="getevent";
    elif [ -x /system/bin/getevent ]; then
        GETEVENT_CMD="/system/bin/getevent";
    elif [ -x /sbin/getevent ]; then
        GETEVENT_CMD="/sbin/getevent";
    fi;

    if [ "$IS_RECOVERY" -eq 1 ]; then
        ui_print " ";
        ui_print "----------------------------------------";
        ui_print " Profil GPU & Voltase:";
        ui_print "   (Vol +) OC + UV (683 MHz, Undervolt)";
        ui_print "   (Vol -) Stock   (670 MHz, Safe Volt)";
        ui_print "----------------------------------------";
        ui_print " Menunggu input tombol (timeout 15 detik, default: OC)...";

        CHOSEN_DTB="oc";
        KEYCHECK_BIN="";
        if [ -x "$AKHOME/tools/keycheck" ]; then
            KEYCHECK_BIN="$AKHOME/tools/keycheck";
        elif [ -x /tmp/keycheck ]; then
            KEYCHECK_BIN="/tmp/keycheck";
        fi;

        if [ -n "$KEYCHECK_BIN" ]; then
            timeout 15 "$KEYCHECK_BIN";
            res=$?;
            if [ $res -eq 42 ]; then
                ui_print "  Selected : OC + Undervolt (683 MHz)" " ";
                CHOSEN_DTB="oc";
            elif [ $res -eq 41 ]; then
                ui_print "  Selected : Stock Default (670 MHz)" " ";
                CHOSEN_DTB="stock";
            else
                ui_print "  ! Timeout reached, memakai default: OC + Undervolt (683 MHz)" " ";
                CHOSEN_DTB="oc";
            fi;
        else
            timeout=15;
            start=$(date +%s 2>/dev/null || echo 0);

            while :; do
                key_event=$(timeout 0.2 getevent -qlc 1 2>/dev/null);

                if [ -n "$key_event" ]; then
                    if echo "$key_event" | grep -qiE "KEY_VOLUMEUP|0073"; then
                        ui_print "  Selected : OC + Undervolt (683 MHz)" " ";
                        CHOSEN_DTB="oc";
                        break;
                    fi;

                    if echo "$key_event" | grep -qiE "KEY_VOLUMEDOWN|0072"; then
                        ui_print "  Selected : Stock Default (670 MHz)" " ";
                        CHOSEN_DTB="stock";
                        break;
                    fi;
                fi;

                now=$(date +%s 2>/dev/null || echo 0);
                if [ "$start" -gt 0 ] && [ "$now" -gt 0 ] && [ $((now - start)) -ge $timeout ]; then
                    ui_print "  ! Timeout reached, memakai default: OC + Undervolt (683 MHz)" " ";
                    CHOSEN_DTB="oc";
                    break;
                fi;
            done;
        fi;
    else
        # Flashing dari Android menyala (KernelSU / Magisk / FKM app)
        ui_print " -> Flashing via App (non-recovery): Memakai default OC + Undervolt (683 MHz)";
        CHOSEN_DTB="oc";
    fi;
fi;

# Apply chosen DTB to vendor_boot
if [ "$CHOSEN_DTB" = "stock" ] && [ -f "$AKHOME/dtb_stock" ]; then
    cp -f "$AKHOME/dtb_stock" "$AKHOME/dtb_vendor";
elif [ -f "$AKHOME/dtb_oc" ]; then
    cp -f "$AKHOME/dtb_oc" "$AKHOME/dtb_vendor";
elif [ -f "$AKHOME/dtb_stock" ]; then
    cp -f "$AKHOME/dtb_stock" "$AKHOME/dtb_vendor";
fi;

# Preserve existing single-kernel dtb for vendor_boot before clearing boot dtb
if [ ! -f "$AKHOME/dtb_vendor" ] && [ -f "$AKHOME/dtb" ]; then
    cp -f "$AKHOME/dtb" "$AKHOME/dtb_vendor";
fi;

# DO NOT touch DTBO (preserve panel/touch drivers from ROM)
# Remove dtb from boot flashing stage (DTB on SM8250 belongs in vendor_boot)
rm -f "$AKHOME/dtb" "$AKHOME/dtbo.img" "$AKHOME/dtbo" 2>/dev/null;

# Verify that target Image exists before proceeding with flash
[ -f "$AKHOME/Image" ] || abort "  ! Image tidak ditemukan di $AKHOME (cek folder kernels/ dan paket AnyKernel3)";

# 1. Flash Kernel Image to boot partition with e404 dynamic cmdline
ui_print "- Flashing kernel (boot)...";
split_boot;
patch_cmdline "e404_args" "e404_args=${rom_arg:-rom_port},dtbo_oem,dtb_def,batt_def";
flash_boot;

# 2. Flash DTB to vendor_boot partition
if [ -f "$AKHOME/dtb_vendor" ]; then
    ui_print "- Flashing DTB (vendor_boot)...";
    BLOCK=vendor_boot;
    reset_ak;
    rm -f "$AKHOME/Image";
    cp -f "$AKHOME/dtb_vendor" "$AKHOME/dtb";
    split_boot;
    flash_boot;
    rm -f "$AKHOME/dtb" "$AKHOME/dtb_vendor" "$AKHOME/dtb_oc" "$AKHOME/dtb_stock" 2>/dev/null;
fi;

# Setup NKM Bypass permissions and profiles on boot (if Magisk / KernelSU exists)
if [ -d /data/adb ]; then
    mkdir -p /data/adb/service.d /data/adb/post-fs-data.d;
    rm -f /data/adb/post-fs-data.d/00_early_adb.sh /data/adb/post-fs-data.d/00_maple.sh 2>/dev/null;

    cat << 'EOF' > /data/adb/service.d/00_nkm_bypass.sh
#!/system/bin/sh
SEPOLICY_CMD=""
if [ -x /data/adb/ksud ]; then
    SEPOLICY_CMD="/data/adb/ksud sepolicy patch"
elif [ -x /data/adb/ksu/bin/ksud ]; then
    SEPOLICY_CMD="/data/adb/ksu/bin/ksud sepolicy patch"
elif [ -x /data/adb/magisk/magiskpolicy ]; then
    SEPOLICY_CMD="/data/adb/magisk/magiskpolicy --live"
elif command -v magiskpolicy >/dev/null 2>&1; then
    SEPOLICY_CMD="magiskpolicy --live"
fi

if [ -n "$SEPOLICY_CMD" ]; then
    $SEPOLICY_CMD "allow untrusted_app vendor_sysfs_battery_supply dir { search read getattr open }" 2>/dev/null
    $SEPOLICY_CMD "allow untrusted_app vendor_sysfs_battery_supply file { read getattr open }" 2>/dev/null
    $SEPOLICY_CMD "allow untrusted_app_all vendor_sysfs_battery_supply dir { search read getattr open }" 2>/dev/null
    $SEPOLICY_CMD "allow untrusted_app_all vendor_sysfs_battery_supply file { read getattr open }" 2>/dev/null
    $SEPOLICY_CMD "allow system_app sysfs_ro file { read open getattr }" 2>/dev/null
    $SEPOLICY_CMD "allow hal_displayfeature_xiaomi_default vendor_default_prop property_service set" 2>/dev/null
    $SEPOLICY_CMD "allow platform_app vendor_display_prop file { read open getattr }" 2>/dev/null
    $SEPOLICY_CMD "allow vendor_hal_perf_default system_server dir search" 2>/dev/null
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
chmod 666 /sys/kernel/ki_profile/* 2>/dev/null
chmod 666 /dev/ntsync 2>/dev/null
chmod 666 /sys/devices/platform/kcal_ctrl.0/* 2>/dev/null
chmod 666 /sys/kernel/mm/lru_gen/* 2>/dev/null
chmod 666 /proc/mglru 2>/dev/null
chmod 664 /proc/bypass_charging 2>/dev/null
chmod 664 /sys/kernel/dyn_fsync/* 2>/dev/null
chmod 664 /sys/module/sync/parameters/fsync_enabled 2>/dev/null
chmod 666 /sys/kernel/gpu/gpu_governor 2>/dev/null
chmod 666 /sys/kernel/gpu/gpu_force_683 2>/dev/null
chmod 666 /sys/kernel/gpu/gpu_clocks 2>/dev/null
chmod 666 /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
chmod 666 /sys/class/kgsl/kgsl-3d0/min_clock_mhz 2>/dev/null
chmod 666 /sys/class/kgsl/kgsl-3d0/idle_timer 2>/dev/null
chmod 666 /sys/touchpanel/double_tap 2>/dev/null
chmod 666 /sys/touchpanel/reversed_keys 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/dimming 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/dc_dimming 2>/dev/null
chmod 666 /sys/class/drm/card0-DSI-*/disp_param 2>/dev/null
chmod 666 /sys/devices/platform/soc/soc:qcom,dsi-display-primary/disp_param 2>/dev/null
chmod 666 /sys/devices/platform/soc/soc:qcom,dsi-display-primary/dimming 2>/dev/null
chmod 666 /sys/devices/platform/soc/soc:qcom,dsi-display-primary/dc_dimming 2>/dev/null
chmod 666 /sys/devices/platform/soc/soc:qcom,dsi-display-primary/hbm 2>/dev/null
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
chmod 666 /sys/kernel/wakelock_blocker/wake_lock 2>/dev/null
chmod 666 /sys/kernel/wakelock_blocker/debug 2>/dev/null
chmod 666 /sys/class/misc/boeffla_wakelock_blocker/wakelock_blocker 2>/dev/null
chmod 666 /sys/class/misc/boeffla_wakelock_blocker/debug 2>/dev/null
chmod 666 /sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker 2>/dev/null

# OPlus / ColorOS / OxygenOS stub nodes permissions
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
    if [ -f /data/adb/service.d/00_nkm_bypass.sh ]; then
        chmod 755 /data/adb/service.d/00_nkm_bypass.sh;
        ui_print "- Configuring security & bypass nodes...";
    fi;
fi;

ui_print " ";
ui_print "- Done! Reboot and enjoy.";
ui_print " ";
