// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026, The Linux Foundation. All rights reserved.
 * KCAL - Advanced Color Control for Qualcomm SDE DSPP
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/bitops.h>
#include <linux/device.h>
#include <linux/platform_device.h>
#include <linux/math64.h>
#include <linux/mutex.h>
#include <linux/string.h>
#include <uapi/drm/msm_drm_pp.h>

#include "sde_kms.h"
#include "sde_crtc.h"
#include "sde_hw_dspp.h"
#include "sde_hw_ctl.h"
#include "sde_hw_lm.h"
#include "sde_hw_mdss.h"
#include "sde_connector.h"
#include "sde_kcal.h"
#include "exposure_adjustment.h"

#define KCAL_UNITY_GAIN 32768U

static DEFINE_MUTEX(kcal_mutex);

static bool kcal_enabled;
static bool kcal_dirty;
static bool kcal_restored = true;

static u32 kcal_red = 256;
static u32 kcal_green = 256;
static u32 kcal_blue = 256;
static u32 kcal_min = 35;
static u32 kcal_sat = 256;
static u32 kcal_val = 256;
static u32 kcal_cont = 256;
static u32 kcal_hue;
static u32 kcal_invert;

static struct drm_msm_pcc kcal_pcc_cfg;

static inline struct sde_kms *kcal_get_kms(struct drm_crtc *crtc)
{
	struct msm_drm_private *priv;

	if (!crtc || !crtc->dev || !crtc->dev->dev_private)
		return NULL;
	priv = crtc->dev->dev_private;
	if (!priv || !priv->kms)
		return NULL;
	return to_sde_kms(priv->kms);
}

static inline s32 kcal_decode_coeff(u32 val)
{
	if ((val & ~0x3FFFFU) == 0 && (val & 0x20000U))
		return sign_extend32(val, 17);
	return (s32)val;
}

static inline u32 kcal_encode_coeff(s64 val)
{
	val = clamp_t(s64, val, -131072, 131071);
	return (u32)val & 0x3FFFFU;
}

/* Returns sin(2*pi * step / 1536) scaled by KCAL_UNITY_GAIN (32768) */
static s32 kcal_sin_q15(u32 step)
{
	u32 a = step % 1536;
	s32 sign = 1;
	s64 p, num, den;

	if (a >= 768) {
		a -= 768;
		sign = -1;
	}
	p = (s64)a * (768 - a);
	num = (s64)KCAL_UNITY_GAIN * 4 * p;
	den = 737280 - p;
	return sign * (s32)div64_s64(num + (den >> 1), den);
}

static s32 kcal_cos_q15(u32 step)
{
	return kcal_sin_q15(step + 384);
}

