#!/usr/bin/env bash
# ==============================================================================
# Ki-Kernel log collector & analyzer for munch
# Pulls every crash trace the phone keeps (pstore, dropbox last_kmsg,
# ki_crashlog archives, PMIC power-on/off reasons, boot reasons, suspend
# stats, panel vsync) into one folder and prints what killed the phone.
#
#   ./ki_logcheck.sh                         # analyze the connected phone
#   ./ki_logcheck.sh KernelSU_bugreport.tar.gz   # also analyze a KSU bugreport
#   ./ki_logcheck.sh --offline KernelSU_bugreport.tar.gz   # bugreport only
# ==============================================================================
set -u

OUT="ki_logs_$(date +%Y%m%d_%H%M%S)"
CRTC=/sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0
DSI=/sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/card0-DSI-1

ONLINE=1
BUGREPORT=""
for arg in "$@"; do
	case "$arg" in
	--offline) ONLINE=0 ;;
	*) BUGREPORT=$arg ;;
	esac
done

root() { printf '%s\n' "$*" | timeout 60 adb shell su 2>/dev/null | tr -d '\r'; }
shell() { timeout 60 adb shell "$@" 2>/dev/null | tr -d '\r'; }

mkdir -p "$OUT"

collect_device() {
	if [ -z "$(adb get-serialno 2>/dev/null)" ]; then
		echo "[!] No ADB device; use --offline with a bugreport." >&2
		exit 1
	fi
	if [ "$(root id -u)" != "0" ]; then
		echo "[!] No root: grant Superuser to 'Shell' in KernelSU Manager." >&2
		exit 1
	fi
	echo "[*] collecting from phone into $OUT/"
	{
		echo "kernel: $(root cat /proc/version)"
		echo "uptime: $(shell uptime)"
		echo "sys.boot.reason: $(shell getprop sys.boot.reason)"
		echo "sys.boot.reason.last: $(shell getprop sys.boot.reason.last)"
		echo "boot.reason.history: $(shell getprop persist.sys.boot.reason.history | tr '\n' ' ')"
		echo "rom: $(shell getprop ro.build.fingerprint)"
	} > "$OUT/device.txt"

	root dmesg > "$OUT/dmesg.txt"
	root 'for f in /sys/fs/pstore/*; do [ -f "$f" ] && { echo "=== $f"; cat "$f"; }; done' > "$OUT/pstore.txt"
	root 'cd /sys/power/suspend_stats && for f in *; do echo "$f=$(cat $f)"; done' > "$OUT/suspend_stats.txt"
	root 'cat /sys/kernel/debug/wakeup_sources 2>/dev/null' |
		awk 'NR == 1 || $6 > 0' | sort -k6 -n -r | head -n 25 > "$OUT/wakeup_sources_top.txt"
	{
		echo "hw_vsync: $(root cat $DSI/hw_vsync_info)"
		echo "measured: $(root cat $CRTC/measured_fps)"
		shell dumpsys display | grep -m 3 -E "mDesiredDisplayModeSpecs|PEAK_REFRESH_RATE"
	} > "$OUT/display.txt"
	shell dumpsys dropbox --print SYSTEM_LAST_KMSG > "$OUT/dropbox_last_kmsg.txt"
	shell dumpsys dropbox --print SYSTEM_BOOT | grep -E "^20|Kernel:" > "$OUT/dropbox_boots.txt"
	shell dumpsys dropbox | grep -E "SYSTEM_(TOMBSTONE|RESTART|LAST_KMSG)|system_server_(crash|watchdog)" > "$OUT/dropbox_crashes.txt"
	root 'cd /data/local/tmp && tar -cf - ki_crashlog 2>/dev/null' | tar -xf - -C "$OUT" 2>/dev/null
	shell logcat -d -b crash > "$OUT/logcat_crash.txt"
}

collect_bugreport() {
	local dst="$OUT/ksu_bugreport"
	mkdir -p "$dst"
	tar -xzf "$BUGREPORT" -C "$dst" || { echo "[!] cannot extract $BUGREPORT" >&2; return; }
	for t in pstore dropbox bootlog tombstones; do
		[ -s "$dst/$t.tar.gz" ] && mkdir -p "$dst/x_$t" && tar -xzf "$dst/$t.tar.gz" -C "$dst/x_$t" 2>/dev/null
	done
	echo "[*] bugreport: $(grep -E '^Kernel(Version|Release)' "$dst/basic.txt" | tr '\n' ' ')"
	if [ ! -s "$dst/pstore.tar.gz" ] || [ -z "$(ls -A "$dst/x_pstore" 2>/dev/null | grep -v '^\.$')" ]; then
		echo "    note: bugreport pstore is empty, its logs start AFTER the crash reboot"
	fi
}

