#!/usr/bin/env bash
# ==============================================================================
# Ki-Kernel UI stutter test for munch
# Scrolls an app with scripted swipes and reports HWUI jank stats from
# `dumpsys gfxinfo`. With --profiles it repeats the run for every ki_profile
# mode and restores the original mode afterwards.
#
#   ./test_jank.sh [package=com.android.settings] [swipes=40] [--profiles]
#
# Keep the screen on and unlocked. Pick a scrollable app (Settings, Telegram).
# ==============================================================================
set -u

PKG=${1:-com.android.settings}
SWIPES=${2:-40}
ALL_PROFILES=0
[ "${3:-}" = "--profiles" ] && ALL_PROFILES=1
PROFILE_NODE=/sys/kernel/ki_profile/mode

root() { printf '%s\n' "$*" | timeout 20 adb shell su 2>/dev/null | tr -d '\r'; }
shell() { timeout 20 adb shell "$@" 2>/dev/null | tr -d '\r'; }

if [ -z "$(adb get-serialno 2>/dev/null)" ]; then
	echo "[!] No ADB device connected."
	exit 1
fi

run_once() {
	local label=$1
	shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
	sleep 2
	shell dumpsys gfxinfo "$PKG" reset >/dev/null
	for i in $(seq 1 "$SWIPES"); do
		if [ $((i % 2)) -eq 1 ]; then
			root cmd input swipe 540 1900 540 600 120
		else
			root cmd input swipe 540 600 540 1900 120
		fi
		sleep 0.25
	done
	echo "== $label | $(root "cat /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq" | tr '\n' ' ')(gold/prime max kHz) | batt $(root "cat /sys/class/power_supply/battery/temp")/10 C"
	shell dumpsys gfxinfo "$PKG" | grep -m 12 -E \
		"Total frames rendered|Janky frames|(50|90|95|99)th percentile|Number Missed Vsync|Number High input latency|Number Slow UI thread|Number Frame deadline missed"
}

if [ "$ALL_PROFILES" = 0 ]; then
	run_once "profile $(root "cat $PROFILE_NODE")"
	exit 0
fi

original=$(root "cat $PROFILE_NODE")
for mode in 0 1 2; do
	root "echo $mode > $PROFILE_NODE"
	sleep 3
	run_once "profile $mode"
done
root "echo $original > $PROFILE_NODE"
echo "restored ki_profile mode $original"
