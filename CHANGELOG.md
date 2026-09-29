# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-09-29  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI / HyperOS & AOSP
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## v1.4
• Backported epoll_pwait2 
• Added TCP Westwood-sub improvements for Wi-Fi
• Optimized CFS load balancing
• Pinned kswapd to Little cores
• Synced RAM watermarks with Ki-Profile
• Hardened netd broken pipe handling
• Removed Adreno 650 POPP throttling
• Removed Wi-Fi debug wakelocks
• Added Boeffla Wakelock Blocker
• Optimized deep sleep & suspend
• Fixed MIUI and AnyKernel3 flashing issues
• Added experimental EEVDF + CASS AOSP
• Fine-tuned schedutil & CPU migration for butter-smooth 120Hz scrolling while keeping low idle drain

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

