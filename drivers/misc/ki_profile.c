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
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
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
	const int total_zones = ARRAY_SIZE(ki_guard_die_zones) + 1;

	for (i = 0; i < ARRAY_SIZE(ki_guard_die_zones); i++) {
		if (!ki_guard_die_tz[i]) {
			tz = thermal_zone_get_zone_by_name(ki_guard_die_zones[i]);
			ki_guard_die_tz[i] = IS_ERR(tz) ? NULL : tz;
		}
		if (ki_guard_die_tz[i])
			valid_count++;
	}

	if (!ki_guard_skin_tz) {
		tz = thermal_zone_get_zone_by_name("quiet_therm");
		ki_guard_skin_tz = IS_ERR(tz) ? NULL : tz;
	}
	if (ki_guard_skin_tz)
		valid_count++;

	/* Only mark resolved if all expected thermal zones are found */
	if (valid_count == total_zones)
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
	unsigned int iowait_boost_max;	/* % (0 = disabled, 100 = full) */
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
			{ .up_us = 2000,  .down_us = 2000, .hispeed_freq = 1056000, .hispeed_load = 95, .iowait_boost_max = 0 },
			{ .up_us = 4000,  .down_us = 2000, .hispeed_freq = 1171200, .hispeed_load = 95, .iowait_boost_max = 0 },
			{ .up_us = 8000,  .down_us = 2000, .hispeed_freq = 1267200, .hispeed_load = 95, .iowait_boost_max = 0 },
		},
		.thermal_throttle = true,
		.up_migrate = 98, .down_migrate = 90,
		.grp_up_migrate = 100, .grp_down_migrate = 95,
		.window_stats_policy = 2,
		.swappiness = 60, .wmark_scale = 20, .vfs_cache_pressure = 80,
	},
	/*
	 * Balanced:
	 * Nyaman, super smooth, dan adem untuk harian & gaming santai (sosmed, chat, UI responsif).
	 * Schedutil up-rate instan 500us di semua cluster untuk merespons burst render tanpa micro-jank.
	 * Down-rate hold time diset stabil ke 20ms (20000us) sinkron dengan ritme frame display,
	 * mencegah clock bouncing / frequency thrashing yang memicu panas & micro-stutter (nyendat).
	 * Hispeed responsif: Silver 1.21GHz, Gold 1.65GHz, Prime 1.80GHz pada load 70-80%.
	 * Migrasi seimbang (up_migrate = 80, down_migrate = 70) agar game/app berat dibantu Gold tanpa lag.
	 * iowait_boost_max diredam (35% Silver, 20% Gold, 0% Prime) agar scroll video (TikTok/IG) adem & irit.
	 * Swappiness = 80, Wmark = 20, vfs_cache_pressure = 80 (anti-kill multitasking & kswapd sleep).
	 */
	[KI_PROFILE_BALANCED] = {
		.cl = {
			{ .up_us = 500, .down_us = 20000, .hispeed_freq = 1209600, .hispeed_load = 80, .iowait_boost_max = 35 },
			{ .up_us = 500, .down_us = 20000, .hispeed_freq = 1651200, .hispeed_load = 70, .iowait_boost_max = 20 },
			{ .up_us = 500, .down_us = 20000, .hispeed_freq = 1804800, .hispeed_load = 70, .iowait_boost_max = 0 },
		},
		.thermal_throttle = true,
		.up_migrate = 80, .down_migrate = 70,
		.grp_up_migrate = 90, .grp_down_migrate = 80,
		.window_stats_policy = 2,
		.swappiness = 80, .wmark_scale = 20, .vfs_cache_pressure = 80,
	},
	/*
	 * Performance / Gaming Turbo (Optimized):
	 *  - Zero-lag ramp up (up_us: 0), frame-synchronized down hold (16-20ms)
	 *    prevents clock-bouncing without wasting power during scene pauses.
	 *  - Responsive floors (Silver 691M, Gold 1.05G, Prime 1.07G) eliminate idle drain.
	 *  - Efficient gaming hispeeds (Gold 2.15G @ 60% load, Prime 2.65G @ 65% load),
	 *    scaling naturally to 2.42G / 3.19G (3.2GHz) on heavy sustained spikes.
	 *  - Clean cluster separation (up_migrate 65/50) isolates game threads from background noise.
	 *  - MAX_RECENT_AVG window stats + swappiness 60 prevents zRAM stalls & micro-stutters.
	 *  - GPU perf mode + thermal auto-guard protection.
	 */
	[KI_PROFILE_PERFORMANCE] = {
		.cl = {
			{ .up_us = 0, .down_us = 10000, .hispeed_freq = 1420800, .hispeed_load = 70, .rtg_boost_freq = 1420800, .floor_freq = 691200, .iowait_boost_max = 100 },
			{ .up_us = 0, .down_us = 16000, .hispeed_freq = 2150400, .hispeed_load = 60, .rtg_boost_freq = 2150400, .floor_freq = 1056000, .iowait_boost_max = 100 },
			{ .up_us = 0, .down_us = 20000, .hispeed_freq = 2649600, .hispeed_load = 65, .rtg_boost_freq = 2649600, .floor_freq = 1075200, .iowait_boost_max = 100 },
		},
		.pl = true,
		.gpu_perf = true,
		.thermal_throttle = false,
		.sched_boost = 0,
		.up_migrate = 65, .down_migrate = 50,
		.grp_up_migrate = 75, .grp_down_migrate = 60,
		.window_stats_policy = 2,
		.swappiness = 60, .wmark_scale = 20, .vfs_cache_pressure = 80,
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
		sugov_set_cluster_iowait_boost(cpu, c->iowait_boost_max);
		sugov_set_cluster_pl(cpu, t->pl);
	}

	if (force)
		ki_cpufreq_reset_idle_floors(mode);

	kgsl_set_performance_mode(t->gpu_perf);
	sched_set_updown_migrate(t->up_migrate, t->down_migrate);
	sched_set_group_updown_migrate(t->grp_up_migrate, t->grp_down_migrate);
	sched_set_boost(t->sched_boost);

	sysctl_sched_window_stats_policy = t->window_stats_policy;

	/* Atomic thermal & active mode state switch under spinlock */
	spin_lock_irqsave(&ki_guard_lock, flags);
	WRITE_ONCE(ki_active_mode, mode);
	ki_thermal_throttle_enabled = t->thermal_throttle;
	ki_guard_tripped = false;
	spin_unlock_irqrestore(&ki_guard_lock, flags);

	/* Thermal auto-guard runs only while thermal bypass is active */
	if (!t->thermal_throttle)
		mod_delayed_work(system_power_efficient_wq, &ki_guard_work, 0);
	else
		cancel_delayed_work_sync(&ki_guard_work);

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

