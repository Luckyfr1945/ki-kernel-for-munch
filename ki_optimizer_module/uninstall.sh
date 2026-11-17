#!/system/bin/sh
# Ki-Optimizer Uninstaller script
/data/adb/modules/ki_optimizer/bin/ki-charge-limit off >/dev/null 2>&1
rm -f /data/adb/ksu/bin/ki /data/adb/ap/bin/ki /data/adb/magisk/ki 2>/dev/null
