#!/system/bin/sh
# Ki-Kernel persistent crash logger for munch.
# Streams the kernel log and a periodic status line to /data, so the last
# lines before a freeze, watchdog bite or silent reboot survive the reboot.
#
#   su -c 'sh /data/local/tmp/ki_crashlog.sh start'    # run now (background)
#   su -c 'sh /data/local/tmp/ki_crashlog.sh install'  # also start on every boot
#   su -c 'sh /data/local/tmp/ki_crashlog.sh stop'
#   su -c 'sh /data/local/tmp/ki_crashlog.sh uninstall'
#
# After an unexpected reboot, the previous boot's logs are in
# /data/local/tmp/ki_crashlog/prev_<time>/ (with pstore + boot reason).

DIR=/data/local/tmp/ki_crashlog
SELF=/data/local/tmp/ki_crashlog.sh
SERVICE=/data/adb/service.d/ki_crashlog.sh
MAX_LOG_BYTES=8388608	# rotate kmsg.log at 8 MiB (keeps one .1 backup)
STATUS_SEC=30		# shell sleep stops during suspend, so no extra wakeups
CRTC=/sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0

archive_previous_boot() {
	now_id=$(cat /proc/sys/kernel/random/boot_id)
	prev_id=$(cat $DIR/boot_id 2>/dev/null)
	echo "$now_id" > $DIR/boot_id
	[ -z "$prev_id" ] || [ "$prev_id" = "$now_id" ] && return 0

	dst=$DIR/prev_$(date +%Y%m%d_%H%M%S)
	mkdir -p $dst
	mv $DIR/kmsg.log* $DIR/status.log $dst/ 2>/dev/null
	cp /sys/fs/pstore/* $dst/ 2>/dev/null
	{
		echo "sys.boot.reason=$(getprop sys.boot.reason)"
		echo "ro.boot.bootreason=$(getprop ro.boot.bootreason)"
		dmesg | grep -iE "power-(on|off) reason"
	} > $dst/boot_reason.txt
	# keep the 5 newest archives
	ls -dt $DIR/prev_* | tail -n +6 | xargs rm -rf 2>/dev/null
}

status_line() {
	echo "$(date '+%m-%d %H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime)" \
		"screen=$(cat /sys/kernel/ki_profile/screen_state 2>/dev/null)" \
		"susp_ok=$(cat /sys/power/suspend_stats/success)" \
		"susp_fail=$(cat /sys/power/suspend_stats/fail)" \
		"fail_dev=$(cat /sys/power/suspend_stats/last_failed_dev)" \
		"batt=$(cat /sys/class/power_supply/battery/temp)" \
		"usb=$(cat /sys/class/power_supply/usb/online 2>/dev/null)" \
		"f0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)" \
		"f4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq)" \
		"f7=$(cat /sys/devices/system/cpu/cpufreq/policy7/scaling_cur_freq)" \
		"memfree=$(awk '/MemAvailable/{print $2}' /proc/meminfo)" \
		"$(cat $CRTC/measured_fps 2>/dev/null)"
}

run_logger() {
	mkdir -p $DIR
	archive_previous_boot
	echo $$ > $DIR/pid
	dmesg > $DIR/kmsg.log
	dmesg -W >> $DIR/kmsg.log &
	dmesg_pid=$!
	while true; do
		status_line >> $DIR/status.log
		if [ "$(stat -c %s $DIR/kmsg.log)" -gt $MAX_LOG_BYTES ]; then
			kill $dmesg_pid
			mv -f $DIR/kmsg.log $DIR/kmsg.log.1
			dmesg -W > $DIR/kmsg.log &
			dmesg_pid=$!
		fi
		# page cache is lost on a hard reset; flush what we have
		sync
		sleep $STATUS_SEC
	done
}

stop_logger() {
	pid=$(cat $DIR/pid 2>/dev/null)
	[ -n "$pid" ] && pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
	rm -f $DIR/pid
}

case "$1" in
start)
	stop_logger
	nohup sh "$0" run >/dev/null 2>&1 &
	echo "ki_crashlog: logging to $DIR"
	;;
run)
	run_logger
	;;
stop)
	stop_logger
	;;
install)
	[ "$0" = "$SELF" ] || cp -f "$0" $SELF
	mkdir -p /data/adb/service.d
	printf '#!/system/bin/sh\nsh %s start\n' $SELF > $SERVICE
	chmod 755 $SERVICE $SELF
	sh $SELF start
	;;
uninstall)
	stop_logger
	rm -f $SERVICE
	;;
*)
	echo "usage: $0 start|stop|install|uninstall"
	exit 1
	;;
esac
