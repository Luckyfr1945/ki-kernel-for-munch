#!/bin/sh
# Ki-Kernel unified metrics collector for SM8250 munch

FPS=$(awk '{print $2}' /sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0/measured_fps 2>/dev/null)
[ -z "$FPS" ] && FPS="0.0"

KI_MODE=$(cat /sys/kernel/ki_profile/mode 2>/dev/null)
[ -z "$KI_MODE" ] && KI_MODE=1

KI_THROT=$(cat /sys/kernel/ki_profile/thermal_throttle 2>/dev/null)
[ -z "$KI_THROT" ] && KI_THROT=1

CPU0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
CPU4=$(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq 2>/dev/null)
CPU7=$(cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq 2>/dev/null)

GPU_FREQ=$(cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null)
GPU_LOAD=$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null)
GPU_THROT=$(cat /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null)
GPU_BUS=$(cat /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null)

SOC_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
BATT_TEMP=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
BATT_LEVEL=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
BATT_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
BATT_CURRENT=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
BYPASS=$(cat /sys/class/power_supply/battery/bypass_charging 2>/dev/null)

MEM_INFO=$(awk '
/MemAvailable:/ {free=int($2/1024)}
/MemTotal:/ {total=int($2/1024)}
/SwapTotal:/ {st=$2}
/SwapFree:/ {sf=$2}
END {print (free?free:0)"|"(total?total:0)"|"int((st-sf)/1024)}
' /proc/meminfo)

PANEL_HZ=$(dumpsys SurfaceFlinger 2>/dev/null | grep -m1 "renderRate=" | grep -oE "[0-9.]+" | head -n1 | awk '{print int($1)}')
[ -z "$PANEL_HZ" ] && PANEL_HZ=60

TOP_APP=$(dumpsys activity activities 2>/dev/null | grep -E "topResumedActivity=" | head -n1 | grep -oE "[a-zA-Z0-9._]+/[a-zA-Z0-9._]+" | head -n1 | cut -d/ -f1)
[ -z "$TOP_APP" ] && TOP_APP=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus" | grep -oE "[a-zA-Z0-9._]+/[a-zA-Z0-9._]+" | head -n1 | cut -d/ -f1)
[ -z "$TOP_APP" ] && TOP_APP="System"

GFX=$(dumpsys gfxinfo "$TOP_APP" 2>/dev/null)
TOTAL_FRAMES=$(echo "$GFX" | grep -m1 "Total frames rendered:" | awk '{print $NF}')
JANKY_FRAMES=$(echo "$GFX" | grep -m1 "Janky frames:" | awk '{print $3}')
FRAME_DROPS=$(echo "$GFX" | grep -m1 "Number Missed Vsync:" | awk '{print $NF}')
[ -z "$TOTAL_FRAMES" ] && TOTAL_FRAMES=0
[ -z "$JANKY_FRAMES" ] && JANKY_FRAMES=0
[ -z "$FRAME_DROPS" ] && FRAME_DROPS=0

echo "$FPS|$KI_MODE|$KI_THROT|$CPU0|$CPU4|$CPU7|$GPU_FREQ|$GPU_LOAD|$GPU_THROT|$GPU_BUS|$SOC_TEMP|$BATT_TEMP|$BATT_LEVEL|$BATT_STATUS|$BATT_CURRENT|$BYPASS|$MEM_INFO|$PANEL_HZ|$TOP_APP|$TOTAL_FRAMES|$JANKY_FRAMES|$FRAME_DROPS"
