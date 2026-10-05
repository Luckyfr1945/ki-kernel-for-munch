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
#ifdef CONFIG_DYNAMIC_FSYNC
#include <linux/dyn_fsync.h>
#endif

int current_profile_mode = KI_PROFILE_BALANCED;
EXPORT_SYMBOL_GPL(current_profile_mode);
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
		/* Clear RTG boost: prevent WALT rtgb_active from holding CPUs high during idle */
		sugov_set_cluster_rtg_boost(0, 0);
		sugov_set_cluster_rtg_boost(4, 0);
		sugov_set_cluster_rtg_boost(7, 0);
		sugov_set_cluster_hispeed(0, 0, 85);
		sugov_set_cluster_hispeed(4, 0, 85);
		sugov_set_cluster_hispeed(7, 0, 85);
		sugov_set_cluster_floor(0, 0);
		sugov_set_cluster_floor(4, 0);
		sugov_set_cluster_floor(7, 0);
		sugov_set_cluster_pl(0, false);
		sugov_set_cluster_pl(4, false);
		sugov_set_cluster_pl(7, false);
		kgsl_set_performance_mode(false);
		/* High migration margin → stay on Silver for light tasks */
		sched_set_updown_migrate(92, 85);
		sched_set_group_updown_migrate(100, 95);
		sched_set_boost(0);
		sysctl_sched_window_stats_policy = 2; /* WINDOW_STATS_MAX_RECENT_AVG */
		ki_thermal_throttle_enabled = true;
		/*
		 * RAM Tuning — Battery Saver:
		 * Swappiness 90 with LZ4 fast swapping ensures anonymous pages are compressed
		 * cleanly into zRAM without holding back app memory.
		 */
		vm_swappiness = 150;
		watermark_scale_factor = 12;
		watermark_boost_factor = 0;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 100;
		pr_info("ki_profile: Battery profile active (CPU lazy + minimal zRAM churn)\n");
		break;

	case KI_PROFILE_BALANCED:
	default:
		/* Silver (cpu0): zero ramp-up delay, 2000us down hold for snappy 120Hz */
		ret = sugov_set_cluster_rate_limits(0, 0, 2000);
		if (ret) {
			pr_warn("ki_profile: cpu0 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 1;
		}
		/* Gold (cpu4): zero ramp-up delay for instant game thread responsiveness */
		ret = sugov_set_cluster_rate_limits(4, 0, 2000);
		if (ret) {
			pr_warn("ki_profile: cpu4 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 2;
		}
		/* Prime (cpu7): zero ramp-up delay for heavy load spikes and 120Hz frame deadlines */
		ret = sugov_set_cluster_rate_limits(7, 0, 2000);
		if (ret) {
			pr_warn("ki_profile: cpu7 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 4;
		}
		/* Clear RTG boost: prevent stale WALT rtgb_active from previous Performance mode */
		sugov_set_cluster_rtg_boost(0, 0);
		sugov_set_cluster_rtg_boost(4, 0);
		sugov_set_cluster_rtg_boost(7, 0);
		sugov_set_cluster_hispeed(0, 0, 85);
		sugov_set_cluster_hispeed(4, 0, 85);
		sugov_set_cluster_hispeed(7, 0, 85);
		sugov_set_cluster_floor(0, 0);
		sugov_set_cluster_floor(4, 0);
		sugov_set_cluster_floor(7, 0);
		sugov_set_cluster_pl(0, false);
		sugov_set_cluster_pl(4, false);
		sugov_set_cluster_pl(7, false);
		kgsl_set_performance_mode(false);
		/* Balanced migration: light tasks on Silver, bursts assist on Gold */
		sched_set_updown_migrate(85, 75);
		sched_set_group_updown_migrate(100, 95);
		sched_set_boost(0);
		sysctl_sched_window_stats_policy = 2; /* WINDOW_STATS_MAX_RECENT_AVG */
		ki_thermal_throttle_enabled = true;
		/*
		 * RAM Tuning — Balanced Daily:
		 * watermark_scale_factor 16 + watermark_boost_factor 0:
		 * Provides healthy free page headroom while preventing catastrophic
		 * kswapd storms and direct reclaim freezes upon waking from deep idle.
		 */
		vm_swappiness = 150;
		watermark_scale_factor = 16;
		watermark_boost_factor = 0;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 80;
		pr_info("ki_profile: Balanced profile active (Butter-smooth 120Hz + Fast Response)\n");
		break;

	case KI_PROFILE_PERFORMANCE:
		/*
		 * Silver, Gold, Prime: 0us up delay (instant boost to top speed).
		 * 150000us (150ms) down hold: holds frequencies across consecutive frame
		 * rendering intervals (8.3ms for 120Hz, 11.1ms for 90Hz, 16.6ms for 60Hz),
		 * completely eliminating micro-stutters and mid-game FPS dips!
		 */
		ret = sugov_set_cluster_rate_limits(0, 0, 150000);
		if (ret) {
			pr_warn("ki_profile: cpu0 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 1;
		}
		ret = sugov_set_cluster_rate_limits(4, 0, 150000);
		if (ret) {
			pr_warn("ki_profile: cpu4 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 2;
		}
		ret = sugov_set_cluster_rate_limits(7, 0, 150000);
		if (ret) {
			pr_warn("ki_profile: cpu7 sugov not ready (%d), cpufreq limits skipped\n", ret);
			err |= 4;
		}

		/*
		 * High Frequency Floor (Zero-Lag Floor):
		 * Eliminates DVFS ramp-up and clock synthesizer latency by preventing
		 * cores from dropping into low power states between frame renders:
		 * Silver (cpu0): 1.21 GHz floor (1209600 kHz)
		 * Gold   (cpu4): 1.61 GHz floor (1612800 kHz)
		 * Prime  (cpu7): 1.71 GHz floor (1708800 kHz)
		 */
		sugov_set_cluster_floor(0, 1209600);
		sugov_set_cluster_floor(4, 1612800);
		sugov_set_cluster_floor(7, 1708800);

		/*
		 * Instant Snap Hispeed (Game Boost without RTG dependency):
		 * When any cluster load crosses 15%, snaps directly to max turbo.
		 * Silver: 1.80 GHz max (1804800 kHz)
		 * Gold:   2.42 GHz max (2419200 kHz)
		 * Prime:  3.19 GHz max turbo (3187200 kHz)
		 */
		sugov_set_cluster_hispeed(0, 1804800, 15);
		sugov_set_cluster_hispeed(4, 2419200, 15);
		sugov_set_cluster_hispeed(7, 3187200, 15);

		/*
		 * WALT RTG Turbo Boost (Mentok):
		 * Boosts foreground top-app / gaming render threads immediately
		 * to max cluster frequencies if marked by RTG.
		 */
		sugov_set_cluster_rtg_boost(0, 1804800);
		sugov_set_cluster_rtg_boost(4, 2419200);
		sugov_set_cluster_rtg_boost(7, 3187200);

		/*
		 * WALT Performance Level (PL) Hinting:
		 * Enables instant frequency response from foreground game threads.
		 */
		sugov_set_cluster_pl(0, true);
		sugov_set_cluster_pl(4, true);
		sugov_set_cluster_pl(7, true);

		/*
		 * Ultra-Aggressive Task Migration:
		 * Tasks migrate to Gold/Prime at only 20% load and remain pinned
		 * until load drops below 10%. Related thread groups upmigrate at 30%.
		 */
		sched_set_updown_migrate(20, 10);
		sched_set_group_updown_migrate(30, 15);

		/*
		 * Full Throttle Boost & Core Revive:
		 * Unisolate all 8 cores and enable WALT frequency aggregation
		 * for instant dual/multi-core turbo spikes.
		 */
		sched_set_boost(1);
		{
			int cpu;
			for_each_possible_cpu(cpu)
				sched_unisolate_cpu(cpu);
		}

		/*
		 * WINDOW_STATS_MAX (1):
		 * Tracks peak demand across windows instead of average, providing
		 * zero-lag instantaneous cpufreq responsiveness under load.
		 */
		sysctl_sched_window_stats_policy = 1;

		/*
		 * Thermal Throttling Bypass (Gaming Unlocked):
		 * Bypasses thermal drops on CPU and GPU so 3.19GHz Prime and 683MHz
		 * GPU stay locked without dropping FPS. Critical emergency shutdown
		 * remains intact for hardware safety.
		 */
		ki_thermal_throttle_enabled = false;

		/*
		 * GPU Extreme Gaming Turbo (Adreno 650 Mentok):
		 * - Floor GPU clock at 510 MHz (never drops to 150/330 MHz).
		 * - Keep DDR AXI bus locked open (eliminates texture streaming hitching).
		 * - Disable internal Adreno cycle-skipping clock throttling.
		 * - Idle timeout 1000ms.
		 */
		kgsl_set_performance_mode(true);

#ifdef CONFIG_DYNAMIC_FSYNC
		/* Bypasses synchronous filesystem stalls while screen is ON */
		dyn_fsync_active = true;
#endif

		/*
		 * RAM Tuning — Gaming Turbo Mentok:
		 * - swappiness 150: aggressively moves idle/cold anonymous memory into fast
		 *   LZ4-compressed zRAM, freeing up uncompressed physical RAM for game assets
		 *   and filesystem page cache.
		 * - watermark_scale_factor 25: large free memory buffer prevents mid-game
		 *   direct reclaim freezes and hitching.
		 * - watermark_boost_factor 0: prevents kswapd stall storms.
		 * - vfs_cache_pressure 100: balanced reclamation prevents memory starvation in 4GB+ games.
		 */
		vm_swappiness = 150;
		watermark_scale_factor = 25;
		watermark_boost_factor = 0;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = 100;
		pr_info("ki_profile: Performance profile active (Mentok Extreme Gaming Turbo — 120FPS Locked!)\n");
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

static umode_t ki_profile_is_visible(struct kobject *kobj, struct attribute *attr, int n)
{
	if (attr == &mode_attr.attr || attr == &thermal_throttle_attr.attr)
		return 0666;
	return attr->mode;
}

static const struct attribute_group ki_profile_attr_group = {
	.attrs = ki_profile_attrs,
	.is_visible = ki_profile_is_visible,
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
