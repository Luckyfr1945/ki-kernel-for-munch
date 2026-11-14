# Ki-kernel for POCO F4 / Redmi K40S (munch)

**Build Date:** 2026-11-14  
**Kernel Version:** Linux 4.19.325  
**Variant:** MIUI/HyperOS, AOSP, And ColorOS/OxygenOS (Universal & Single Variants)  
**Toolchain:** ZyCromerZ Clang 16.0.6 (LLVM 16.0.6 + GNU Binutils 2.47)  

---

## Unreleased

- Pin BakaSU, NoMount and Baseband-guard sources; verify patch checksums and final source trees before building.
- Sync Droidspaces kernel requirements with upstream: enable devtmpfs and nftables in munch defconfig, fix old config names, and check the resolved config before building.
- Remove the hidden watermark limit of 20 so ROM tuning follows the existing sysctl range.
- Keep ROM memory settings when switching profiles; profile VM tuning is now opt-in through `memory_tuning`.
- Let ROMs choose ZRAM size and compressor without forcing 6 GiB or replacing LZO/LZO-RLE with ZSTD.
- Backport CPUFreq policy initialization, camera request-queue lifetime, BPF checksum/tailcall/sockops, and memory compaction fixes.
- Restrict KGSL mmap to the address space that opened the device, with balanced mm references.
- Refresh munch fuel-gauge properties independently of charger presence; preserve local battery guards and fix forced-SOC output ordering.
- Propagate wired charging errors in munch SMB5 paths, including temperature, night charging, USB online, Type-C setup and charge-pump discovery.
- Backport selected IPv4/IPv6, netfilter, packet socket, CNSS2 QMI, USB, audio, HID, F2FS and exFAT fixes.
- Record all 32 source commits, local adaptations, partial imports and validation in `UPSTREAM_BACKPORTS.md`.

## Ki-kernel v1.6.6 (Display Driver Clean-up, Anti-Flicker DC Dimming Final Stabilization & Anti-SOD Architecture) :
- Anti-Flicker DC Dimming Calibrated Linear-Light DSPP PCC:
  - Linear-Light Panel Luminance Alignment: replaced sRGB gamma-domain LUT alpha interpolation in `techpack/display/msm/dsi/exposure_adjustment.c` with direct linear panel luminance ratio matching the `l11r` Munch OLED panel (`nits(bl) / nits(thresh)` = `(498 * bl + 1046) / (498 * thresh + 1046)`). Because `DSPP_IGC` linearizes incoming pixels before `DSPP_PCC` and `DSPP_GC` re-applies panel gamma afterward, scaling in linear light eliminates the ~4.1x brightness jump when toggling DC dimming at minimum slider level (`bl = 33`), achieving exact luminance parity between DC ON and DC OFF.
  - Sub-Threshold Headroom: lowered `EXPOSURE_ADJUSTMENT_MIN` to 256 (down from 2048) in `exposure_adjustment.h`, allowing ultra-low brightness levels (e.g. Extra Dim down to DBV 2) to scale cleanly without artificial clamping.
- Display Sleep-of-Death (SOD) Eradication & Driver Simplification:
  - Eliminated Deferred Backlight Traps (Black Screen SOD): completely removed asynchronous backlight deferral and queueing (`ea_pending_bl`, `ea_pending_seq`, `ea_commit_seq`) from `techpack/display/msm/dsi/dsi_panel.c` and `exposure_adjustment.c`. `dsi_panel_set_backlight()` now updates physical hardware DBV immediately via `dsi_panel_update_backlight()`. Completely eliminates display wake failures where physical backlight was trapped behind uncommitted sequences during power state transitions.
  - Eradicated DRM Atomic Commit Workqueue Deadlocks: removed `dsi_display_ea_commit_work()` and background atomic commits (`drm_atomic_nonblocking_commit()`) from `techpack/display/msm/dsi/dsi_display.c`. SDE CRTC commits driven by SurfaceFlinger at 60/120Hz naturally apply dirty DSPP PCC states via `sde_cp_crtc_apply_properties()` and `sde_kcal_apply()` on active frames without competing for `connection_mutex` or hanging on `PP_DONE` timeouts during sleep/wake cycles.
  - Removed Hazardous DSI Clock Toggling in Pre-Kickoff: eliminated manual `DSI_CORE_CLK` gating and redundant DCS `0x53 0x20` dimming-off commands inside `dsi_display_pre_kickoff()`, preventing DSI command FIFO underflows and display engine stalls prior to frame transmission.
  - KCAL & EA Harmonious Integration: removed out-of-band commit scheduling from `techpack/display/msm/sde/sde_kcal.c`, allowing SurfaceFlinger's render pipeline to consume `sde_kcal_consume_dirty()` synchronously. Retained 18-bit signed matrix multiplication and stack-local scratch buffers for 100% thread safety across night light, LiveDisplay, KCAL, and DC dimming.
