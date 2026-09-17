# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-09-16  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI & AOSP  
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## v1.3 — 2026-09-16

- **[Toolchain Migration]** Migrated compiler to **ZyCromerZ Clang 16.0.6** with integrated GNU Binutils 2.47 for proven rock-solid stability, optimal power efficiency, and flawless codegen on Linux 4.19 SM8250.
- **[GPU OC & UV Restored]** Restored the optimal Adreno 650 OC + Underclock & Undervolt profile (150 MHz – 683 MHz) as default: 683 MHz peak boost for gaming with undervolted voltage bins, down to 150 MHz low idle floor for maximum battery endurance. Stock 305–670 MHz DTB is retained as alternate.
- **[TikTok Crash Fix]** Eliminated media player signal SIGSEGV crashes (`libttmplayer.so`) by stabilizing compiler optimizations and enforcing `KCFLAGS=-O2`.
- **[Compiler Hardening]** Enforced `-mgeneral-regs-only` and `-mno-implicit-float` in `arch/arm64/Makefile` to block auto-vectorizer from corrupting floating-point/NEON context during kernel-space interrupts.
- **[Thermal & Battery]** Idle battery temperature stabilized at 39°C with low background load; eliminated GPU bus starvation on 120 Hz display panels.

## v1.2 — 2026-09-15

- Added DT2W (Double Tap To Wake) support via universal `/sys/touchpanel/double_tap` interface for FocalTech (FT3658U) and Novatek (NT36672C).
- Fixed touchscreen gesture state updates and recovery during display suspend.
- Added delayed initialization workqueue for touchscreen to ensure instant response on cold boot and recovery.
- Added haptic and vibration strength control for AW86927 via `/sys/kernel/haptics/gain`, `/sys/kernel/haptics/vmax`, and `/sys/kernel/haptics/level`.
- Fixed app crashes (TikTok MediaCodec & BoringSSL FIPS abort) by fixing memory buffer corruption in ZRAM swap.
- Reverted experimental fsync modifications to stock to maintain atomic SQLite WAL transaction integrity.
- Fixed touchscreen mode 25 error spam in dmesg on MIUI / HyperOS.
- Fixed I2C bus arbitration lost and timeout errors on fuel gauge IC (BQ27Z561).

---
  <a href="https://t.me/+i7NfuXZA6mZjOWJl">
    <img src="https://img.shields.io/badge/Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram">
  </a>
</p>