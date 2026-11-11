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

struct dsi_panel;

/**
 * Device-specific parameters
 * @ELVSS_OFF_THRESHOLD: Minimum backlight threshold for disable smart elvss
 * @EXPOSURE_ADJUSTMENT_MIN: Minimum available PCC coefficient for OLED panel
 * @EXPOSURE_ADJUSTMENT_MAX: Q15 unity (32768)
 */
#define ELVSS_OFF_THRESHOLD        500
#define EXPOSURE_ADJUSTMENT_MIN    2048
#define EXPOSURE_ADJUSTMENT_MAX    32768

void ea_panel_mode_ctrl(struct dsi_panel *panel, bool enable);
bool ea_panel_is_enabled(void);
u32 ea_panel_calc_backlight(u32 bl_lvl);

#endif /* EXPOSURE_ADJUSTMENT_H */

