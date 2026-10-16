# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-15  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI/HyperOS and AOSP  
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## Ki-kernel v1.4.1 P1:
- Added Boeffla Wakelock Blocker with clean `1`/`0` toggle via `/sys/kernel/wakelock_blocker/enabled`
- Block unnecessary background scan wakeups (`wlan_pno_wl`, `wlan_extscan_wl`, `netmgr_wl`) to reduce idle battery drain
- Kept CPU governor & scheduler EAS migration untouched to maintain 100% smooth, stutter-free 120 FPS gaming
- Updated Ki-Optimizer Magisk/KSU WebUI module (v1.1) with clean "Wakelock Blocker" toggle switch (no CLI required)
- Default state set to OFF (`0`) for zero regression on stock behavior
- Smart Multi-Stage AnyKernel3 ROM Detection (E404 Method Integrated):
  - Added `/vendor/build.prop` and `/product/etc/build.prop` region checks (`ro.vendor.miui.build.region` / `ro.miui.build.region`)
  - Added POCO F4 hardware feature verification (`device_features/munch.xml`)
  - Added dynamic A/B slot-aware (`system$SLOT` / `product$SLOT`) detection for HyperOS & Custom AOSP ROMs
  - Accurate ROM detection reporting in recovery UI automatically
- Completely purged all hardcoded kernel overrides from AnyKernel scripts (swappiness, vfs_cache_pressure, maple scheduler, scaling_min_freq, mglru, wakelock blocker)
- All kernel features and toggles are now 100% user-controlled exclusively via the Ki-Kernel Settings module (`ki_optimizer.conf` and WebUI)
- Fixed MGLRU and Wakelock Blocker turning back on across reboots (prevented interference with WhatsApp background notifications)
- Tuned Balanced Profile Schedutil Golden Ratio: ramp-up 500us Silver/Gold & 1500us Prime, down-rate hold time 10ms (covers 120Hz 8.33ms frame window with zero micro-stutter while keeping SoC ~4-6°C cooler)
- Enabled selective thermal bypass on Performance mode with 46°C skin auto-guard to eliminate 30/31 FPS thermal cap during gaming
- Enhanced Battery Saver with Ultra Power Saving tunings (Silver 979MHz, Gold 1.07GHz, Prime 1.17GHz, 1ms instant drop to 300MHz idle)
- Hardened AOSP screen-off battery state logic against getting stuck in low-power mode when screen wakes up
- Added SurfaceFlinger anti-30fps cap properties in AnyKernel and module service scripts
- Fixed persistent 50W fast charging lock and overheating when screen is active
- Set `force_fast_charge` and `screen_on_fast_charge` to OFF (`0`) by default to protect battery health and avoid thermal degradation
- Synchronized `force_fast_charge` toggle to automatically deactivate `screen_on_fast_charge` when turned off in Kernel Manager
- Restored instant re-evaluation to stock thermal throttling levels upon turning off fast charge overdrive
- Fixed 49°C thermal emergency clamp in Screen-on / Force Fast Charge by evaluating from `raw_system_temp_level` and preserved PPS thermal stepping
- Hardened Bypass Charging against bypassing hardware safety voters by unvoting `USER_VOTER` & `MAIN_CHG_SUSPEND_VOTER` without `vote_override` (maintains moisture & thermal protection)
- Isolated USB connector thermal emergency shutdown and BMS I2C error recovery to direct `smblib_set_usb_suspend` calls (prevented accidental Bypass Charging toggles)
- Fixed non-functional Night Light (Cahaya Malam) on AOSP / Custom ROMs (crDroid / Lunaris / Android 14–16)
- Fixed LiveDisplay and Color Calibration (Warna) settings not applying to display
- Set KCAL disabled by default to grant native Android ColorTransform (PCC/CTM) full hardware control
- Prevented KCAL from overriding the display DSPP hardware block on every frame commit
- Enabled harmonious color blending when KCAL is active alongside Night Light

---

## Ki-kernel v1.4.1:
- Fixed CPU governor switch kernel panics and Use-After-Free crashes
- Fixed schedutil clock bouncing and frequency micro-stutters
- Restored 300 MHz CPU deep idle frequency
- Tuned CPU hispeed clocks, ramp-up delays, and task migration thresholds
- Added dynamic per-cluster I/O wait boost controls in Ki-Profile
- Fixed PMIC brownout and hard reboots under heavy overclock loads
- Fixed Ki-Profile Thermal Auto-Guard race conditions and late sensor probing
- Added dynamic screen-off profile switching on charger events
- Fixed active Ki-Profile log reporting during screen-off boot
- Fixed 30-minute bypass charging cutoff and raised thermal limit to 48°C
- Backported ARM64 WFE hardware lock contention optimizations
- Optimized rwsem fast-spin lock handoff and memory mapping latency
- Fixed realtime timer slack jitter on SurfaceFlinger, audio HAL, and GPU workers
- Tuned Multi-Gen LRU (MGLRU) and fixed aggressive LMKD game kills
- Fixed kswapd0 100% CPU thrashing on saturated zRAM
- Set ADIOS as default multi-queue I/O scheduler on UFS 3.1 storage
- Optimized block I/O path and asynchronous bio submission
- Fixed Ki-Optimizer invalid sysfs writes on virtual block devices
- Backported Futex2 multi-wait fsync support
- Added BINFMT_MISC binary emulation support
- Added manual VFS stat hooks and fixed KernelSU init.rc injection
- Added multi-format ramdisk decompression and fixed AOSP boot hangs
- Added EROFS compression and security xattr support
- Fixed IR blaster transmission issues
- Integrated lockless per-CPU Blake2s CSPRNG crypto engine
- Modernized Clang ThinLTO linker script and fixed vendor module loading

---

## Ki-kernel v1.4

Changelog:
• Backported modern eBPF support for Android 16 and 17
• Fixed BPF loader boot issues on newer Android ROMs
• Added dynamic kernel version reporting for BPF loaders
• Added Adreno 650 GPU idle frequency reporting
• Retained custom GPU undervolt and overclock profiles
• Updated BakaSU and ReSukiSU integration
• Fixed KernelSU Manager root detection
• Synced SuSFS v2.3.0 inline hooks
• Added non-root Ki-Profile controls
• Added non-root bypass charging controls
• Added Force Fast Charge controls
• Added universal DC Dimming support
• Added KCAL hardware color calibration
• Added Dynamic Fsync controls
• Tuned CPU scheduling and gaming frame pacing
• Improved RAM reclaim and multitasking behavior
• Improved Deep Sleep and background power consumption
• Fixed screen-off charging freezes and Sleep of Death
• Fixed AOSP boot freezes and kernel panic issues
• Fixed lockscreen and display refresh-rate issues
• Improved battery protection and bypass charging handling
• Added native Linux container support
• Added NoMount kernel integration
• Added ADIOS I/O scheduler
• Added CAKE queue management support
• Added PS5 DualSense controller support
• Improved touchscreen and haptic driver handling
• Fixed background music playback during screen-off
• Improved AnyKernel3 flashing and DTB handling
• Unified support for Android 13–17 ROM builds

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

