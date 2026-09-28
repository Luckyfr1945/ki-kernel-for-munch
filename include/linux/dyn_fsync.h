/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_DYN_FSYNC_H
#define _LINUX_DYN_FSYNC_H

#include <linux/types.h>

#ifdef CONFIG_DYNAMIC_FSYNC
extern bool dyn_fsync_active;
bool dyn_fsync_screen_is_on(void);

static inline bool dyn_fsync_should_skip(void)
{
	return dyn_fsync_active && dyn_fsync_screen_is_on();
}
#else
static inline bool dyn_fsync_should_skip(void)
{
	return false;
}
#endif

#endif /* _LINUX_DYN_FSYNC_H */
