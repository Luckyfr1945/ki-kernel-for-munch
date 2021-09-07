# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-01  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI / HyperOS & AOSP
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## v1.5
• Backported Binder IPC `TF_CLEAR_BUF` flag from upstream Android (AOSP): zero-clears IPC transaction buffer on `BC_FREE_BUFFER` to prevent sensitive data leakage across Binder shared memory — improves app-switch responsiveness and eliminates stale payload exposure
• Enabled USB UAS (`CONFIG_USB_UAS=y`): OTG SSD/flash drives now use USB Attached SCSI protocol for faster, lower-latency bulk transfers vs. USB Mass Storage
• Enabled NTFS filesystem (`CONFIG_NTFS_FS=y`): NTFS-formatted OTG drives mount and read out-of-the-box without third-party apps

---

## v1.4
• Backported epoll_pwait2 
• Added TCP Westwood-sub improvements for Wi-Fi
• Optimized CFS load balancing
• Unpinned kswapd across all online CPUs to prevent direct reclaim stalls during gaming
• Synced RAM watermarks with Ki-Profile (`watermark_scale_factor = 30`) to eliminate multitasking frame drops
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
  - Display: eliminated DSI error workqueues, avoided FPS event broadcasting to display listeners, and switched to no-log register access
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

