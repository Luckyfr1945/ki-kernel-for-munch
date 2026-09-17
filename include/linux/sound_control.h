/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_SOUND_CONTROL_H
#define _LINUX_SOUND_CONTROL_H

#define SOUND_CONTROL_VERSION "3.8"

int sound_control_get_hph_l_gain(void);
int sound_control_get_hph_r_gain(void);
int sound_control_get_mic_gain(void);
int sound_control_get_speaker_gain(void);
int sound_control_get_high_perf_mode(void);

#endif /* _LINUX_SOUND_CONTROL_H */
