# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-05  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI / HyperOS & AOSP
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## v1.4 P3
• Extreme Gaming & Anti-Drop FPS Overhaul (Locked 60 / 120 FPS Pacing):
  - Added Zero-Lag CPU Floor Frequency (`sugov_set_cluster_floor`):
    * Silver (CPU 0–3): 1.21 GHz minimum floor (eliminates 300 MHz drops)
    * Gold (CPU 4–6): 1.61 GHz minimum floor (eliminates 710 MHz drops)
    * Prime (CPU 7): 1.71 GHz minimum floor (eliminates 844 MHz drops)
    * Completely eliminates DVFS ramp-up and clock synthesizer relock delay
  - Instant Snap Hispeed threshold lowered to 15% load (immediate jump to 1.80 / 2.42 / 3.19 GHz on any render activity)
  - Extended cpufreq down-rate delay (`down_rate_limit_us`) to 150ms (holds peak turbo across ~9 frames without clock bouncing)
  - Enabled WALT Performance Level (PL) Hinting (`sugov_set_cluster_pl`) for foreground game threads
  - Ultra-aggressive task & group migration:
    * `sched_set_updown_migrate(20, 10)` — tasks migrate to Gold at only 20% load
    * `sched_set_group_updown_migrate(30, 15)` — render thread groups pinned to Gold/Prime
  - Adreno 650 GPU Turbo Enhancements:
    * Floor frequency raised to 587 MHz (operates exclusively at 587 MHz & 683 MHz OC)
    * Instant jump to 683 MHz max turbo upon activating Performance mode
    * Forced `CLK_ON = 1` (GPU clocks stay awake, eliminating slumber/wake-up stalls)
    * Extended GPU idle timeout to 2000ms
  - Tuned VM Swappiness to 150 across profiles with LZ4 zRAM (frees up physical RAM for game assets and hot page cache, eliminates direct reclaim freezes)
  - Integrated Konabess Extreme UV v2 + OC 683 MHz DTB into AnyKernel3 vendor_boot flashing
• Stability, Thermal Safety & Multitasking Upgrades:
  - Added In-Kernel Thermal Auto-Guard (`ki_profile`):
    * Bypasses thermal throttle during Performance gaming for maximum FPS, but monitors die and skin thermals every 2s
    * Automatically re-arms throttling if CPU/GPU die >= 85°C or body (quiet_therm) >= 46°C for hardware protection
    * Automatically releases throttle when cooled to die <= 75°C and body <= 42°C with hysteresis
  - Added Screen-off Auto Battery Profile (`ki_profile`):
    * Hooks into Xiaomi DRM display notifier (`mi_drm_register_client`)
    * Automatically switches to Battery profile after 3s of screen off to maximize deep sleep battery life
    * Instantly (0ms) restores user's active profile (Balanced/Performance) upon screen on
    * Sysfs controls: `/sys/kernel/ki_profile/screen_off_battery` and `/sys/kernel/ki_profile/active_profile`
  - Added LMKD & PSI Anti-Kill Multitasking Tuning:
    * Disabled `sys.lmk.kill_heaviest_task` to prevent sudden app closures during memory spikes
    * Extended `ro.lmk.psi_partial_stall_ms` to 180ms to allow zRAM compression before killing apps
    * Tuned `ro.lmk.thrashing_limit` to 50 for smooth foreground app retention
  - Refactored Ki-Profile core into a clean, lightweight, table-driven engine
• Networking & Controller Upgrades:
  - Enabled CAKE Smart Queue Management Qdisc (`CONFIG_NET_SCH_CAKE=y`):
    * Advanced bufferbloat elimination paired with native BBRv3 congestion control
    * Keeps online gaming ping ultra-low and jitter-free even under heavy background downloads or hotspot tethering
  - Enabled Sony PlayStation 5 DualSense Controller Driver (`CONFIG_HID_PLAYSTATION=y` & `CONFIG_PLAYSTATION_FF=y`):
    * Full native plug-and-play support for PS5 DualSense controllers via USB and Bluetooth
    * Force feedback vibration, lightbar, and motion sensor controls fully supported

---

## v1.4 P2
• Unified & Ported all optimizations to Astide Base (Android 14-17 AOSP & MIUI/HyperOS)
• Extreme Gaming Performance Mode Overhaul (WuWa / Heavy Games Edition):
  - Adreno 650 GPU floor frequency locked to 510 MHz (runs only at 510, 587, and 683 MHz OC, eliminating mid-game frame drops)
  - DDR AXI Bus locked high (`force_bus_on = 1`) to eliminate 3D texture & shader streaming hitches
  - Disabled internal Adreno cycle-skipping clock throttling in Performance mode
  - Extended GPU idle timeout to 1000ms for stable inter-frame clock pacing
  - Added CPU Instant Snap Hispeed (`sugov_set_cluster_hispeed`) — snaps to max turbo (1.80/2.42/3.19 GHz) at 35-40% load without relying on Android WALT RTG classification
  - Extended cpufreq down-rate delay to 25ms to maintain peak clock speeds across 60, 90, and 120 FPS frame intervals
  - Bypassed Qualcomm thermal CPU core isolation (`cpu_isolate`) and GPU devfreq throttling in Performance mode — all 8 cores stay active
  - Auto-revive all isolated cores (`sched_unisolate_cpu`) upon activating Performance mode
  - Optimized VFS cache pressure and memory headroom for heavy 4GB+ games
• Added Maple I/O Scheduler (Android flash/UFS 3.1 optimized FIFO scheduler)
• Added KCAL Color Calibration driver (/sys/devices/platform/kcal_ctrl.0)
• Auto-populated Boeffla Wakelock Blocker on boot (wlan_pno_wl, wlan_extscan_wl, wlan_wow_wl, netmgr_wl)
• Fixed Focaltech 3658u Touchscreen sleep EIO and CRC abnormal logs on screen off/on
• Fixed Aftermarket / KW LCD DC dimming DCS commands and smart FPS fallback

---

## v1.4
• Switched default ZRAM compression to LZ4
• Fixed hardware DC Dimming
• Tuned Ki-Profile for higher gaming performance
• Improved CPU migration and schedutil response
• Tuned RAM, VM and kswapd behavior
• Improved Force Fast Charge and Screen-On Fast Charge
• Set ZRAM and system swappiness to 90
• Backported Binder TF_CLEAR_BUF support
• Added USB UAS support
• Added NTFS filesystem support
• Fixed CPU idle frequency and wake-from-idle issues
• Fixed MIUI and AnyKernel3 flashing issues
• Backported epoll_pwait2 and improved TCP Westwood
• Optimized CFS load balancing
• Optimized Focaltech touch and aw86927 haptic handling
• Removed Adreno POPP throttling and Wi-Fi debug wakelocks
• Added Boeffla Wakelock Blocker
• Improved Deep Sleep and suspend behavior
• Added Virtual A/B snapshot support
• Tuned F2FS background GC
• Improved GPU and touchscreen thread scheduling
• Enabled Clang ThinLTO
---

## v1.3
• Added in-kernel ki_profile switcher (Battery / Balanced / Performance)
• Added Dynamic Fsync
• Migrated to ReSukiSU v4.2.0
• Backported NTSYNC driver
• Upstream SUSFS v2.3.0
• Improved CPU idle frequency handling
• Added I/O wait boost limits
• Fixed Wi-Fi hotspot and tethering
• Improved bypass charging handling
• Migrated to ZyCromerZ Clang 16.0.6

---
  <a href="https://t.me/+i7NfuXZA6mZjOWJl">
    <img src="https://img.shields.io/badge/Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram">
  </a>

