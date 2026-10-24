# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-24  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI/HyperOS, AOSP, And ColorOS/OxygenOS
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## Ki-kernel v1.5 (2026-10-24 Update):
• Ported Hardware SDE Exposure Dim Layer from re404 for True AOSP DC Dimming:
  - Integrated DevriesL's SDE Exposure Dim Layer driver and EcrosoftXiao's calibrated alpha model (`sde_expo_dim_layer.c`, `sde_expo_dim_layer.h`, `sde_crtc.c`, `sde_crtc.h`) from re404 kernel.
  - Clamps physical AMOLED backlight to 440 (`DIM_THRES_LEVEL`) to completely eliminate low-brightness PWM flicker.
  - SDE CRTC hardware stage automatically blends `{0, 0, 0, alpha}` digital dimming over the display pipeline without requiring MIUI SurfaceFlinger.
  - Multi-node sysfs bridge automatically synchronizes `dimlayer_exposure`, `dc_dimming`, `dimming`, and `disp_param`.
• Native Kernel SELinux Bypass for Display Sysfs:
  - Implemented direct LSM policy bypass in `inode_has_perm` and `selinux_inode_permission` (`security/selinux/hooks.c`) for `system_app` (LineageOS / Infinity-X Settings / XiaomiParts) and `system_server` on `vendor_sysfs_graphics` and `sysfs_graphics`.
  - Fixes SELinux denials (`comm="eageos.settings" name="dimlayer_exposure"`) natively inside the kernel without relying on any Magisk/KernelSU `sepolicy.rule` module.
• Fixed USB Tethering DHCP & Host IP Assignment:
  - Enabled `CONFIG_NETFILTER_XT_TARGET_CHECKSUM=y`: resolves `Warning: Extension CHECKSUM revision 0 not supported` in Android's TetherController, enabling `--checksum-fill` so host PCs accept UDP port 68 DHCP offers.
  - Enabled `CONFIG_USB_CONFIGFS_RNDIS=y` and `CONFIG_USB_CONFIGFS_ECM=y`: restores standard RNDIS and ECM tethering gadget function creation.
  - Fixed NCM/RNDIS Interface Naming (`f_ncm.c`, `f_rndis.c`, `f_ecm.c`): named network devices `ncm%d`, `rndis%d`, and `ecm%d` instead of generic `usb%d`. Resolves `ERROR could not enable IpServer for function NCM` where Android 14+ Tethering rejected `usb0` (expecting `ncm\d`), which previously caused Android to fail to start its DHCP server and left host PCs stuck on "Configuring network address".
• MGLRU Stability & `mmap_sem` Lock Contention Fix:
  - Mapped sysfs writes of `1` in `mm/vmscan.c` to `0x0001` (`LRU_GEN_CORE` only), disabling `LRU_GEN_MM_WALK` table walker lock contention on `mmap_sem` that previously caused app freezes under memory pressure.
• Fixed Screen-Off Wakeup Freeze & Deep Eco Black Screen:
  - Added retry workqueue in `drivers/misc/ki_profile.c` when secondary CPUs are offline during screen-on resume, preventing system lockups.
  - Treated AOD LP1/LP2 low-power display modes as active display to prevent throttling governor frequencies while interacting with lockscreen.
  - Rebalanced Battery profile CPU frequencies and set `SCREEN_OFF_BATTERY=0` default.
• Overhauled Thermal & Performance Profiles for Outdoor Stability:
  - Rebalanced Balanced and Battery profiles for efficient daily multitasking with schedutil down-hold and WALT migration tuning, keeping temperatures cool under direct sunlight.

## Ki-kernel v1.5 (Initial Release):
• Fixed Force Fast Charge and Restored Peak 67W / PPS Turbo Charging ("Gacor"):
  - Fixed Force Fast Charge having no effect on Wall Chargers (DCP/HVDCP/QC): previous implementation only updated `usb_icl_votable` for PC USB ports (`POWER_SUPPLY_TYPE_USB` / CDP), leaving wall adapters hardcoded to 1.5A. `smblib_set_force_fast_charge()` and plugin handlers now un-throttle `SW_ICL_MAX_VOTER`, `DCP_VOTER`, and `HVDCP2_ICL_VOTER` across all charger types up to 3.5A.
  - Eliminated PPS Thermal Postponement & Starvation: `mi_thermald` writes to `system_temp_level` every 1–2s previously rescheduled a 3-second delayed worker continuously, starving PPS thermal level updates and locking charging to throttled levels (~15W–30W).
  - Instant PPS Thermal Clamping: Re-introduced instantaneous PPS thermal clamping to Level 0 (12.4A / 67W) and canceled the delayed worker whenever Force Fast Charge or Screen-On Fast Charge is active.
  - Unlocked Dual Charge Pump (Master + Slave BQ): Clamping thermal level to 0 at entry prevents lockout (`MAX_THERMAL_LEVEL_FOR_DUAL_BQ`), allowing dual charge pump to engage full 12.4A turbo power while retaining hardware emergency thermal protection at 49.0°C.
