# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-19  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI/HyperOS, AOSP, And ColorOS/OxygenOS
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## Ki-kernel v1.4.1 P3:
- Full Native ColorOS / OxygenOS / RealmeUI Subsystem (`bpf-testing` re-noroi port):
  - Enabled `CONFIG_OPLUS_PORT=y` and `CONFIG_OPLUS_NANDSWAP=y` in defconfigs.
  - Implemented complete `drivers/oplus/` subsystem:
    - `oemports10t.c` & `oplus_project.c`: Board ID, project ID, and hardware revision identification for ColorOS/OxygenOS framework services.
    - `nandswap_core.c` & mm integration: Native OPlus RAM Expansion (NANDswap) driver integrated into `mm/swapfile.c` with dedicated `SWP_NANDSWAP` flag, isolated swap info (`nandswap_si`), and accurate sysinfo swap accounting.
    - Comprehensive charging emulator (`oplus_stub_nodes.c`): Exposes `/sys/class/oplus_chg/` (battery, usb, common, ac, mutual_cmd, wattage, otg) and `/proc/oplus_charger/batt_health` to prevent crash-loops of `oplus_chg` and battery management services.
    - Network socket power manager (`oplus_nwpower.c`, `oplus_ipv6_rto.c`): Integrated `include/net/oplus_nwpower.h`, custom netlink family (`NETLINK_OPLUS_NWPOWER`), TCP random timestamps, and socket power wakeup hooks (`bts_net_fill`/`bts_net_clear` in `kernel/power/wakeup_reason.c`).
    - Proc/sysfs service nodes: Emulated nodes for proprietary daemons (`theia` watchdog, `sched_assist`, `devinfo`, `bootprof`, `oplus_storage`).
    - SELinux integration: Hooked `security/selinux/selinuxfs.c` to gracefully allow OPlus system services without bootlooping.
- Fixed Facebook Reels & Video Playback Stuttering (Issue 1):
  - Enabled WALT Related Thread Group (RTG) boost in Balanced profile (`rtg_boost_freq`: 1.21GHz Silver, 1.65GHz Gold, 1.80GHz Prime) providing dedicated frequency headroom for SurfaceFlinger, RenderThread, and video decoders.
  - Configured active floor frequencies (`floor_freq`: 576MHz Silver, 710MHz Gold) to prevent DVFS frequencies from dropping to 300MHz between 120Hz/60Hz video frames.
  - Tuned `iowait_boost_max` (35% Silver, 25% Gold) to prevent network and storage buffer stalls during media streaming.
- Fixed Heavy Powersave Battery Drain & Outdoor Overheat (Issues 3 & 5):
  - Implemented CPU cluster max frequency clamping in `ki_profile.c` and `cpufreq.c` (`ki_cpufreq_set_limits`):
    - Battery Saver mode now firmly clamps Gold cores to 1.71GHz and Prime core to 1.67GHz, eliminating high-voltage VDD states (>1.05V) and cutting heavy background power consumption by >60%.
    - Increased `down_us` hold time in Battery profile (4ms Silver, 6ms Gold, 8ms Prime) to eliminate PLL thrashing and frequency flutter.
    - Balanced profile caps Prime to 2.84GHz and Gold to 2.21GHz, stopping thermal runaway outdoors under sunlight while retaining peak daily responsiveness.
  - Exposed sysfs nodes `/sys/kernel/ki_profile/max_freq_silver`, `max_freq_gold`, and `max_freq_prime` with runtime user overrides.

---

## Ki-kernel v1.4.1 P2:
- Fixed Sleep of Death (SoD) & Unrecoverable Screen-off Hangs:
  - Eliminated deadlock where phone became unresponsive and ADB disappeared after 1-minute screen timeout
  - Added SMP online CPU verification (`num_online_cpus() < nr_cpu_ids`) in `ki_profile.c` to prevent governor changes and GPU performance mutex lock contention while cores are offlined during deep suspend (`PM: suspend entry`)
  - Filtered battery power supply notifications (`ki_psy_notifier_cb`) to prevent asynchronous work queues from waking the governor during sleep
  - Added cluster-rate limit error skip to gracefully handle offline CPUs during suspend transitions
  - Cached `last_gpu_perf` state to avoid redundant GPU mutex acquisitions
- Battery Drain & Thermal Throttling Optimizations:
  - Fixed severe idle battery drain by restoring dynamic display refresh rate scaling on Samsung E4 AMOLED panel
  - Removed forced `ro.surface_flinger.set_idle_timer_ms 0` and `set_touch_timer_ms 0` overrides from AnyKernel installer and Ki-Optimizer module, allowing panel to smoothly drop to 60Hz when idle
  - Restored `.thermal_throttle = true` and `ki_thermal_throttle_enabled = true` by default on Balanced mode
  - Restricted background thermal guard polling (`ki_guard_work_fn`) exclusively to Performance profile, eliminating 2000ms wakeups during normal usage
  - Optimized schedutil `iowait_boost_max` limits (15 for Silver, 10 for Gold) to eliminate excessive frequency spikes on disk operations
  - Set MGLRU mode to generation-only (`MGLRU_MODE=1`) by default to prevent heavy background kswapd page-table scans
