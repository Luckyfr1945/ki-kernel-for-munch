# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-02  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI / HyperOS & AOSP
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

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