- TCP Congestion Control Optimization & Dedicated BBRv3 / Westwood-Sub Streamlining:
  - Clean Dual-Congestion Architecture: streamlined available TCP congestion controls to strictly `bbrv3` and `westwood-sub` (`net/ipv4/tcp_bbr.c`, `net/ipv4/tcp_westwood.c`, `net/ipv4/Kconfig`). Completely eradicated duplicate legacy alias registrations (`bbr`/`bbr3` and `westwood`/`westwood-sub`) and disabled CUBIC/BIC/HTCP across both `munch_defconfig` and `munch_stock-defconfig`.
  - Fair Queueing (FQ) Pacing Default Enforcement: enabled `CONFIG_NET_SCH_DEFAULT=y`, `CONFIG_DEFAULT_FQ=y`, and `CONFIG_DEFAULT_NET_SCH="fq"` across all kernel configs. Previously, missing `CONFIG_NET_SCH_DEFAULT=y` silently forced `pfifo_fast` as default qdisc, causing BBRv3 to blast un-paced packet bursts into cellular/Wi-Fi uplink queues, triggering severe self-inflicted buffer packet loss and crippling mobile upload throughput. FQ nanosecond packet pacing keeps upload pipelines fully saturated.
- Upstream NoMount v2.3.0 Subsystem Integration:
  - Upgraded NoMount VFS redirection subsystem from v2.0.0 (driver 22) to latest official release `v2.3.0-720` (driver 23). Includes OOB read fix when selecting rules from single-element arrays, leaf link reuse, virtual inode lifecycle persistence across lookups, native file resolution from parent, and hardened VFS operations against edge cases.

## Ki-kernel v1.6.5 (Sleep-of-Death & Framework Watchdog Resolution, AnyKernel3 HyperOS Fix & Safe Storage) :
- Qualcomm DSPP PCC Anti-Flicker DC Dimming & Display SOD Hardening:
  - DSPP PCC Exposure Adjustment Integration: implemented Qualcomm DSPP PCC anti-flicker DC dimming (`techpack/display/msm/dsi/exposure_adjustment.c`) for brightness levels below `ELVSS_OFF_THRESHOLD` (500), maintaining stable panel emission while scaling pixel luminance smoothly down to minimum brightness.
  - Fixed Bright Fallback When Disabling DC Dimming (ON → OFF): unified EA mode handling inside `__dsi_display_set_disp_param()` (`techpack/display/msm/dsi/dsi_display_mi.c`) and removed premature calls in `sysfs_disp_param_write()` / `sysfs_dimming_write()` (`techpack/display/msm/dsi/dsi_display.c`) so `dsi_panel_set_disp_param()` clears `mi_cfg->dc_enable` *before* `ea_panel_mode_ctrl(false)` and refreshes `panel->bl_config.bl_level` via `dsi_display_set_backlight()`. Prevents `dc_skip_set_backlight()` (`dc_type = 1`) from discarding low-brightness updates (`< 440`) and leaving physical backlight stuck at 500 at 100% PCC gain.
  - Eliminated Random Brightness Flares During Scrolling: replaced out-of-commit `sde_cp_crtc_set_property()` hijacking of `SDE_DSPP_PCC_V4` with a spinlock-protected DSPP post-modifier (`ea_panel_modify_pcc()`) inside `set_dspp_pcc_feature()` (`techpack/display/msm/sde/sde_color_processing.c`) and `sde_kcal_apply()` (`techpack/display/msm/sde/sde_kcal.c`). Composes `userspace PCC * KCAL * EA` in stack-local PCC buffers without mutating userspace property blobs, triggers `ctl->ops.update_bitmask_dspp` flushes even when CP lists are empty, and restores EA attenuation via `ea_dirty` across idle power collapse (`sde_cp_crtc_suspend`), `sde_crtc_enable()`, and FOD HBM overlay transitions.
  - Eliminated Display-Side SOD Races in EA: removed unlocked `dsi_panel_set_backlight()` and out-of-commit `sde_cp_crtc_set_property()` / `drm_property_blob_put()` calls from `exposure_adjustment.c`, guarding sysfs-triggered backlight refreshes with `sde_kms_is_suspend_blocked()`, `panel->panel_lock`, and `DSI_CORE_CLK`.
- Pure Hardware DC Dimming & Backlight Stability Resolution (Elimination of Grey Notifications & Sudden Brightness Spikes):
  - Elimination of Grey/Washed-Out Notifications: disabled `CONFIG_DRM_SDE_EXPO` in `konadisp.conf`, `konadispconf.h`, and `munch_defconfig`. Previously, the re404 SDE exposure dim layer driver injected a software black alpha layer (`color_fill = {0,0,0,alpha}`) at the highest mixer stage (`zpos++`). On Android 14–17 AOSP, translucent notification cards and heads-up banners suffered severe alpha interference, making notifications appear washed out and grey.
  - Eradication of Random Brightness Flare-ups ("terang sendiri kadang"): removing `CONFIG_DRM_SDE_EXPO` eliminates the artificial hardware backlight clamp to 440 (`DIM_THRES_LEVEL`). Previously, whenever multi-layer composition (notifications, shade, dialogs) exceeded `maxblendstages` or caused atomic check fallback, the software darkening layer vanished while the physical LEDs were still forced to 440, causing abrupt flashes of high brightness.
  - Autonomous Hardware Panel DC Dimming on AOSP: added `mi,mdss-dsi-panel-dc-type = <0>;` alongside `mi,mdss-dsi-dc-on-command` and `mi,mdss-dsi-dc-off-command` (`0x53 0x28` / `0x53 0x20`) across all display timings (`timing@0`, `timing@1`, `timing@2`) in `dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi`, matching `k11a` (Redmi K40 / POCO F3). With `dc_type = 0`, the DDIC handles DC dimming autonomously, `dc_skip_set_backlight` no longer skips backlight levels below 440, and the slider operates smoothly down to true minimum level 1.
  - Backlight Clamping Alignment: restored `sde_connector.c` comparison to `brightness_max_level` matching stock Qualcomm/LineageOS, ensuring linear and monotonic scaling without slider clipping regardless of userspace scale.
  - Seamless Sysfs Integration: maintained `dimlayer_exposure`, `dimming`, `dc_dimming`, and `disp_param` sysfs nodes wired directly to hardware DCS dimming commands, ensuring complete out-of-the-box compatibility with AOSP LiveDisplay, crDroid display settings, and custom scripts.
