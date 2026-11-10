# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-11-09  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI/HyperOS, AOSP, And ColorOS/OxygenOS (Universal & Single Variants)  
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## Ki-kernel v1.6.5 (Sleep-of-Death & Framework Watchdog Resolution, AnyKernel3 HyperOS Fix & Safe Storage) :
- Anti-Cheat & Native Detector Uname Spoofing Hardening: restricted `bpfloader`, `netbpfload`, `uprobestats`, and `netd` fake uname response in `kernel/sys.c` strictly to root system daemons (`current_uid().val == 0`) during early boot phase (`< 120 seconds`). Unprivileged apps (`UID >= 10000`), Native Detector, and mobile anti-cheat engines calling `prctl(PR_SET_NAME)` will always receive authentic `4.19` uname info, completely eliminating false environment modification detections and game account bans while preserving 100% Android 16/17 `netbpfload` boot compliance. Removed verbose fake uname kernel log messages from `kmsg`.
- Aftermarket Battery Shutdown & Charge Cutoff Fix: ported battery gauge stability fixes from upstream e404 (`37da736cf32c` by Muhammad Guntur). Guarded negative initial sentinel values (`batt_volt`, `batt_curr`, `batt_soc`) in `drivers/power/supply/qcom/bq27z561_fg_munch.c`, rejected fake temperature placeholders on persistent I2C bus read errors (`i2c_error_cnt >= 3`), guarded against division by zero on `fcc <= 0`, and eliminated aggressive USB charge suspension (`input_suspend`) in `drivers/power/supply/qcom/smb5-lib-munch.c` to prevent abrupt power-offs and charging failures on non-genuine replacement batteries.
- Stock MIUI / HyperOS Sleep-of-Death (SOD) Elimination:
  - LHBM White Read Guard: resolved `-EAGAIN` (`-11`) display enable kickoff errors in `techpack/display/msm-miui/dsi/dsi_panel_mi.c` by verifying `fod_lhbm_white_update_flag` and command counts before executing DCS commands. Munch panels with physical side-mounted fingerprint sensors no longer hang trying to read optical under-display fingerprint registers.
  - Synchronous ESD Teardown & Inactive IRQ Filter: guarded `esd_err_irq_handle()` in `techpack/display/msm-miui/sde/sde_connector.c` and `techpack/display/msm/sde/sde_connector.c` to drop spurious ESD interrupts received while the display is uninitialized or powered off (`power_mode != ON/LP1`), preventing false `panel_dead = true` lockups during screen-off. Added `synchronize_irq()` to `dsi_panel_esd_irq_ctrl()` to guarantee in-flight ESD handlers terminate completely before panel power rails are cut.
  - Qualcomm RPMH Integrity: restored standard CAF blocking transaction loops in `rpmh_rsc_send_data()` (`drivers/soc/qcom/rpmh-rsc.c`) and `rpmh_flush()` (`drivers/soc/qcom/rpmh.c`). Eliminates artificial timeout bails that previously aborted pending power rail writes (`-EBUSY`) and dropped in-flight bus votes during Wi-Fi/PCIe runtime sleep transitions, preventing system freezes.
  - Rotator Kickoff Panic Disabler: set `SDE_EVTLOG_DEFAULT_PANIC = 0` in `techpack/display/rotator/sde_rotator_debug.c`, matching SDE debug panic disabler.
