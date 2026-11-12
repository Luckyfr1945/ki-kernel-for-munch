// SPDX-License-Identifier: GPL-2.0-only
/*
 * An exposure adjustment driver based on Qcom DSPP for OLED devices
 *
 * Copyright (C) 2012-2014, The Linux Foundation. All rights reserved.
 * Copyright (C) Sony Mobile Communications Inc. All rights reserved.
 * Copyright (C) 2014-2018, AngeloGioacchino Del Regno <kholk11@gmail.com>
 * Copyright (C) 2018, Devries <therkduan@gmail.com>
 * Copyright (C) 2026, Muhammad Guntur <mochtur@gmail.com>
 */

#include <linux/bitops.h>
#include <linux/kernel.h>
#include <linux/math64.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <uapi/drm/msm_drm_pp.h>

#include "../sde/sde_connector.h"
#include "../sde/sde_crtc.h"
#include "../sde/sde_hw_dspp.h"
#include "dsi_mi_feature.h"
#include "exposure_adjustment.h"

static DEFINE_SPINLOCK(ea_lock);
static bool pcc_backlight_enable;
static bool pcc_attenuation_active;
static bool ea_dirty;
static bool ea_last_fod_hbm;
static u32 ea_coeff = EXPOSURE_ADJUSTMENT_MAX;

static inline u32 ea_scale_coeff(u32 val, u32 coeff)
{
	bool masked_18 = ((val & ~0x3FFFFU) == 0) && (val & 0x20000U);
	s32 s = masked_18 ? sign_extend32(val, 17) : (s32)val;
	s64 scaled = div_s64((s64)s * (s64)coeff, EXPOSURE_ADJUSTMENT_MAX);

	return masked_18 ? ((u32)scaled & 0x3FFFFU) : (u32)(s32)scaled;
}

static void ea_scale_pcc_plane(struct drm_msm_pcc_coeff *plane, u32 coeff)
{
	plane->c = ea_scale_coeff(plane->c, coeff);
	plane->r = ea_scale_coeff(plane->r, coeff);
	plane->g = ea_scale_coeff(plane->g, coeff);
	plane->b = ea_scale_coeff(plane->b, coeff);
	plane->rg = ea_scale_coeff(plane->rg, coeff);
	plane->gb = ea_scale_coeff(plane->gb, coeff);
	plane->rb = ea_scale_coeff(plane->rb, coeff);
	plane->rgb = ea_scale_coeff(plane->rgb, coeff);
}

bool ea_panel_is_enabled(void)
{
	unsigned long flags;
	bool enabled;

	spin_lock_irqsave(&ea_lock, flags);
	enabled = pcc_backlight_enable;
	spin_unlock_irqrestore(&ea_lock, flags);

	return enabled;
}

bool ea_panel_is_attenuating(void)
{
	unsigned long flags;
	bool active;

	spin_lock_irqsave(&ea_lock, flags);
	active = pcc_backlight_enable && pcc_attenuation_active &&
		 ea_coeff < EXPOSURE_ADJUSTMENT_MAX;
	spin_unlock_irqrestore(&ea_lock, flags);

	return active;
}

void ea_panel_notify_dirty(void)
{
	unsigned long flags;

	spin_lock_irqsave(&ea_lock, flags);
	if (pcc_backlight_enable && pcc_attenuation_active &&
	    ea_coeff < EXPOSURE_ADJUSTMENT_MAX)
		ea_dirty = true;
	spin_unlock_irqrestore(&ea_lock, flags);
}

bool ea_panel_consume_dirty(void)
{
	unsigned long flags;
	bool dirty;

	spin_lock_irqsave(&ea_lock, flags);
	dirty = ea_dirty;
	ea_dirty = false;
	spin_unlock_irqrestore(&ea_lock, flags);

	return dirty;
}

bool ea_panel_check_fod_changed(bool fod_hbm)
{
	unsigned long flags;
	bool changed = false;

	spin_lock_irqsave(&ea_lock, flags);
	if (ea_last_fod_hbm != fod_hbm) {
		ea_last_fod_hbm = fod_hbm;
		if (pcc_backlight_enable && pcc_attenuation_active &&
		    ea_coeff < EXPOSURE_ADJUSTMENT_MAX) {
			ea_dirty = true;
			changed = true;
		}
	}
	spin_unlock_irqrestore(&ea_lock, flags);

	return changed;
}

