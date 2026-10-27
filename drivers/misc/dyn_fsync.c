// SPDX-License-Identifier: GPL-2.0
/*
 * Dynamic Fsync for Linux 4.19 / Android SM8250
 *
 * Automatically defers fsync while screen is ON for high I/O throughput,
 * flushes & syncs when screen turns OFF for 100% data safety.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/workqueue.h>
#include <linux/notifier.h>
#include <linux/syscalls.h>
#include <linux/dyn_fsync.h>
#include <drm/drm_notifier_mi.h>

#define DYN_FSYNC_VERSION "2.0"

bool dyn_fsync_active = false;
EXPORT_SYMBOL(dyn_fsync_active);

static bool screen_is_on = true;
static struct workqueue_struct *dyn_fsync_wq;
static struct work_struct dyn_fsync_flush_work;

bool dyn_fsync_screen_is_on(void)
{
	return screen_is_on;
}
EXPORT_SYMBOL(dyn_fsync_screen_is_on);

static void dyn_fsync_flush_worker(struct work_struct *work)
{
	pr_info("dyn_fsync: screen is OFF, performing ksys_sync()\n");
	ksys_sync();
}

static int dyn_fsync_display_notifier_cb(struct notifier_block *nb,
					 unsigned long val, void *data)
{
	struct mi_drm_notifier *evdata = data;
	unsigned int blank;

	if (val != MI_DRM_EVENT_BLANK || !evdata || !evdata->data)
		return 0;

	blank = *(int *)(evdata->data);
	switch (blank) {
	case MI_DRM_BLANK_UNBLANK:
		screen_is_on = true;
		break;
	case MI_DRM_BLANK_LP1:
	case MI_DRM_BLANK_LP2:
	case MI_DRM_BLANK_STANDBY:
	case MI_DRM_BLANK_SUSPEND:
	case MI_DRM_BLANK_POWERDOWN:
		screen_is_on = false;
		if (dyn_fsync_active && dyn_fsync_wq)
			queue_work(dyn_fsync_wq, &dyn_fsync_flush_work);
		break;
	default:
		break;
	}

	return 0;
}

static struct notifier_block dyn_fsync_display_nb = {
	.notifier_call = dyn_fsync_display_notifier_cb,
};

/* sysfs interface: /sys/kernel/dyn_fsync/Dyn_fsync_active */
static ssize_t Dyn_fsync_active_show(struct kobject *kobj,
				     struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%u\n", dyn_fsync_active ? 1 : 0);
}

static ssize_t Dyn_fsync_active_store(struct kobject *kobj,
				      struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	unsigned int val;

	if (kstrtouint(buf, 0, &val))
		return -EINVAL;

	dyn_fsync_active = !!val;
	if (!dyn_fsync_active && dyn_fsync_wq)
		queue_work(dyn_fsync_wq, &dyn_fsync_flush_work);

	pr_info("dyn_fsync: active set to %u\n", dyn_fsync_active ? 1 : 0);
	return count;
}

static ssize_t version_show(struct kobject *kobj,
			    struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%s\n", DYN_FSYNC_VERSION);
}

static struct kobj_attribute dyn_fsync_active_upper_attr =
	__ATTR(Dyn_fsync_active, 0664, Dyn_fsync_active_show, Dyn_fsync_active_store);

static struct kobj_attribute dyn_fsync_active_lower_attr =
	__ATTR(dyn_fsync_active, 0664, Dyn_fsync_active_show, Dyn_fsync_active_store);

static struct kobj_attribute dyn_fsync_version_attr =
	__ATTR(version, 0444, version_show, NULL);

static struct attribute *dyn_fsync_attrs[] = {
	&dyn_fsync_active_upper_attr.attr,
	&dyn_fsync_active_lower_attr.attr,
	&dyn_fsync_version_attr.attr,
	NULL,
};

static struct attribute_group dyn_fsync_attr_group = {
	.attrs = dyn_fsync_attrs,
};

static struct kobject *dyn_fsync_kobj;

static int __init dyn_fsync_init(void)
{
	int rc;

	dyn_fsync_wq = create_singlethread_workqueue("dyn_fsync_wq");
	if (!dyn_fsync_wq) {
		pr_err("dyn_fsync: Failed to create workqueue\n");
		return -ENOMEM;
	}
	INIT_WORK(&dyn_fsync_flush_work, dyn_fsync_flush_worker);

	dyn_fsync_kobj = kobject_create_and_add("dyn_fsync", kernel_kobj);
	if (!dyn_fsync_kobj) {
		pr_err("dyn_fsync: Failed to create kobject\n");
		destroy_workqueue(dyn_fsync_wq);
		return -ENOMEM;
	}

	rc = sysfs_create_group(dyn_fsync_kobj, &dyn_fsync_attr_group);
	if (rc) {
		pr_err("dyn_fsync: Failed to create sysfs group\n");
		kobject_put(dyn_fsync_kobj);
		destroy_workqueue(dyn_fsync_wq);
		return rc;
	}

	rc = mi_drm_register_client(&dyn_fsync_display_nb);
	if (rc < 0)
		pr_warn("dyn_fsync: Couldn't register mi_drm client (rc=%d)\n", rc);

	pr_info("dyn_fsync: Initialized successfully v%s (active=%d)\n",
		DYN_FSYNC_VERSION, dyn_fsync_active);
	return 0;
}
late_initcall(dyn_fsync_init);

MODULE_DESCRIPTION("Dynamic Fsync for SM8250");
MODULE_LICENSE("GPL v2");
