/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _BOEFFLA_WL_BLOCKER_H
#define _BOEFFLA_WL_BLOCKER_H

#define LENGTH_LIST_WL 2048
#define LENGTH_LIST_WL_DEFAULT 512
#define LENGTH_LIST_WL_SEARCH 2560

#ifdef CONFIG_BOEFFLA_WL_BLOCKER
bool is_wakelock_blocked(const char *name);
void boeffla_wl_blocker_relax_blocked(void);
#else
static inline bool is_wakelock_blocked(const char *name) { return false; }
static inline void boeffla_wl_blocker_relax_blocked(void) {}
#endif

#endif /* _BOEFFLA_WL_BLOCKER_H */
