#!/system/bin/sh
# Ki-Daemon Boot Service

MODDIR="/data/adb/modules/ki_daemon"
CONF_PATH="/sdcard/ki_daemon.conf"

# Verify Ki-Kernel Support
KERNEL_VER="$(uname -r)"
if ! echo "$KERNEL_VER" | grep -qi "ki-kernel" && [ ! -f /proc/ki_profile ] && [ ! -d /sys/kernel/ki_profile ]; then
    exit 0
fi

# Wait until boot process is fully completed
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 3
done

# Ensure ki_daemon is linked in root PATH without touching /system
for bin_dir in /data/adb/ksu/bin /data/adb/ap/bin /data/adb/magisk; do
    if [ -d "$bin_dir" ]; then
        [ ! -e "$bin_dir/ki_daemon" ] && ln -sf "$MODDIR/bin/ki_daemon" "$bin_dir/ki_daemon" 2>/dev/null
    fi
done

# Sleep 5 seconds to ensure system settlement
sleep 5

# Ensure /sdcard/ki_daemon.conf exists
if [ ! -f "$CONF_PATH" ]; then
    cp -f "$MODDIR/ki_daemon.conf" "$CONF_PATH" 2>/dev/null
    chmod 666 "$CONF_PATH" 2>/dev/null
fi

# Launch Ki-Daemon (Rust Auto Game Turbo & Background Controller)
if [ -x "$MODDIR/bin/ki_daemon" ]; then
    killall ki_daemon 2>/dev/null
    rm -f /data/adb/modules/ki_daemon/daemon.pid /data/adb/modules/ki_daemon/daemon.status 2>/dev/null
    "$MODDIR/bin/ki_daemon" start >/dev/null 2>&1 || ( "$MODDIR/bin/ki_daemon" run >/dev/null 2>&1 & )
fi
