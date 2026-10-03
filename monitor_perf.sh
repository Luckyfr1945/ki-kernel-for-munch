#!/usr/bin/env bash
# ==============================================================================
# Ki-Kernel Realtime Gaming & Hardware Monitor for POCO F4 / munch (SM8250)
# Tracks Hardware Display FPS, CPU clusters, Adreno 650 GPU, Temperatures,
# Bypass Charging, and Ki-Profile mode with interactive profile toggles.
# ==============================================================================

# ANSI Color Codes
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_MAGENTA="\033[35m"
C_BLUE="\033[34m"
C_WHITE="\033[37m"
C_GRAY="\033[90m"

# Ensure ADB device is available
DEVICE=$(adb get-serialno 2>/dev/null)
if [ -z "$DEVICE" ] || [ "$DEVICE" = "unknown" ]; then
    echo -e "${C_RED}[!] Error: No ADB device connected. Please connect your phone via USB with USB debugging enabled.${C_RESET}"
    exit 1
fi

# Set 500ms periodicity on device for accurate real-time FPS
adb shell "su -c 'echo 500 > /sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0/fps_periodicity_ms 2>/dev/null'" 2>/dev/null

clear
echo -e "${C_CYAN}${C_BOLD}Starting Ki-Kernel Monitor on device ${DEVICE}...${C_RESET}"

