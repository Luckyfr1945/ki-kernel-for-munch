# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-09-29  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI / HyperOS & AOSP (Android 11 - 17)  
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## v1.4
• Backported syscall epoll_pwait2 from Linux 5.11 (Nanosecond precision I/O event polling)
• Backported TCP Westwood-sub congestion control (Modernized sampling rate & loss recovery for Wi-Fi)
• Optimized CFS scheduler newly-idle balance latency (Reduce long-tail load balance cost)
• Removed Qualcomm POPP throttling from Adreno 650 KGSL driver (Unthrottled GPU sustain)
• Nuked debugging wakelocks from qcacld-3.0 Wi-Fi driver (Deep sleep battery savings)
• Created experimental AOSP-only branch with EEVDF + CASS scheduler




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