- crDroid & AOSP ROM Boot Resolution (Hexagon SLPI & SurfaceFlinger Hang Fix):
  - AnyKernel3 Cmdline Dynamic DTBO Selection: dynamically assigned `dtbo_def` on AOSP / Custom ROM targets and `dtbo_oem` on MIUI/HyperOS/ColorOS in `anykernel.sh` (`e404_args=${rom_arg},${dtbo_arg},dtb_def,batt_def`). Previously, `dtbo_oem` was hardcoded, causing AOSP ROMs with stock AOSP DTBOs to misconfigure hardware subsystems.
  - Universal Zip OS-Specific DTB Staging: restructured AnyKernel3 package hierarchy to stage and flash DTBs per OS target (`kernels/aosp/dtb_stock`, `kernels/aosp/dtb_oc`, `kernels/miui/dtb_stock`, etc.). Completely prevents MIUI DTB from erroneously overwriting `vendor_boot` on AOSP devices during interactive GPU prompt timeouts.
  - Pure AOSP Config Clean-up: disabled Xiaomi proprietary hooks and daemons (`CONFIG_SF_BINDER`, `CONFIG_BOOTUP_RECLAIM`, `CONFIG_MILLET`, `CONFIG_MIGT`, `CONFIG_RTMM`, `CONFIG_MI_RECLAIM`, `CONFIG_MIUI_ZRAM_MEMORY_TRACKING`, `CONFIG_REGULATOR_QCOM_RPMH`, `CONFIG_I2C_RETRY`) when compiling the AOSP kernel target. Eliminates SurfaceFlinger binder thread priority corruptions and prevents Hexagon SLPI sensor DSP I2C transfer timeout crash-loops.
- Upstream BPF Security & Stability Hardening: backported 15 official upstream Linux stable bugfixes for the eBPF subsystem. Eliminates 3 Use-After-Free vulnerabilities (`bpf_netns_link_update_prog`, `tcp_bpf_sendmsg`, offload info), prevents 4 integer overflow conditions in `bpf_msg_push_data`/`pop_data` and array map element indexing, eliminates `metadata_dst` route leaks on IPv4/IPv6 BPF redirection, resolves race conditions in `bpf_get_btf_vmlinux`, and hardens verifier precision tracking. Provides rock-solid networking and tethering offload reliability across Android 14–17.
- Laptop 15W C-to-C & Maximum Charging Wattage Unthrottling:
  - Policy Engine Munch: fixed fatal PDO negotiation bug in `drivers/usb/pd/policy_engine_munch.c` where laptops/chargers lacking a 9V fixed PDO caused `usbpd_fixed_pdo_workfunc` to force an invalid PDO index 2, resulting in request rejection and fallback to 500mA. The driver now cleanly retains the negotiated 5V/3A (15W) contract.
  - Type-C Rp & USB Current Resolution: updated `smb5-lib-munch.c` to parse `typec_mode` (`POWER_SUPPLY_TYPEC_SOURCE_HIGH` = 3.0A, `SOURCE_MEDIUM` = 1.5A) in both `update_sw_icl_max` and `smblib_handle_usb_current`. USB gadget enumeration no longer truncates Type-C input current down to 500mA SDP, ensuring full 15W draw from laptop C-to-C ports.
    - Progressive Thermal Stepping & Overdrive: restored smart progressive thermal stepping in `smblib_get_screen_on_clamped_level` with default `force_fast_charge = 1` and `screen_on_fast_charge = 1` in `smblib_init` and `ki_optimizer.conf`. Re-enabled peak 40W QC/HVDCP target and unthrottled non-PPS PD charging by raising `NON_PPS_PD_FCC_LIMIT` to 6.0A in `pd_policy_manager_munch.h`.