static void kcal_recompute_pcc_locked(void)
{
	u32 scale_r, scale_g, scale_b;
	s32 s, c_val, c_cont;
	/* Rec. 709 luminance weights scaled by KCAL_UNITY_GAIN */
	u32 pr = 9798, pg = 19235, pb = 3735;
	s32 m[3][3];
	s32 h[3][3];
	int i, j;

	u32 r = clamp_t(u32, kcal_red, kcal_min, 256);
	u32 g = clamp_t(u32, kcal_green, kcal_min, 256);
	u32 b = clamp_t(u32, kcal_blue, kcal_min, 256);
	u32 sat = clamp_t(u32, kcal_sat, 128, 383);
	u32 val = clamp_t(u32, kcal_val, 128, 383);
	u32 cont = clamp_t(u32, kcal_cont, 128, 383);
	u32 hue = kcal_hue % 1536;

	memset(&kcal_pcc_cfg, 0, sizeof(kcal_pcc_cfg));

	/* Scale RGB (0..256 -> 0..32768) */
	scale_r = (r * KCAL_UNITY_GAIN) / 256;
	scale_g = (g * KCAL_UNITY_GAIN) / 256;
	scale_b = (b * KCAL_UNITY_GAIN) / 256;

	if (sat == 256) {
		m[0][0] = KCAL_UNITY_GAIN; m[0][1] = 0; m[0][2] = 0;
		m[1][0] = 0; m[1][1] = KCAL_UNITY_GAIN; m[1][2] = 0;
		m[2][0] = 0; m[2][1] = 0; m[2][2] = KCAL_UNITY_GAIN;
	} else {
		/* 128: Grayscale (0.0), 256: Normal (1.0), 383: Boost (~2.0) */
		s = (s32)sat - 128;
		m[0][0] = ((128 - s) * (s32)pr + s * (s32)KCAL_UNITY_GAIN) / 128;
		m[0][1] = ((128 - s) * (s32)pg) / 128;
		m[0][2] = ((128 - s) * (s32)pb) / 128;

		m[1][0] = ((128 - s) * (s32)pr) / 128;
		m[1][1] = ((128 - s) * (s32)pg + s * (s32)KCAL_UNITY_GAIN) / 128;
		m[1][2] = ((128 - s) * (s32)pb) / 128;

		m[2][0] = ((128 - s) * (s32)pr) / 128;
		m[2][1] = ((128 - s) * (s32)pg) / 128;
		m[2][2] = ((128 - s) * (s32)pb + s * (s32)KCAL_UNITY_GAIN) / 128;
	}

	if (hue != 0) {
		s32 c = kcal_cos_q15(hue);
		s32 sn = kcal_sin_q15(hue);
		s32 one_minus_c_3 = (s32)div_s64((s64)KCAL_UNITY_GAIN - c, 3);
		s32 s_sqrt3 = (s32)div_s64((s64)sn * 18919, KCAL_UNITY_GAIN);
		s32 diag = c + one_minus_c_3;
		s32 pos_off = one_minus_c_3 + s_sqrt3;
		s32 neg_off = one_minus_c_3 - s_sqrt3;
		s32 rot[3][3] = {
			{ diag, neg_off, pos_off },
			{ pos_off, diag, neg_off },
			{ neg_off, pos_off, diag },
		};

		for (i = 0; i < 3; i++) {
			for (j = 0; j < 3; j++) {
				h[i][j] = (s32)div_s64(
					(s64)rot[i][0] * m[0][j] +
					(s64)rot[i][1] * m[1][j] +
					(s64)rot[i][2] * m[2][j],
					KCAL_UNITY_GAIN);
			}
		}
		memcpy(m, h, sizeof(m));
	}

	/* Apply per-channel RGB gain and contrast */
	c_cont = (s32)cont;
	for (i = 0; i < 3; i++) {
		s32 scale = (i == 0) ? (s32)scale_r : ((i == 1) ? (s32)scale_g : (s32)scale_b);

		for (j = 0; j < 3; j++) {
			s64 v = div_s64((s64)m[i][j] * scale, KCAL_UNITY_GAIN);

			if (cont != 256)
				v = div_s64(v * c_cont, 256);
			h[i][j] = (s32)clamp_t(s64, v, -131072, 131071);
		}
	}

	/* Value / Brightness offset (128..383, 256 is 0) */
	c_val = 0;
	if (val != 256) {
		c_val = (((s32)val - 256) * (s32)KCAL_UNITY_GAIN) / 256;
		c_val = clamp_t(s32, c_val, -32768, 32767);
	}

	if (kcal_invert) {
		for (i = 0; i < 3; i++)
			for (j = 0; j < 3; j++)
				h[i][j] = -h[i][j];
		c_val = clamp_t(s32, c_val + 32767, -32768, 32767);
	}

	kcal_pcc_cfg.r.r = kcal_encode_coeff(h[0][0]);
	kcal_pcc_cfg.r.g = kcal_encode_coeff(h[0][1]);
	kcal_pcc_cfg.r.b = kcal_encode_coeff(h[0][2]);

	kcal_pcc_cfg.g.r = kcal_encode_coeff(h[1][0]);
	kcal_pcc_cfg.g.g = kcal_encode_coeff(h[1][1]);
	kcal_pcc_cfg.g.b = kcal_encode_coeff(h[1][2]);

	kcal_pcc_cfg.b.r = kcal_encode_coeff(h[2][0]);
	kcal_pcc_cfg.b.g = kcal_encode_coeff(h[2][1]);
	kcal_pcc_cfg.b.b = kcal_encode_coeff(h[2][2]);

	kcal_pcc_cfg.r.c = kcal_encode_coeff(c_val);
	kcal_pcc_cfg.g.c = kcal_encode_coeff(c_val);
	kcal_pcc_cfg.b.c = kcal_encode_coeff(c_val);
}