# Fetch and print one-shot formatted dashboard
get_metrics() {
    adb shell "su -c '
        # 1. FPS & Refresh Rate
        FPS_RAW=\$(cat /sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0/measured_fps 2>/dev/null)
        FPS=\$(echo \"\$FPS_RAW\" | grep -oE \"fps: [0-9.]+\" | awk \"{print \\\$2}\")
        [ -z \"\$FPS\" ] && FPS=\"0.0\"

        # 2. Ki-Profile
        KI_MODE=\$(cat /sys/kernel/ki_profile/mode 2>/dev/null)
        KI_NAME=\$(cat /sys/kernel/ki_profile/current_profile 2>/dev/null)
        KI_THROTTLE=\$(cat /sys/kernel/ki_profile/thermal_throttle 2>/dev/null)

        # 3. CPU Clocks (Silver cpu0, Gold cpu4, Prime cpu7)
        CPU0=\$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
        CPU4=\$(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq 2>/dev/null)
        CPU7=\$(cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq 2>/dev/null)

        # 4. GPU Adreno 650
        GPU_FREQ=\$(cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null)
        GPU_LOAD=\$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null)
        GPU_THROT=\$(cat /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null)
        GPU_BUS=\$(cat /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null)

        # 5. Temperatures
        SOC_TEMP=\$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        BATT_TEMP=\$(cat /sys/class/power_supply/battery/temp 2>/dev/null)

        # 6. Battery & Bypass
        BATT_LEVEL=\$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
        BATT_STATUS=\$(cat /sys/class/power_supply/battery/status 2>/dev/null)
        BATT_CURRENT=\$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
        BYPASS=\$(cat /sys/class/power_supply/battery/bypass_charging 2>/dev/null)

        # 7. Memory
        MEM_FREE=\$(awk \"/MemAvailable:/ {print int(\\\$2/1024)}\" /proc/meminfo)
        MEM_TOTAL=\$(awk \"/MemTotal:/ {print int(\\\$2/1024)}\" /proc/meminfo)
        ZRAM_USED=\$(awk \"/SwapTotal/ {total=\\\$2} /SwapFree/ {free=\\\$2} END {print int((total-free)/1024)}\" /proc/meminfo)

        echo \"\$FPS|\$KI_MODE|\$KI_NAME|\$KI_THROTTLE|\$CPU0|\$CPU4|\$CPU7|\$GPU_FREQ|\$GPU_LOAD|\$GPU_THROT|\$GPU_BUS|\$SOC_TEMP|\$BATT_TEMP|\$BATT_LEVEL|\$BATT_STATUS|\$BATT_CURRENT|\$BYPASS|\$MEM_FREE|\$MEM_TOTAL|\$ZRAM_USED\"
    '"
}

trap 'tput cnorm; echo -e "\n${C_RESET}Monitor closed."; exit 0' INT TERM EXIT
tput civis

while true; do
    RAW=$(get_metrics)
    if [ -z "$RAW" ]; then
        sleep 1
        continue
    fi

    IFS='|' read -r FPS KI_MODE KI_NAME KI_THROTTLE CPU0 CPU4 CPU7 GPU_FREQ GPU_LOAD GPU_THROT GPU_BUS SOC_TEMP BATT_TEMP BATT_LEVEL BATT_STATUS BATT_CURRENT BYPASS MEM_FREE MEM_TOTAL ZRAM_USED <<< "$RAW"

    # Conversions
    CPU0_GHZ=$(awk "BEGIN {printf \"%.2f\", ${CPU0:-0}/1000000}")
    CPU4_GHZ=$(awk "BEGIN {printf \"%.2f\", ${CPU4:-0}/1000000}")
    CPU7_GHZ=$(awk "BEGIN {printf \"%.2f\", ${CPU7:-0}/1000000}")
    GPU_MHZ=$(awk "BEGIN {printf \"%d\", ${GPU_FREQ:-0}/1000000}")
    SOC_C=$(awk "BEGIN {printf \"%.1f\", ${SOC_TEMP:-0}/1000}")
    BATT_C=$(awk "BEGIN {printf \"%.1f\", ${BATT_TEMP:-0}/10}")
    BATT_MA=$(awk "BEGIN {printf \"%d\", ${BATT_CURRENT:-0}/1000}")

    # Colors based on thresholds
    # FPS color
    FPS_NUM=$(echo "$FPS" | awk '{print int($1)}')
    if [ "$FPS_NUM" -ge 110 ]; then
        FPS_COLOR="$C_CYAN"
    elif [ "$FPS_NUM" -ge 55 ]; then
        FPS_COLOR="$C_GREEN"
    elif [ "$FPS_NUM" -ge 40 ]; then
        FPS_COLOR="$C_YELLOW"
    else
        FPS_COLOR="$C_RED"
    fi

    # Profile color
    if [ "$KI_MODE" = "2" ]; then
        PROF_COLOR="${C_RED}${C_BOLD}"
        PROF_TXT="[2] PERFORMANCE (TURBO MENTOK)"
    elif [ "$KI_MODE" = "0" ]; then
        PROF_COLOR="${C_BLUE}"
        PROF_TXT="[0] BATTERY SAVER"
    else
        PROF_COLOR="${C_GREEN}"
        PROF_TXT="[1] BALANCED DAILY"
    fi

    # Bypass status
    if [ "$BYPASS" = "1" ]; then
        BYPASS_TXT="${C_GREEN}${C_BOLD}TRUE BYPASS ACTIVE (0mA into Battery)${C_RESET}"
    else
        BYPASS_TXT="${C_YELLOW}Normal Charging / Discharge${C_RESET}"
    fi

    # Clear screen and draw UI
    tput cup 0 0
    echo -e "${C_CYAN}╔════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET} ${C_BOLD}⚡ Ki-Kernel Live Hardware & Gaming Monitor (SM8250 munch) ⚡${C_RESET}        ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚════════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo -e " ${C_BOLD}Display FPS:${C_RESET} ${FPS_COLOR}${C_BOLD}${FPS} FPS${C_RESET}      ${C_BOLD}Ki-Profile:${C_RESET} ${PROF_COLOR}${PROF_TXT}${C_RESET}"
    echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e " ${C_BOLD}GPU (Adreno 650):${C_RESET}"
    echo -e "   • Clock:  ${C_CYAN}${GPU_MHZ} MHz${C_RESET} (Floor 510MHz in Perf)  • Load: ${C_YELLOW}${GPU_LOAD:-0%}${C_RESET}"
    echo -e "   • DDR Bus: $([ "$GPU_BUS" = "1" ] && echo -e "${C_GREEN}LOCKED HIGH (Zero Latency)${C_RESET}" || echo -e "${C_GRAY}Dynamic${C_RESET}")"
    echo -e "   • Adreno Throttling: $([ "$GPU_THROT" = "0" ] && echo -e "${C_GREEN}DISABLED (Bypassed)${C_RESET}" || echo -e "${C_YELLOW}Active${C_RESET}")"
    echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e " ${C_BOLD}CPU (Snapdragon 870 1+3+4):${C_RESET}"
    echo -e "   • Prime (C7):  ${C_RED}${CPU7_GHZ} GHz${C_RESET} / 3.19 GHz (Instant Snap Hispeed)"
    echo -e "   • Gold  (C4-6):${C_YELLOW}${CPU4_GHZ} GHz${C_RESET} / 2.42 GHz (Instant Snap Hispeed)"
    echo -e "   • Silver(C0-3):${C_CYAN}${CPU0_GHZ} GHz${C_RESET} / 1.80 GHz"
    echo -e "   • Thermal Core Isolation: $([ "$KI_THROTTLE" = "0" ] && echo -e "${C_GREEN}BYPASSED (8/8 Cores Locked)${C_RESET}" || echo -e "${C_YELLOW}Active${C_RESET}")"
    echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e " ${C_BOLD}Power & Battery:${C_RESET}"
    echo -e "   • Bypass Mode:  ${BYPASS_TXT}"
    echo -e "   • Battery:      ${C_BOLD}${BATT_LEVEL}%${C_RESET} (${BATT_STATUS}, Current: ${C_BOLD}${BATT_MA} mA${C_RESET})"
    echo -e "   • SoC Temp:     ${C_BOLD}${SOC_C}°C${C_RESET}      • Battery Temp: ${C_BOLD}${BATT_C}°C${C_RESET}"
    echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e " ${C_BOLD}Memory (RAM & zRAM LZ4):${C_RESET}"
    echo -e "   • Free RAM:     ${C_GREEN}${MEM_FREE} MB${C_RESET} / ${MEM_TOTAL} MB"
    echo -e "   • zRAM Used:    ${C_YELLOW}${ZRAM_USED} MB${C_RESET} (LZ4 swappiness 90)"
    echo -e "${C_GRAY}────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e " ${C_BOLD}Interactive Commands (Tekan tombol langsung):${C_RESET}"
    echo -e "  [${C_RED}2${C_RESET}] Mode Performa   [${C_GREEN}1${C_RESET}] Mode Balanced   [${C_BLUE}0${C_RESET}] Mode Battery"
    echo -e "  [${C_CYAN}b${C_RESET}] Toggle Bypass    [${C_YELLOW}h${C_RESET}] Force 120Hz     [${C_MAGENTA}q${C_RESET}] Keluar"
    echo -e "${C_CYAN}════════════════════════════════════════════════════════════════════════${C_RESET}"

    # Non-blocking input check
    if [ -t 0 ]; then
        read -t 1 -s -n 1 KEY
    else
        sleep 1
        KEY=""
    fi
    if [ -n "$KEY" ]; then
        case "$KEY" in
            2)
                adb shell "su -c 'echo 2 > /sys/kernel/ki_profile/mode'" 2>/dev/null
                ;;
            1)
                adb shell "su -c 'echo 1 > /sys/kernel/ki_profile/mode'" 2>/dev/null
                ;;
            0)
                adb shell "su -c 'echo 0 > /sys/kernel/ki_profile/mode'" 2>/dev/null
                ;;
            b|B)
                if [ "$BYPASS" = "1" ]; then
                    adb shell "su -c 'echo 0 > /sys/class/power_supply/battery/bypass_charging'" 2>/dev/null
                else
                    adb shell "su -c 'echo 1 > /sys/class/power_supply/battery/bypass_charging'" 2>/dev/null
                fi
                ;;
            h|H)
                adb shell "su -c 'service call SurfaceFlinger 1035 i32 1'" 2>/dev/null
                adb shell "cmd display set-user-preferred-display-mode 1080 2400 120.0 0 true" 2>/dev/null
                adb shell "settings put system min_refresh_rate 120.0; settings put system peak_refresh_rate 120.0" 2>/dev/null
                ;;
            q|Q)
                break
                ;;
        esac
    fi
done

tput cnorm
echo -e "\n${C_GREEN}Monitor selesai.${C_RESET}"
