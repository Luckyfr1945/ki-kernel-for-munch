/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _NET_KI_TETHER_H
#define _NET_KI_TETHER_H

#include <linux/netdevice.h>
#include <linux/string.h>

/*
 * Downstream (hotspot / USB tethering) interfaces. Forwarded packets that
 * leave through any other interface go to the carrier upstream.
 */
static inline bool ki_is_tether_dev(const struct net_device *dev)
{
	const char *name;

	if (!dev)
		return false;
	name = dev->name;
	return (!strncmp(name, "wlan", 4) && name[4] >= '1' && name[4] <= '9') ||
	       !strncmp(name, "ap", 2) ||
	       !strncmp(name, "swlan", 5) ||
	       !strncmp(name, "rndis", 5) ||
	       !strncmp(name, "ncm", 3) ||
	       !strncmp(name, "ecm", 3) ||
	       !strncmp(name, "usb", 3) ||
	       !strncmp(name, "bt-pan", 6) ||
	       !strncmp(name, "softap", 6);
}

#endif /* _NET_KI_TETHER_H */
