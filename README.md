# Ki-kernel - POCO F4 (munch)

Custom kernel for POCO F4 / Redmi K40S (munch / sm8250) based on LineageOS 4.19 with KernelSU-Next and SuSFS.

## Specs & Features
- Linux 4.19.325
- KernelSU-Next v3.3.0 (Driver UAPI v2)
- SuSFS v1.5.7 (15/15 features enabled)
- Metamodul / OverlayFS support (fixed error 17)
- Realtime discard (TRIM) for EROFS & F2FS
- ZRAM: LZ4, LZ4HC, ZSTD

## Builds
- **AOSP**: For AOSP based ROMs (tested on Android 16 / AxionOS 2.8 Beta)
- **MIUI**: For MIUI / HyperOS stock based ROMs

## Changelog
Lihat catatan lengkap pembaruan di [CHANGELOG.md](CHANGELOG.md).
- **Universal Dual-Partition Flashing**: AnyKernel3 mem-flash `Image` ke `boot` dan `dtb` ke `vendor_boot` (Fix bootloop A16 / Infinity-X & TWRP hilang).
- **KernelSU-Next v3.3.0 & SuSFS 1.5.7**: 15/15 fitur aktif lengkap, fix OverlayFS mount error 17, fix panic setuid & string buffer.
- **Schedutil & Daily Ojol Tuning**: Silver 1ms responsif 120Hz, Prime 10ms thermal guard (anti-panas matahari), auto turbo gaming saat beban tinggi.
- **Jaringan & TCP (BBRv3)**: Google BBRv3 (2023+) default, anti packet-drop di sinyal 4G jalanan & Wi-Fi 6, pilihan dibatasi hanya `bbr` dan `westwood`.
- **Hardware Bypass Charging**: SMB5 driver tweak untuk direct power ke motherboard saat gaming.

## Flashing
Flash the zip via Custom Recovery (TWRP / OrangeFox) or Kernel Flasher:
- AOSP: `Ki-kernel-AOSP_*.zip`
- MIUI: `Ki-kernel-MIUI_*.zip`

## Notes
Root hiding di kernel level (SuSFS) udah aktif semua. Untuk bypass app banking / DANA, pastikan setup userspace juga bener:
- Play Integrity lolos device integrity (PlayIntegrityFix)
- Sembunyikan app root (MT Manager, KSU, LSPosed, Termux) pake Hide My Applist
- Hide Zygisk pake Shamiko / Zygisk Assistant

## Credits
- [LineageOS SM8250](https://github.com/LineageOS/android_kernel_xiaomi_sm8250)
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)
- [SuSFS](https://gitlab.com/simonpunk/susfs4kernel) by simonpunk
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) by osm0sis
- [liyafe1997](https://github.com/liyafe1997/kernel_xiaomi_sm8250_mod)
- [UtsavBalar1231](https://github.com/UtsavBalar1231/kernel_xiaomi_sm8250)