- BakaSU Upstream Sync: rebased KernelSU BakaSU implementation onto official upstream main branch (`548d1dda`) and regenerated CI patch while preserving custom multi-manager support (OriginSU 4096-bit cert, FinaSU, MidoriSU, KowSU, KSUN, RKSU, MKSU, YukiSU) and SuSFS v2.4.0 integration.
- Upstream SuSFS v2.4.0: upgraded kernel SuSFS inline hooks and headers to official v2.4.0 (`simonpunk/susfs4ksu`). Added `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` with fast `packages.list` parser (`O_NOATIME`), ratelimited SELinux rule & type logging (`pr_info_ratelimited`), robust `susfs_av_rule_hash` full-tuple verification, and `DEFAULT_KSU_MNT_MINOR_DEV` support for seamless detection evasion.
- ZRAM 6GB & ZSTD Compression Integration: enforced 6GB (6144 MB) ZRAM disksize in `drivers/block/zram/zram_drv.c` for optimal multitasking across all ROMs. Enabled `CONFIG_CRYPTO_ZSTD=y`, `CONFIG_ZSTD_COMPRESS=y`, `CONFIG_ZSTD_DECOMPRESS=y`, and configured `CONFIG_ZRAM_DEF_COMP_ZSTD=y` (`CONFIG_ZRAM_DEF_COMP="zstd"`) across `munch_defconfig` and `munch_stock-defconfig`. Removed legacy forced override to LZ4, allowing native ZSTD compression for superior ~2.5x-3x memory compression ratio while auto-upgrading legacy LZO/LZO-RLE requests.
- Anti-Cheat Module Security Hardening: enabled `CONFIG_MODVERSIONS=y`, `CONFIG_MODULE_SIG=y`, `CONFIG_MODULE_SIG_SHA512=y`, and disabled `CONFIG_MODULE_FORCE_LOAD` across `munch_defconfig` and `munch_stock-defconfig`. Modules are cryptographically verified with SHA-512, eliminating untrusted force-load vectors and passing Tencent ACE / mobile anti-cheat kernel integrity audits without game account bans.
- Stock MIUI / HyperOS Vendor Module Loader & Boot Synchronization:
  - Dynamic Stock ROM Module Loading: enabled `CONFIG_MODULE_FORCE_LOAD=y`, disabled `CONFIG_MODVERSIONS`, and disabled `CONFIG_MODULE_SIG` dynamically in `build.sh` for MIUI / HyperOS target and in `munch_stock-defconfig`. Resolves fatal `disagrees about version of symbol module_layout` errors on Stock MIUI/HyperOS where proprietary Xiaomi vendor modules (`wlan.ko`, `cs35l41_dlkm.ko`, `q6_pdr_dlkm.ko`, `fpc1540.ko`, `rmnet_perf.ko`) were rejected on boot. AOSP retains module signature verification and CRC checking for game anti-cheat safety.
  - Daemon Uname Synchronization: updated early-boot uname spoofing in `kernel/sys.c` to check `current_uid().val <= 1000`, covering both `AID_ROOT` (UID 0, for `netd` & `bpfloader`) and `AID_SYSTEM` (UID 1000, for `netbpfload` & `uprobestats`) without artificial time limits. Eliminates `libnetd_updatable_init` BPF map retrieval aborts, prevents boot delays, stops Zygisk Next failsafe shutdowns, and ensures 100% seamless boot across both Stock MIUI/HyperOS (Android 14) and AOSP (Android 15–17). Unprivileged user apps and games (`UID >= 10000`) continue to receive authentic `4.19` uname info to prevent anti-cheat bans.
- Aftermarket Battery Shutdown & Charge Cutoff Fix: ported battery gauge stability fixes from upstream e404 (`37da736cf32c` by Muhammad Guntur). Guarded negative initial sentinel values (`batt_volt`, `batt_curr`, `batt_soc`) in `drivers/power/supply/qcom/bq27z561_fg_munch.c`, rejected fake temperature placeholders on persistent I2C bus read errors (`i2c_error_cnt >= 3`), guarded against division by zero on `fcc <= 0`, and eliminated aggressive USB charge suspension (`input_suspend`) in `drivers/power/supply/qcom/smb5-lib-munch.c` to prevent abrupt power-offs and charging failures on non-genuine replacement batteries.
- Stock MIUI / HyperOS Sleep-of-Death (SOD) Elimination:
  - HyperOS DozeSuspend (LP2) ESD Handling: updated `esd_err_irq_handle()` in `techpack/display/msm-miui/sde/sde_connector.c` and `techpack/display/msm/sde/sde_connector.c` to recognize `SDE_MODE_DPMS_LP2` (HyperOS AOD DozeSuspend). Prevents spurious interrupts from erroneously marking `panel_dead = true` and permanently locking the display in sleep.
  - Schedutil Default Governor Settlement: enforced `CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y` across `munch_stock-defconfig` and `build.sh`. Eliminates boot-time `performance` governor lock that caused `ki_profile` sugov rate limit configuration to fail (`-19 / -ENODEV`) and time out.
  - Safe Default DTB Packaging: updated `build.sh` and `anykernel.sh` to default to `dtb_stock` (670 MHz safe voltage curve). Prevents accidental flashing of 1 uV extreme undervolting (`dtb_oc`) during recovery timeouts or app installations that caused low-power GPU sleep lockups.
  - LHBM White Read Guard: resolved `-EAGAIN` (`-11`) display enable kickoff errors across both AOSP (`techpack/display/msm/dsi/dsi_panel_mi.c`) and MIUI (`techpack/display/msm-miui/dsi/dsi_panel_mi.c`) by verifying `fod_lhbm_white_update_flag` and command counts before executing DCS commands. Munch panels with physical side-mounted fingerprint sensors no longer hang trying to read optical under-display fingerprint registers.
  - Synchronous ESD Teardown & Inactive IRQ Filter: guarded `esd_err_irq_handle()` in `techpack/display/msm-miui/sde/sde_connector.c` and `techpack/display/msm/sde/sde_connector.c` to drop spurious ESD interrupts received while the display is uninitialized or powered off (`power_mode != ON/LP1`), preventing false `panel_dead = true` lockups during screen-off. Added `synchronize_irq()` to `dsi_panel_esd_irq_ctrl()` to guarantee in-flight ESD handlers terminate completely before panel power rails are cut.
  - Qualcomm RPMH Integrity: restored standard CAF blocking transaction loops in `rpmh_rsc_send_data()` (`drivers/soc/qcom/rpmh-rsc.c`) and `rpmh_flush()` (`drivers/soc/qcom/rpmh.c`). Eliminates artificial timeout bails that previously aborted pending power rail writes (`-EBUSY`) and dropped in-flight bus votes during Wi-Fi/PCIe runtime sleep transitions, preventing system freezes.
  - Rotator Kickoff Panic Disabler: set `SDE_EVTLOG_DEFAULT_PANIC = 0` in `techpack/display/rotator/sde_rotator_debug.c`, matching SDE debug panic disabler.
