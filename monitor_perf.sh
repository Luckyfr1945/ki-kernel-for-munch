#!/usr/bin/env bash
# ==============================================================================
# Ki-Kernel Realtime Gaming & Hardware Monitor for POCO F4 / munch (SM8250)
# Tracks Hardware Display FPS, App/Game FPS, frame jank/drops,
# rolling FPS graph, CPU clusters, Adreno 650 GPU, Temperatures,
# Bypass Charging, RAM & zRAM, and Ki-Profile mode with interactive toggles.
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

# Deploy helper script to device for zero-overhead atomic metrics collection
HELPER_SRC="$(dirname "$0")/scripts/ki_monitor_helper.sh"
if [ -f "$HELPER_SRC" ]; then
    adb push "$HELPER_SRC" /data/local/tmp/ki_monitor_helper.sh >/dev/null 2>&1
    adb shell "su -c 'chmod 755 /data/local/tmp/ki_monitor_helper.sh'" >/dev/null 2>&1
fi

# Set 500ms periodicity on device for accurate real-time FPS
adb shell "su -c 'echo 500 > /sys/devices/platform/soc/ae00000.qcom,mdss_mdp/drm/card0/sde-crtc-0/fps_periodicity_ms 2>/dev/null'" >/dev/null 2>&1

# Rolling FPS history (last 30 samples = ~30s)
FPS_HISTORY=()
HISTORY_MAX=30
PREV_TOTAL_FRAMES=0
PREV_JANKY_FRAMES=0
PREV_TIME_MS=0
APP_FPS="0.0"
JANK_PCT="0.0"

clear
echo -e "${C_CYAN}${C_BOLD}Starting Ki-Kernel Monitor on device ${DEVICE}...${C_RESET}"

