/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (C) 2026 \xx / aerath
 * Built-in UID priority hiding for Ki-kernel
 */

#ifndef _LINUX_FGETPRIORITY_H
#define _LINUX_FGETPRIORITY_H

#include <linux/cred.h>
#include <linux/uidgid.h>
#include <linux/user_namespace.h>

#define FGP_MIN_APP_PROCESS_UID      10000
#define FGP_MIN_ISOLATED_PROCESS_UID 90000
#define FGP_AID_USER_OFFSET          100000

static inline bool fgetpriority_is_blocked(uid_t cuid, uid_t who)
{
	/* System/privileged callers (< 10000) are never filtered */
	if (unlikely(cuid < FGP_MIN_APP_PROCESS_UID || who < FGP_MIN_APP_PROCESS_UID))
		return false;

	if (unlikely(cuid >= FGP_AID_USER_OFFSET))
		cuid %= FGP_AID_USER_OFFSET;

	/* Convert isolated process to base app UID */
	if (unlikely(cuid >= FGP_MIN_ISOLATED_PROCESS_UID)) {
		struct user_namespace *ns = current_cred()->user_ns;
		if (ns && ns != &init_user_ns) {
			kuid_t host_kuid = make_kuid(ns, 0);
			if (uid_valid(host_kuid))
				cuid = from_kuid(&init_user_ns, host_kuid);
		}
	}

	if (unlikely(who >= FGP_MIN_ISOLATED_PROCESS_UID)) {
		struct user_namespace *ns = current_cred()->user_ns;
		if (ns && ns != &init_user_ns) {
			kuid_t host_kuid = make_kuid(ns, 0);
			if (uid_valid(host_kuid))
				who = from_kuid(&init_user_ns, host_kuid);
		}
	}

	if (unlikely(who >= FGP_AID_USER_OFFSET))
		who %= FGP_AID_USER_OFFSET;

	/* An app checking its own priority is allowed */
	if (likely(cuid == who))
		return false;

	/* Untrusted app attempting to probe another app UID is blocked */
	return true;
}

#endif /* _LINUX_FGETPRIORITY_H */