- Fatal Sleep-of-Death (SOD) & Screen Wake Freeze Resolution: restored upstream `needs_force_resume` sanitization in `drivers/base/power/runtime.c` and `include/linux/pm.h`. Previously, waking from wakelocks or deep sleep evaluated `pm_runtime_need_not_resume(dev)` as `true` on the Qualcomm Adreno 650 GPU (`adreno_device.c`), skipping its `runtime_resume` callback. The GPU remained in `RPM_SUSPENDED` while the panel backlight was powered, causing SurfaceFlinger/WindowManager display fence deadlocks, UI freeze, and triggering 60-second Android Framework Watchdog soft-reboots.
- Display SDE Kickoff Panic Disabler: set `DEFAULT_PANIC = 0` in `techpack/display/msm/sde_dbg.c` and `msm-miui/sde_dbg.c`. Frame kickoff timeouts and debug dump delays during display wake transitions no longer panic or crash the phone, delegating recovery smoothly to hardware CTL reset. Fixed DMA buffer memory leak and NULL pointer dereference in SDE register dump routines.
- Cpufreq Sugov Mutex Locking: protected cpufreq governor policy tuning with `down_read_trylock(&policy->rwsem)` in `drivers/misc/ki_profile.c` and retried gracefully when busy. Prevents kernel race conditions and use-after-free faults when switching profiles while secondary cores or the Prime core (CPU7) enter deep sleep/offline.
- Ordered Workqueue for CPU Boost: migrated `input_boost_work` in `drivers/cpufreq/cpu-boost.c` to an ordered single-threaded workqueue (`cpu_boost_wq`) to prevent touch and powerkey boost races across multiple CPU clusters.
- Balanced Profile Efficiency & Temperature Safeguard: disabled touch scheduler boost (`.touch_sched_boost = 0, .touch_boost_ms = 0`) in Balanced mode. Completely eliminates the aggressive 1-second full-throttle scheduler lock during scrolling, keeping device temperatures cool and restoring maximum battery efficiency for daily use.
- Dedicated Performance / Gaming Turbo Boost: touch scheduler boost (`.touch_sched_boost = 1, .touch_boost_ms = 150`) is now strictly exclusive to Performance mode, holding instant 150ms task migration to big cores for competitive zero-latency gaming.
- Unlocked Swappiness Control: removed hardcoded `vm_swappiness` override from `ki_profile.c`. Memory swappiness is now 100% user-customizable via WebUI `ki_optimizer`, init scripts, or `/proc/sys/vm/swappiness` without being overridden by kernel profile switching.
- Dynamic Fsync Safety & SQLite Protection: set `dyn_fsync_active` default to `false` in `drivers/misc/dyn_fsync.c`. Eliminates the risk of SQLite database and WhatsApp chat corruption caused by deferred writes during unexpected shutdowns or force reboots, while keeping it opt-in via sysfs.
- AnyKernel3 HyperOS / MIUI Flashing Fix: restricted live `getprop` ROM inspection to `BOOTMODE=true` in `anykernel.sh` and `anykernel_template/anykernel.sh` to prevent inheriting recovery properties during TWRP/OrangeFox flashing. Removed the generic `ro.product.system.name` fallback that caused HyperOS ports to be misidentified as AOSP, added regex support for Android 14/15/16 HyperOS incremental version strings (`^([0-9]+)?OS[0-9]`), and added inspection for `/system_ext/priv-app/MiuiSystemUI`.
- Multi-Manager & Signature Verification Expansion: added OriginSU signature support and raised X.509 certificate limits to 2048 bytes in `KernelSU/kernel/manager/apk_sign.c` for full RSA 4096-bit compatibility across modern custom managers.
- Module Startup Settlement Optimization: relaxed post-boot settlement sleep from 4s to 12s in `ki_optimizer_module/service.sh` to prevent CPU governor initialization from colliding with early post-boot screen-off transitions.

