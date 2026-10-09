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
#include <linux/spinlock.h>
#include <linux/mm.h>
#include <linux/workqueue.h>
#include <linux/thermal.h>
#include <linux/power_supply.h>
#include <linux/notifier.h>
#include <drm/drm_notifier_mi.h>
#include <linux/ki_profile.h>

/* Profile chosen by the user (sysfs "mode") */
int current_profile_mode = KI_PROFILE_BALANCED;
EXPORT_SYMBOL_GPL(current_profile_mode);
static DEFINE_MUTEX(ki_profile_mutex);
static DEFINE_SPINLOCK(ki_guard_lock);

/* Profile actually applied right now (differs while screen is off) */
static int ki_active_mode = -1;

int ki_get_active_profile(void)
{
	int mode = READ_ONCE(ki_active_mode);
	if (mode < 0)
		return READ_ONCE(current_profile_mode);
	return mode;
}
EXPORT_SYMBOL_GPL(ki_get_active_profile);

/*
 * Screen-off Auto Battery:
 * Screen off  -> after KI_SCREEN_OFF_DELAY_MS switch to Battery profile.
 * Screen on   -> restore the user's profile immediately (via early DRM blank).
 * The delay avoids flapping from proximity-sensor blanking during calls.
 */
#define KI_SCREEN_OFF_DELAY_MS	3000
static bool ki_screen_off_battery = true;
static bool ki_screen_on = true;
static struct delayed_work ki_screen_work;

static const char * const profile_names[] = {
	[KI_PROFILE_BATTERY] = "battery",
	[KI_PROFILE_BALANCED] = "balanced",
	[KI_PROFILE_PERFORMANCE] = "performance",
};

extern int vm_swappiness;
extern int watermark_scale_factor;
extern int sysctl_compact_unevictable_allowed;
extern int sysctl_vfs_cache_pressure;

/*
 * Thermal Auto-Guard (Performance mode only):
 * Thermal bypass stays active for max FPS, but throttling is re-armed when
 * CPU/GPU die >= 85C, body (quiet_therm) >= 46C, or battery >= 45C.
 * Released again once die <= 75C, body <= 42C, and battery <= 41C.
 * Polls every 2s, only while Performance is active.
 */
#define KI_GUARD_POLL_MS	2000
#define KI_GUARD_DIE_HOT	85000 /* 85.0°C */
#define KI_GUARD_DIE_COOL	75000 /* 75.0°C */
#define KI_GUARD_SKIN_HOT	46000 /* 46.0°C */
#define KI_GUARD_SKIN_COOL	42000 /* 42.0°C */
#define KI_GUARD_BATT_HOT	45000 /* 45.0°C */
#define KI_GUARD_BATT_COOL	41000 /* 41.0°C */

static const char * const ki_guard_die_zones[] = {
	"cpu-1-0-usr", "cpu-1-1-usr", "cpu-1-2-usr", "cpu-1-3-usr",
	"cpu-1-4-usr", "cpu-1-5-usr", "cpu-1-6-usr", "cpu-1-7-usr",
	"gpuss-0-usr", "gpuss-1-usr",
};

static struct thermal_zone_device *ki_guard_die_tz[ARRAY_SIZE(ki_guard_die_zones)];
static struct thermal_zone_device *ki_guard_skin_tz;
static bool ki_guard_resolved;
static bool ki_guard_tripped;
static struct delayed_work ki_guard_work;

bool ki_thermal_throttle_enabled = true;
EXPORT_SYMBOL_GPL(ki_thermal_throttle_enabled);

