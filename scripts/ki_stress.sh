#!/system/bin/sh
# Ki-Kernel fast reboot/SOD reproducer for munch (runs ON the phone as root).
# Compresses a night of idle into minutes by hammering the paths a phone
# goes through while idle: suspend/resume, charger plug/unplug, screen
# off/on with profile switches, and CPU hotplug. Every step is logged and
# synced BEFORE it runs, so after a crash the last line names the trigger.
#
#   su -c 'sh /data/local/tmp/ki_stress.sh <phase> [cycles] [sleep_sec]'
#   phase: suspend | charger | screen | hotplug | all
#
# Log: /data/adb/ki_crashlog/stress.log  (root-only, survives the reboot)

DIR=/data/adb/ki_crashlog
LOG=$DIR/stress.log
PHASE=${1:-all}
CYCLES=${2:-50}
SLEEP_SEC=${3:-8}
RTC=/sys/class/rtc/rtc0/wakealarm
CHG=/sys/class/power_supply/battery/input_suspend
PROFILE=/sys/kernel/ki_profile/mode

[ -L $DIR ] && rm -f $DIR
mkdir -p $DIR
chown root:root $DIR
chmod 700 $DIR

step() {
	echo "$(date '+%H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) $*" >> $LOG
	sync
}

restore() {
	echo 0 > $CHG 2>/dev/null
	for c in 1 2 3 4 5 6 7; do echo 1 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null; done
	[ -n "$ORIG_PROFILE" ] && echo "$ORIG_PROFILE" > $PROFILE 2>/dev/null
	echo 0 > $RTC
	cmd input keyevent KEYCODE_WAKEUP
}
ORIG_PROFILE=$(cat $PROFILE 2>/dev/null)
trap 'restore; step "ABORTED"; exit 1' INT TERM

# Forced suspend-to-RAM, woken by the PMIC RTC after SLEEP_SEC.
# Runs regardless of wakelocks, so USB/adb does not keep the phone awake.
phase_suspend() {
	i=1
	while [ $i -le $CYCLES ]; do
		ok0=$(cat /sys/power/suspend_stats/success)
		echo 0 > $RTC
		echo +$SLEEP_SEC > $RTC
		step "suspend $i/$CYCLES charger_off=$(cat $CHG) enter"
		echo mem > /sys/power/state
		rc=$?
		step "suspend $i/$CYCLES resumed rc=$rc slept=$(( $(cat /sys/power/suspend_stats/success) - ok0 )) fail_dev=$(cat /sys/power/suspend_stats/last_failed_dev)"
		sleep 1
		i=$((i + 1))
	done
}

# Charger present/absent flips, alone and across suspend (the "dicas / ga dicas" case)
phase_charger() {
	i=1
	while [ $i -le $CYCLES ]; do
		v=$((i % 2))
		step "charger $i/$CYCLES input_suspend=$v"
		echo $v > $CHG
		sleep 2
		echo 0 > $RTC
		echo +$SLEEP_SEC > $RTC
		step "charger $i/$CYCLES suspend with input_suspend=$v"
		echo mem > /sys/power/state
		step "charger $i/$CYCLES resumed"
		i=$((i + 1))
	done
	echo 0 > $CHG
}

# Screen off/on bursts plus ki_profile switches: DRM blank notifier,
# ki_profile screen worker, panel power sequence (SOD path).
phase_screen() {
	i=1
	while [ $i -le $CYCLES ]; do
		step "screen $i/$CYCLES off"
		cmd input keyevent KEYCODE_SLEEP
		sleep $SLEEP_SEC
		cmd notification post -t ki-stress ki_stress "cycle $i" >/dev/null 2>&1
		step "screen $i/$CYCLES on"
		cmd input keyevent KEYCODE_WAKEUP
		sleep 2
		m=$((i % 3))
		step "screen $i/$CYCLES profile=$m fps=$(cut -d' ' -f2 /sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0/measured_fps)"
		echo $m > $PROFILE 2>/dev/null
		i=$((i + 1))
	done
}

# CPU hotplug: cluster leaders 4 and 7 go too, which ki_profile special-cases
phase_hotplug() {
	i=1
	while [ $i -le $CYCLES ]; do
		for c in 1 2 3 4 5 6 7; do
			step "hotplug $i/$CYCLES cpu$c off"
			echo 0 > /sys/devices/system/cpu/cpu$c/online
		done
		echo $((i % 3)) > $PROFILE 2>/dev/null
		for c in 7 6 5 4 3 2 1; do
			step "hotplug $i/$CYCLES cpu$c on"
			echo 1 > /sys/devices/system/cpu/cpu$c/online
		done
		i=$((i + 1))
	done
}

USB_UNPLUG_WAIT_SEC=30
step "START phase=$PHASE cycles=$CYCLES sleep=$SLEEP_SEC kernel=$(uname -r) usb=$(cat /sys/class/power_supply/usb/online)"
# USB data to a PC holds the a600000.ssusb controller busy (-EBUSY), so
# suspend never happens; give the user time to unplug (a wall charger is fine).
if [ "$PHASE" != "hotplug" ] && [ "$(cat /sys/class/power_supply/usb/online)" = 1 ]; then
	step "UNPLUG the PC cable now (wall charger is OK), waiting ${USB_UNPLUG_WAIT_SEC}s"
	sleep $USB_UNPLUG_WAIT_SEC
fi
case "$PHASE" in
suspend) phase_suspend ;;
charger) phase_charger ;;
screen) phase_screen ;;
hotplug) phase_hotplug ;;
all)
	phase_suspend
	phase_charger
	phase_screen
	phase_hotplug
	;;
*)
	echo "usage: $0 suspend|charger|screen|hotplug|all [cycles] [sleep_sec]"
	exit 1
	;;
esac
restore
step "DONE phase=$PHASE"