void sde_kcal_notify_dirty(void)
{
	mutex_lock(&kcal_mutex);
	if (kcal_enabled)
		kcal_dirty = true;
	mutex_unlock(&kcal_mutex);
}

void sde_kcal_apply(struct drm_crtc *crtc)
{
	struct sde_crtc *sde_crtc;
	struct sde_hw_cp_cfg hw_cfg;
	struct drm_msm_pcc identity_pcc;
	struct drm_msm_pcc ea_pcc;
	struct sde_kms *kms;
	struct sde_mdss_cfg *catalog;
	u32 i, num_mixers;
	bool apply_identity = false;

	if (!crtc)
		return;

	sde_crtc = to_sde_crtc(crtc);
	if (!sde_crtc || !sde_crtc->enabled)
		return;

	mutex_lock(&kcal_mutex);

	/* Safety Guard 1: Never alter display while FOD fingerprint illumination is active */
	if (sde_crtc->mi_dimlayer_type & MI_DIMLAYER_FOD_HBM_OVERLAY) {
		if (kcal_enabled)
			kcal_dirty = true;
		mutex_unlock(&kcal_mutex);
		return;
	}

	/* Safety Guard 2: If disabled, only restore identity once if needed, then skip */
	if (!kcal_enabled) {
		if (kcal_restored) {
			mutex_unlock(&kcal_mutex);
			return;
		}
		apply_identity = true;
	} else if (!kcal_dirty) {
		/* KCAL is enabled but values have not changed: do not overwrite native Android color/night-light */
		mutex_unlock(&kcal_mutex);
		return;
	}

	kms = kcal_get_kms(crtc);
	if (!kms || !kms->catalog) {
		mutex_unlock(&kcal_mutex);
		return;
	}
	catalog = kms->catalog;

	num_mixers = sde_crtc->num_mixers;
	if (!num_mixers) {
		mutex_unlock(&kcal_mutex);
		return;
	}

	memset(&hw_cfg, 0, sizeof(hw_cfg));
	hw_cfg.len = sizeof(struct drm_msm_pcc);
	hw_cfg.num_of_mixers = num_mixers;
	hw_cfg.broadcast_disabled = catalog->dma_cfg.broadcast_disabled;

	for (i = 0; i < num_mixers; i++) {
		if (i >= DSPP_MAX)
			break;
		hw_cfg.dspp[i] = sde_crtc->mixers[i].hw_dspp;
	}

	if (apply_identity) {
		memset(&identity_pcc, 0, sizeof(identity_pcc));
		identity_pcc.r.r = KCAL_UNITY_GAIN;
		identity_pcc.g.g = KCAL_UNITY_GAIN;
		identity_pcc.b.b = KCAL_UNITY_GAIN;
		hw_cfg.payload = &identity_pcc;
	} else {
		hw_cfg.payload = &kcal_pcc_cfg;
	}

	ea_panel_modify_pcc(sde_crtc, &hw_cfg, &ea_pcc);

	for (i = 0; i < num_mixers; i++) {
		struct sde_hw_dspp *hw_dspp = sde_crtc->mixers[i].hw_dspp;
		struct sde_hw_ctl *ctl = sde_crtc->mixers[i].hw_ctl;
		struct sde_hw_mixer *hw_lm = sde_crtc->mixers[i].hw_lm;

		if (!hw_dspp || !hw_dspp->ops.setup_pcc || !ctl || !hw_lm)
			continue;

		hw_cfg.ctl = ctl;
		hw_cfg.mixer_info = hw_lm;
		hw_cfg.displayh = num_mixers * hw_lm->cfg.out_width;
		hw_cfg.displayv = hw_lm->cfg.out_height;
		hw_cfg.mi_dimlayer_type = sde_crtc->mi_dimlayer_type;

		hw_dspp->ops.setup_pcc(hw_dspp, &hw_cfg);

		if (ctl->ops.update_bitmask_dspp)
			ctl->ops.update_bitmask_dspp(ctl, hw_dspp->idx, 1);
	}

	if (apply_identity) {
		kcal_restored = true;
		pr_info("[KCAL] reset to stock identity matrix\n");
	} else if (kcal_dirty) {
		kcal_restored = false;
		pr_info_ratelimited("[KCAL] applied: R=%u G=%u B=%u sat=%u val=%u cont=%u\n",
			kcal_red, kcal_green, kcal_blue, kcal_sat, kcal_val, kcal_cont);
	}

	kcal_dirty = false;
	mutex_unlock(&kcal_mutex);
}

