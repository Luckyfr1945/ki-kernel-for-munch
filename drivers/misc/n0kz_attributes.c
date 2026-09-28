// SPDX-License-Identifier: GPL-2.0
/*
 * N0Kontzzz Kernel Attributes Driver
 *
 * Exposes /sys/kernel/n0kz_attributes/ sysfs group for compatibility
 * with N0Kontzzz Kernel Manager (NKM).
 *
 * Nodes:
 *   bg_blocklist       - Background app blocker (package list, newline-separated)
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/string.h>
#include <linux/mutex.h>
#include <linux/slab.h>

#define BG_BLOCKLIST_MAX 4096

static DEFINE_MUTEX(n0kz_mutex);

/* --- bg_blocklist --- */
static char bg_blocklist_buf[BG_BLOCKLIST_MAX] = "";

static ssize_t bg_blocklist_show(struct kobject *kobj,
				 struct kobj_attribute *attr, char *buf)
{
	ssize_t len;

	mutex_lock(&n0kz_mutex);
	len = scnprintf(buf, PAGE_SIZE, "%s", bg_blocklist_buf);
	mutex_unlock(&n0kz_mutex);
	return len;
}

static ssize_t bg_blocklist_store(struct kobject *kobj,
				  struct kobj_attribute *attr,
				  const char *buf, size_t count)
{
	if (count >= BG_BLOCKLIST_MAX)
		return -EINVAL;

	mutex_lock(&n0kz_mutex);
	strncpy(bg_blocklist_buf, buf, count);
	bg_blocklist_buf[count] = '\0';
	mutex_unlock(&n0kz_mutex);

	pr_info("n0kz_attributes: bg_blocklist updated (%zu bytes)\n", count);
	return count;
}

static struct kobj_attribute bg_blocklist_attr = __ATTR_RW(bg_blocklist);

static struct attribute *n0kz_attrs[] = {
	&bg_blocklist_attr.attr,
	NULL,
};

static const struct attribute_group n0kz_attr_group = {
	.attrs = n0kz_attrs,
};

static struct kobject *n0kz_kobj;

static int __init n0kz_attributes_init(void)
{
	int rc;

	n0kz_kobj = kobject_create_and_add("n0kz_attributes", kernel_kobj);
	if (!n0kz_kobj) {
		pr_err("n0kz_attributes: failed to create kobject\n");
		return -ENOMEM;
	}

	rc = sysfs_create_group(n0kz_kobj, &n0kz_attr_group);
	if (rc) {
		pr_err("n0kz_attributes: failed to create sysfs group\n");
		kobject_put(n0kz_kobj);
		return rc;
	}

	pr_info("n0kz_attributes: initialized (NKM compatibility layer)\n");
	return 0;
}
late_initcall(n0kz_attributes_init);

MODULE_DESCRIPTION("N0Kontzzz Kernel Attributes (NKM compatibility)");
MODULE_LICENSE("GPL v2");
