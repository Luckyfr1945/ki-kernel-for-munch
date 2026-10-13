#!/system/bin/sh
# Ki-Optimizer Boot Service

MODDIR="/data/adb/modules/ki_optimizer"
CONF_PATH="/sdcard/ki_optimizer.conf"
KERNEL_VER="$(uname -r)"

# Verify Ki-Kernel Support
is_ki=0
if echo "$KERNEL_VER" | grep -qi "ki-kernel"; then
    is_ki=1
elif [ -f /proc/ki_profile ] || [ -d /sys/kernel/ki_profile ]; then
    is_ki=1
fi

if [ "$is_ki" -eq 0 ]; then
    # Incompatible kernel detected! Automatically deactivate module
    if [ -f "$MODDIR/module.prop" ]; then
        sed -i 's/^name=.*/name=❌ Ki-Optimizer [INCOMPATIBLE]/' "$MODDIR/module.prop"
        sed -i 's|^description=.*|description=❌ [DEACTIVATED] Kernel '"$KERNEL_VER"' is NOT supported! This module strictly requires Ki-Kernel. Please re-flash Ki-Kernel to reactivate.|' "$MODDIR/module.prop"
    fi
    touch "$MODDIR/disable"
    exit 0
else
    # Ki-Kernel confirmed! Ensure active module metadata
    if [ -f "$MODDIR/module.prop" ]; then
        sed -i 's/^name=.*/name=Ki-Kernel Settings/' "$MODDIR/module.prop"
        sed -i 's|^description=.*|description=WebUI Controller for Ki-Kernel: Profile switcher, MGLRU, Bypass Charging, Fast Charge, Dynamic Fsync, Thermal Guard \& TCP BBR via KernelSU WebUI.|' "$MODDIR/module.prop"
    fi
    rm -f "$MODDIR/disable" 2>/dev/null
fi

# Wait until boot process is fully completed
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 3
done

# Sleep 5 seconds to ensure system settlement
sleep 5

# Ensure /sdcard/ki_optimizer.conf exists
if [ ! -f "$CONF_PATH" ]; then
    cp -f "$MODDIR/ki_optimizer.conf" "$CONF_PATH" 2>/dev/null
    chmod 666 "$CONF_PATH" 2>/dev/null
fi

# Ensure all Ki-Kernel tweak nodes have correct read/write permissions
chmod 666 /proc/ki_profile 2>/dev/null
chmod 666 /proc/mglru 2>/dev/null
chmod 666 /proc/bypass_charging 2>/dev/null
chmod 666 /sys/kernel/ki_profile/* 2>/dev/null
chmod 666 /sys/kernel/mm/lru_gen/* 2>/dev/null
chmod 666 /sys/kernel/fast_charge/* 2>/dev/null
chmod 666 /sys/kernel/dyn_fsync/* 2>/dev/null
chmod 666 /sys/class/power_supply/battery/bypass_charging 2>/dev/null
chmod 666 /sys/class/power_supply/battery/input_suspend 2>/dev/null

# Apply configured tweaks
if [ -x "$MODDIR/system/bin/ki" ]; then
    "$MODDIR/system/bin/ki" reload >/dev/null 2>&1
fi
