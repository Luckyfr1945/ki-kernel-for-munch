# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-10-13  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI/HyperOS and AOSP  
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## Ki-kernel v1.4.1

Changelog:
• Fixed schedutil clock bouncing and micro-stutters by restoring 20ms down-hold delay
• Removed idle floor frequency clamps, allowing CPU to rest at 300 MHz idle
• Tuned hispeed frequencies and loads for smooth 120 Hz scrolling and gaming
• Increased bypass charging thermal threshold to 48°C for extended gaming sessions
• Fixed bypass charging cutting off after 30 minutes of heavy gaming
• Tuned Multi-Gen LRU (MGLRU) with hardware PTE walk for heavy gaming and multitasking
• Fixed aggressive LMKD kills and game crashes during memory pressure / zRAM saturation
• Added manual `newfstat` and `fstat64` hooks in `fs/stat.c` for reliable KSU init.rc injection
• Disabled LSM AUTO_INITRC_HOOK in favor of native sys_read manual hooks
• Fixed race condition in Thermal Auto-Guard (`ki_profile`) during Performance profile switch
• Added Power Supply notifier to dynamically adjust screen-off profile on charger connect/disconnect
• Improved thermal sensor resolution in `ki_profile` with asynchronous retry for late-probing sensors
• Fixed boot settlement log reporting true active profile during screen-off boot
• Fixed AOSP boot hangs across custom ROMs with multi-format ramdisk decompressors (LZ4, XZ, LZO, GZIP)
• Added EROFS compression & security xattr configs (`CONFIG_EROFS_FS_SECURITY`, `CONFIG_EROFS_FS_ZIP`)
• Added `CONFIG_FHANDLE` for modern Android init and Apexd container compatibility
• Modernized Clang ThinLTO linker script with upstream wildcards (`..L*`, `ro_after_init`, initcall tables)
• Restricted `-fsplit-lto-unit` to CFI configurations to eliminate ThinLTO driver symbol misplacements
• Disabled `CONFIG_MODVERSIONS` to prevent symbol CRC mismatch on vendor modules with Clang LTO
• Replaced single-node IR driver with clean Hybrid Dual-Interface driver (`/dev/lirc0` for AOSP and `/dev/ir_spi` for MIUI)
• Fixed IR transmission failure on AOSP custom ROMs by restoring rc-core LIRC device node and pulse-space modulation
• Fixed broken process comm check (`service_is_ir`) that rejected `/dev/ir_spi` access with `-ENODEV` on MIUI/HyperOS
• Added dummy regulator (`irda_regulator`) to SM8250 device tree and bound power supply to SPI SE2
• Fixed LIRC signal trailing space truncation in `lirc_dev.c` for accurate IR protocol packet transmission

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