static int ki_psy_notifier_cb(struct notifier_block *nb,
			      unsigned long event, void *data)
{
	struct power_supply *psy = data;

	if (event != PSY_EVENT_PROP_CHANGED || !psy || !psy->desc || !psy->desc->name)
		return NOTIFY_OK;

	if (!strcmp(psy->desc->name, "battery") || !strcmp(psy->desc->name, "usb")) {
		if (!READ_ONCE(ki_screen_on)) {
			mod_delayed_work(system_power_efficient_wq, &ki_screen_work,
					 msecs_to_jiffies(1000));
		}
	}
	return NOTIFY_OK;
}

static struct notifier_block ki_psy_nb = {
	.notifier_call = ki_psy_notifier_cb,
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

/*
 * Non-root userspace control interface via /proc/ki_profile
 * Allows Termux, Tasker, shell scripts, and unprivileged apps to switch profiles.
 */
static ssize_t ki_profile_proc_read(struct file *file, char __user *buf,
		size_t count, loff_t *ppos)
{
	char kbuf[32];
	int len;
	int mode = READ_ONCE(current_profile_mode);
	const char *name = "unknown";

	if (*ppos != 0)
		return 0;

	if (mode >= 0 && mode < KI_PROFILE_MAX)
		name = profile_names[mode];

	len = scnprintf(kbuf, sizeof(kbuf), "%d (%s)\n", mode, name);
	if (copy_to_user(buf, kbuf, len))
		return -EFAULT;

	*ppos += len;
	return len;
}

static ssize_t ki_profile_proc_write(struct file *file, const char __user *buf,
		size_t count, loff_t *ppos)
{
	char kbuf[32];
	int val = -1;
	char *trimmed;

	if (count == 0 || count >= sizeof(kbuf))
		return -EINVAL;

	if (copy_from_user(kbuf, buf, count))
		return -EFAULT;

	kbuf[count] = '\0';
	trimmed = strim(kbuf);

	if (!strcmp(trimmed, "0") || !strcasecmp(trimmed, "battery"))
		val = KI_PROFILE_BATTERY;
	else if (!strcmp(trimmed, "1") || !strcasecmp(trimmed, "balanced"))
		val = KI_PROFILE_BALANCED;
	else if (!strcmp(trimmed, "2") || !strcasecmp(trimmed, "performance"))
		val = KI_PROFILE_PERFORMANCE;
	else if (!kstrtoint(trimmed, 10, &val)) {
		if (val < 0 || val >= KI_PROFILE_MAX)
			return -EINVAL;
	} else {
		return -EINVAL;
	}

	mutex_lock(&ki_profile_mutex);
	WRITE_ONCE(current_profile_mode, val);
	ki_apply_effective(true);
	mutex_unlock(&ki_profile_mutex);

	return count;
}

static const struct file_operations ki_profile_proc_fops = {
	.owner = THIS_MODULE,
	.read = ki_profile_proc_read,
	.write = ki_profile_proc_write,
	.llseek = default_llseek,
};

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

	{
		int active = ki_get_active_profile();
		const char *active_name = (active >= 0 && active < KI_PROFILE_MAX) ?
					  profile_names[active] : "unknown";

		pr_info("ki_profile: Boot settlement complete, profile %d (%s) active\n",
			active, active_name);
	}
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

	/* Non-root unprivileged interface */
	proc_create("ki_profile", 0666, NULL, &ki_profile_proc_fops);

	/* 3. Apply default profile */
	mutex_lock(&ki_profile_mutex);
	ki_apply_effective(true);
	mutex_unlock(&ki_profile_mutex);

	/* 4. Register MI DRM display notifier */
	rc = mi_drm_register_client(&ki_display_nb);
	if (rc)
		pr_warn("ki_profile: display notifier register failed (%d), screen-off battery disabled\n",
			rc);

	/* 5. Register Power Supply notifier for charging state changes while screen off */
	rc = power_supply_reg_notifier(&ki_psy_nb);
	if (rc)
		pr_warn("ki_profile: power supply notifier register failed (%d)\n", rc);

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