## Ki-kernel v1.6.4 (Fatal Sleep Lockup Fix & In-Kernel Non-Root Hotspot Engine) :
- Fatal Screen-off Sleep Lockup & Black Screen Fix: reverted problematic PM runtime commit `d0b4c0a390fb` (`PM: runtime: Drop pm_runtime_force_suspend/resume()`) in `drivers/base/power/runtime.c` and `include/linux/pm.h`. This commit erroneously omitted `needs_force_resume = 1` for devices that were already runtime-suspended before system sleep (notably the Adreno GPU / KGSL). On wake, `pm_runtime_force_resume()` evaluated `!dev->power.needs_force_resume` and skipped powering back on the Adreno GPU and GDSC rails, causing SurfaceFlinger/InputDispatcher display fence deadlocks, system freezes, and Black Screen of Death.
- Power Management Workqueue Hardening: reverted `pm_wq` back to per-CPU `WQ_FREEZABLE` in `kernel/power/main.c` and reverted pool lock optimization in `kernel/workqueue.c` to prevent unbound workqueue race conditions during AP suspend/resume transitions.
- In-Kernel Hotspot DNS DNAT Engine (Root & Non-Root Universal): implemented native in-kernel DNS DNAT redirect hook directly in `net/ipv4/netfilter/iptable_nat.c`. The kernel automatically intercepts DNS queries (port 53 UDP & TCP) originating from tethering interfaces (`wlan1+`, `ap+`, `swlan+`, `rndis+`) and transparently binds them via `nf_nat_setup_info()` to upstream DNS (`1.1.1.1:53`). This guarantees 100% working hotspot internet on Android 16 even on completely unrooted (NOKSU / Non-Root) systems without dnsmasq or userspace iptables rules.
- In-Kernel BPF Tether Ingress Bypass: hardened `sch_handle_ingress()` in `net/core/dev.c` to automatically bypass ingress qdisc classification on active tether interfaces (`wlan1+`, `ap+`, `rndis+`, `swlan+`), permanently preventing Android BPF tethering offload filters from dropping forwarded client packets across both Root and Non-Root configurations.
- Zero Background Daemon Overhead: completely eliminated the need for any background userspace hotspot watcher or polling script in `/data/adb/service.d/00_nkm_bypass.sh`. The startup script now cleanly exits immediately after applying device permissions on boot, leaving **zero background processes** while the kernel handles 100% of network offloading and DNS redirection natively.
- TCP BBR Kernel Warning Silencing: clamped `lost_prev = 0` when `lost_prev < 0` for aggregated GRO/TSO packets in `net/ipv4/tcp_bbr.c`, eliminating harmless `WARN_ONCE` logspam in `dmesg` and removing unused `tp` variable.

