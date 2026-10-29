#!/system/bin/sh
# Ki-Daemon Uninstaller script
killall ki_daemon 2>/dev/null
rm -f /data/adb/ksu/bin/ki_daemon /data/adb/ap/bin/ki_daemon /data/adb/magisk/ki_daemon 2>/dev/null
rm -f /dev/ki_daemon.engaged 2>/dev/null