# PMIC power-on/off reasons decide reboot vs power loss vs user long-press
explain_pon() {
	case "$1" in
	*SMPL*) echo "SMPL: sudden momentary power loss (battery/connector/PMIC brown-out)" ;;
	*UVLO*) echo "UVLO: battery voltage collapsed (power draw spike or weak battery)" ;;
	*OTST3*) echo "OTST3: PMIC over-temperature shutdown" ;;
	*KPDPWR*S2*|*"S2 reset"*|*KPDPWR_AND_RESIN*) echo "power key long-press reset (user forced it, e.g. during SOD)" ;;
	*PS_HOLD*) echo "PS_HOLD: SoC asked for reset (kernel panic/watchdog/normal reboot)" ;;
	*"Hard Reset"*) echo "hard reset (watchdog bite or PMIC reset)" ;;
	*) echo "" ;;
	esac
}

SIGNATURES='Kernel panic|Unable to handle|Internal error: Oops|BUG: |WARNING: CPU|Watchdog bark|wdog bite|apps_wdog|soft lockup|hard LOCKUP|rcu_sched.*stall|rcu_preempt.*stall|blocked for more than|kickoff timed out|esd .*fail|panel dead|SError|subsys-restart.*crashed|Fatal error on|thermal.*critical|reached critical|scheduling while atomic|sleeping function called|list_.*corruption|i2c error :-107|nfc_write: failed'

analyze() {
	echo
	echo "=================== RESULT ($OUT) ==================="
	[ -f "$OUT/device.txt" ] && cat "$OUT/device.txt"

	echo
	echo "--- PMIC power-on/off reason (why the last boot happened) ---"
	grep -rhoE "PMIC@SID[0-9]+:? Power-(on|off) reason: .*" "$OUT" 2>/dev/null | sort -u | while read -r line; do
		why=$(explain_pon "$line")
		echo "  $line${why:+   <= $why}"
	done

	echo
	echo "--- crash signatures (count, first hit) ---"
	grep -rhoE "$SIGNATURES" "$OUT" --include='*.txt' --include='*.log' --include='kmsg*' --include='console-ramoops*' 2>/dev/null |
		sort | uniq -c | sort -rn | head -n 20
	echo
	echo "--- first panic/oops context ---"
	grep -rh -m 1 -B 4 -A 22 -E "Internal error: Oops|Kernel panic - not syncing|Watchdog bark" "$OUT" 2>/dev/null | head -n 40

	echo
	echo "--- suspend health ---"
	[ -f "$OUT/suspend_stats.txt" ] && grep -E "^(success|fail|last_failed_dev|last_failed_errno|last_failed_step)=" "$OUT/suspend_stats.txt"
	[ -s "$OUT/wakeup_sources_top.txt" ] && { echo "  top wakeup sources:"; head -n 8 "$OUT/wakeup_sources_top.txt" | awk '{print "   ", $1, "active_count=" $2, "active_ms=" $6}'; }

	if [ -d "$OUT/ki_crashlog" ]; then
		echo
		echo "--- ki_crashlog: last steps before each unexpected reboot ---"
		for d in "$OUT"/ki_crashlog/prev_*; do
			[ -d "$d" ] || continue
			echo "  $(basename "$d"):"
			cat "$d/boot_reason.txt" 2>/dev/null | sed 's/^/    /'
			tail -n 2 "$d/status.log" 2>/dev/null | sed 's/^/    status: /'
			tail -n 5 "$d/kmsg.log" 2>/dev/null | cut -c1-160 | sed 's/^/    kmsg: /'
		done
		[ -f "$OUT/ki_crashlog/stress.log" ] && { echo "  stress.log tail:"; tail -n 6 "$OUT/ki_crashlog/stress.log" | sed 's/^/    /'; }
	fi

	if [ -f "$OUT/display.txt" ]; then
		echo
		echo "--- display ---"
		sed 's/^/  /' "$OUT/display.txt" | cut -c1-170
	fi
	echo
	echo "Full logs: $OUT/"
}

[ "$ONLINE" = 1 ] && collect_device
[ -n "$BUGREPORT" ] && collect_bugreport
analyze | tee "$OUT/summary.txt"
