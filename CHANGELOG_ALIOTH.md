# Ki-kernel for POCO F3 / Redmi K40 / Mi 11X (alioth)

**Status:** Public Beta (Initial Port)  
**Build Date:** 2026-11-05  
**Kernel Version:** Linux 4.19.325  
**Variant:** Universal Dual-OS (AOSP & MIUI/HyperOS & ColorOS/OxygenOS)  
**Root / Hide:** KernelSU + SuSFS v2.3.0  
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + LLD)  

---

> [!WARNING]
> **BETA RELEASE NOTICE:**  
> Ini adalah rilis **Beta Perdana (Initial Port)** Ki-kernel untuk POCO F3 (`alioth`).  
> Harap selalu lakukan **backup partisi boot & dtbo** via recovery (TWRP/OrangeFox) sebelum melakukan flashing!

---

## Ki-kernel v1.6.1 Beta (Initial Alioth Port)

- Samsung E4 AMOLED late cleanup safeguard: protected display power rails from being disabled at late boot
- Fixed AnyKernel3 Universal installer: proper directory binding for multi-ROM detection
- fast charging
- Added universal AnyKernel3 multi-ROM detection
- Integrated KernelSU, SuSFS v2.3.0 inline hooks, and NoMount
- Added built-in getpriority
- Enabled Baseband Guard (CONFIG_BBG) kernel modem isolation
- Compiled with Clang 16
- Optimized sync_file ioctl for faster SurfaceFlinger frame pacing
- Aligned clear_page to 16 bytes
- Enabled Multi-Gen LRU (MGLRU) by default
- Set Maple as default I/O scheduler alongside ADIOS v3.3.0
- Added NTSYNC 
- Enabled BBRv3
- Added Boeffla Wakelock Blocker, Dynamic Fsync, and Suspend Skip Sync
- Enabled power-efficient workqueues and silenced smcinvoke log spam
- Added native Droidspaces, and WireGuard support

---

### 📝 Catatan Pengujian Beta (Testing Checklist):
Bagi para tester POCO F3, mohon feedback untuk aspek-aspek berikut:
1. Kecepatan pengisian daya (33W Fast Charging) dan pembacaan persentase baterai.
2. Responsivitas touchscreen dan getaran haptic feedback (AW8697).
3. Deep sleep dan konsumsi baterai saat layar mati (screen-off drain).
4. Kamera, suara speaker/mic, dan koneksi Wi-Fi/Bluetooth.

