// SPDX-License-Identifier: GPL-2.0
/*
 * Ki-Kernel CPU Profile Driver for POCO F4 (munch)
 * Exposes /sys/kernel/ki_profile/mode:
 *   0: Battery Saver
 *   1: Balanced (Default)
 *   2: Performance / Turbo Gaming
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/string.h>
#include <linux/sched.h>
#include <linux/mutex.h>
#include <linux/ki_profile.h>

static int current_profile_mode = KI_PROFILE_BALANCED;
static DEFINE_MUTEX(ki_profile_mutex);

static const char * const profile_names[] = {
	[KI_PROFILE_BATTERY] = "battery",
	[KI_PROFILE_BALANCED] = "balanced",
	[KI_PROFILE_PERFORMANCE] = "performance",
};

extern int vm_swappiness;
extern int watermark_scale_factor;
extern int sysctl_compact_unevictable_allowed;
extern int sysctl_vfs_cache_pressure;

static void apply_ki_profile(int mode)
{
	switch (mode) {
	case KI_PROFILE_BATTERY:
		/* Silver (cpu0): 2500us up, 500us down */
		sugov_set_cluster_rate_limits(0, 2500, 500);
		/* Gold (cpu4): 5000us up, 500us down */
		sugov_set_cluster_rate_limits(4, 5000, 500);
		/* Prime (cpu7): 20000us up, 500us down */
		sugov_set_cluster_rate_limits(7, 20000, 500);
		/* Higher margin before migrating to big cores -> saves battery */
		sched_set_updown_migrate(98, 90);
		sched_set_boost(0);
		/* In-Kernel RAM Tuning: Gentle swapping, zero compaction burn */
		vm_swappiness = 80;
		watermark_scale_factor = 12;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 80;
		pr_info("ki_profile: Switched to Battery profile (CPU & RAM Optimized)\n");
		break;

	case KI_PROFILE_BALANCED:
	default:
		/* Silver (cpu0): 1000us up, 500us down -> snappy 120Hz UI, instant idle drop */
		sugov_set_cluster_rate_limits(0, 1000, 500);
		/* Gold (cpu4): 2000us up, 500us down -> fast app switches (Grab, Maps, WA) */
		sugov_set_cluster_rate_limits(4, 2000, 500);
		/* Prime (cpu7): 4000us up, 500us down -> cool under sun, fires on heavy sustained load */
		sugov_set_cluster_rate_limits(7, 4000, 500);
		/* Responsive smooth margins */
		sched_set_updown_migrate(95, 85);
		sched_set_boost(0);
		/* In-Kernel RAM Tuning: Anti-swap churn, fast UI asset caching */
		vm_swappiness = 80;
		watermark_scale_factor = 12;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 80;
		pr_info("ki_profile: Switched to Balanced profile (Ngojek & Daily Optimized)\n");
		break;

	case KI_PROFILE_PERFORMANCE:
		/* Silver, Gold, Prime: instantaneous ramp-up 500us, hold high freq 2000us */
		sugov_set_cluster_rate_limits(0, 500, 2000);
		sugov_set_cluster_rate_limits(4, 500, 2000);
		sugov_set_cluster_rate_limits(7, 500, 2000);
		/* Aggressive upmigration to Gold/Prime cores for high FPS gaming */
		sched_set_updown_migrate(65, 50);
		sched_set_boost(1);
		/* In-Kernel RAM Tuning: Dedicated gaming RAM, silence kswapd */
		vm_swappiness = 60;
		watermark_scale_factor = 10;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 80;
		pr_info("ki_profile: Switched to Performance / Turbo Gaming profile (Gacor!)\n");
		break;
	}
}

static ssize_t mode_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", current_profile_mode);
}

static ssize_t mode_store(struct kobject *kobj, struct kobj_attribute *attr,
			  const char *buf, size_t count)
{
	int val;

	if (kstrtoint(buf, 10, &val))
		return -EINVAL;

	if (val < 0 || val >= KI_PROFILE_MAX)
		return -EINVAL;

	mutex_lock(&ki_profile_mutex);
	if (current_profile_mode != val) {
		current_profile_mode = val;
		apply_ki_profile(val);
	}
	mutex_unlock(&ki_profile_mutex);

	return count;
}

static ssize_t current_profile_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	const char *name = "unknown";

	if (current_profile_mode >= 0 && current_profile_mode < KI_PROFILE_MAX)
		name = profile_names[current_profile_mode];

	return scnprintf(buf, PAGE_SIZE, "%s\n", name);
}

static ssize_t available_modes_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "0: Battery Saver\n1: Balanced\n2: Performance/Gaming Turbo\n");
}

bool ki_thermal_throttle_enabled = true;
EXPORT_SYMBOL_GPL(ki_thermal_throttle_enabled);

static ssize_t thermal_throttle_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", ki_thermal_throttle_enabled ? 1 : 0);
}

static ssize_t thermal_throttle_store(struct kobject *kobj, struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	int val;

	if (kstrtoint(buf, 10, &val))
		return -EINVAL;

	ki_thermal_throttle_enabled = (val != 0);
	pr_info("ki_profile: Thermal throttle %s\n",
		ki_thermal_throttle_enabled ? "enabled (Safe)" : "disabled (Gaming Unlocked)");

	return count;
}

static struct kobj_attribute mode_attr = __ATTR_RW(mode);
static struct kobj_attribute current_profile_attr = __ATTR_RO(current_profile);
static struct kobj_attribute available_modes_attr = __ATTR_RO(available_modes);
static struct kobj_attribute thermal_throttle_attr = __ATTR_RW(thermal_throttle);

static struct attribute *ki_profile_attrs[] = {
	&mode_attr.attr,
	&current_profile_attr.attr,
	&available_modes_attr.attr,
	&thermal_throttle_attr.attr,
	NULL,
};

static const struct attribute_group ki_profile_attr_group = {
	.attrs = ki_profile_attrs,
};

static struct kobject *ki_profile_kobj;

static int __init ki_profile_init(void)
{
	int rc;

	ki_profile_kobj = kobject_create_and_add("ki_profile", kernel_kobj);
	if (!ki_profile_kobj) {
		pr_err("ki_profile: Failed to create kobject\n");
		return -ENOMEM;
	}

	rc = sysfs_create_group(ki_profile_kobj, &ki_profile_attr_group);
	if (rc) {
		pr_err("ki_profile: Failed to create sysfs group\n");
		kobject_put(ki_profile_kobj);
		return rc;
	}

	apply_ki_profile(current_profile_mode);
	pr_info("ki_profile: Ki-kernel Profile driver initialized (default: Balanced)\n");
	return 0;
}
late_initcall(ki_profile_init);

MODULE_DESCRIPTION("Ki-kernel CPU Profile Driver");
MODULE_LICENSE("GPL v2");