void ea_panel_mode_ctrl(bool enable)
{
	unsigned long flags;

	spin_lock_irqsave(&ea_lock, flags);
	if (pcc_backlight_enable != enable) {
		pcc_backlight_enable = enable;
		if (!enable) {
			pcc_attenuation_active = false;
			ea_coeff = EXPOSURE_ADJUSTMENT_MAX;
		}
		ea_dirty = true;
		pr_info("ea_panel: mode changed to %d\n", enable);
	}
	spin_unlock_irqrestore(&ea_lock, flags);
}

u32 ea_panel_calc_backlight(u32 bl_lvl)
{
	unsigned long flags;
	u32 ret_lvl = bl_lvl;

	spin_lock_irqsave(&ea_lock, flags);
	if (pcc_backlight_enable && bl_lvl != 0 && bl_lvl < ELVSS_OFF_THRESHOLD) {
		u32 coeff = EXPOSURE_ADJUSTMENT_MIN +
			DIV_ROUND_CLOSEST(bl_lvl * (EXPOSURE_ADJUSTMENT_MAX -
			EXPOSURE_ADJUSTMENT_MIN), ELVSS_OFF_THRESHOLD);

		if (!pcc_attenuation_active || ea_coeff != coeff) {
			ea_coeff = coeff;
			pcc_attenuation_active = true;
			ea_dirty = true;
		}
		ret_lvl = ELVSS_OFF_THRESHOLD;
	} else {
		if (pcc_attenuation_active ||
		    ea_coeff != EXPOSURE_ADJUSTMENT_MAX) {
			pcc_attenuation_active = false;
			ea_coeff = EXPOSURE_ADJUSTMENT_MAX;
			ea_dirty = true;
		}
	}
	spin_unlock_irqrestore(&ea_lock, flags);

	return ret_lvl;
}

void ea_panel_modify_pcc(struct sde_crtc *sde_crtc,
			 struct sde_hw_cp_cfg *hw_cfg,
			 struct drm_msm_pcc *scratch_pcc)
{
	unsigned long flags;
	u32 coeff;
	bool active;

	if (!sde_crtc || !hw_cfg || !scratch_pcc)
		return;

	if (sde_crtc->mi_dimlayer_type & MI_DIMLAYER_FOD_HBM_OVERLAY)
		return;

	spin_lock_irqsave(&ea_lock, flags);
	active = pcc_backlight_enable && pcc_attenuation_active &&
		 ea_coeff < EXPOSURE_ADJUSTMENT_MAX;
	coeff = ea_coeff;
	spin_unlock_irqrestore(&ea_lock, flags);

	if (!active)
		return;

	if (hw_cfg->payload && hw_cfg->len == sizeof(*scratch_pcc)) {
		if (hw_cfg->payload != scratch_pcc)
			memcpy(scratch_pcc, hw_cfg->payload,
			       sizeof(*scratch_pcc));

		ea_scale_pcc_plane(&scratch_pcc->r, coeff);
		ea_scale_pcc_plane(&scratch_pcc->g, coeff);
		ea_scale_pcc_plane(&scratch_pcc->b, coeff);
		scratch_pcc->r_rr = ea_scale_coeff(scratch_pcc->r_rr, coeff);
		scratch_pcc->r_gg = ea_scale_coeff(scratch_pcc->r_gg, coeff);
		scratch_pcc->r_bb = ea_scale_coeff(scratch_pcc->r_bb, coeff);
		scratch_pcc->g_rr = ea_scale_coeff(scratch_pcc->g_rr, coeff);
		scratch_pcc->g_gg = ea_scale_coeff(scratch_pcc->g_gg, coeff);
		scratch_pcc->g_bb = ea_scale_coeff(scratch_pcc->g_bb, coeff);
		scratch_pcc->b_rr = ea_scale_coeff(scratch_pcc->b_rr, coeff);
		scratch_pcc->b_gg = ea_scale_coeff(scratch_pcc->b_gg, coeff);
		scratch_pcc->b_bb = ea_scale_coeff(scratch_pcc->b_bb, coeff);
	} else {
		memset(scratch_pcc, 0, sizeof(*scratch_pcc));
		scratch_pcc->r.r = coeff;
		scratch_pcc->g.g = coeff;
		scratch_pcc->b.b = coeff;
	}

	hw_cfg->payload = scratch_pcc;
	hw_cfg->len = sizeof(*scratch_pcc);
	hw_cfg->payload_clear = NULL;
}

