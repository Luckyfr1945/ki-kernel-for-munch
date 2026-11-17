#!/usr/bin/env bash
# ==============================================================================
# Ki-Kernel fast reboot / power-off reproducer for munch (host side)
# Pushes scripts/ki_crashlog.sh + scripts/ki_stress.sh, runs the stress phase
# on the phone (detached, so USB/adb drops during suspend do not matter),
# watches boot_id to catch a reboot, then runs ki_logcheck.sh.
# Instead of waiting a whole night, ~10-30 minutes covers hundreds of
# suspend/resume, charger and screen transitions.
#
#   ./test_reboot_stress.sh [phase=all] [cycles=50] [sleep_sec=8]
#   phase: suspend | charger | screen | hotplug | all
# ==============================================================================
set -u

PHASE=${1:-all}
CYCLES=${2:-50}
SLEEP_SEC=${3:-8}
HERE=$(cd "$(dirname "$0")" && pwd)
POLL_SEC=5
REBOOT_WAIT_SEC=300
STRESS_LOG=/data/adb/ki_crashlog/stress.log

root() { printf '%s\n' "$*" | timeout 20 adb shell su 2>/dev/null | tr -d '\r'; }
boot_id() { timeout 10 adb shell cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r'; }

if [ -z "$(adb get-serialno 2>/dev/null)" ]; then
	echo "[!] No ADB device connected."
	exit 1
fi
if [ "$(root id -u)" != "0" ]; then
	echo "[!] No root: grant Superuser to 'Shell' in KernelSU Manager."
	exit 1
fi

adb push "$HERE/scripts/ki_crashlog.sh" /data/local/tmp/ki_crashlog.sh >/dev/null
adb push "$HERE/scripts/ki_stress.sh" /data/local/tmp/ki_stress.sh >/dev/null
root "sh /data/local/tmp/ki_crashlog.sh start; rm -f $STRESS_LOG"
# run as root only from a root-owned copy (/data/local/tmp is shell-writable)
root "cp -f /data/local/tmp/ki_stress.sh /data/adb/ki_stress.sh && chmod 700 /data/adb/ki_stress.sh && rm -f /data/local/tmp/ki_stress.sh"
root "nohup sh /data/adb/ki_stress.sh $PHASE $CYCLES $SLEEP_SEC >/dev/null 2>&1 &"

BOOT_ID=$(boot_id)
echo "[*] stress '$PHASE' x$CYCLES running on phone (boot_id ${BOOT_ID:0:8}); Ctrl-C stops watching only"
if [ "$PHASE" != "hotplug" ] && [ "$(root cat /sys/class/power_supply/usb/online)" = 1 ]; then
	echo "[!] USB to this PC blocks deep sleep: UNPLUG the cable within 30s (wall charger is OK)."
	echo "    Plug it back after ~$(( CYCLES * (SLEEP_SEC + 3) / 60 + 1 )) min per phase; this script keeps waiting."
fi

while true; do
	sleep "$POLL_SEC"
	id=$(boot_id)
	if [ -z "$id" ]; then
		continue	# phone suspended or USB re-enumerating
	fi
	if [ "$id" != "$BOOT_ID" ]; then
		echo
		echo "[!!] PHONE REBOOTED during stress. Waiting for boot to complete..."
		timeout "$REBOOT_WAIT_SEC" adb wait-for-device
		until [ "$(timeout 5 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; done
		# the logger is not persistent: start it once so it archives the crashed boot
		root "sh /data/local/tmp/ki_crashlog.sh start"
		sleep 3
		echo "[*] last stress steps before the reboot:"
		root "tail -n 5 $STRESS_LOG"
		"$HERE/ki_logcheck.sh"
		exit 2
	fi
	last=$(root "tail -n 1 $STRESS_LOG")
	printf '\r%-110s' "${last:0:110}"
	case "$last" in
	*DONE*|*ABORTED*)
		echo
		echo "[*] stress finished without reboot"
		"$HERE/ki_logcheck.sh"
		exit 0
		;;
	esac
done
