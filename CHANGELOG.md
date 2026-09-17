# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-09-17  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI & AOSP  
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## v1.3 — 2026-09-17

### 🚀 Fitur Baru & Optimasi
- **[Sound Control]** Menambahkan interface audio gain Franco / Flar2 via `/sys/kernel/sound_control/` untuk kustomisasi volume headphone dan mic.
- **[Ki-Profile Engine]** Menambahkan kontrol profil performa modular (`/sys/kernel/ki_profile/mode`) yang mendukung mode *battery*, *balanced*, *performance*, dan *gaming*.
- **[Bypass Charging & Fast Charge]** Memperkenalkan sysfs control untuk bypass charging saat gaming (`/sys/class/power_supply/battery/bypass_charging`) serta fast charging tetap aktif saat layar menyala (`screen_on_fast_charge`).
- **[Network Gaming (TCP BBRv2 & PLB)]** Mengintegrasikan algoritma TCP BBRv2 dan Protective Loss Boost (PLB) untuk kestabilan koneksi dan ping rendah saat bermain game online.
- **[GPU OC & UV Restored]** Mengaktifkan kembali profile Adreno 650 OC + Underclock & Undervolt (150 MHz – 683 MHz): boost 683 MHz untuk performa game maksimal, dan floor 150 MHz untuk penghematan daya idle baterai. DTB stock 305–670 MHz tetap disertakan.

### 📱 Kompatibilitas Android Modern (Android 15 / 16 / A17 Ready)
- **[Backport `clone3()` Syscall]** Melakukan backport penuh syscall `clone3` (435) beserta `copy_thread_tls` arm64, `CLONE_CLEAR_SIGHAND`, `CLONE_PIDFD`, dan validasi stack. Fitur ini wajib untuk runtime Bionic libc pada Android 15/16/A17 modern agar process spawning berjalan lancar tanpa fallback error atau crash.

### 🛠️ Perbaikan & Bug Fixes
- **[Syscall Table & Linker Fix]** Memperbaiki error bounds array pada `arch/arm64/kernel/sys32.c` (`__NR_compat_syscalls 436`) dan membersihkan entri syscall non-existent di Linux 4.19 (`close_range` 436 & `epoll_pwait2` 441) sehingga `vmlinux` ter-link sukses tanpa error undefined reference.
- **[CFI Failure Fix]** Memperbaiki crash kernel CFI (Control Flow Integrity) saat inisialisasi modul jaringan `rmnet_shs` dan `rmnet_perf`.
- **[Audio Driver Fix]** Mengatasi warning compiler `-Wimplicit-enum-enum-cast` pada techpack audio Qualcomm `wcd_cpe`.
- **[TikTok Crash Fix & Compiler Hardening]** Menstabilkan optimasi compiler `KCFLAGS=-O2` serta menegakkan `-mgeneral-regs-only` dan `-mno-implicit-float` pada `arch/arm64/Makefile` untuk mencegah korupsi floating-point/NEON yang memicu crash SIGSEGV (`libttmplayer.so`).


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