void sde_kcal_modify_pcc(struct sde_crtc *sde_crtc, struct sde_hw_cp_cfg *hw_cfg)
{
	struct drm_msm_pcc *pcc;

	if (!sde_crtc || !hw_cfg)
		return;

	/* Never alter display during FOD fingerprint illumination */
	if (sde_crtc->mi_dimlayer_type & MI_DIMLAYER_FOD_HBM_OVERLAY)
		return;

	mutex_lock(&kcal_mutex);
	if (!kcal_enabled) {
		mutex_unlock(&kcal_mutex);
		return;
	}

	/*
	 * When KCAL is enabled, blend/scale with the incoming Android color matrix
	 * (e.g. Night Light / LiveDisplay) instead of dropping it.
	 */
	if (hw_cfg->payload) {
		struct drm_msm_pcc in_pcc;
		s32 kr0 = kcal_decode_coeff(kcal_pcc_cfg.r.r);
		s32 kr1 = kcal_decode_coeff(kcal_pcc_cfg.r.g);
		s32 kr2 = kcal_decode_coeff(kcal_pcc_cfg.r.b);
		s32 kg0 = kcal_decode_coeff(kcal_pcc_cfg.g.r);
		s32 kg1 = kcal_decode_coeff(kcal_pcc_cfg.g.g);
		s32 kg2 = kcal_decode_coeff(kcal_pcc_cfg.g.b);
		s32 kb0 = kcal_decode_coeff(kcal_pcc_cfg.b.r);
		s32 kb1 = kcal_decode_coeff(kcal_pcc_cfg.b.g);
		s32 kb2 = kcal_decode_coeff(kcal_pcc_cfg.b.b);
		s32 ir0, ir1, ir2, ig0, ig1, ig2, ib0, ib1, ib2;

		pcc = (struct drm_msm_pcc *)hw_cfg->payload;
		in_pcc = *pcc;
		ir0 = kcal_decode_coeff(in_pcc.r.r);
		ir1 = kcal_decode_coeff(in_pcc.r.g);
		ir2 = kcal_decode_coeff(in_pcc.r.b);
		ig0 = kcal_decode_coeff(in_pcc.g.r);
		ig1 = kcal_decode_coeff(in_pcc.g.g);
		ig2 = kcal_decode_coeff(in_pcc.g.b);
		ib0 = kcal_decode_coeff(in_pcc.b.r);
		ib1 = kcal_decode_coeff(in_pcc.b.g);
		ib2 = kcal_decode_coeff(in_pcc.b.b);

		pcc->r.r = kcal_encode_coeff(div_s64((s64)kr0 * ir0 + (s64)kr1 * ig0 + (s64)kr2 * ib0, KCAL_UNITY_GAIN));
		pcc->r.g = kcal_encode_coeff(div_s64((s64)kr0 * ir1 + (s64)kr1 * ig1 + (s64)kr2 * ib1, KCAL_UNITY_GAIN));
		pcc->r.b = kcal_encode_coeff(div_s64((s64)kr0 * ir2 + (s64)kr1 * ig2 + (s64)kr2 * ib2, KCAL_UNITY_GAIN));

		pcc->g.r = kcal_encode_coeff(div_s64((s64)kg0 * ir0 + (s64)kg1 * ig0 + (s64)kg2 * ib0, KCAL_UNITY_GAIN));
		pcc->g.g = kcal_encode_coeff(div_s64((s64)kg0 * ir1 + (s64)kg1 * ig1 + (s64)kg2 * ib1, KCAL_UNITY_GAIN));
		pcc->g.b = kcal_encode_coeff(div_s64((s64)kg0 * ir2 + (s64)kg1 * ig2 + (s64)kg2 * ib2, KCAL_UNITY_GAIN));

		pcc->b.r = kcal_encode_coeff(div_s64((s64)kb0 * ir0 + (s64)kb1 * ig0 + (s64)kb2 * ib0, KCAL_UNITY_GAIN));
		pcc->b.g = kcal_encode_coeff(div_s64((s64)kb0 * ir1 + (s64)kb1 * ig1 + (s64)kb2 * ib1, KCAL_UNITY_GAIN));
		pcc->b.b = kcal_encode_coeff(div_s64((s64)kb0 * ir2 + (s64)kb1 * ig2 + (s64)kb2 * ib2, KCAL_UNITY_GAIN));

		pcc->r.c = kcal_encode_coeff(clamp_t(s64, (s64)kcal_decode_coeff(in_pcc.r.c) + kcal_decode_coeff(kcal_pcc_cfg.r.c), -32768, 32767));
		pcc->g.c = kcal_encode_coeff(clamp_t(s64, (s64)kcal_decode_coeff(in_pcc.g.c) + kcal_decode_coeff(kcal_pcc_cfg.g.c), -32768, 32767));
		pcc->b.c = kcal_encode_coeff(clamp_t(s64, (s64)kcal_decode_coeff(in_pcc.b.c) + kcal_decode_coeff(kcal_pcc_cfg.b.c), -32768, 32767));
	} else {
		hw_cfg->payload = &kcal_pcc_cfg;
		hw_cfg->len = sizeof(kcal_pcc_cfg);
	}
	hw_cfg->payload_clear = NULL;
	mutex_unlock(&kcal_mutex);
}

