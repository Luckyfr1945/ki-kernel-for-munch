// SPDX-License-Identifier: GPL-2.0
/*
 * Boeffla Wakelock Blocker
 *
 * Implements a generic sysfs interface to block selected wakelocks
 * from keeping the device awake, significantly boosting deep sleep time.
 * Fully compatible with NKM (N0Kontzzz Kernel Manager), FKM (Franco Kernel Manager),
 * EXKM, and SmartPack-Kernel Manager.
 *
 * Author: andip71 (original design)
 * Hardened & modernized for Linux 4.19 / Android SM8250
 */

#include <linux/module.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/device.h>
#include <linux/miscdevice.h>
#include <linux/printk.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include "boeffla_wl_blocker.h"

#define DRIVER_VERSION "1.1.0"

/* Default blocked wakelocks on SM8250 known for idle drain */
#define DEFAULT_BLOCKED_WAKELOCKS \
	"wlan_pno_wl;wlan_extscan_wl;wlan_wow_wl;netmgr_wl;"

static char list_wl[LENGTH_LIST_WL] = {0};
static char list_wl_default[LENGTH_LIST_WL_DEFAULT] = {0};
static char list_wl_search[LENGTH_LIST_WL_SEARCH] = {0};

static DEFINE_SPINLOCK(wl_blocker_lock);

static bool wl_blocker_active = false;
static bool wl_blocker_debug = false;

/*
 * Critical wakeups that MUST NEVER be blocked to preserve 100% reliable
 * alarms, phone calls, WhatsApp/VoIP calls, FCM push notifications,
 * power key / fingerprint wakeups, and display wakeups.
 */
static bool is_critical_wakelock(const char *name)
{
	if (!name)
		return true;

	if (strstr(name, "alarmtimer") ||
	    strstr(name, "alarm") ||
	    strstr(name, "rtc") ||
	    strstr(name, "event") ||
	    strstr(name, "gpio_keys") ||
	    strstr(name, "fingerprint") ||
	    strstr(name, "fp_wakelock") ||
	    strstr(name, "fpc") ||
	    strstr(name, "qcom_rx_wakelock") ||
	    strstr(name, "IPA_WS") ||
	    strstr(name, "IPA_CLIENT") ||
	    strstr(name, "AudioMix") ||
	    strstr(name, "msm_drm") ||
	    strstr(name, "display"))
		return true;

	return false;
}

static void build_search_string(const char *list1, const char *list2)
{
	unsigned long flags;

	spin_lock_irqsave(&wl_blocker_lock, flags);

	snprintf(list_wl_search, sizeof(list_wl_search), ";%s;%s;", list1, list2);

	/* Set flag if search string contains actual entries beyond delimiters */
	if (strlen(list_wl_search) > 4)
		wl_blocker_active = true;
	else
		wl_blocker_active = false;

	spin_unlock_irqrestore(&wl_blocker_lock, flags);

	/* Relax any matching wakelocks currently active */
	boeffla_wl_blocker_relax_blocked();
}

bool is_wakelock_blocked(const char *name)
{
	char search_pattern[128];
	unsigned long flags;
	bool blocked = false;

	if (!wl_blocker_active || !name)
		return false;

	/* Never block system-critical wakeups */
	if (is_critical_wakelock(name))
		return false;

	if (snprintf(search_pattern, sizeof(search_pattern), ";%s;", name) >= sizeof(search_pattern))
		return false;

	spin_lock_irqsave(&wl_blocker_lock, flags);
	if (strstr(list_wl_search, search_pattern))
		blocked = true;
	spin_unlock_irqrestore(&wl_blocker_lock, flags);

	if (blocked && unlikely(wl_blocker_debug))
		pr_info("boeffla_wl_blocker: blocked %s\n", name);

	return blocked;
}
EXPORT_SYMBOL_GPL(is_wakelock_blocked);

/* sysfs: wakelock_blocker */
static ssize_t wakelock_blocker_show(struct device *dev,
				     struct device_attribute *attr, char *buf)
{
	unsigned long flags;
	ssize_t ret;

	spin_lock_irqsave(&wl_blocker_lock, flags);
	ret = sprintf(buf, "%s\n", list_wl);
	spin_unlock_irqrestore(&wl_blocker_lock, flags);

	return ret;
}

