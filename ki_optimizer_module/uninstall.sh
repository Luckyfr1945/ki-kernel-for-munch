#!/system/bin/sh
# Ki-Optimizer Uninstaller script
/data/adb/modules/ki_optimizer/bin/ki-charge-limit off >/dev/null 2>&1
# Saved logs in /data/adb/ki_crashlog are kept for bug reports.
/data/adb/modules/ki_optimizer/bin/ki-crashlog off >/dev/null 2>&1
# Session logs in /sdcard/Download/Ki-NetLog are kept.
/data/adb/modules/ki_optimizer/bin/ki-netlog off >/dev/null 2>&1
# Without post-fs-data.sh the real model is back on the next boot.
rm -rf /data/adb/ki_spoof
rm -f /data/adb/ksu/bin/ki /data/adb/ap/bin/ki /data/adb/magisk/ki 2>/dev/null
