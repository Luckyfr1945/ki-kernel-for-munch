# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-09  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI / HyperOS & AOSP (Android 14 – Android 17 ✅)
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  
**BPF Compatibility:** LineageOS 24 / LineageOS Base ✅ (Verified Boot on Android 17)  

---

## v1.4 P5 ✅ Verified Booting on Android 17 (LineageOS 24 Base)
• Resolved Sleep of Death (SoD) & Charging Black-Screen Hang:
  - Smart AC/Power Supply Aware: Prevented forced Battery Saver throttling on screen-off when plugged into charger (`power_supply_is_system_supplied() > 0`), ensuring Android idle maintenance (dexopt, fstrim) runs smoothly without starving the CPU
  - Sane Headroom & Lock Protection: Removed dynamic `setup_per_zone_wmarks()` and `ki_cpufreq_reset_idle_floors()` from rapid screen on/off workqueues to prevent memory zone lock contention and deadlocks with kswapd/zRAM
  - Active Screen-Off Profile Sync: Added `ki_get_active_profile()` in [include/linux/ki_profile.h](file:///home/kiki/kernel/kernel_xiaomi_sm8250_mod/include/linux/ki_profile.h) and [drivers/cpufreq/cpufreq.c](file:///home/kiki/kernel/kernel_xiaomi_sm8250_mod/drivers/cpufreq/cpufreq.c) so CPU idle floor clamp (300 MHz) is enforced against background daemons during standby
• Native Baseband-Guard LSM Integration (Anti-Format / Partition Shield):
  - Integrated `Baseband-guard` Linux Security Module (`security/baseband-guard/` with `CONFIG_BBG=y`)
  - Hardens and write-protects critical partitions against malicious root scripts, bad flashers, and wipe commands:
    * Protected: `modemst1`, `modemst2`, `fsg`, `fsc` (IMEI & Baseband RF calibration)
    * Protected: `xbl`, `xbl_config`, `abl`, `tz`, `hyp`, `dsp`, `devinfo` (Bootloader & TrustZone)
    * Enforces strict allowlist (`boot`, `userdata`, `metadata`, `misc`, `dtbo`, `vbmeta`, `recovery`)
• Multi-Manager Root Support (ReSukiSU + KSU Multi-Manager):
  - Enabled `CONFIG_KSU_MULTI_MANAGER_SUPPORT=y` in kernel and build system
  - Built-in recognition for APK signatures of 6 top manager implementations:
    * ReSukiSU Manager (Official)
    * KSUN / RKSU (KernelSU-Next)
    * KOWSU (KOWX712/KernelSU)
    * SukiSU-Ultra
    * MKSU (5ec1cff/KernelSU)
    * Official KernelSU (tiann/KernelSU)
  - Retained Dynamic Manager feature for custom/self-compiled APK signatures
• Fixed Background Media & Music Streaming Stopping on Screen-Off:
  - Removed `wlan_wow_wl` (Wake-on-WLAN) and `netmgr_wl` from Boeffla Wakelock Blocker default list in [boeffla_wl_blocker.c](file:///home/kiki/kernel/kernel_xiaomi_sm8250_mod/drivers/base/power/boeffla_wl_blocker.c) and [anykernel.sh](file:///home/kiki/kernel/kernel_xiaomi_sm8250_mod/anykernel_template/anykernel.sh)
  - Added strict in-kernel exemption in `is_critical_wakelock()` for audio/sound/media and network streaming wakelocks so YouTube (ReVanced/Premium), Spotify, and browser music continue smoothly without pausing when the screen is locked
• Fixed Aggressive App Kills & Multitasking Eviction (2x TikTok & Instagram No-Reload):
  - Fixed erroneous LMKD props in [anykernel.sh](file:///home/kiki/kernel/kernel_xiaomi_sm8250_mod/anykernel_template/anykernel.sh): set `kill_heaviest_task = true` (preventing brute-force serial purging of cached apps)
  - Relaxed `ro.lmk.psi_partial_stall_ms` to 250ms and `ro.lmk.thrashing_limit` to 100, preventing false-positive kills during heavy video segment caching (TikTok / IG reels)
  - Lowered `vm_swappiness` from 150 to 80 and set `vfs_cache_pressure = 80` across Balanced & Battery profiles to keep app dentry/inode caches in RAM
• Clear Differentiation Between Balanced and Battery Saver:
  - Balanced: Smooth 120Hz scrolling, fast 500us touch ramp, shortened 4ms down-hold (down from 20ms for battery savings), Silver 1.21G / Gold 1.38G / Prime 1.51G, migration 85/75
  - Battery Saver: True power-saver ("Irit Pol"), 98% pinned to Silver (migration 98/90), down-hold 2ms (instant drop to 300MHz), swappiness 60 (minimal zRAM churn), Silver 1.05G / Gold 1.17G / Prime 1.27G
• Cleaned Schedutil Governor Locking:
  - Removed redundant spinlock in `sugov_set_cluster_floor()` in [cpufreq_schedutil.c](file:///home/kiki/kernel/kernel_xiaomi_sm8250_mod/kernel/sched/cpufreq_schedutil.c)
• Live Hardware & Gaming Monitor (monitor_perf.sh) Overhaul:
  - Fixed blank RAM & zRAM metrics (`Free MB / Total MB / zRAM MB`) via atomic device helper script
  - Fixed duplicate Display FPS string formatting (`Display FPS : 42.9 FPS`)
  - Modernized App detection via `topResumedActivity` (supports Android 14/15/16/17)
  - SurfaceFlinger display rate synchronization (clean 60 Hz / 120 Hz)
  - Added `[r]` interactive key to reset frame/jank stats on the fly

## v1.4 P4
• Android 17 Boot & BPF Subsystem Overhaul — **Confirmed Working** ✅:
  - **Real-device verified:** Ki-Kernel boots cleanly and fully stable on Android 17 (LineageOS 24 base)
  - **BPF on par with LineageOS 24:** BPF verifier, program loader, and map semantics behave identically to upstream LineageOS 4.19-based kernels
  - Fixed fatal `reboot,bpfloader-failed` on Android 15, 16, and 17:
    * Cherry-picked upstream LineageOS fix (`UPSTREAM: selinux: enable genfscon labeling for securityfs` with `SE_SBGENFS` in `security/selinux/hooks.c`)
    * Enabled `CONFIG_SECURITYFS=y` in vendor & device defconfigs
  - Modernized arm64 BPF JIT & instruction set:
    * Backported BPF `JMP32` instruction set (32-bit jumps) for modern Clang `-mcpu=v3` compatibility
    * Backported 64-bit atomic operations (`BPF_ATOMIC`, atomic add, fetch_add)
    * Backported `XDP_SOCKETS` socket ops and coarse-grained ktime for Bionic bpf loader compatibility
  - Wired up `close_range()` system call (NR 436 in `fs/open.c` & `syscalls.h`) for Bionic runtime loader
  - Purged all dirty e404 hacks & fake uname (`5.15`) — kernel cleanly identifies as native **4.19.325** to prevent BPF verifier breakage and GKI mismatch rejections
• Native NoMount Subsystem Integration (Built-in VFS Redirection):
  - Integrated `NoMount` driver natively into kernel core (`fs/nomount/` with `CONFIG_NOMOUNT=y`)
  - Enables mountless module loading & path redirection in RAM without generating visible mounts in `/proc/mounts` or `/proc/self/mountinfo`
  - Integrated Linux Keyring communication (`add_key`) for userspace `nm` tool and WebUI
  - Supports UID app exclusion/isolation for banking apps and root detectors
  - Seamlessly paired with ReSukiSU and SUSFS v1.5.x
• Smart Bypass Charging UI Polish:
  - Hidden lightning/charging icon during bypass charging mode for clean static battery status bar indication

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
• Hardened Bypass Charging v2 Architecture Overhaul (No-Drain Gaming Edition):
  - Decoupled bypass charging completely from `POWER_SUPPLY_PROP_INPUT_SUSPEND` to prevent breaking internal kernel suspend operations (connector thermal protection >= 70°C & BMS I2C error recovery)
  - Enforced 3.0A USB Input Current Limit override (`vote_override` 3000000 uA) during bypass: guarantees chargers (including laptop USB-PD 65W/100W) deliver full 15W–27W to the motherboard (`VSYS`), completely eliminating battery supplement drain (-1400 mA) during heavy gaming loads
  - Added anti-choke guard in `smblib_set_prop_battery_charging_enabled`: prevents Android battery HAL from throttling input current to 50mA (`MAIN_CHG_SUSPEND_ICL`) when charging is disabled
  - Automatically unvotes Charge Pump (`cp_disable_votable`) so fast charging pump does not feed battery
  - Added automatic cable-disconnect cleanup: resets bypass state and restores normal charging when the charger is unplugged
  - Integrated Automatic Failsafe Guard: monitors battery state during bypass and automatically disengages bypass if SOC drops <= 15% or battery temperature exceeds 43°C
  - Hardened sysfs node `/sys/class/power_supply/battery/bypass_charging` with root permission enforcement (`-EPERM` for non-root) and strict error handling
• Deep Idle Frequency Unlocking & Userspace Boost Defense (`cpufreq` & `ki_profile`):
  - Solved Little cluster stuck at 691.2 MHz caused by vendor ROM `post_boot.sh` and `powerhint.json` hardcoded baseline
  - In-kernel sysfs intercept in `store_scaling_min_freq`: maps userspace idle hint reset (`val <= 691200`) directly to true hardware minimum (300 MHz)
  - Preserved silky touch/interaction boost response while guaranteeing instant drop back to 300 MHz idle
  - Added programmatic floor enforcement (`ki_cpufreq_reset_idle_floors`) across all clusters on boot and profile switch
  - Locked minimum frequency to hardware baseline in Battery mode (Silver 300M, Gold 710M, Prime 845M), preventing runaway userspace apps from inflating idle floor
  - Added baseline frequency initialization in AnyKernel3 `00_nkm_bypass.sh` service
• Universal 67W Turbo Charge & PPS Optimization Across All ROMs (AOSP & MIUI/HyperOS):
  - Completely unlocked 67W direct flash charging on AOSP / Custom ROMs by bypassing MIUI-proprietary userspace digest checks
  - Eliminated BQ27Z561 fuel gauge 2A charging current clamp (`CURRENT_MAX`) and unvoted `BMS_FG_VERIFY` / `BMS_VERIFY_VOTER` limits
  - Automated PPS verification in USB-PD Policy Manager (`pd_policy_manager_munch`): promotes all qualified PPS adapters to `POWER_SUPPLY_PPS_VERIFIED` immediately without requiring proprietary `pd_authentication`
  - Unvoted `NON_PPS_PD_FCC_VOTER` 3000 mA restriction and eliminated 5-second PPS negotiation delay
  - Automatically unvoted `PD_VERIFED_VOTER` in `smb5-lib-munch` and mapped all USB-PD / PPS charging to `QUICK_CHARGE_TURBE` for full turbo speeds and UI animation support
  - Integrated AnyKernel3 service.d triggers for `pd_authentication`, `fastcharge_mode`, and `authentic` sysfs nodes

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