- Fatal Sleep-of-Death (SOD) & Screen Wake Freeze Resolution: restored upstream `needs_force_resume` sanitization in `drivers/base/power/runtime.c` and `include/linux/pm.h`. Previously, waking from wakelocks or deep sleep evaluated `pm_runtime_need_not_resume(dev)` as `true` on the Qualcomm Adreno 650 GPU (`adreno_device.c`), skipping its `runtime_resume` callback. The GPU remained in `RPM_SUSPENDED` while the panel backlight was powered, causing SurfaceFlinger/WindowManager display fence deadlocks, UI freeze, and triggering 60-second Android Framework Watchdog soft-reboots.
- Display SDE Kickoff Panic Disabler: set `DEFAULT_PANIC = 0` in `techpack/display/msm/sde_dbg.c` and `msm-miui/sde_dbg.c`. Frame kickoff timeouts and debug dump delays during display wake transitions no longer panic or crash the phone, delegating recovery smoothly to hardware CTL reset. Fixed DMA buffer memory leak and NULL pointer dereference in SDE register dump routines.
- Cpufreq Sugov Mutex Locking: protected cpufreq governor policy tuning with `down_read_trylock(&policy->rwsem)` in `drivers/misc/ki_profile.c` and retried gracefully when busy. Prevents kernel race conditions and use-after-free faults when switching profiles while secondary cores or the Prime core (CPU7) enter deep sleep/offline.
- Ordered Workqueue for CPU Boost: migrated `input_boost_work` in `drivers/cpufreq/cpu-boost.c` to an ordered single-threaded workqueue (`cpu_boost_wq`) to prevent touch and powerkey boost races across multiple CPU clusters.
- Balanced Profile Efficiency & Temperature Safeguard: disabled touch scheduler boost (`.touch_sched_boost = 0, .touch_boost_ms = 0`) in Balanced mode. Completely eliminates the aggressive 1-second full-throttle scheduler lock during scrolling, keeping device temperatures cool and restoring maximum battery efficiency for daily use.
- Dedicated Performance / Gaming Turbo Boost: touch scheduler boost (`.touch_sched_boost = 1, .touch_boost_ms = 150`) is now strictly exclusive to Performance mode, holding instant 150ms task migration to big cores for competitive zero-latency gaming.
- Unlocked Swappiness Control: removed hardcoded `vm_swappiness` override from `ki_profile.c`. Memory swappiness is now 100% user-customizable via WebUI `ki_optimizer`, init scripts, or `/proc/sys/vm/swappiness` without being overridden by kernel profile switching.
- Dynamic Fsync Safety & SQLite Protection: set `dyn_fsync_active` default to `false` in `drivers/misc/dyn_fsync.c`. Eliminates the risk of SQLite database and WhatsApp chat corruption caused by deferred writes during unexpected shutdowns or force reboots, while keeping it opt-in via sysfs.
- AnyKernel3 HyperOS / MIUI Flashing Fix: restricted live `getprop` ROM inspection to `BOOTMODE=true` in `anykernel.sh` and `anykernel_template/anykernel.sh` to prevent inheriting recovery properties during TWRP/OrangeFox flashing. Removed the generic `ro.product.system.name` fallback that caused HyperOS ports to be misidentified as AOSP, added regex support for Android 14/15/16 HyperOS incremental version strings (`^([0-9]+)?OS[0-9]`), and added inspection for `/system_ext/priv-app/MiuiSystemUI`.
- Multi-Manager & Signature Verification Expansion: added OriginSU signature support and raised X.509 certificate limits to 2048 bytes in `KernelSU/kernel/manager/apk_sign.c` for full RSA 4096-bit compatibility across modern custom managers.
- Module Startup Settlement Optimization: relaxed post-boot settlement sleep from 4s to 12s in `ki_optimizer_module/service.sh` to prevent CPU governor initialization from colliding with early post-boot screen-off transitions.

## Ki-kernel v1.6.4 (Fatal Sleep Lockup Fix & In-Kernel Non-Root Hotspot Engine) :
- Fatal Screen-off Sleep Lockup & Black Screen Fix: reverted problematic PM runtime commit `d0b4c0a390fb` (`PM: runtime: Drop pm_runtime_force_suspend/resume()`) in `drivers/base/power/runtime.c` and `include/linux/pm.h`. This commit erroneously omitted `needs_force_resume = 1` for devices that were already runtime-suspended before system sleep (notably the Adreno GPU / KGSL). On wake, `pm_runtime_force_resume()` evaluated `!dev->power.needs_force_resume` and skipped powering back on the Adreno GPU and GDSC rails, causing SurfaceFlinger/InputDispatcher display fence deadlocks, system freezes, and Black Screen of Death.
- Power Management Workqueue Hardening: reverted `pm_wq` back to per-CPU `WQ_FREEZABLE` in `kernel/power/main.c` and reverted pool lock optimization in `kernel/workqueue.c` to prevent unbound workqueue race conditions during AP suspend/resume transitions.
- In-Kernel Hotspot DNS DNAT Engine (Root & Non-Root Universal): implemented native in-kernel DNS DNAT redirect hook directly in `net/ipv4/netfilter/iptable_nat.c`. The kernel automatically intercepts DNS queries (port 53 UDP & TCP) originating from tethering interfaces (`wlan1+`, `ap+`, `swlan+`, `rndis+`) and transparently binds them via `nf_nat_setup_info()` to upstream DNS (`1.1.1.1:53`). This guarantees 100% working hotspot internet on Android 16 even on completely unrooted (NOKSU / Non-Root) systems without dnsmasq or userspace iptables rules.
- In-Kernel BPF Tether Ingress Bypass: hardened `sch_handle_ingress()` in `net/core/dev.c` to automatically bypass ingress qdisc classification on active tether interfaces (`wlan1+`, `ap+`, `rndis+`, `swlan+`), permanently preventing Android BPF tethering offload filters from dropping forwarded client packets across both Root and Non-Root configurations.
- Zero Background Daemon Overhead: completely eliminated the need for any background userspace hotspot watcher or polling script in `/data/adb/service.d/00_nkm_bypass.sh`. The startup script now cleanly exits immediately after applying device permissions on boot, leaving **zero background processes** while the kernel handles 100% of network offloading and DNS redirection natively.
- TCP BBR Kernel Warning Silencing: clamped `lost_prev = 0` when `lost_prev < 0` for aggregated GRO/TSO packets in `net/ipv4/tcp_bbr.c`, eliminating harmless `WARN_ONCE` logspam in `dmesg` and removing unused `tp` variable.