• Fixed Notorious POCO F4 (munch) Auto-Shutdown While Charging Bug:
  - Root Cause: Stock Xiaomi driver (`bq27z561_fg_munch.c`) live-polled hardware I2C registers on every sysfs read whenever USB was connected (`usb_in`). High-wattage fast charging (67W / 6A) switching noise and EMI induced intermittent I2C read spikes or 0xFFFF returns (6280.5°C), prompting Android's BatteryService to trigger an emergency thermal shutdown (`ro.boot.bootreason = shutdown,thermal,battery`).
  - I2C Polling Rate-Limiter: Capped I2C temperature sampling to at most once per 1000ms, eliminating 95% of unnecessary bus traffic and preventing bus collisions.
  - Sanity Check & Auto-Retry: Rejects raw Kelvin anomalies (< -20°C or > 65°C, 0x0000, 0xFFFF) with immediate retry on bus contention, falling back to last valid temperature instead of injecting fake error spikes.
  - Slew-Rate Transient Filter: Rejects physically impossible single-sample jumps (> 4.0°C/s), eliminating single-frame thermal spikes.
  - Safe Temperature Clamp (56.0°C): Guarantees reported battery temperature never trips Android's shutdown threshold while preserving hardware JEITA current cutoffs.
  - Dual-Layer Defense: Added fallback temperature validation in SMB5 PMIC charger (`smblib_get_prop_from_bms`).
• Restored Balanced Profile to cool, ultra-efficient daily multitasking sweet-spot:
  - Capped Prime to 2.84GHz and Gold to 2.21GHz (avoids power-hungry 1.15V+ voltage spike while keeping 120Hz butter-smooth)
  - Schedutil 10ms down-hold & 1500us Prime ramp-up delay (eliminates -1000mA to -1500mA active drain, drops multitasking current to -300mA ~ -600mA)
  - Restored WALT group migration to 95/85 to retain background multitasking threads on power-efficient Silver cluster
• Supercharged Performance / Gaming Turbo Profile for maximum competitive gaming (MLBB/Genshin/COD):
  - Peak hardware clocks unlocked (Prime 3.19GHz, Gold 2.42GHz) with zero-lag ramp-up (0us) and 20ms frame hold
  - Boosted Prime RTG render thread frequency to 2.84GHz (delivers rock-solid 120 FPS in intense teamfights)
  - Eager gaming thread promotion (up_migrate 60/45, grp 70/55) to prevent any render threads from staying on LITTLE cores
  - Tuned swappiness (50) and vfs_cache_pressure (60) to eliminate asset streaming micro-stutters
• Defaulted blk-mq I/O scheduler to low-latency BFQ / Maple (eliminated ADIOS barrier flush stalls)
• Perfected OPlus / ColorOS subsystem: added robust hardware fallback for Project ID (20807), PCB (T6), boot mode, modem, and operator when SMEM 135 is absent on Xiaomi bootloader
• Fixed OPlus NWPower & IPv6 RTO netlink initialization failure by raising MAX_LINKS to 48 in `netlink.h` and `af_netlink.c`
• Implemented OPlus Frame Boost & SchedAssist emulation nodes (`/proc/oplus_frame_boost/{ctrl,sys_ctrl}`, `/proc/oplus_scheduler/sched_assist/{ux_task_app,audio/status}`, `/proc/oplus_binder/ux_flag`, `/proc/sys/fbg/frame_boost_enabled`, and per-task `/proc/<pid>/task/<tid>/ux_state`), eliminating SchedAssist ENOENT errors
• Added dummy ioctl handler for OPlus procfs nodes to prevent launcher and service ioctl rejections
• Fixed potential kernel panic in `get_serialID()` by adding null checks on `saved_command_line`
• Eliminated 4KB memory leak in `oemports10t.c` and implemented proper module exit cleanup
• Configured system group ownership (1000) and read permissions for `/proc/oplusVersion/*` and `/proc/oplus_charger/*`
• Updated ReSuKSU / BakaSU to latest upstream (`v4.2.0-rc3-70`):
  - Added 32-bit userspace compat support on 64-bit kernel
  - Improved SELinux hide time side-channel defense and hash-indexed sidtab checking
  - Synced SuSFS inline hooks with latest KernelSU changes
  - Retained multi-manager signature support (KernelSU Official, KernelSU-Next, SukiSU, RKSU, MKSU, and BakaSU)
  - Implemented KernelSU `KSU_IOCTL_LOOKUP_SYMBOLS` & `KSU_GET_INFO_FLAG_PREINIT` while maintaining UAPI 5 compatibility for BakaSU / ReSukiSU manager, Zygisk, and `ksud` modules
• Resolved Turbo Gaming GPU Power Collapse & Adreno GMU lockup (anti-freeze & anti-Sleep of Death)
• Removed dangerous force_on flags (`KGSL_PWRFLAGS_CLK_ON` / `AXI_ON`) that stalled system suspend
• Auto-disarmed GPU Performance mode when screen is OFF to ensure complete SoC low-power sleep
• Restored CPU relaxation (`cpu_relax`) in `rwsem_spin_on_owner` loop to prevent lock contention
• Allowed Screen-Off Battery profile to engage cleanly during screen-off under Performance mode
• Tuned Adreno GPU interval timeout (200ms) for frame-pacing without breaking power collapse
• Introduced Ki-Daemon (Rust Native Auto Game Turbo & Automation) & Ki-Kernel Settings v1.2:
  - Ultra-lightweight native Rust daemon (<500KB stripped, ~1MB RAM usage, zero GC overhead)
  - Zero-overhead in-memory top-app cgroup detection with robust `:sub_process` suffix stripping and game priority matching
  - Automated Game Turbo switching: jumps to Performance mode in games, seamlessly reverts to Balanced on exit
  - Intelligent Auto Bypass Charging: engages direct charger power only while actively gaming, disarms on exit
  - Automated MGLRU Depth scaling: shifts to Mode 7 Gaming Turbo in games, restores Mode 1 for daily multitasking
  - Pocket power preservation: enters 4s sleep when display panel is dark
  - Ki-Setting WebUI Tab 2 "Auto Game Turbo": toggle daemon, customize game/exit profiles, auto-bypass, auto-MGLRU, clean responsive layout, and add/remove game packages dynamically

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

