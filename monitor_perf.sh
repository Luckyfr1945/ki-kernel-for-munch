#!/usr/bin/env bash
# ==============================================================================
# Ki-Kernel Realtime Gaming & Hardware Monitor for POCO F4 / munch (SM8250)
# Tracks Hardware Display FPS, per-game SurfaceFlinger FPS, frame jank/drops,
# rolling FPS graph, CPU clusters, Adreno 650 GPU, Temperatures,
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
C_BG_RED="\033[41m"

# Ensure ADB device is available
DEVICE=$(adb get-serialno 2>/dev/null)
if [ -z "$DEVICE" ] || [ "$DEVICE" = "unknown" ]; then
    echo -e "${C_RED}[!] Error: No ADB device connected.${C_RESET}"
    exit 1
fi

# Set 500ms periodicity on device for accurate real-time FPS
adb shell "su -c 'echo 500 > /sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0/fps_periodicity_ms 2>/dev/null'" 2>/dev/null

# Rolling FPS history (last 30 samples = ~30s)
FPS_HISTORY=()
HISTORY_MAX=30
JANK_COUNT=0
FRAME_DROP_COUNT=0
PREV_TOTAL_FRAMES=0
PREV_JANKY_FRAMES=0

clear
echo -e "${C_CYAN}${C_BOLD}Starting Ki-Kernel Monitor on device ${DEVICE}...${C_RESET}"