- Expanded Multi-Manager KernelSU Support:
  - Added native kernel-level signature recognition for multiple popular root managers without signature mismatch errors
  - Supported Managers:
    - **KernelSU-Next** (rifsxd / KernelSU-Next — cert size `0x3e6`, SHA-256 `79e59011...`)
    - **SukiSU / SukiSU-Ultra** (SukiSU Team — cert size `0x35c`, SHA-256 `947ae944...`)
    - **RKSU** (rsuntk / rKSU legacy — cert size `0x396`, SHA-256 `f415f4ed...`)
    - **MKSU (midori01/KernelSU)** (midori01 SuperManager — cert size `0x0368`, SHA-256 `b9ee6759...`)
    - **MKSU (Magic KernelSU)** (5ec1cff with native Magic Mount — uses official cert)
    - **Official KernelSU** (tiann — cert size `0x033b`, SHA-256 `c371061b...`)
    - **BakaSU** (Baka-SU — cert size `0x377`, SHA-256 `d3469712...`)
    - **KOWSU** (KOWX712 — cert size `0x375`, SHA-256 `484fcba6...`)

---

## Ki-kernel v1.4.1 P1:
- Universal Triple-OS Compatibility (AOSP, MIUI / HyperOS, & ALL ColorOS / OxygenOS / RealmeUI Ports):
  - Built-in `drivers/oplus` stub and fake subsystem nodes preventing crash-loops of OPlus proprietary daemons (`theia` watchdog, `sched_assist`, `oplus_chg`, `oplus_mem`, `devinfo`, `bootprof`, `oplus_storage`)
  - Universal dynamic port detection in AnyKernel3 installer: automatically detects ANY ColorOS, OxygenOS, or RealmeUI port (by Danda, BlackMamba, SGSI, OEM ports, etc.) via dynamic partitions (`my_product`), filesystem inspection (`/vendor/euclid`, `oplus-framework.jar`, `OplusSystemUI`, `oplusVersion`), and live build properties (`ro.build.version.oplusrom`, `ro.coloros.version`, `ro.oxygen.version`, `ro.build.version.opporom`, `ro.realme.version`)
  - Automatically matches and applies OEM display panel DSI timings required by OPlus ports for glitch-free, 120Hz display output without black screen or reboot loops
  - Completely non-intrusive: zero overhead or regression on standard AOSP or stock MIUI/HyperOS ROMs
- Added Boeffla Wakelock Blocker with clean `1`/`0` toggle via `/sys/kernel/wakelock_blocker/enabled`
- Block unnecessary background scan wakeups (`wlan_pno_wl`, `wlan_extscan_wl`, `netmgr_wl`) to reduce idle battery drain
- Kept CPU governor & scheduler EAS migration untouched to maintain 100% smooth, stutter-free 120 FPS gaming
- Updated Ki-Optimizer Magisk/KSU WebUI module (v1.1) with clean "Wakelock Blocker" toggle switch (no CLI required)
- Default state set to OFF (`0`) for zero regression on stock behavior
- Smart Multi-Stage AnyKernel3 ROM Detection (E404 Method Integrated):
  - Added `/vendor/build.prop` and `/product/etc/build.prop` region checks (`ro.vendor.miui.build.region` / `ro.miui.build.region`)
  - Added POCO F4 hardware feature verification (`device_features/munch.xml`)
  - Added dynamic A/B slot-aware (`system$SLOT` / `product$SLOT` / `my_product$SLOT`) detection for HyperOS, OPlus, & Custom AOSP ROMs
  - Accurate ROM detection reporting in recovery UI automatically
- Completely purged all hardcoded kernel overrides from AnyKernel scripts (swappiness, vfs_cache_pressure, maple scheduler, scaling_min_freq, mglru, wakelock blocker)
- All kernel features and toggles are now 100% user-controlled exclusively via the Ki-Kernel Settings module (`ki_optimizer.conf` and WebUI)
- Fixed MGLRU and Wakelock Blocker turning back on across reboots (prevented interference with WhatsApp background notifications)
- Tuned Balanced Profile Schedutil Golden Ratio: ramp-up 500us Silver/Gold & 1500us Prime, down-rate hold time 10ms (covers 120Hz 8.33ms frame window with zero micro-stutter while keeping SoC ~4-6°C cooler)
- Anti-Stutter CPU Core Isolation Bypass (Option A): Prevented `cpu_isolate` driver from offlining Big (Gold) and Prime cores in Balanced and Performance modes, eliminating severe outdoor stuttering, UI freeze, and display refresh dropping to 30 FPS when streaming YouTube under high ambient sun and cellular data
- Intelligent Thermal Auto-Guard for Balanced Mode (Option B): Extended dynamic `ki_guard` thermal management to Balanced profile with raised 47°C skin threshold, keeping daily UI and video playback 100% fluid while retaining emergency hardware safety (re-arms throttle if die ≥ 85°C, skin ≥ 47°C, or battery ≥ 45°C)
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
- Fixed potential 32-bit signed integer overflow in `charging_limit_current` sysfs with dual mA/uA auto-detection and 12A hardware clamp
- Added automatic Bypass Charging hardware deactivation on shutdown/reboot to preserve offline and TWRP/recovery charging
- Fixed `thermal_fcc_override` not clearing voter when written with `0`
- Unified `__smbchg` and `g_smb_chg` references and added NULL pointer protection to `smb_get_usbpd()`
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