static ssize_t wakelock_blocker_store(struct device *dev,
				      struct device_attribute *attr,
				      const char *buf, size_t count)
{
	unsigned long flags;
	size_t len = count;

	if (len >= LENGTH_LIST_WL)
		return -EINVAL;

	spin_lock_irqsave(&wl_blocker_lock, flags);
	strncpy(list_wl, buf, len);
	list_wl[len] = '\0';

	/* Strip trailing newline */
	if (len > 0 && list_wl[len - 1] == '\n')
		list_wl[len - 1] = '\0';
	spin_unlock_irqrestore(&wl_blocker_lock, flags);

	build_search_string(list_wl, list_wl_default);

	return count;
}
static DEVICE_ATTR_RW(wakelock_blocker);

/* sysfs: wakelock_blocker_default & default_wakelocks */
static ssize_t wakelock_blocker_default_show(struct device *dev,
					     struct device_attribute *attr,
					     char *buf)
{
	unsigned long flags;
	ssize_t ret;

	spin_lock_irqsave(&wl_blocker_lock, flags);
	ret = sprintf(buf, "%s\n", list_wl_default);
	spin_unlock_irqrestore(&wl_blocker_lock, flags);

	return ret;
}

static ssize_t wakelock_blocker_default_store(struct device *dev,
					      struct device_attribute *attr,
					      const char *buf, size_t count)
{
	unsigned long flags;
	size_t len = count;

	if (len >= LENGTH_LIST_WL_DEFAULT)
		return -EINVAL;

	spin_lock_irqsave(&wl_blocker_lock, flags);
	strncpy(list_wl_default, buf, len);
	list_wl_default[len] = '\0';

	if (len > 0 && list_wl_default[len - 1] == '\n')
		list_wl_default[len - 1] = '\0';
	spin_unlock_irqrestore(&wl_blocker_lock, flags);

	build_search_string(list_wl, list_wl_default);

	return count;
}
static DEVICE_ATTR_RW(wakelock_blocker_default);

static struct device_attribute dev_attr_default_wakelocks = {
	.attr = { .name = "default_wakelocks", .mode = 0644 },
	.show = wakelock_blocker_default_show,
	.store = wakelock_blocker_default_store,
};

/* sysfs: version */
static ssize_t version_show(struct device *dev,
			    struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "%s\n", DRIVER_VERSION);
}
static DEVICE_ATTR_RO(version);

/* sysfs: debug */
static ssize_t debug_show(struct device *dev,
			  struct device_attribute *attr, char *buf)
{
	return sprintf(buf, "%u\n", wl_blocker_debug ? 1 : 0);
}

static ssize_t debug_store(struct device *dev,
			   struct device_attribute *attr,
			   const char *buf, size_t count)
{
	unsigned int val;

	if (kstrtouint(buf, 0, &val))
		return -EINVAL;

	wl_blocker_debug = !!val;
	return count;
}
static DEVICE_ATTR_RW(debug);

static struct attribute *boeffla_wl_blocker_attrs[] = {
	&dev_attr_wakelock_blocker.attr,
	&dev_attr_wakelock_blocker_default.attr,
	&dev_attr_default_wakelocks.attr,
	&dev_attr_version.attr,
	&dev_attr_debug.attr,
	NULL,
};

static const struct attribute_group boeffla_wl_blocker_group = {
	.attrs = boeffla_wl_blocker_attrs,
};

static struct miscdevice boeffla_wl_blocker_device = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "boeffla_wakelock_blocker",
};

static int __init boeffla_wl_blocker_init(void)
{
	int ret;

	ret = misc_register(&boeffla_wl_blocker_device);
	if (ret) {
		pr_err("boeffla_wl_blocker: misc_register failed (%d)\n", ret);
		return ret;
	}

	ret = sysfs_create_group(&boeffla_wl_blocker_device.this_device->kobj,
				 &boeffla_wl_blocker_group);
	if (ret) {
		pr_err("boeffla_wl_blocker: sysfs_create_group failed (%d)\n", ret);
		misc_deregister(&boeffla_wl_blocker_device);
		return ret;
	}

	/* Initialize with default list */
	strncpy(list_wl_default, DEFAULT_BLOCKED_WAKELOCKS, sizeof(list_wl_default) - 1);
	build_search_string(list_wl, list_wl_default);

	pr_info("boeffla_wl_blocker: v%s registered successfully\n", DRIVER_VERSION);
	return 0;
}
late_initcall(boeffla_wl_blocker_init);

MODULE_AUTHOR("andip71");
MODULE_DESCRIPTION("Boeffla generic wakelock blocker");
MODULE_LICENSE("GPL v2");