/* Sysfs interface matching standard KCAL apps */
static ssize_t kcal_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u %u %u\n", kcal_red, kcal_green, kcal_blue);
}

static ssize_t kcal_store(struct device *dev, struct device_attribute *attr, const char *buf, size_t count)
{
	u32 r, g, b;

	if (sscanf(buf, "%u %u %u", &r, &g, &b) != 3)
		return -EINVAL;

	mutex_lock(&kcal_mutex);
	kcal_red = clamp_t(u32, r, kcal_min, 256);
	kcal_green = clamp_t(u32, g, kcal_min, 256);
	kcal_blue = clamp_t(u32, b, kcal_min, 256);
	kcal_recompute_pcc_locked();
	kcal_dirty = true;
	kcal_enabled = true;
	kcal_restored = false;
	mutex_unlock(&kcal_mutex);

	return count;
}
static DEVICE_ATTR_RW(kcal);

static ssize_t kcal_enable_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", kcal_enabled ? 1 : 0);
}

static ssize_t kcal_enable_store(struct device *dev, struct device_attribute *attr, const char *buf, size_t count)
{
	bool enable;

	if (strtobool(buf, &enable) < 0) {
		u32 val;
		if (kstrtou32(buf, 0, &val))
			return -EINVAL;
		enable = (val != 0);
	}

	mutex_lock(&kcal_mutex);
	if (kcal_enabled != enable) {
		kcal_enabled = enable;
		if (kcal_enabled) {
			kcal_recompute_pcc_locked();
			kcal_dirty = true;
			kcal_restored = false;
		} else {
			kcal_dirty = true;
			kcal_restored = false;
		}
	}
	mutex_unlock(&kcal_mutex);

	return count;
}
static DEVICE_ATTR_RW(kcal_enable);

static ssize_t kcal_min_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", kcal_min);
}

static ssize_t kcal_min_store(struct device *dev, struct device_attribute *attr, const char *buf, size_t count)
{
	u32 val;

	if (kstrtou32(buf, 0, &val))
		return -EINVAL;

	mutex_lock(&kcal_mutex);
	kcal_min = clamp_t(u32, val, 0, 256);
	kcal_recompute_pcc_locked();
	if (kcal_enabled)
		kcal_dirty = true;
	mutex_unlock(&kcal_mutex);

	return count;
}
static DEVICE_ATTR_RW(kcal_min);

static ssize_t kcal_sat_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", kcal_sat);
}

static ssize_t kcal_sat_store(struct device *dev, struct device_attribute *attr, const char *buf, size_t count)
{
	u32 val;

	if (kstrtou32(buf, 0, &val))
		return -EINVAL;

	mutex_lock(&kcal_mutex);
	kcal_sat = clamp_t(u32, val, 128, 383);
	kcal_recompute_pcc_locked();
	kcal_dirty = true;
	kcal_enabled = true;
	kcal_restored = false;
	mutex_unlock(&kcal_mutex);

	return count;
}
static DEVICE_ATTR_RW(kcal_sat);

