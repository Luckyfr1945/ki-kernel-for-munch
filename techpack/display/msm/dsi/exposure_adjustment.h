/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * An exposure adjustment driver based on Qcom DSPP for OLED devices
 *
 * Copyright (C) 2012-2014, The Linux Foundation. All rights reserved.
 * Copyright (C) Sony Mobile Communications Inc. All rights reserved.
 * Copyright (C) 2014-2018, AngeloGioacchino Del Regno <kholk11@gmail.com>
 * Copyright (C) 2018, Devries <therkduan@gmail.com>
 * Copyright (C) 2026, Muhammad Guntur <mochtur@gmail.com>
 */

#ifndef EXPOSURE_ADJUSTMENT_H
#define EXPOSURE_ADJUSTMENT_H

#include <linux/types.h>

struct sde_crtc;
struct sde_hw_cp_cfg;
struct drm_msm_pcc;

/**
 * Device-specific parameters
 * @ELVSS_OFF_THRESHOLD: Minimum backlight threshold for disable smart elvss
 * @EXPOSURE_ADJUSTMENT_MIN: Minimum available PCC coefficient for OLED panel
 * @EXPOSURE_ADJUSTMENT_MAX: Q15 unity (32768)
 */
#define ELVSS_OFF_THRESHOLD        440
#define EXPOSURE_ADJUSTMENT_MIN    256
#define EXPOSURE_ADJUSTMENT_MAX    32768

void ea_panel_mode_ctrl(bool enable);
bool ea_panel_is_enabled(void);
bool ea_panel_is_attenuating(void);
void ea_panel_notify_dirty(void);
bool ea_panel_consume_dirty(void);
bool ea_panel_check_fod_changed(bool fod_hbm, bool kcal_active);
u32 ea_panel_calc_backlight(u32 bl_lvl, u32 dc_threshold);
u32 ea_panel_get_hw_backlight(u32 bl_lvl, u32 dc_threshold);
void ea_panel_modify_pcc(struct sde_crtc *sde_crtc,
			 struct sde_hw_cp_cfg *hw_cfg,
			 struct drm_msm_pcc *scratch_pcc);

#endif /* EXPOSURE_ADJUSTMENT_H */