## Ki-kernel v1.6.3 (Display Brightness Range Calibration & AnyKernel3 GPU OC Flasher) :
- Hotspot & Tethering Fix: bypassed TTL and Hop Limit decrement on forwarded IPv4 (`net/ipv4/ip_forward.c`) and IPv6 (`net/ipv6/ip6_output.c`) packets (ported from e404 / Alexander Winkowski) to prevent carrier DPI tethering blocks and fix "Connected, without internet" bug on connected hotspot devices
- BPF & Netfilter Defconfig Compatibility: enabled `CONFIG_XDP_SOCKETS=y`, `CONFIG_NETFILTER_XT_TARGET_HL=y`, `CONFIG_NETFILTER_XT_TARGET_CHECKSUM=y`, and `CONFIG_IP6_NF_NAT=y` across munch defconfigs (`munch_defconfig` & `munch_stock-defconfig`) to support Tethering BPF maps (`osrtpPolicy.o`) and fix Wi-Fi sharing (STA+SAP) UDP/DHCP checksum validation
- BPF Generic Pop Header Optimization: corrected `memmove` offset and pull sequence in `bpf_skb_generic_pop()` (`net/core/filter.c`) from upstream commit 315fcbead697 to prevent packet corruption during BPF header pop
- SuSFS Kernel Panic Fix: guarded `kfree_rcu(old_bitmap, rcu)` with `if (old_bitmap)` in `susfs_set_priority_uid_filter()` and `susfs_priority_app_strings_worker()` (`fs/susfs.c`) to prevent fatal NULL pointer dereference in `__call_rcu()` during initial boot priority UID filter configuration (Issue #1, reported & suggested by @zdanysfa)
- Memory Reclaim Unevictable Page Hardening: skipped unevictable/mlocked pages (`PageUnevictable`) in `reclaim_pte_range()` (`fs/proc/task_mmu.c`) to prevent isolated count mismatch and VM assertions during Android `CachedAppOptimizer` background reclaim (Issue #1, reported & suggested by @zdanysfa)
- Display Backlight Reversion to Stock Stability: restored `sde_connector.c` to stock Qualcomm/LineageOS clean driver mapping (`mult_frac`) while keeping `qcom,mdss-dsi-bl-min-level = <1>` in DTS. This completely eliminates all slider jumping, threshold cliffs, and flickering ("redup terus terang") across all ROM frameworks (HyperOS, AOSP, ColorOS).
- Hardware-Accurate Backlight Calibration: calibrated brightness mapping to 11-bit KTZ8866 hardware DAC (2047) and added defensive clamp in dualktz8866 to prevent array out-of-bounds and driver rejection
- Fixed AnyKernel3 GPU OC vendor_boot flashing: Exported lowercase `block=vendor_boot` alongside uppercase `BLOCK` to ensure DTB partition is repacked correctly on SM8250
- Fixed recovery volume key selector: replaced fragile timeout command subshell with continuous background getevent listener to reliably detect Vol+ (OC 683 MHz) and Vol- (Stock 670 MHz) in TWRP/OrangeFox
- Added automated GPU OC trigger support: Flasher now detects `/sdcard/oc`, `/sdcard/Download/oc`, and `/tmp/oc` to automatically select 683 MHz OC + UV profile even in app-based flashers (Kernel Flasher)
- Updated Ki-Settings / Ki-Optimizer module to v1.4.0 with WebUI charging, profile, and thermal toggles
- SMB5 charging driver & Boeffla Wakelock Blocker optimizations
- Synced KernelSU / BakaSU upstream to latest main (516d3e87) with OriginOS panic prevention (vklp_smaps_rollup block) and preserved multi-manager support
- Backported Linux 5.4 PM runtime & sleep fixes: resolved force_suspend/resume refcount unbalance, device removal UAF, and wakeirq races to eliminate screen-off wake deadlocks
- Fixed scheduler PELT period truncation: upgraded period accumulation from u32 to u64 to prevent CPU load tracking freezes
- Hardened Adreno GPU (KGSL): added refcount zero bailout in vm_open and fixed repeated sparse page mapping indices to prevent game crashes (PUBG/Genshin) and texture buffer corruption
- Power Management & Deep Sleep: offloaded pm_wq to WQ_UNBOUND, synced Android wakeup_srcu, hardened sleep_time delta calculations, and fixed wakelock counter limits
- Optimized kernel workqueues: reduced pool lock contention in flush_workqueue_prep_pwqs for unbound workqueues and guarded against NULL current_pwq dereferences

## Ki-kernel v1.6.2 (ColorOS 17 Support, Dynamic Fsync & Thermal Guard Fixes) :
- Fixed screen-off / lockscreen deadlock: replaced synchronous ksys_sync() in Dynamic Fsync with asynchronous wakeup_flusher_threads() and removed wakelock contention with Android apexd/VFS
- Fixed Dynamic Thermal Guard toggle: implemented thermal_throttle_store() and made /sys/kernel/ki_profile/thermal_throttle read-write (__ATTR_RW) to allow bypassing thermal throttling for unthrottled gaming
- Fixed TCP Congestion Control switcher: enabled CONFIG_TCP_CONG_CUBIC and registered both "westwood" and "westwood-sub"
- Added ColorOS 17 oplus_display sysfs nodes for Luminous Rendering Engine
- Added ColorOS 17 oplus_hans procfs interface to fix system_server ANRs
- Added Horae thermal procfs nodes (shell-temp, horae_mode) to prevent false throttling
- Added SuperVOOC UI sysfs nodes and dynamic fast_chg_type support
- Expanded OPlus SchedAssist v3 and Frame Boost procfs interfaces
- Added OPlus Theia watchdog, GameOpt, opbootfrom, and devinfo procfs nodes
- Added OPlus charger gauge sysfs groups and battery health metrics
- Migrate anykernel lifaye to anykernel re404

## Ki-kernel v1.6.1 :
- Fixed Samsung E4 AMOLED black screen bug: permanently protected display power rails (`display_panel_vci`, `disp_vddio_vreg`, `oled_dvdd_ldo`) from being cut off at second 32 by `regulator_late_cleanup`, completely eliminating hard reboots
- Fixed AnyKernel3 Universal installer: initialized `$AKHOME` directory binding to resolve `! Kernel Image not found` abort during recovery flashing
- Added built-in fgetpriority UID priority hiding to defeat syscall-based app detection (Applist Detector/Momo)
- Accelerated display & frame sync: speed up sync_file ioctl by omitting debug names (improves SurfaceFlinger and gaming FPS)
- Optimized memory zeroing: align clear_page() to 16 bytes for Cortex-A77/A55 cacheline throughput
- Silenced smcinvoke false error logspam during suspend/resume
- Fixed ARM PMU and devfreq memlat random reboots and qspinlock lockups
- Restored stable v1.5 display KMS commit order and touch synchronization
- Restored stable v1.5 kswapd LITTLE cluster affinity (CPUs 0-3) and watermark scale factor (improves gaming stability and prevents aggressive LMK oom_reaper)

## Ki-kernel v1.6 :
- Fix Selinux
- Updated ADIOS I/O scheduler v3.3.0
- Added AnyKernel GPU selector 
- Added YukiSU manager support and YukiSU feature
- Synced SuSFS v2.3.0 upstream changes and fixed UID filter UAF race conditions
- Added SuSFS multi-user and dual apps UID support with no-atime parsing
- Fixed Dynamic Fsync screen-off suspend hangs
- Fixed Binder page allocation failures and improved kswapd sleep reclaim
- Fixed cpufreq policy rwsem suspend deadlocks
- Fixed cpu-boost touch workqueue deadlocks and reduced policy lock contention
- Fixed Wakelock Blocker PCIe Wi-Fi drops and USB/ADB disconnects
- Fixed Ki-Profile screen-off workqueue loops and deep sleep wakeups

## Ki-kernel v1.5 :
- Updated BakaSU and ReSukiSU to UAPI v6
- Added full FinaSU Manager support
- Added 32-bit userspace KernelSU compatibility
- Added kernel-side per-app network isolation
- Synced SuSFS v2.3.0 inline hooks and bugfixes
- Added automated SuSFS early-boot spoofing
- Added SuSFS priority UID filter protection
- Updated NoMount kernel integration to v2.2.0
- Fixed Kernel Manager sysfs SELinux denials
- Ported hardware AOSP DC Dimming support
- Fixed display sysfs SELinux permission issues
- Improved SDE KCAL hardware color calibration
- Fixed Force Fast Charge on wall adapters
- Restored full 67W PPS turbo charging
- Fixed random thermal shutdowns while charging
- Fixed duplicate charger sysfs registration warnings
- Tuned Battery, Balanced, and Performance profiles
- Tuned CPU scheduling and gaming frame pacing
- Fixed screen-off wakeup freezes and AOD issues
- Hardened Ki-Profile sysfs and worker stability
- Fixed Adreno GPU freezes and Sleep of Death
- Fixed MGLRU lock contention and app freezes
- Set BFQ and Maple as default I/O schedulers
- Improved BBRv3 network congestion control
- Fixed USB tethering and DHCP connection issues
- Improved Droidspaces and Linux container support
- Added OPlus Frame Boost and SchedAssist support
- Fixed OPlus port netlink and driver issues
- Improved AnyKernel3 universal Multi-ROM detection

## Ki-kernel v1.4.1:
• Backported modern eBPF features for Android 16 and 17
• Cherry-picked selected commits from re-noroi/FD and e404
• Fixed BPF loader bootloops on newer Android ROMs
• Added dynamic kernel version reporting for BPF loaders
• Added OPlus subsystem support for ColorOS, OxygenOS and RealmeUI ports
• Added OPlus NANDswap and charging subsystem compatibility
• Improved AnyKernel3 ROM detection for AOSP, MIUI, HyperOS and OPlus ports
• Fixed Sleep of Death and screen-off hangs
• Fixed CPU governor switch kernel panics and use-after-free crashes
• Restored 300MHz CPU idle frequency
• Tuned schedutil, WALT, CPU migration and hispeed thresholds
• Added per-cluster CPU frequency controls in Ki-Profile
• Improved Battery Saver and Balanced profile tuning
• Improved screen-off battery life and dynamic refresh rate handling
• Added thermal auto-guard with temperature-based protection
• Improved CPU and GPU stability under heavy loads
• Improved bypass charging safety and charger disconnect handling
• Fixed fast charging cutoff, thermal limits and charging state handling
• Set Force Fast Charge and Screen-On Fast Charge to OFF by default
• Added non-root controls for Ki-Profile and charging features
• Expanded KernelSU manager compatibility
• Fixed KernelSU root detection and restored SuSFS inline hooks
• Added Boeffla Wakelock Blocker with a configurable toggle
• Fixed background music playback stopping when the screen is off
• Improved memory management with MGLRU and LMKD tuning
• Fixed excessive kswapd activity under heavy ZRAM usage
• Improved app retention and reduced unnecessary background app kills
• Added Adreno 650 GPU idle frequency reporting
• Retained Adreno 650 GPU undervolt and overclock profiles
• Fixed DC Dimming support on AOSP and compatible AMOLED panels
• Fixed Night Light and LiveDisplay on supported custom ROMs
• Added KCAL hardware color calibration support
• Added Dynamic Fsync control
• Added ADIOS multi-queue I/O scheduler
• Added NoMount kernel integration
• Added native Linux container support for Droidspaces, LXC and Docker
• Added BINFMT_MISC binary emulation support
• Backported Futex2 multi-wait support
• Added EROFS compression and security xattr support
• Improved block I/O and asynchronous bio submission
• Improved CPU locking and memory mapping performance
• Tuned real-time timer handling for SurfaceFlinger, audio and GPU workers
• Fixed touchscreen sleep errors and display-related issues
• Fixed IR blaster transmission issues
• Improved boot image ramdisk decompression and AOSP boot compatibility
• Added a lockless per-CPU Blake2s random number generator
• Updated Clang ThinLTO and fixed vendor module loading
• Added multi-stage thermal, charging and screen-off profile handling
• Improved container networking and systemd cgroup compatibility

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