static ssize_t kcal_val_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", kcal_val);
}

static ssize_t kcal_val_store(struct device *dev, struct device_attribute *attr, const char *buf, size_t count)
{
	u32 val;

	if (kstrtou32(buf, 0, &val))
		return -EINVAL;

	mutex_lock(&kcal_mutex);
	kcal_val = clamp_t(u32, val, 128, 383);
	kcal_recompute_pcc_locked();
	kcal_dirty = true;
	kcal_enabled = true;
	kcal_restored = false;
	mutex_unlock(&kcal_mutex);

	return count;
}
static DEVICE_ATTR_RW(kcal_val);

static ssize_t kcal_cont_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", kcal_cont);
}

static ssize_t kcal_cont_store(struct device *dev, struct device_attribute *attr, const char *buf, size_t count)
{
	u32 val;

	if (kstrtou32(buf, 0, &val))
		return -EINVAL;

	mutex_lock(&kcal_mutex);
	kcal_cont = clamp_t(u32, val, 128, 383);
	kcal_recompute_pcc_locked();
	kcal_dirty = true;
	kcal_enabled = true;
	kcal_restored = false;
	mutex_unlock(&kcal_mutex);

	return count;
}
static DEVICE_ATTR_RW(kcal_cont);

static ssize_t kcal_hue_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", kcal_hue);
}

static ssize_t kcal_hue_store(struct device *dev, struct device_attribute *attr, const char *buf, size_t count)
{
	u32 val;

	if (kstrtou32(buf, 0, &val))
		return -EINVAL;

	mutex_lock(&kcal_mutex);
	kcal_hue = clamp_t(u32, val, 0, 1536);
	kcal_recompute_pcc_locked();
	kcal_dirty = true;
	kcal_enabled = true;
	kcal_restored = false;
	mutex_unlock(&kcal_mutex);

	return count;
}
static DEVICE_ATTR_RW(kcal_hue);

static ssize_t kcal_invert_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", kcal_invert);
}

static ssize_t kcal_invert_store(struct device *dev, struct device_attribute *attr, const char *buf, size_t count)
{
	bool val;

	if (strtobool(buf, &val) < 0)
		return -EINVAL;

	mutex_lock(&kcal_mutex);
	kcal_invert = val ? 1 : 0;
	kcal_recompute_pcc_locked();
	kcal_dirty = true;
	kcal_enabled = true;
	kcal_restored = false;
	mutex_unlock(&kcal_mutex);

	return count;
}
static DEVICE_ATTR_RW(kcal_invert);

static struct attribute *kcal_attrs[] = {
	&dev_attr_kcal.attr,
	&dev_attr_kcal_enable.attr,
	&dev_attr_kcal_min.attr,
	&dev_attr_kcal_sat.attr,
	&dev_attr_kcal_val.attr,
	&dev_attr_kcal_cont.attr,
	&dev_attr_kcal_hue.attr,
	&dev_attr_kcal_invert.attr,
	NULL,
};

static umode_t kcal_is_visible(struct kobject *kobj, struct attribute *attr, int n)
{
	return 0664;
}

static const struct attribute_group kcal_attr_group = {
	.is_visible = kcal_is_visible,
	.attrs = kcal_attrs,
};

static struct platform_device kcal_device = {
	.name = "kcal_ctrl",
	.id = 0,
};

static int __init sde_kcal_init(void)
{
	int ret;

	ret = platform_device_register(&kcal_device);
	if (ret) {
		pr_err("[KCAL] failed to register platform device: %d\n", ret);
		return ret;
	}

	ret = sysfs_create_group(&kcal_device.dev.kobj, &kcal_attr_group);
	if (ret) {
		pr_err("[KCAL] failed to create sysfs group: %d\n", ret);
		platform_device_unregister(&kcal_device);
		return ret;
	}

	mutex_lock(&kcal_mutex);
	kcal_recompute_pcc_locked();
	mutex_unlock(&kcal_mutex);

	pr_info("[KCAL] driver initialized successfully (default: enabled=%d, 256 256 256)\n",
		kcal_enabled);
	return 0;
}
late_initcall(sde_kcal_init);

MODULE_DESCRIPTION("KCAL Color Calibration for Qualcomm SDE");
MODULE_LICENSE("GPL v2");