static void ki_guard_resolve_zones(void)
{
	struct thermal_zone_device *tz;
	int i, valid_count = 0;

	for (i = 0; i < ARRAY_SIZE(ki_guard_die_zones); i++) {
		tz = thermal_zone_get_zone_by_name(ki_guard_die_zones[i]);
		ki_guard_die_tz[i] = IS_ERR(tz) ? NULL : tz;
		if (ki_guard_die_tz[i])
			valid_count++;
	}
	tz = thermal_zone_get_zone_by_name("quiet_therm");
	ki_guard_skin_tz = IS_ERR(tz) ? NULL : tz;
	if (ki_guard_skin_tz)
		valid_count++;

	/* Only mark resolved if at least one thermal zone is valid */
	if (valid_count > 0)
		ki_guard_resolved = true;
}

static int ki_guard_read(struct thermal_zone_device *tz)
{
	int temp;

	if (!tz || thermal_zone_get_temp(tz, &temp))
		return INT_MIN;
	return temp;
}

static int ki_guard_read_batt(void)
{
	struct power_supply *psy = power_supply_get_by_name("battery");
	union power_supply_propval val;
	int ret;

	if (!psy)
		return INT_MIN;
	ret = power_supply_get_property(psy, POWER_SUPPLY_PROP_TEMP, &val);
	power_supply_put(psy);
	if (ret)
		return INT_MIN;
	return val.intval * 100; /* convert tenths of °C to millidegrees C */
}

static void ki_guard_work_fn(struct work_struct *work)
{
	int i, die = INT_MIN, skin, batt;
	unsigned long flags;
	bool hot_condition = false;
	bool cool_condition = false;
	bool die_ok, skin_ok, batt_ok;

	spin_lock_irqsave(&ki_guard_lock, flags);
	if (READ_ONCE(ki_active_mode) != KI_PROFILE_PERFORMANCE) {
		ki_guard_tripped = false;
		spin_unlock_irqrestore(&ki_guard_lock, flags);
		return;
	}
	spin_unlock_irqrestore(&ki_guard_lock, flags);

	if (!ki_guard_resolved)
		ki_guard_resolve_zones();

	for (i = 0; i < ARRAY_SIZE(ki_guard_die_tz); i++)
		die = max(die, ki_guard_read(ki_guard_die_tz[i]));
	skin = ki_guard_read(ki_guard_skin_tz);
	batt = ki_guard_read_batt();

	/* Hot / Trip condition: if ANY valid sensor crosses HOT threshold */
	if ((die != INT_MIN && die >= KI_GUARD_DIE_HOT) ||
	    (skin != INT_MIN && skin >= KI_GUARD_SKIN_HOT) ||
	    (batt != INT_MIN && batt >= KI_GUARD_BATT_HOT))
		hot_condition = true;

	/*
	 * Cool / Recovery condition (Fail-safe):
	 * Must have valid die readings and all available sensors <= COOL.
	 * If sensor readings are missing/INT_MIN, cool_condition is FALSE.
	 */
	die_ok = (die != INT_MIN) && (die <= KI_GUARD_DIE_COOL);
	skin_ok = (skin == INT_MIN) || (skin <= KI_GUARD_SKIN_COOL);
	batt_ok = (batt == INT_MIN) || (batt <= KI_GUARD_BATT_COOL);
	if (die_ok && skin_ok && batt_ok)
		cool_condition = true;

	spin_lock_irqsave(&ki_guard_lock, flags);
	/* Re-check active mode under spinlock to eliminate races with apply_ki_profile */
	if (READ_ONCE(ki_active_mode) != KI_PROFILE_PERFORMANCE) {
		ki_guard_tripped = false;
		spin_unlock_irqrestore(&ki_guard_lock, flags);
		return;
	}

	if (!ki_guard_tripped && hot_condition) {
		ki_guard_tripped = true;
		WRITE_ONCE(ki_thermal_throttle_enabled, true);
		pr_info("ki_profile: guard tripped (die=%d skin=%d batt=%d), throttle re-armed\n",
			die, skin, batt);
	} else if (ki_guard_tripped && cool_condition) {
		ki_guard_tripped = false;
		WRITE_ONCE(ki_thermal_throttle_enabled, false);
		pr_info("ki_profile: guard cooled (die=%d skin=%d batt=%d), gaming unlocked\n",
			die, skin, batt);
	}
	spin_unlock_irqrestore(&ki_guard_lock, flags);

	queue_delayed_work(system_power_efficient_wq, &ki_guard_work,
			   msecs_to_jiffies(KI_GUARD_POLL_MS));
}

