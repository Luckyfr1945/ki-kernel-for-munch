#!/system/bin/sh
# Ki-Kernel Settings post-fs-data: runs before zygote starts.
MODDIR=${0%/*}

# Same Ki-Kernel check as service.sh, which is what clears the spoof boot
# guard; without it the guard would trip after two normal boots.
if ! uname -r | grep -qi "ki-kernel" && [ ! -f /proc/ki_profile ] && [ ! -d /sys/kernel/ki_profile ]; then
    exit 0
fi

# Opt-in device model spoof. Props must change before zygote caches Build.*.
[ -f /data/adb/ki_spoof/enabled ] && sh "$MODDIR/bin/ki-spoof" apply
