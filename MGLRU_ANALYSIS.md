# Analisis RAM dan MGLRU — munch

Pemeriksaan 15 November 2026 memakai source lokal dan ADB root. Kernel yang
berjalan: 4.19.325-Ki-kernel-v1.6, build 14 November 2026 22:00:33 WIB.

## Bukti runtime

- Log 23:59:36–00:00:03 memuat 30 kill LMKD dengan alasan
  `low watermark is breached`, oom_score_adj 800–985. Ini proses background,
  termasuk Chrome, kamera, dan WhatsApp; bukan bukti foreground crash.
- MGLRU aktif dengan mask `0x0001`, min_ttl_ms 0. Batch page-table walk mati.
- kswapd0:0 memiliki affinity CPU 0–3. ZRAM memakai ZSTD, kapasitas logis 6 GiB.
- Pada 00:00:02, MemAvailable 2.71 GiB dan swap terpakai 1.08 GiB. MemAvailable
  mencakup memori yang perlu direclaim dan bukan jaminan alokasi langsung lancar.
- Snapshot 00:00:02–00:00:30 menunjukkan tambahan 41 allocstall, 32.271 halaman
  direct reclaim (sekitar 126 MiB pada halaman 4 KiB), dan 76.932 refault.
  PSI memory full avg10 pada snapshot pertama 7,70%. oom_kill tetap 0;
  counter kernel OOM tidak menghitung kill yang dilakukan LMKD.
- User 0 dan cloneUser 10 berjalan. Belum diukur kontribusi masing-masing.

## Perbaikan source

`mm/page_alloc.c`: hapus clamp tersembunyi watermark_scale_factor ke 20 setelah
validasi sysctl. Rentang yang sudah ada pada kernel/sysctl.c adalah 1–1000;
dokumentasi lokal Documentation/sysctl/vm.txt juga menjelaskan batas 1000.
Sebelumnya nilai valid seperti 25 diterima tetapi diam-diam diganti menjadi 20,
sementara profil Performance dapat memasang 25 langsung.

Perubahan ini memperbaiki perilaku penulisan sysctl, bukan menaikkan watermark
otomatis. Default 20 dan nilai profil Battery/Balanced/Performance 10/12/25
tetap sama. Pergantian profil eksplisit masih bisa mengganti nilai sesuai
profil. Perubahan belum berjalan di HP sampai kernel baru dibangun dan diflash.
Belum terbukti perubahan ini sendiri mengurangi reload.

## Validasi

- Kompilasi mm/page_alloc.o dengan konfigurasi out/.config dan ZyC Clang 16
  berhasil. Bukan build Image/ZIP baru. Ada warning host modpost const qualifier
  dan peringatan egrep usang pada log build, bukan error page_alloc.
- checkpatch: 0 error, 0 warning. git diff --check berhasil.
- Cek fungsi runtime 00:22:04–00:22:24: mask 3 terbaca 0x0003 dan bertahan
  selama 20 detik, kemudian dipulihkan ke 0x0001. Tidak ada tambahan allocstall
  atau pgscan selama interval itu, jadi workload tidak cukup tertekan untuk
  menilai manfaat mode 3. Penurunan PSI saat itu bukan bukti perbaikan.
- Bukti mentah: ki_logs_mglru_live/{snapshot.txt,snapshot2.txt,logcat.txt,
  before_changes.txt,mode3-smoke.txt}. Log kompilasi: /tmp/ki-watermark-build.log.

## Pengujian yang ditunda

Pengguna memilih mengerjakan kode dahulu. Uji pindah aplikasi dengan urutan dan
kondisi yang sama untuk mode 1 versus 3 belum dilakukan. Default MGLRU/module/
daemon, affinity kswapd, LMKD, TTL, kompresor dan ukuran ZRAM tidak diubah.
Jangan menggabungkan perubahan watermark, mode MGLRU dan kompresor sekaligus
dalam perbandingan karena penyebab hasilnya akan sulit dipisahkan.

Referensi komponen MGLRU:
https://docs.kernel.org/admin-guide/mm/multigen_lru.html

## Perubahan source lanjutan

Setelah disetujui, driver profil mendapat sysfs memory_tuning (default 0).
Dengan default ini, boot, pergantian profil, dan reapply tidak menulis empat
pengaturan VM di atas. Pengaturan CPU/GPU, thermal dan idle floor tetap berjalan.
Menulis 1 mengaktifkan kebijakan VM profil lama dan langsung menerapkannya;
menulis 0 menghentikan penimpaan selanjutnya tanpa memulihkan nilai lama.
Pengaturan eksplisit module, misalnya VFS_CACHE_PRESSURE, tetap berlaku.
ABI lengkap ada di Documentation/ABI/testing/sysfs-kernel-ki-profile-memory-tuning.

ZRAM tidak lagi memaksa disksize 6 GiB atau mengganti permintaan kompresor
LZO/LZO-RLE menjadi ZSTD. Default kompresor dari Kconfig tetap ZSTD; perubahan
ini menghormati permintaan ROM, bukan mengganti default menjadi LZ4. Pemeriksaan
algoritma yang tersedia dan penolakan perubahan device yang sudah aktif tetap
dipertahankan. Nilai kapasitas/kompresor setelah reboot bergantung konfigurasi ROM.

Affinity kswapd, default MGLRU dan swappiness tidak diubah. Perubahan ini masih
di source; tidak ada reset swap atau perubahan ZRAM aktif pada HP.

Validasi lanjutan: target drivers/misc/ki_profile.o,
drivers/block/zram/zram_drv.o dan mm/page_alloc.o berhasil dengan konfigurasi
out/.config. checkpatch untuk ketiga perubahan C: 0 error, 0 warning;
git diff --check berhasil. Log: /tmp/ki-memory-build.log. Belum dibuat Image/ZIP
baru dan perilaku setelah boot kernel baru belum diuji.