/* Representative CPU of each cluster: Silver, Gold, Prime */
#define KI_NR_CLUSTERS	3
static const unsigned int ki_cluster_cpu[KI_NR_CLUSTERS] = { 0, 4, 7 };

struct ki_cluster_tune {
	unsigned int up_us;		/* sugov up rate limit */
	unsigned int down_us;		/* sugov down rate limit */
	unsigned int hispeed_freq;	/* kHz, 0 = disabled */
	unsigned int hispeed_load;	/* % */
	unsigned int rtg_boost_freq;	/* kHz, 0 = disabled */
	unsigned int floor_freq;	/* kHz, 0 = disabled */
};

struct ki_profile_tune {
	struct ki_cluster_tune cl[KI_NR_CLUSTERS];
	bool pl;			/* WALT PL hints */
	bool gpu_perf;			/* kgsl performance mode */
	bool thermal_throttle;
	int sched_boost;
	unsigned int up_migrate, down_migrate;
	unsigned int grp_up_migrate, grp_down_migrate;
	unsigned int window_stats_policy; /* 1 = MAX, 2 = MAX_RECENT_AVG */
	int swappiness;
	int wmark_scale;
	int vfs_cache_pressure;
};

static const struct ki_profile_tune ki_tunes[KI_PROFILE_MAX] = {
	/*
	 * Battery Saver:
	 * Fokus hemat baterai nyata (irit polll).
	 * Tasks dikurung di Silver cluster (up_migrate = 98/90),
	 * Hispeed rendah (Silver 1.05GHz, Gold 1.17GHz, Prime 1.27GHz).
	 * Ramp-up malas (up_us: 2ms, 4ms, 8ms), drop cepat ke idle (down_us: 2000us = 2ms).
	 * Swappiness 60 untuk menghemat daya CPU dari kompresi zRAM berlebih.
	 */
	[KI_PROFILE_BATTERY] = {
		.cl = {
			{ .up_us = 2000,  .down_us = 2000, .hispeed_freq = 1056000, .hispeed_load = 95 },
			{ .up_us = 4000,  .down_us = 2000, .hispeed_freq = 1171200, .hispeed_load = 95 },
			{ .up_us = 8000,  .down_us = 2000, .hispeed_freq = 1267200, .hispeed_load = 95 },
		},
		.thermal_throttle = true,
		.up_migrate = 98, .down_migrate = 90,
		.grp_up_migrate = 100, .grp_down_migrate = 95,
		.window_stats_policy = 2,
		.swappiness = 60, .wmark_scale = 16, .vfs_cache_pressure = 80,
	},
	/*
	 * Balanced:
	 * Nyaman & smooth 120Hz untuk harian (sosmed, chat, UI responsif).
	 * Schedutil up-rate cepat (up_us: 500us, 1000us, 2000us) saat layar disentuh,
	 * tapi down_us dipersingkat dari 20ms jadi 4ms (4000us) agar tidak buang baterai.
	 * Hispeed: Silver 1.21GHz, Gold 1.38GHz, Prime 1.51GHz.
	 * Migrasi seimbang (up_migrate = 85, down_migrate = 75) agar app berat dibantu Gold tanpa lag.
	 * Swappiness = 80, Wmark = 16, vfs_cache_pressure = 80 (anti-kill multitasking).
	 */
	[KI_PROFILE_BALANCED] = {
		.cl = {
			{ .up_us = 500,  .down_us = 4000, .hispeed_freq = 1209600, .hispeed_load = 90 },
			{ .up_us = 1000, .down_us = 4000, .hispeed_freq = 1382400, .hispeed_load = 90 },
			{ .up_us = 2000, .down_us = 4000, .hispeed_freq = 1516800, .hispeed_load = 90 },
		},
		.thermal_throttle = true,
		.up_migrate = 85, .down_migrate = 75,
		.grp_up_migrate = 95, .grp_down_migrate = 85,
		.window_stats_policy = 2,
		.swappiness = 80, .wmark_scale = 16, .vfs_cache_pressure = 80,
	},
	/*
	 * Performance / Gaming Turbo:
	 *  - 0us up / 150ms down hold across frame intervals (no clock bouncing)
	 *  - Zero-lag floor: Silver 1.21G, Gold 1.61G, Prime 1.71G
	 *  - Snap to cluster max at 15% load, RTG boost to cluster max
	 *  - Aggressive migration 20/10 (groups 30/15), PL hints, sched_boost 1
	 *  - WINDOW_STATS_MAX, thermal throttle bypass with auto-guard, GPU perf mode
	 */
	[KI_PROFILE_PERFORMANCE] = {
		.cl = {
			{ 0, 150000, 1804800, 15, 1804800, 1209600 },
			{ 0, 150000, 2419200, 15, 2419200, 1612800 },
			{ 0, 150000, 3187200, 15, 3187200, 1708800 },
		},
		.pl = true,
		.gpu_perf = true,
		.thermal_throttle = false,
		.sched_boost = 1,
		.up_migrate = 20, .down_migrate = 10,
		.grp_up_migrate = 30, .grp_down_migrate = 15,
		.window_stats_policy = 1,
		.swappiness = 150, .wmark_scale = 25, .vfs_cache_pressure = 100,
	},
};

