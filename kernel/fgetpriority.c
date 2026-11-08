// SPDX-License-Identifier: GPL-2.0-only
/*
 * Built-in UID priority hiding for Ki-kernel
 */

#include <linux/init.h>
#include <linux/printk.h>

static int __init fgetpriority_init(void)
{
	pr_info("Ki-kernel: fgetpriority built-in UID hiding initialized\n");
	return 0;
}
core_initcall(fgetpriority_init);
