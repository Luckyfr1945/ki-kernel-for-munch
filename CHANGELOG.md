# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-22  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI/HyperOS, AOSP, And ColorOS/OxygenOS
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## Ki-kernel v1.5:
• Fixed MLBB & gaming frame drops / micro-janks: restored schedutil down_us hold time to 20ms across frames (eliminated frequency thrashing)
• Restored instant Prime core ramp-up (up_us 500us) and responsive hispeed loads (70%)
• Relaxed WALT group migration thresholds (grp_up_migrate 85 / down 75) to prevent game render threads being trapped on LITTLE cores
• Uncapped hardware burst clock headroom in Balanced profile (Prime 3.19GHz, Gold 2.42GHz)
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
  - Upgraded KernelSU UAPI to version 6 (implemented `KSU_IOCTL_LOOKUP_SYMBOLS` & `KSU_GET_INFO_FLAG_PREINIT`), eliminating "Kernel update required" warning on latest KernelSU-Next managers
• Resolved Turbo Gaming GPU Power Collapse & Adreno GMU lockup (anti-freeze & anti-Sleep of Death)
• Removed dangerous force_on flags (`KGSL_PWRFLAGS_CLK_ON` / `AXI_ON`) that stalled system suspend
• Auto-disarmed GPU Performance mode when screen is OFF to ensure complete SoC low-power sleep
• Restored CPU relaxation (`cpu_relax`) in `rwsem_spin_on_owner` loop to prevent lock contention
• Allowed Screen-Off Battery profile to engage cleanly during screen-off under Performance mode
• Tuned Adreno GPU interval timeout (200ms) for frame-pacing without breaking power collapse

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