static int apply_ki_profile(int mode, bool force)
{
	const struct ki_profile_tune *t;
	int i, ret, err = 0;
	unsigned long flags;

	if (mode < 0 || mode >= KI_PROFILE_MAX)
		mode = KI_PROFILE_BALANCED;
	t = &ki_tunes[mode];

	for (i = 0; i < KI_NR_CLUSTERS; i++) {
		const struct ki_cluster_tune *c = &t->cl[i];
		unsigned int cpu = ki_cluster_cpu[i];

		ret = sugov_set_cluster_rate_limits(cpu, c->up_us, c->down_us);
		if (ret) {
			pr_warn("ki_profile: cpu%u sugov not ready (%d), cpufreq limits skipped\n",
				cpu, ret);
			err |= BIT(i);
		}
		sugov_set_cluster_rtg_boost(cpu, c->rtg_boost_freq);
		sugov_set_cluster_hispeed(cpu, c->hispeed_freq, c->hispeed_load);
		sugov_set_cluster_floor(cpu, c->floor_freq);
		sugov_set_cluster_pl(cpu, t->pl);
	}

	if (force)
		ki_cpufreq_reset_idle_floors(mode);

	kgsl_set_performance_mode(t->gpu_perf);
	sched_set_updown_migrate(t->up_migrate, t->down_migrate);
	sched_set_group_updown_migrate(t->grp_up_migrate, t->grp_down_migrate);
	sched_set_boost(t->sched_boost);

	sysctl_sched_window_stats_policy = t->window_stats_policy;

	/* Atomic thermal state switch under spinlock */
	spin_lock_irqsave(&ki_guard_lock, flags);
	ki_thermal_throttle_enabled = t->thermal_throttle;
	ki_guard_tripped = false;
	spin_unlock_irqrestore(&ki_guard_lock, flags);

	/* Thermal auto-guard runs only while thermal bypass is active */
	if (!t->thermal_throttle)
		mod_delayed_work(system_power_efficient_wq, &ki_guard_work, 0);
	else
		cancel_delayed_work(&ki_guard_work);

	/*
	 * Update VM watermarks only on explicit force switch (boot or user sysfs),
	 * never during rapid screen on/off to prevent zone lock contention & SoD.
	 */
	if (force) {
		vm_swappiness = t->swappiness;
		watermark_scale_factor = t->wmark_scale;
		watermark_boost_factor = 0;
		sysctl_compact_unevictable_allowed = 0;
		sysctl_vfs_cache_pressure = t->vfs_cache_pressure;
		setup_per_zone_wmarks();
	}

	WRITE_ONCE(ki_active_mode, mode);
	pr_info("ki_profile: %s profile active\n", profile_names[mode]);
	return err;
}