# ─── Rolling FPS Bar Graph (30 samples) ───────────────────────────────────────
draw_fps_graph() {
    local fps_val="$1"
    FPS_HISTORY+=("$fps_val")
    if [ "${#FPS_HISTORY[@]}" -gt "$HISTORY_MAX" ]; then
        FPS_HISTORY=("${FPS_HISTORY[@]:1}")
    fi

    local bars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
    local max_fps=125
    local graph=""
    for val in "${FPS_HISTORY[@]}"; do
        local fint=$(echo "$val" | awk '{print int($1)}')
        [ "$fint" -gt "$max_fps" ] && fint=$max_fps
        [ "$fint" -lt 0 ] && fint=0
        local idx=$(awk "BEGIN {print int($fint * 7 / $max_fps)}")
        local bar="${bars[$idx]}"
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
clear

while true; do
    NOW_MS=$(date +%s%3N)

    # Fetch hardware metrics in one fast atomic pass
    RAW=$(adb shell "su -c /data/local/tmp/ki_monitor_helper.sh" 2>/dev/null)
    if [ -z "$RAW" ]; then
        sleep 0.8
        continue
    fi

    IFS='|' read -r FPS KI_MODE KI_THROT CPU0 CPU4 CPU7 GPU_FREQ GPU_LOAD GPU_THROT GPU_BUS SOC_TEMP BATT_TEMP BATT_LEVEL BATT_STATUS BATT_CURRENT BYPASS MEM_FREE MEM_TOTAL ZRAM_USED PANEL_HZ TOP_APP TOTAL_FRAMES JANKY_FRAMES FRAME_DROPS <<< "$RAW"

    # Delta App FPS calculation
    if [ "$PREV_TIME_MS" -gt 0 ]; then
        DELTA_MS=$((NOW_MS - PREV_TIME_MS))
        DELTA_FRAMES=$((TOTAL_FRAMES - PREV_TOTAL_FRAMES))
        DELTA_JANKY=$((JANKY_FRAMES - PREV_JANKY_FRAMES))

        if [ "$DELTA_MS" -gt 0 ] && [ "$DELTA_FRAMES" -ge 0 ]; then
            APP_FPS=$(awk "BEGIN {printf \"%.1f\", ($DELTA_FRAMES * 1000) / $DELTA_MS}")
        else
            APP_FPS="0.0"
        fi

        if [ "$DELTA_FRAMES" -gt 0 ] && [ "$DELTA_JANKY" -ge 0 ]; then
            JANK_PCT=$(awk "BEGIN {printf \"%.1f\", ($DELTA_JANKY * 100) / $DELTA_FRAMES}")
        else
            JANK_PCT="0.0"
        fi
    fi
    PREV_TOTAL_FRAMES=${TOTAL_FRAMES:-0}
    PREV_JANKY_FRAMES=${JANKY_FRAMES:-0}
    PREV_TIME_MS=$NOW_MS

    # Friendly App Name
    case "$TOP_APP" in
        *trill*|*tiktok*|*aweme*) APP_NAME="TikTok" ;;
        *shopee*) APP_NAME="Shopee" ;;
        *instagram*) APP_NAME="Instagram" ;;
        *whatsapp*) APP_NAME="WhatsApp" ;;
        *youtube*) APP_NAME="YouTube" ;;
        *freefire*|*dts*) APP_NAME="Free Fire" ;;
        *mobile.legends*) APP_NAME="Mobile Legends" ;;
        *genshin*) APP_NAME="Genshin Impact" ;;
        *launcher*|*System*|*systemui*) APP_NAME="System Launcher" ;;
        *) APP_NAME=$(echo "$TOP_APP" | sed 's/.*\.\([^.]*\)$/\1/') ;;
    esac

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

    # App FPS color
    AFPS_NUM=$(echo "$APP_FPS" | awk '{print int($1)}')
    if [ "$AFPS_NUM" -ge 110 ]; then AFPS_COLOR="${C_CYAN}${C_BOLD}"
    elif [ "$AFPS_NUM" -ge 55 ]; then AFPS_COLOR="${C_GREEN}${C_BOLD}"
    elif [ "$AFPS_NUM" -ge 40 ]; then AFPS_COLOR="${C_YELLOW}${C_BOLD}"
    else AFPS_COLOR="${C_RED}${C_BOLD}"; fi

    # Profile display
    if [ "$KI_MODE" = "2" ]; then
        PROF_COLOR="${C_RED}${C_BOLD}"; PROF_TXT="[2] PERFORMANCE (TURBO)"
    elif [ "$KI_MODE" = "0" ]; then
        PROF_COLOR="${C_BLUE}${C_BOLD}"; PROF_TXT="[0] BATTERY SAVER"
    else
        PROF_COLOR="${C_GREEN}${C_BOLD}"; PROF_TXT="[1] BALANCED"
    fi

    # Bypass status
    if [ "$BYPASS" = "1" ]; then
        BYPASS_TXT="${C_GREEN}${C_BOLD}BYPASS ACTIVE (0mA to Battery)${C_RESET}"
    else
        BYPASS_TXT="${C_YELLOW}Normal (Charging Battery)${C_RESET}"
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
    printf " ${C_BOLD}Display FPS :${C_RESET} ${FPS_COLOR}${C_BOLD}%-5s FPS${C_RESET}   " "$FPS"
    printf "${C_BOLD}App FPS :${C_RESET} ${AFPS_COLOR}%-5s FPS${C_RESET}\n" "$APP_FPS"
    # Panel Hz indicator
    if [ "${PANEL_HZ:-0}" -ge 110 ]; then
        PANEL_COLOR="${C_CYAN}${C_BOLD}"
    else
        PANEL_COLOR="${C_YELLOW}"
    fi
    printf " ${C_GRAY}Panel HW    :${C_RESET} ${PANEL_COLOR}%-3s Hz${C_RESET} ${C_GRAY}(hardware vsync)${C_RESET}  ${C_BOLD}App:${C_RESET} ${C_WHITE}%-16s${C_RESET}\n" "${PANEL_HZ:-60}" "$APP_NAME"
    echo -e " ${C_BOLD}Jank        :${C_RESET} ${JANK_DISPLAY}   ${C_BOLD}Ki-Profile:${C_RESET} ${PROF_COLOR}${PROF_TXT}${C_RESET}"

    # ── Rolling FPS Graph ─────────────────────────────────────────────────────
    echo -e "${C_GRAY}── FPS History (30s) ──────────────────────── 0▁ 40▄ 60▅ 90▇ 120█ ─────${C_RESET}"
    echo -e " ${FPS_GRAPH}"
    echo -e " ${C_GRAY}Frame Drops: ${C_RESET}${C_YELLOW}${FRAME_DROPS:-0}${C_RESET}   ${C_GRAY}Total Janky: ${C_RESET}${C_YELLOW}${JANKY_FRAMES:-0}${C_RESET}   ${C_GRAY}Total Frames: ${C_RESET}${TOTAL_FRAMES:-0}"

    # ── GPU Section ───────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── GPU (Adreno 650) ────────────────────────────────────────────────────${C_RESET}"
    echo -e "   Clock: ${C_CYAN}${GPU_MHZ} MHz${C_RESET}  Load: ${C_YELLOW}${GPU_LOAD:-0%}${C_RESET}  DDR: $([ "$GPU_BUS" = "1" ] && echo -e "${C_GREEN}LOCKED${C_RESET}" || echo -e "${C_GRAY}Auto${C_RESET}")  Throttle: $([ "$GPU_THROT" = "0" ] && echo -e "${C_GREEN}OFF${C_RESET}" || echo -e "${C_RED}ON${C_RESET}")"

    # ── CPU Section ───────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── CPU (1+3+4 SD870) ───────────────────────────────────────────────────${C_RESET}"
    echo -e "   ${C_GRAY}Prime ${C_RESET}C7: ${C_RED}${CPU7_GHZ} GHz${C_RESET}  ${C_GRAY}Gold${C_RESET} C4-6: ${C_YELLOW}${CPU4_GHZ} GHz${C_RESET}  ${C_GRAY}Silver${C_RESET} C0-3: ${C_CYAN}${CPU0_GHZ} GHz${C_RESET}"
    echo -e "   Thermal Isolation: $([ "$KI_THROT" = "0" ] && echo -e "${C_GREEN}BYPASSED (8 cores locked)${C_RESET}" || echo -e "${C_YELLOW}Active${C_RESET}")"

    # ── Temp & Battery ────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── Thermals & Power ────────────────────────────────────────────────────${C_RESET}"
    echo -e "   SoC: ${C_BOLD}${SOC_C}°C${C_RESET}  Batt: ${C_BOLD}${BATT_C}°C${C_RESET}   Bypass: ${BYPASS_TXT}"
    echo -e "   Battery: ${C_BOLD}${BATT_LEVEL}%${C_RESET} (${BATT_STATUS}, ${C_BOLD}${BATT_MA} mA${C_RESET})"

    # ── Memory ────────────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── RAM & zRAM ──────────────────────────────────────────────────────────${C_RESET}"
    echo -e "   Free: ${C_GREEN}${MEM_FREE} MB${C_RESET} / ${MEM_TOTAL} MB   zRAM: ${C_YELLOW}${ZRAM_USED} MB${C_RESET}"

    # ── Controls ──────────────────────────────────────────────────────────────
    echo -e "${C_GRAY}── Controls ────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "  [${C_RED}2${C_RESET}] Performa  [${C_GREEN}1${C_RESET}] Balanced  [${C_BLUE}0${C_RESET}] Battery  [${C_CYAN}b${C_RESET}] Bypass  [${C_YELLOW}h${C_RESET}] 120Hz  [${C_MAGENTA}r${C_RESET}] Reset  [${C_GRAY}q${C_RESET}] Quit"
    echo -e "${C_CYAN}════════════════════════════════════════════════════════════════════════${C_RESET}"

    # Non-blocking user input
    if [ -t 0 ]; then
        read -t 0.7 -s -n 1 KEY
    else
        sleep 0.7
        KEY=""
    fi

    if [ -n "$KEY" ]; then
        case "$KEY" in
            2) adb shell "su -c 'echo 2 > /sys/kernel/ki_profile/mode'" >/dev/null 2>&1 ;;
            1) adb shell "su -c 'echo 1 > /sys/kernel/ki_profile/mode'" >/dev/null 2>&1 ;;
            0) adb shell "su -c 'echo 0 > /sys/kernel/ki_profile/mode'" >/dev/null 2>&1 ;;
            b|B)
                if [ "$BYPASS" = "1" ]; then
                    adb shell "su -c 'echo 0 > /sys/class/power_supply/battery/bypass_charging'" >/dev/null 2>&1
                else
                    adb shell "su -c 'echo 1 > /sys/class/power_supply/battery/bypass_charging'" >/dev/null 2>&1
                fi ;;
            h|H)
                if [ "${PANEL_HZ:-60}" -ge 110 ]; then
                    adb shell "su -c 'service call SurfaceFlinger 1035 i32 0'" >/dev/null 2>&1
                    adb shell "settings put system peak_refresh_rate 60.0; settings put system min_refresh_rate 60.0" >/dev/null 2>&1
                else
                    adb shell "su -c 'service call SurfaceFlinger 1035 i32 1'" >/dev/null 2>&1
                    adb shell "settings put system peak_refresh_rate 120.0; settings put system min_refresh_rate 120.0" >/dev/null 2>&1
                fi ;;
            r|R)
                [ -n "$TOP_APP" ] && adb shell "su -c 'dumpsys gfxinfo $TOP_APP reset'" >/dev/null 2>&1
                PREV_TOTAL_FRAMES=0; PREV_JANKY_FRAMES=0 ;;
            q|Q) break ;;
        esac
    fi
done

tput cnorm
echo -e "\n${C_GREEN}Monitor selesai.${C_RESET}"
