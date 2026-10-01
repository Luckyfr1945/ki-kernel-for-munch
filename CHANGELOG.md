# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-01  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI / HyperOS & AOSP
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## v1.4
• Built-in Kernel Version Spoofing to Linux 5.15 (Android GKI): Integrated `CONFIG_SPOOF_KERNEL_VERSION` reporting `5.15.148-ki-kernel-v1.4` across `uname()`, `/proc/version`, and `/proc/sys/kernel/osrelease` while maintaining 100% stable 4.19 driver compatibility. Seamlessly tricks modern Android 14/15/16, Play Integrity, root detectors, and benchmark apps to recognize the kernel as Linux 5.xx, with optional dynamic override support via SuSFS
• Backported Binder IPC `TF_CLEAR_BUF` flag from upstream Android (AOSP): zero-clears IPC transaction buffer on `BC_FREE_BUFFER` to prevent sensitive data leakage across Binder shared memory — improves app-switch responsiveness and eliminates stale payload exposure
• Enabled USB UAS (`CONFIG_USB_UAS=y`): OTG SSD/flash drives now use USB Attached SCSI protocol for faster, lower-latency bulk transfers vs. USB Mass Storage
• Enabled NTFS filesystem (`CONFIG_NTFS_FS=y`): NTFS-formatted OTG drives mount and read out-of-the-box without third-party apps
• Fixed CPU Idle Clock Stuck: Fixed WALT `rtgb_active` flag pinning Prime (cpu7 @ 3189MHz) and Little (cpu0 @ 1800MHz) during idle by explicitly zero-resetting RTG boost (`sugov_set_cluster_rtg_boost`), syncing schedutil tunables, and tuning Balanced `down_rate_limit` to 2000µs
• Fixed Wake-from-Idle Freeze: Restored display DSI error recovery workqueue (`dsi_err_workq`) to recover from transient FIFO underflow/overflow on panel unblanking/scrolling, preventing permanent display panel lockups
• Eliminated Direct Reclaim Stall Storms: Disabled `watermark_boost_factor = 0` (upstream Android GKI / Sultan standard) and tuned `watermark_scale_factor = 16` to prevent massive kswapd memory reclaim freezes when waking from deep sleep and scrolling
• Bound `kswapd` to LITTLE cluster (CPUs 0-3): Prevents background memory reclaim threads from stealing cycles from Big (Gold) and Prime cores during UI rendering
• Watchdog Bark/Pet Tuning: Safely increased watchdog bark-time to 30s and pet-time to 18s in device tree to prevent false-positive kernel panic reboots during heavy I/O or memory burst allocation
• Backported epoll_pwait2 
• Added TCP Westwood-sub improvements for Wi-Fi
• Optimized CFS load balancing
• Zero schedutil up-rate-limit delay (0µs) for instant 120Hz gaming responsiveness
• Optimized aw86927 haptic driver: reduced standby delay from 2.5ms to 250µs and silenced printk spam to prevent touchscreen freeze during notifications
• Hardened netd broken pipe handling
• Removed Adreno 650 POPP throttling
• Removed Wi-Fi debug wakelocks
• Added Boeffla Wakelock Blocker
• Optimized deep sleep & suspend
• Fixed MIUI and AnyKernel3 flashing issues
• Added experimental EEVDF + CASS AOSP
• Fine-tuned schedutil & CPU migration for butter-smooth 120Hz scrolling while keeping low idle drain
• Added post-boot delayed settlement in Ki-Profile
• Ported e404r gaming performance optimizations:
  - Avoided FPS event broadcasting to display listeners, and switched to no-log register access
  - Latency: stripped heavy debugging and verbose overhead from fast-paths (tsens, synx, npu, lmh_dcvs, iommu, cnss2, xhci)
  - Preserved Ki-Profile dynamic governor switching (daily battery efficiency + full gaming turbo)
• Enabled CONFIG_DM_BOW and CONFIG_DM_USER for Virtual A/B userspace snapshot compatibility (Android 15+ / HyperOS 2.0)
• Tuned F2FS background GC intervals (extended min sleep to 120s) to eliminate storage I/O stutter during active use and gaming
• Elevated Adreno KGSL GPU worker thread to SCHED_FIFO (priority 50, nice -20) and stripped high-frequency active_count tracing overhead
• Boosted Focaltech touchscreen threaded IRQ (`focaltech_3658u`) to real-time SCHED_RR (priority 90, nice -20) for zero-lag touch response
• Silenced Focaltech debug logging (`FTS_DEBUG_EN = 0`) to eliminate printk spam on every touch interrupt
• Enabled Clang ThinLTO (CONFIG_LTO_CLANG & CONFIG_THINLTO) for cross-translation-unit compiler optimization and superior CPU cache locality

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

