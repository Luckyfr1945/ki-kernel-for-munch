#!/usr/bin/env bash
# ==============================================================================
# Ki-Kernel Sleep-of-Death / wake-freeze / silent-reboot test for munch
# Each cycle: screen off -> forced Doze -> sleep -> notification + wake ->
# check the display pipeline still commits frames, touch IRQs (manual mode),
# new kernel errors, and whether the phone rebooted (boot_id changed).
#
#   ./test_sod.sh [cycles=20] [sleep_sec=60] [--manual]
#
# Real deep sleep needs USB unplugged. Use wireless ADB:
#   adb tcpip 5555 && adb connect <phone-ip>:5555   (then unplug the cable)
# --manual asks you to touch the screen after each wake to verify touch IRQs.
# Input is injected as root (HyperOS blocks shell input without the
# "USB debugging (Security settings)" toggle). With a PIN/pattern lock,
# run with --manual and unlock by hand after each wake.
# ==============================================================================
set -u

CYCLES=${1:-20}
SLEEP_SEC=${2:-60}
MANUAL=0
[ "${3:-}" = "--manual" ] && MANUAL=1

CRTC=/sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0
WAKE_TIMEOUT_SEC=5
REBOOT_WAIT_SEC=240
KERNEL_ERR_RE='kickoff timed out|esd.*fail|panel dead|Oops|BUG:|panic|Unable to handle|watchdog|bark|lockup|blocked for more'
LOG="sod_test_$(date +%Y%m%d_%H%M%S).log"

# Run a command as root on the phone (stdin avoids nested quoting)
root() { printf '%s\n' "$*" | timeout 20 adb shell su 2>/dev/null | tr -d '\r'; }
shell() { timeout 20 adb shell "$@" 2>/dev/null | tr -d '\r'; }

boot_id() { shell cat /proc/sys/kernel/random/boot_id; }
suspend_ok() { shell cat /sys/power/suspend_stats/success; }
kernel_ts() { root "dmesg | tail -n 1" | sed -n 's/^\[ *\([0-9.]*\)\].*/\1/p'; }
touch_irqs() { root "grep fts_ts /proc/interrupts" | awk '{s=0; for (i = 2; i <= 9; i++) s += $i; print s + 0}'; }
display_on() { shell dumpsys power | grep -q 'mWakefulness=Awake'; }

kernel_errors_since() {
	root "dmesg" | awk -v t="$1" '
		{ ts = $0; sub(/^\[ */, "", ts); sub(/\].*/, "", ts) }
		ts + 0 > t + 0' | grep -iE "$KERNEL_ERR_RE"
}

# Frames committed by the display after a swipe; 0 means the pipeline is stuck
frames_after_swipe() {
	local best=0 n
	for _ in 1 2; do
		root cmd input swipe 540 1700 540 900 150
		sleep 0.6
		n=$(root "cat $CRTC/measured_fps" | sed -n 's/.*frame_count:\([0-9]*\).*/\1/p')
		[ "${n:-0}" -gt "$best" ] && best=$n
	done
	echo "$best"
}

log() { echo -e "$*" | tee -a "$LOG"; }

if [ -z "$(adb get-serialno 2>/dev/null)" ]; then
	echo "[!] No ADB device connected."
	exit 1
fi
if [ "$(root id -u)" != "0" ]; then
	echo "[!] No root: grant Superuser to 'Shell' in KernelSU Manager."
	exit 1
fi

root "echo 500 > $CRTC/fps_periodicity_ms"
BOOT_ID=$(boot_id)
fails=0
log "SOD test: $CYCLES cycles x ${SLEEP_SEC}s, kernel $(shell uname -r), log $LOG"
log "cycle  deepsleep  wake_ms  frames  touch  verdict"

for i in $(seq 1 "$CYCLES"); do
	ts=$(kernel_ts)
	s0=$(suspend_ok)
	t0=$(touch_irqs)

	root cmd input keyevent KEYCODE_SLEEP
	shell dumpsys deviceidle force-idle >/dev/null
	sleep "$SLEEP_SEC"

	if [ "$(boot_id)" != "$BOOT_ID" ] || ! adb get-state >/dev/null 2>&1; then
		log "$i  -  -  -  -  REBOOT/LOST during sleep, waiting for phone..."
		timeout "$REBOOT_WAIT_SEC" adb wait-for-device
		log "    boot reason: $(shell getprop sys.boot.reason)"
		log "    see /data/adb/ki_crashlog/prev_* if ki_crashlog.sh is installed"
		fails=$((fails + 1))
		BOOT_ID=$(boot_id)
		continue
	fi

	# A notification arriving while asleep is the reported SOD trigger
	shell cmd notification post -t "ki-sod-test" ki_sod "cycle $i" >/dev/null
	start_ms=$(date +%s%3N)
	root cmd input keyevent KEYCODE_WAKEUP
	shell dumpsys deviceidle unforce >/dev/null
	wake_ms=-1
	while [ $(( $(date +%s%3N) - start_ms )) -lt $((WAKE_TIMEOUT_SEC * 1000)) ]; do
		if display_on; then
			wake_ms=$(( $(date +%s%3N) - start_ms ))
			break
		fi
		sleep 0.2
	done
	shell wm dismiss-keyguard
	sleep 0.5
	frames=$(frames_after_swipe)

	touch="-"
	if [ "$MANUAL" = 1 ]; then
		read -r -t 10 -p "    touch the screen now, then press Enter " _ || true
		touch=$(( $(touch_irqs) - t0 ))
	fi

	slept=$(( $(suspend_ok) - s0 ))
	errs=$(kernel_errors_since "${ts:-0}")
	verdict=OK
	[ "$wake_ms" -lt 0 ] && verdict="FAIL(display did not turn on)"
	[ "$frames" -eq 0 ] && verdict="FAIL(frozen: no frames)"
	[ "$touch" = 0 ] && verdict="FAIL(touch dead)"
	[ -n "$errs" ] && verdict="$verdict +kernel errors"
	[ "$verdict" != OK ] && fails=$((fails + 1))

	log "$i  $slept  $wake_ms  $frames  $touch  $verdict"
	[ -n "$errs" ] && log "$(echo "$errs" | sed 's/^/    /' | head -n 10)"
done

shell cmd notification cancel ki_sod >/dev/null
log "done: $fails/$CYCLES cycles failed"
[ "$fails" -eq 0 ]