# ─── SurfaceFlinger per-game FPS ─────────────────────────────────────────────
get_game_fps() {
    # Dump SurfaceFlinger stats for the top visible app layer
    # Returns: "GAME_PKG|GAME_FPS|TOTAL_FRAMES|JANKY_FRAMES"
    adb shell "su -c '
        TOP_APP=\$(dumpsys activity activities 2>/dev/null | grep -m1 \"mResumedActivity\" | grep -oE \"[a-zA-Z0-9._]+/[a-zA-Z0-9._]+\" | head -n1 | cut -d/ -f1)
        [ -z \"\$TOP_APP\" ] && TOP_APP=\"unknown\"

        # Get SurfaceFlinger stats for matching layers
        SF_STATS=\$(dumpsys SurfaceFlinger --latency-clear 2>/dev/null; sleep 0.5; dumpsys SurfaceFlinger --latency 2>/dev/null | grep -A 500 \"\$TOP_APP\" | head -n 200)

        # Count frames from timestamp differences (ns to fps)
        FRAME_TIMES=\$(echo \"\$SF_STATS\" | awk \"NR>1 && \\\$1>0 && \\\$1!~/^0+\$/ {print \\\$1}\" | head -n 100)
        TOTAL=\$(echo \"\$FRAME_TIMES\" | wc -l)
        if [ \"\$TOTAL\" -gt 5 ]; then
            FIRST=\$(echo \"\$FRAME_TIMES\" | head -n1)
            LAST=\$(echo \"\$FRAME_TIMES\" | tail -n1)
            DURATION_NS=\$((LAST - FIRST))
            if [ \"\$DURATION_NS\" -gt 0 ]; then
                GAME_FPS=\$(awk \"BEGIN {printf \\\"%.1f\\\", (\$TOTAL * 1000000000) / \$DURATION_NS}\")
            else
                GAME_FPS=0
            fi
        else
            GAME_FPS=0
        fi

        # Jank via gfxinfo
        GFXINFO=\$(dumpsys gfxinfo \"\$TOP_APP\" 2>/dev/null)
        TOTAL_FRAMES=\$(echo \"\$GFXINFO\" | grep -m1 \"Total frames\" | awk \"{print \\\$NF}\")
        JANKY_FRAMES=\$(echo \"\$GFXINFO\" | grep -m1 \"Janky frames\" | awk \"{print \\\$NF}\" | grep -oE \"[0-9]+\" | head -n1)
        FRAME_DROPS=\$(echo \"\$GFXINFO\" | grep -m1 \"Number Missed Vsync\" | awk \"{print \\\$NF}\")
        [ -z \"\$TOTAL_FRAMES\" ]  && TOTAL_FRAMES=0
        [ -z \"\$JANKY_FRAMES\" ]  && JANKY_FRAMES=0
        [ -z \"\$FRAME_DROPS\" ]   && FRAME_DROPS=0

        echo \"\$TOP_APP|\$GAME_FPS|\$TOTAL_FRAMES|\$JANKY_FRAMES|\$FRAME_DROPS\"
    '" 2>/dev/null
}

# ─── Hardware metrics ─────────────────────────────────────────────────────────
get_metrics() {
    adb shell "su -c '
        FPS_RAW=\$(cat /sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0/measured_fps 2>/dev/null)
        FPS=\$(echo \"\$FPS_RAW\" | grep -oE \"fps: [0-9.]+\" | awk \"{print \$2}\")
        [ -z \"\$FPS\" ] && FPS=\"0.0\"

        KI_MODE=\$(cat /sys/kernel/ki_profile/mode 2>/dev/null)
        KI_THROTTLE=\$(cat /sys/kernel/ki_profile/thermal_throttle 2>/dev/null)

        CPU0=\$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
        CPU4=\$(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq 2>/dev/null)
        CPU7=\$(cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq 2>/dev/null)

        GPU_FREQ=\$(cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null)
        GPU_LOAD=\$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null)
        GPU_THROT=\$(cat /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null)
        GPU_BUS=\$(cat /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null)

        SOC_TEMP=\$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        BATT_TEMP=\$(cat /sys/class/power_supply/battery/temp 2>/dev/null)

        BATT_LEVEL=\$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
        BATT_STATUS=\$(cat /sys/class/power_supply/battery/status 2>/dev/null)
        BATT_CURRENT=\$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
        BYPASS=\$(cat /sys/class/power_supply/battery/bypass_charging 2>/dev/null)

        MEM_FREE=\$(awk \"/MemAvailable:/ {print int(\$2/1024)}\" /proc/meminfo)
        MEM_TOTAL=\$(awk \"/MemTotal:/ {print int(\$2/1024)}\" /proc/meminfo)
        ZRAM_USED=\$(awk \"/SwapTotal/ {total=\$2} /SwapFree/ {free=\$2} END {print int((total-free)/1024)}\" /proc/meminfo)

        # Count actual hardware vsync events from DRM in 200ms window
        count=0
        start=\$(date +%s%3N)
        end=\$((start + 200))
        while [ \$(date +%s%3N) -lt \$end ]; do
            read -r line < /sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0/vsync_event 2>/dev/null && count=\$((count+1))
        done
        PANEL_HZ=\$(awk \"BEGIN {printf \\\"%d\\\", \$count * 5}\")

        echo \"\$FPS|\$KI_MODE|\$KI_THROTTLE|\$CPU0|\$CPU4|\$CPU7|\$GPU_FREQ|\$GPU_LOAD|\$GPU_THROT|\$GPU_BUS|\$SOC_TEMP|\$BATT_TEMP|\$BATT_LEVEL|\$BATT_STATUS|\$BATT_CURRENT|\$BYPASS|\$MEM_FREE|\$MEM_TOTAL|\$ZRAM_USED|\$PANEL_HZ\"
    '" 2>/dev/null
}

# ─── Rolling FPS Bar Graph (30 samples) ───────────────────────────────────────
draw_fps_graph() {
    local fps_val="$1"
    # Add to history
    FPS_HISTORY+=("$fps_val")
    if [ "${#FPS_HISTORY[@]}" -gt "$HISTORY_MAX" ]; then
        FPS_HISTORY=("${FPS_HISTORY[@]:1}")
    fi

    # Draw graph (height: 6 rows, each row = 20fps)
    local bars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
    local max_fps=125
    local graph=""
    for val in "${FPS_HISTORY[@]}"; do
        local fint=$(echo "$val" | awk '{print int($1)}')
        # clamp
        [ "$fint" -gt "$max_fps" ] && fint=$max_fps
        [ "$fint" -lt 0 ] && fint=0
        local idx=$(awk "BEGIN {print int($fint * 7 / $max_fps)}")
        local bar="${bars[$idx]}"
        # Color by fps
        if [ "$fint" -ge 110 ]; then
            graph+="${C_CYAN}${bar}${C_RESET}"
        elif [ "$fint" -ge 55 ]; then
            graph+="${C_GREEN}${bar}${C_RESET}"
        elif [ "$fint" -ge 40 ]; then
            graph+="${C_YELLOW}${bar}${C_RESET}"
        else
            graph+="${C_RED}${bar}${C_RESET}"
        fi
    done
    # Pad with spaces if history shorter than max
    local pad=$((HISTORY_MAX - ${#FPS_HISTORY[@]}))
    for ((i=0; i<pad; i++)); do
        graph=" ${graph}"
    done
    echo -e "$graph"
}

# ─── Jank indicator ───────────────────────────────────────────────────────────
get_jank_color() {
    local pct="$1"
    if awk "BEGIN {exit !($pct >= 15)}"; then
        echo "${C_RED}${C_BOLD}${pct}% 🔴 HEAVY JANK${C_RESET}"
    elif awk "BEGIN {exit !($pct >= 5)}"; then
        echo "${C_YELLOW}${pct}% ⚠ SOME JANK${C_RESET}"
    else
        echo "${C_GREEN}${pct}% ✓ SMOOTH${C_RESET}"
    fi
}

trap 'tput cnorm; echo -e "\n${C_RESET}Monitor closed."; exit 0' INT TERM EXIT
tput civis

LOOP=0
GAME_PKG=""; GAME_FPS="0.0"; TOTAL_FRAMES=0; JANKY_FRAMES=0; FRAME_DROPS=0

while true; do
    LOOP=$((LOOP + 1))

    # Fetch hardware metrics every loop
    RAW=$(get_metrics)
    if [ -z "$RAW" ]; then
        sleep 1
        continue
    fi

    IFS='|' read -r FPS KI_MODE KI_THROTTLE CPU0 CPU4 CPU7 GPU_FREQ GPU_LOAD GPU_THROT GPU_BUS SOC_TEMP BATT_TEMP BATT_LEVEL BATT_STATUS BATT_CURRENT BYPASS MEM_FREE MEM_TOTAL ZRAM_USED PANEL_HZ <<< "$RAW"

    # Fetch per-game stats every 3 loops (gfxinfo is slower)
    if [ $((LOOP % 3)) -eq 0 ]; then
        GAME_RAW=$(get_game_fps)
        if [ -n "$GAME_RAW" ]; then
            IFS='|' read -r GAME_PKG GAME_FPS TOTAL_FRAMES JANKY_FRAMES FRAME_DROPS <<< "$GAME_RAW"
        fi
    fi

    # Delta jank frames since last sample
    DELTA_JANKY=$((JANKY_FRAMES - PREV_JANKY_FRAMES))
    DELTA_TOTAL=$((TOTAL_FRAMES - PREV_TOTAL_FRAMES))
    if [ "$DELTA_TOTAL" -gt 0 ]; then
        JANK_PCT=$(awk "BEGIN {printf \"%.1f\", ($DELTA_JANKY * 100) / $DELTA_TOTAL}")
    else
        JANK_PCT="0.0"
    fi
    PREV_JANKY_FRAMES=$JANKY_FRAMES
    PREV_TOTAL_FRAMES=$TOTAL_FRAMES

    # Unit conversions
    CPU0_GHZ=$(awk "BEGIN {printf \"%.2f\", ${CPU0:-0}/1000000}")
    CPU4_GHZ=$(awk "BEGIN {printf \"%.2f\", ${CPU4:-0}/1000000}")
    CPU7_GHZ=$(awk "BEGIN {printf \"%.2f\", ${CPU7:-0}/1000000}")
    GPU_MHZ=$(awk "BEGIN {printf \"%d\", ${GPU_FREQ:-0}/1000000}")
    SOC_C=$(awk "BEGIN {printf \"%.1f\", ${SOC_TEMP:-0}/1000}")
    BATT_C=$(awk "BEGIN {printf \"%.1f\", ${BATT_TEMP:-0}/10}")
    BATT_MA=$(awk "BEGIN {printf \"%d\", ${BATT_CURRENT:-0}/1000}")

    # FPS color (hardware display)
    FPS_NUM=$(echo "$FPS" | awk '{print int($1)}')
    if [ "$FPS_NUM" -ge 110 ]; then FPS_COLOR="$C_CYAN"
    elif [ "$FPS_NUM" -ge 55 ]; then FPS_COLOR="$C_GREEN"
    elif [ "$FPS_NUM" -ge 40 ]; then FPS_COLOR="$C_YELLOW"
    else FPS_COLOR="$C_RED"; fi

    # Game FPS color
    GFPS_NUM=$(echo "$GAME_FPS" | awk '{print int($1)}')
    if [ "$GFPS_NUM" -ge 110 ]; then GFPS_COLOR="${C_CYAN}${C_BOLD}"
    elif [ "$GFPS_NUM" -ge 55 ]; then GFPS_COLOR="${C_GREEN}${C_BOLD}"
    elif [ "$GFPS_NUM" -ge 40 ]; then GFPS_COLOR="${C_YELLOW}${C_BOLD}"
    else GFPS_COLOR="${C_RED}${C_BOLD}"; fi

    # Profile display
    if [ "$KI_MODE" = "2" ]; then
        PROF_COLOR="${C_RED}${C_BOLD}"; PROF_TXT="[2] PERFORMANCE (TURBO)"
    elif [ "$KI_MODE" = "0" ]; then
        PROF_COLOR="${C_BLUE}"; PROF_TXT="[0] BATTERY SAVER"
    else
        PROF_COLOR="${C_GREEN}"; PROF_TXT="[1] BALANCED"
    fi

    # Bypass status
    if [ "$BYPASS" = "1" ]; then
        BYPASS_TXT="${C_GREEN}${C_BOLD}BYPASS ACTIVE (0mA to Battery)${C_RESET}"
    else
        BYPASS_TXT="${C_YELLOW}Normal${C_RESET}"
    fi

    # Build FPS rolling graph
    FPS_GRAPH=$(draw_fps_graph "$FPS")

    # Jank indicator
    JANK_DISPLAY=$(get_jank_color "$JANK_PCT")

    # ── Draw UI ──────────────────────────────────────────────────────────────
    tput cup 0 0
    echo -e "${C_CYAN}╔════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET} ${C_BOLD}⚡ Ki-Kernel Live Monitor — SM8250 munch ⚡${C_RESET}                       ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╠════════════════════════════════════════════════════════════════════════╣${C_RESET}"

    # ── FPS Section ───────────────────────────────────────────────────────────
    printf " ${C_BOLD}Display FPS :${C_RESET} ${FPS_COLOR}${C_BOLD}%-8s FPS${C_RESET}   " "$FPS"
    printf "${C_BOLD}App FPS :${C_RESET} ${GFPS_COLOR}%-6s FPS${C_RESET}\n" "$GAME_FPS"
    # Panel Hz indicator
    if [ "${PANEL_HZ:-0}" -ge 110 ]; then
        PANEL_COLOR="${C_CYAN}${C_BOLD}"
    else
        PANEL_COLOR="${C_YELLOW}"
    fi
    echo -e " ${C_GRAY}Panel HW :${C_RESET} ${PANEL_COLOR}${PANEL_HZ:-?} Hz${C_RESET} ${C_GRAY}(hardware vsync)  ${C_RESET}${C_BOLD}App:${C_RESET} ${C_WHITE}$(echo "$GAME_PKG" | sed 's/.*\.\([^.]*\)$/\1/')${C_RESET}"
    echo -e " ${C_BOLD}Jank      :${C_RESET} ${JANK_DISPLAY}   ${C_BOLD}Ki-Profile:${C_RESET} ${PROF_COLOR}${PROF_TXT}${C_RESET}"

    # ── Rolling FPS Graph ─────────────────────────────────────────────────────
    echo -e "${C_GRAY}── FPS History (30s) ──────────────────────── 0▁ 40▄ 60▅ 90▇ 120█ ─────${C_RESET}"
    echo -e " ${FPS_GRAPH}"
    echo -e " ${C_GRAY}Frame Drops: ${C_RESET}${C_YELLOW}${FRAME_DROPS}${C_RESET}   ${C_GRAY}Total Janky: ${C_RESET}${C_YELLOW}${JANKY_FRAMES}${C_RESET}   ${C_GRAY}Total Frames: ${C_RESET}${TOTAL_FRAMES}"

    # ── GPU Section ───────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── GPU (Adreno 650) ────────────────────────────────────────────────────${C_RESET}"
    echo -e "   Clock: ${C_CYAN}${GPU_MHZ} MHz${C_RESET}  Load: ${C_YELLOW}${GPU_LOAD:-0%}${C_RESET}  DDR: $([ "$GPU_BUS" = "1" ] && echo -e "${C_GREEN}LOCKED${C_RESET}" || echo -e "${C_GRAY}Auto${C_RESET}")  Throttle: $([ "$GPU_THROT" = "0" ] && echo -e "${C_GREEN}OFF${C_RESET}" || echo -e "${C_RED}ON${C_RESET}")"

    # ── CPU Section ───────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── CPU (1+3+4 SD870) ───────────────────────────────────────────────────${C_RESET}"
    echo -e "   ${C_GRAY}Prime ${C_RESET}C7: ${C_RED}${CPU7_GHZ} GHz${C_RESET}  ${C_GRAY}Gold${C_RESET} C4-6: ${C_YELLOW}${CPU4_GHZ} GHz${C_RESET}  ${C_GRAY}Silver${C_RESET} C0-3: ${C_CYAN}${CPU0_GHZ} GHz${C_RESET}"
    echo -e "   Thermal Isolation: $([ "$KI_THROTTLE" = "0" ] && echo -e "${C_GREEN}BYPASSED (8 cores locked)${C_RESET}" || echo -e "${C_YELLOW}Active${C_RESET}")"

    # ── Temp & Battery ────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── Thermals & Power ────────────────────────────────────────────────────${C_RESET}"
    echo -e "   SoC: ${C_BOLD}${SOC_C}°C${C_RESET}  Batt: ${C_BOLD}${BATT_C}°C${C_RESET}   Bypass: ${BYPASS_TXT}"
    echo -e "   Battery: ${C_BOLD}${BATT_LEVEL}%${C_RESET} (${BATT_STATUS}, ${C_BOLD}${BATT_MA} mA${C_RESET})"

    # ── Memory ────────────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── RAM & zRAM ──────────────────────────────────────────────────────────${C_RESET}"
    echo -e "   Free: ${C_GREEN}${MEM_FREE} MB${C_RESET} / ${MEM_TOTAL} MB   zRAM: ${C_YELLOW}${ZRAM_USED} MB${C_RESET}"

    # ── Controls ──────────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── Controls ────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "  [${C_RED}2${C_RESET}] Performa  [${C_GREEN}1${C_RESET}] Balanced  [${C_BLUE}0${C_RESET}] Battery  [${C_CYAN}b${C_RESET}] Bypass  [${C_YELLOW}h${C_RESET}] 120Hz  [${C_MAGENTA}q${C_RESET}] Quit"
    echo -e "${C_CYAN}════════════════════════════════════════════════════════════════════════${C_RESET}"

    # ── Non-blocking input ────────────────────────────────────────────────────
    if [ -t 0 ]; then
        read -t 1 -s -n 1 KEY
    else
        sleep 1
        KEY=""
    fi
    if [ -n "$KEY" ]; then
        case "$KEY" in
            2) adb shell "su -c 'echo 2 > /sys/kernel/ki_profile/mode'" 2>/dev/null ;;
            1) adb shell "su -c 'echo 1 > /sys/kernel/ki_profile/mode'" 2>/dev/null ;;
            0) adb shell "su -c 'echo 0 > /sys/kernel/ki_profile/mode'" 2>/dev/null ;;
            b|B)
                if [ "$BYPASS" = "1" ]; then
                    adb shell "su -c 'echo 0 > /sys/class/power_supply/battery/bypass_charging'" 2>/dev/null
                else
                    adb shell "su -c 'echo 1 > /sys/class/power_supply/battery/bypass_charging'" 2>/dev/null
                fi ;;
            h|H)
                adb shell "su -c 'service call SurfaceFlinger 1035 i32 1'" 2>/dev/null
                adb shell "settings put system peak_refresh_rate 120.0; settings put system min_refresh_rate 120.0" 2>/dev/null ;;
            r|R)
                # Reset gfxinfo counters
                adb shell "su -c 'dumpsys gfxinfo ${GAME_PKG} reset'" 2>/dev/null
                PREV_TOTAL_FRAMES=0; PREV_JANKY_FRAMES=0 ;;
            q|Q) break ;;
        esac
    fi
done

tput cnorm
echo -e "\n${C_GREEN}Monitor selesai.${C_RESET}"