## Ki-kernel v1.6.3 (Display Brightness Range Calibration & AnyKernel3 GPU OC Flasher) :
- Hotspot & Tethering Fix: bypassed TTL and Hop Limit decrement on forwarded IPv4 (`net/ipv4/ip_forward.c`) and IPv6 (`net/ipv6/ip6_output.c`) packets (ported from e404 / Alexander Winkowski) to prevent carrier DPI tethering blocks and fix "Connected, without internet" bug on connected hotspot devices
- BPF & Netfilter Defconfig Compatibility: enabled `CONFIG_XDP_SOCKETS=y`, `CONFIG_NETFILTER_XT_TARGET_HL=y`, `CONFIG_NETFILTER_XT_TARGET_CHECKSUM=y`, and `CONFIG_IP6_NF_NAT=y` across munch defconfigs (`munch_defconfig` & `munch_stock-defconfig`) to support Tethering BPF maps (`osrtpPolicy.o`) and fix Wi-Fi sharing (STA+SAP) UDP/DHCP checksum validation
- BPF Generic Pop Header Optimization: corrected `memmove` offset and pull sequence in `bpf_skb_generic_pop()` (`net/core/filter.c`) from upstream commit 315fcbead697 to prevent packet corruption during BPF header pop
- SuSFS Kernel Panic Fix: guarded `kfree_rcu(old_bitmap, rcu)` with `if (old_bitmap)` in `susfs_set_priority_uid_filter()` and `susfs_priority_app_strings_worker()` (`fs/susfs.c`) to prevent fatal NULL pointer dereference in `__call_rcu()` during initial boot priority UID filter configuration (Issue #1, reported & suggested by @zdanysfa)
- Memory Reclaim Unevictable Page Hardening: skipped unevictable/mlocked pages (`PageUnevictable`) in `reclaim_pte_range()` (`fs/proc/task_mmu.c`) to prevent isolated count mismatch and VM assertions during Android `CachedAppOptimizer` background reclaim (Issue #1, reported & suggested by @zdanysfa)
- Display Backlight Reversion to Stock Stability: restored `sde_connector.c` to stock Qualcomm/LineageOS clean driver mapping (`mult_frac`) while keeping `qcom,mdss-dsi-bl-min-level = <1>` in DTS. This completely eliminates all slider jumping, threshold cliffs, and flickering ("redup terus terang") across all ROM frameworks (HyperOS, AOSP, ColorOS).
- Hardware-Accurate Backlight Calibration: calibrated brightness mapping to 11-bit KTZ8866 hardware DAC (2047) and added defensive clamp in dualktz8866 to prevent array out-of-bounds and driver rejection
- Fixed AnyKernel3 GPU OC vendor_boot flashing: Exported lowercase `block=vendor_boot` alongside uppercase `BLOCK` to ensure DTB partition is repacked correctly on SM8250
- Fixed recovery volume key selector: replaced fragile timeout command subshell with continuous background getevent listener to reliably detect Vol+ (OC 683 MHz) and Vol- (Stock 670 MHz) in TWRP/OrangeFox
- Added automated GPU OC trigger support: Flasher now detects `/sdcard/oc`, `/sdcard/Download/oc`, and `/tmp/oc` to automatically select 683 MHz OC + UV profile even in app-based flashers (Kernel Flasher)
- Updated Ki-Settings / Ki-Optimizer module to v1.4.0 with WebUI charging, profile, and thermal toggles
- SMB5 charging driver & Boeffla Wakelock Blocker optimizations
- Synced KernelSU / BakaSU upstream to latest main (516d3e87) with OriginOS panic prevention (vklp_smaps_rollup block) and preserved multi-manager support
- Backported Linux 5.4 PM runtime & sleep fixes: resolved force_suspend/resume refcount unbalance, device removal UAF, and wakeirq races to eliminate screen-off wake deadlocks
- Fixed scheduler PELT period truncation: upgraded period accumulation from u32 to u64 to prevent CPU load tracking freezes
- Hardened Adreno GPU (KGSL): added refcount zero bailout in vm_open and fixed repeated sparse page mapping indices to prevent game crashes (PUBG/Genshin) and texture buffer corruption
- Power Management & Deep Sleep: offloaded pm_wq to WQ_UNBOUND, synced Android wakeup_srcu, hardened sleep_time delta calculations, and fixed wakelock counter limits
- Optimized kernel workqueues: reduced pool lock contention in flush_workqueue_prep_pwqs for unbound workqueues and guarded against NULL current_pwq dereferences

## Ki-kernel v1.6.2 (ColorOS 17 Support, Dynamic Fsync & Thermal Guard Fixes) :
- Fixed screen-off / lockscreen deadlock: replaced synchronous ksys_sync() in Dynamic Fsync with asynchronous wakeup_flusher_threads() and removed wakelock contention with Android apexd/VFS
- Fixed Dynamic Thermal Guard toggle: implemented thermal_throttle_store() and made /sys/kernel/ki_profile/thermal_throttle read-write (__ATTR_RW) to allow bypassing thermal throttling for unthrottled gaming
- Fixed TCP Congestion Control switcher: enabled CONFIG_TCP_CONG_CUBIC and registered both "westwood" and "westwood-sub"
- Added ColorOS 17 oplus_display sysfs nodes for Luminous Rendering Engine
- Added ColorOS 17 oplus_hans procfs interface to fix system_server ANRs
- Added Horae thermal procfs nodes (shell-temp, horae_mode) to prevent false throttling
- Added SuperVOOC UI sysfs nodes and dynamic fast_chg_type support
- Expanded OPlus SchedAssist v3 and Frame Boost procfs interfaces
- Added OPlus Theia watchdog, GameOpt, opbootfrom, and devinfo procfs nodes
- Added OPlus charger gauge sysfs groups and battery health metrics
- Migrate anykernel lifaye to anykernel re404

## Ki-kernel v1.6.1 :
- Fixed Samsung E4 AMOLED black screen bug: permanently protected display power rails (`display_panel_vci`, `disp_vddio_vreg`, `oled_dvdd_ldo`) from being cut off at second 32 by `regulator_late_cleanup`, completely eliminating hard reboots
- Fixed AnyKernel3 Universal installer: initialized `$AKHOME` directory binding to resolve `! Kernel Image not found` abort during recovery flashing
- Added built-in fgetpriority UID priority hiding to defeat syscall-based app detection (Applist Detector/Momo)
- Accelerated display & frame sync: speed up sync_file ioctl by omitting debug names (improves SurfaceFlinger and gaming FPS)
- Optimized memory zeroing: align clear_page() to 16 bytes for Cortex-A77/A55 cacheline throughput
- Silenced smcinvoke false error logspam during suspend/resume
- Fixed ARM PMU and devfreq memlat random reboots and qspinlock lockups
- Restored stable v1.5 display KMS commit order and touch synchronization
- Restored stable v1.5 kswapd LITTLE cluster affinity (CPUs 0-3) and watermark scale factor (improves gaming stability and prevents aggressive LMK oom_reaper)

## Ki-kernel v1.6 :
- Fix Selinux
- Updated ADIOS I/O scheduler v3.3.0
- Added AnyKernel GPU selector 
- Added YukiSU manager support and YukiSU feature
- Synced SuSFS v2.3.0 upstream changes and fixed UID filter UAF race conditions
- Added SuSFS multi-user and dual apps UID support with no-atime parsing
- Fixed Dynamic Fsync screen-off suspend hangs
- Fixed Binder page allocation failures and improved kswapd sleep reclaim
- Fixed cpufreq policy rwsem suspend deadlocks
- Fixed cpu-boost touch workqueue deadlocks and reduced policy lock contention
- Fixed Wakelock Blocker PCIe Wi-Fi drops and USB/ADB disconnects
- Fixed Ki-Profile screen-off workqueue loops and deep sleep wakeups

## Ki-kernel v1.5 :
- Updated BakaSU and ReSukiSU to UAPI v6
- Added full FinaSU Manager support
- Added 32-bit userspace KernelSU compatibility
- Added kernel-side per-app network isolation
- Synced SuSFS v2.3.0 inline hooks and bugfixes
- Added automated SuSFS early-boot spoofing
- Added SuSFS priority UID filter protection
- Updated NoMount kernel integration to v2.2.0
- Fixed Kernel Manager sysfs SELinux denials
- Ported hardware AOSP DC Dimming support
- Fixed display sysfs SELinux permission issues
- Improved SDE KCAL hardware color calibration
- Fixed Force Fast Charge on wall adapters
- Restored full 67W PPS turbo charging
- Fixed random thermal shutdowns while charging
- Fixed duplicate charger sysfs registration warnings
- Tuned Battery, Balanced, and Performance profiles
- Tuned CPU scheduling and gaming frame pacing
- Fixed screen-off wakeup freezes and AOD issues
- Hardened Ki-Profile sysfs and worker stability
- Fixed Adreno GPU freezes and Sleep of Death
- Fixed MGLRU lock contention and app freezes
- Set BFQ and Maple as default I/O schedulers
- Improved BBRv3 network congestion control
- Fixed USB tethering and DHCP connection issues
- Improved Droidspaces and Linux container support
- Added OPlus Frame Boost and SchedAssist support
- Fixed OPlus port netlink and driver issues
- Improved AnyKernel3 universal Multi-ROM detection

## Ki-kernel v1.4.1:
• Backported modern eBPF features for Android 16 and 17
• Cherry-picked selected commits from re-noroi/FD and e404
• Fixed BPF loader bootloops on newer Android ROMs
• Added dynamic kernel version reporting for BPF loaders
• Added OPlus subsystem support for ColorOS, OxygenOS and RealmeUI ports
• Added OPlus NANDswap and charging subsystem compatibility
• Improved AnyKernel3 ROM detection for AOSP, MIUI, HyperOS and OPlus ports
• Fixed Sleep of Death and screen-off hangs
• Fixed CPU governor switch kernel panics and use-after-free crashes
• Restored 300MHz CPU idle frequency
• Tuned schedutil, WALT, CPU migration and hispeed thresholds
• Added per-cluster CPU frequency controls in Ki-Profile
• Improved Battery Saver and Balanced profile tuning
• Improved screen-off battery life and dynamic refresh rate handling
• Added thermal auto-guard with temperature-based protection
• Improved CPU and GPU stability under heavy loads
• Improved bypass charging safety and charger disconnect handling
• Fixed fast charging cutoff, thermal limits and charging state handling
• Set Force Fast Charge and Screen-On Fast Charge to OFF by default
• Added non-root controls for Ki-Profile and charging features
• Expanded KernelSU manager compatibility
• Fixed KernelSU root detection and restored SuSFS inline hooks
• Added Boeffla Wakelock Blocker with a configurable toggle
• Fixed background music playback stopping when the screen is off
• Improved memory management with MGLRU and LMKD tuning
• Fixed excessive kswapd activity under heavy ZRAM usage
• Improved app retention and reduced unnecessary background app kills
• Added Adreno 650 GPU idle frequency reporting
• Retained Adreno 650 GPU undervolt and overclock profiles
• Fixed DC Dimming support on AOSP and compatible AMOLED panels
• Fixed Night Light and LiveDisplay on supported custom ROMs
• Added KCAL hardware color calibration support
• Added Dynamic Fsync control
• Added ADIOS multi-queue I/O scheduler
• Added NoMount kernel integration
• Added native Linux container support for Droidspaces, LXC and Docker
• Added BINFMT_MISC binary emulation support
• Backported Futex2 multi-wait support
• Added EROFS compression and security xattr support
• Improved block I/O and asynchronous bio submission
• Improved CPU locking and memory mapping performance
• Tuned real-time timer handling for SurfaceFlinger, audio and GPU workers
• Fixed touchscreen sleep errors and display-related issues
• Fixed IR blaster transmission issues
• Improved boot image ramdisk decompression and AOSP boot compatibility
• Added a lockless per-CPU Blake2s random number generator
• Updated Clang ThinLTO and fixed vendor module loading
• Added multi-stage thermal, charging and screen-off profile handling
• Improved container networking and systemd cgroup compatibility

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