/* Profile that should be applied given user choice, screen state, and power supply */
static int ki_effective_mode(void)
{
	/*
	 * If connected to external power / charging, do NOT throttle to Battery Saver
	 * when screen is off. Android runs background maintenance (dexopt, fstrim) while
	 * charging and needs normal CPU capacity.
	 */
	if (power_supply_is_system_supplied() > 0)
		return READ_ONCE(current_profile_mode);

	if (ki_screen_off_battery && !READ_ONCE(ki_screen_on))
		return KI_PROFILE_BATTERY;
	return READ_ONCE(current_profile_mode);
}

/* Caller must hold ki_profile_mutex */
static int ki_apply_effective(bool force)
{
	int mode = ki_effective_mode();

	if (!force && mode == READ_ONCE(ki_active_mode))
		return 0;
	return apply_ki_profile(mode, force);
}

static void ki_screen_work_fn(struct work_struct *work)
{
	mutex_lock(&ki_profile_mutex);
	ki_apply_effective(false);
	mutex_unlock(&ki_profile_mutex);
}

static int ki_display_notifier_cb(struct notifier_block *nb,
				  unsigned long val, void *data)
{
	struct mi_drm_notifier *evdata = data;
	int blank;

	if (!evdata || !evdata->data || evdata->id != MSM_DRM_PRIMARY_DISPLAY)
		return NOTIFY_OK;

	blank = *(int *)evdata->data;

	/* Early unblank: restore profile before panel completes powering on */
	if (val == MI_DRM_EARLY_EVENT_BLANK && blank == MI_DRM_BLANK_UNBLANK) {
		if (!READ_ONCE(ki_screen_on)) {
			WRITE_ONCE(ki_screen_on, true);
			mod_delayed_work(system_highpri_wq, &ki_screen_work, 0);
		}
		return NOTIFY_OK;
	}

	if (val != MI_DRM_EVENT_BLANK)
		return NOTIFY_OK;

	switch (blank) {
	case MI_DRM_BLANK_UNBLANK:
		if (!READ_ONCE(ki_screen_on)) {
			WRITE_ONCE(ki_screen_on, true);
			mod_delayed_work(system_highpri_wq, &ki_screen_work, 0);
		}
		break;
	case MI_DRM_BLANK_LP1:
	case MI_DRM_BLANK_LP2:
	case MI_DRM_BLANK_STANDBY:
	case MI_DRM_BLANK_SUSPEND:
	case MI_DRM_BLANK_POWERDOWN:
		if (READ_ONCE(ki_screen_on)) {
			WRITE_ONCE(ki_screen_on, false);
			mod_delayed_work(system_power_efficient_wq, &ki_screen_work,
					 msecs_to_jiffies(KI_SCREEN_OFF_DELAY_MS));
		}
		break;
	default:
		break;
	}

	return NOTIFY_OK;
}

static struct notifier_block ki_display_nb = {
	.notifier_call = ki_display_notifier_cb,
};

static ssize_t mode_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", READ_ONCE(current_profile_mode));
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
	WRITE_ONCE(current_profile_mode, val);
	/* While screen is off the new choice is applied on next screen on */
	ki_apply_effective(true);
	mutex_unlock(&ki_profile_mutex);

	return count;
}

