/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_KI_PROFILE_H
#define _LINUX_KI_PROFILE_H

enum ki_profile_mode {
	KI_PROFILE_BATTERY = 0,
	KI_PROFILE_BALANCED = 1,
	KI_PROFILE_PERFORMANCE = 2,
	KI_PROFILE_MAX,
};

int sugov_set_cluster_rate_limits(unsigned int cpu, unsigned int up_us, unsigned int down_us);
void sched_set_updown_migrate(unsigned int up, unsigned int down);
int sched_set_boost(int type);

extern bool ki_thermal_throttle_enabled;

#endif /* _LINUX_KI_PROFILE_H */
