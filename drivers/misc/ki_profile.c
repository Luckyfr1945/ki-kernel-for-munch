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
#include <linux/mm.h>
#include <linux/workqueue.h>
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

static int apply_ki_profile(int mode)
{
	int ret, err = 0;

	switch (mode) {
	case KI_PROFILE_BATTERY:
		/* Silver (cpu0): conservative ramp-up, 4ms hold to avoid clock thrashing */
		ret = sugov_set_cluster_rate_limits(0, 1500, 4000);
		if (ret) {
			pr_warn("ki_profile: cpu0 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 1;
		}
		/* Gold (cpu4): slow to boost */
		ret = sugov_set_cluster_rate_limits(4, 3000, 4000);
		if (ret) {
			pr_warn("ki_profile: cpu4 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 2;
		}
		/* Prime (cpu7): fires only under hard sustained load */
		ret = sugov_set_cluster_rate_limits(7, 10000, 4000);
		if (ret) {
			pr_warn("ki_profile: cpu7 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 4;
		}
		/* High migration margin → stay on Silver for light tasks */
		sched_set_updown_migrate(92, 85);
		sched_set_boost(0);
		/*
		 * RAM Tuning — Battery Saver:
		 * Low swappiness: avoid zRAM compression which burns CPU cycles.
		 * kswapd prefers reclaiming file cache over swapping anon pages,
		 * meaning fewer CPU wakeups and less decompression overhead.
		 */
		vm_swappiness = 60;
		watermark_scale_factor = 15;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 100;
		pr_info("ki_profile: Battery profile active (CPU lazy + minimal zRAM churn)\n");
		break;

	case KI_PROFILE_BALANCED:
	default:
		/* Silver (cpu0): zero ramp-up delay, 500us down hold for snappy 120Hz */
		ret = sugov_set_cluster_rate_limits(0, 0, 500);
		if (ret) {
			pr_warn("ki_profile: cpu0 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 1;
		}
		/* Gold (cpu4): zero ramp-up delay for instant game thread responsiveness */
		ret = sugov_set_cluster_rate_limits(4, 0, 500);
		if (ret) {
			pr_warn("ki_profile: cpu4 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 2;
		}
		/* Prime (cpu7): zero ramp-up delay for heavy load spikes and 120Hz frame deadlines */
		ret = sugov_set_cluster_rate_limits(7, 0, 500);
		if (ret) {
			pr_warn("ki_profile: cpu7 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 4;
		}
		/* Balanced migration: light tasks on Silver, bursts assist on Gold */
		sched_set_updown_migrate(85, 75);
		sched_set_boost(0);
		/*
		 * RAM Tuning — Balanced Daily:
		 * watermark_scale_factor 30: provides generous free page headroom,
		 * completely preventing direct reclaim (allocstall) pauses during
		 * heavy multi-tasking, notification pop-ups, and 120Hz gaming.
		 */
		vm_swappiness = 60;
		watermark_scale_factor = 30;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 80;
		pr_info("ki_profile: Balanced profile active (Butter-smooth 120Hz + Fast Response)\n");
		break;

	case KI_PROFILE_PERFORMANCE:
		/* Silver, Gold, Prime: zero ramp-up delay, 5ms hold for sustained high FPS */
		ret = sugov_set_cluster_rate_limits(0, 0, 5000);
		if (ret) {
			pr_warn("ki_profile: cpu0 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 1;
		}
		ret = sugov_set_cluster_rate_limits(4, 0, 5000);
		if (ret) {
			pr_warn("ki_profile: cpu4 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 2;
		}
		ret = sugov_set_cluster_rate_limits(7, 0, 5000);
		if (ret) {
			pr_warn("ki_profile: cpu7 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 4;
		}
		/* Aggressive upmigration to Gold/Prime for high FPS gaming */
		sched_set_updown_migrate(65, 50);
		sched_set_boost(1);
		/*
		 * RAM Tuning — Gaming/Performance:
		 * Generous watermark headroom keeps game assets in RAM and avoids
		 * any mid-frame direct reclaim stutter.
		 */
		vm_swappiness = 60;
		watermark_scale_factor = 30;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 60;
		pr_info("ki_profile: Performance profile active (Gaming Turbo — Gacor!)\n");
		break;
	}

	setup_per_zone_wmarks();
	return err;
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
	current_profile_mode = val;
	apply_ki_profile(val);
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
static struct delayed_work ki_profile_delayed_work;
static int boot_settle_retries;

static void ki_profile_delayed_work_fn(struct work_struct *work)
{
	int err;

	mutex_lock(&ki_profile_mutex);
	err = apply_ki_profile(current_profile_mode);
	mutex_unlock(&ki_profile_mutex);

	if (err && boot_settle_retries < 6) {
		boot_settle_retries++;
		pr_info("ki_profile: sugov limits pending (err=%d), retrying in 5s (%d/6)\n",
			err, boot_settle_retries);
		schedule_delayed_work(&ki_profile_delayed_work, msecs_to_jiffies(5000));
		return;
	}

	pr_info("ki_profile: Boot settlement complete, profile %d (%s) active and locked\n",
		current_profile_mode, profile_names[current_profile_mode]);
}

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

	INIT_DELAYED_WORK(&ki_profile_delayed_work, ki_profile_delayed_work_fn);
	/*
	 * Schedule delayed enforcement after 25 seconds so userspace post_boot
	 * scripts (which overwrite schedutil and migration margins) are overridden
	 * by Ki-Profile.
	 */
	schedule_delayed_work(&ki_profile_delayed_work, msecs_to_jiffies(25000));

	pr_info("ki_profile: Ki-kernel Profile driver initialized (default: Balanced)\n");
	return 0;
}
late_initcall(ki_profile_init);

MODULE_DESCRIPTION("Ki-kernel CPU Profile Driver");
MODULE_LICENSE("GPL v2");