static ssize_t current_profile_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	int mode = READ_ONCE(current_profile_mode);
	const char *name = "unknown";

	if (mode >= 0 && mode < KI_PROFILE_MAX)
		name = profile_names[mode];

	return scnprintf(buf, PAGE_SIZE, "%s\n", name);
}

static ssize_t available_modes_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "0: Battery Saver\n1: Balanced\n2: Performance/Gaming Turbo\n");
}

static ssize_t active_profile_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	int mode = READ_ONCE(ki_active_mode);

	if (mode < 0 || mode >= KI_PROFILE_MAX)
		return scnprintf(buf, PAGE_SIZE, "unknown\n");
	return scnprintf(buf, PAGE_SIZE, "%s\n", profile_names[mode]);
}

static ssize_t screen_off_battery_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", ki_screen_off_battery ? 1 : 0);
}

static ssize_t screen_off_battery_store(struct kobject *kobj, struct kobj_attribute *attr,
					const char *buf, size_t count)
{
	bool val;

	if (kstrtobool(buf, &val))
		return -EINVAL;

	mutex_lock(&ki_profile_mutex);
	ki_screen_off_battery = val;
	ki_apply_effective(false);
	mutex_unlock(&ki_profile_mutex);

	return count;
}

static ssize_t thermal_throttle_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", READ_ONCE(ki_thermal_throttle_enabled) ? 1 : 0);
}

static struct kobj_attribute mode_attr = __ATTR_RW(mode);
static struct kobj_attribute current_profile_attr = __ATTR_RO(current_profile);
static struct kobj_attribute available_modes_attr = __ATTR_RO(available_modes);
static struct kobj_attribute thermal_throttle_attr = __ATTR_RO(thermal_throttle);
static struct kobj_attribute active_profile_attr = __ATTR_RO(active_profile);
static struct kobj_attribute screen_off_battery_attr = __ATTR_RW(screen_off_battery);

static struct attribute *ki_profile_attrs[] = {
	&mode_attr.attr,
	&current_profile_attr.attr,
	&available_modes_attr.attr,
	&thermal_throttle_attr.attr,
	&active_profile_attr.attr,
	&screen_off_battery_attr.attr,
	NULL,
};

static umode_t ki_profile_is_visible(struct kobject *kobj, struct attribute *attr, int n)
{
	if (attr == &mode_attr.attr || attr == &screen_off_battery_attr.attr)
		return 0644;
	return attr->mode; /* 0444 for RO attrs */
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
	err = ki_apply_effective(true);
	mutex_unlock(&ki_profile_mutex);

	if (err && boot_settle_retries < 6) {
		boot_settle_retries++;
		pr_info("ki_profile: sugov limits pending (err=%d), retrying in 5s (%d/6)\n",
			err, boot_settle_retries);
		schedule_delayed_work(&ki_profile_delayed_work, msecs_to_jiffies(5000));
		return;
	}

	pr_info("ki_profile: Boot settlement complete, profile %d (%s) active\n",
		READ_ONCE(current_profile_mode), profile_names[READ_ONCE(current_profile_mode)]);
}

static int __init ki_profile_init(void)
{
	int rc;

	/* 1. Initialize all delayed work queues BEFORE creating sysfs */
	INIT_DELAYED_WORK(&ki_guard_work, ki_guard_work_fn);
	INIT_DELAYED_WORK(&ki_screen_work, ki_screen_work_fn);
	INIT_DELAYED_WORK(&ki_profile_delayed_work, ki_profile_delayed_work_fn);

	/* 2. Create kobject and sysfs group */
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

	/* 3. Apply default profile */
	mutex_lock(&ki_profile_mutex);
	ki_apply_effective(true);
	mutex_unlock(&ki_profile_mutex);

	/* 4. Register MI DRM display notifier */
	rc = mi_drm_register_client(&ki_display_nb);
	if (rc)
		pr_warn("ki_profile: display notifier register failed (%d), screen-off battery disabled\n",
			rc);

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
