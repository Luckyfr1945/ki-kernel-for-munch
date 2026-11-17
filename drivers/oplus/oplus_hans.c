// SPDX-License-Identifier: GPL-2.0-only
/*
 * OPlus HANS (ofreezer) generic netlink endpoint for ColorOS/OxygenOS ports.
 *
 * ColorOS 16/17 freezer daemons talk to the kernel through the "oplus_hans"
 * generic netlink family (see OnePlusOSS vendor/oplus/kernel/hans). This
 * kernel has no binder/signal vendor hooks to report unfreeze events, so only
 * the handshake is implemented: LOOP_BACK is answered with the cpuctl version
 * and the cgroup v2 capability, which makes the framework freeze apps through
 * cgroup.freeze (supported here). PKG and FROZEN_TRANS requests are accepted
 * and ignored.
 */

#include <linux/atomic.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/string.h>
#include <net/genetlink.h>

#define HANS_FAMILY		"oplus_hans"
#define HANS_FAMILY_VERSION	1
#define NETLINK_PORT_HANS	0x15356
#define INTERFACETOKEN_BUFF_SIZE 140
#define CPUCTL_VERSION		2
#define HANS_USE_CGRPV2		(-99)
#define CHECK_KERN_SUPPORT_CGRPV2 (-8000)

enum {
	HANS_ATTR_MSG_UNDEFINE = 0,
	HANS_ATTR_MSG_GENL,
	__HANS_ATTR_MSG_MAX
};
#define HANS_ATTR_MSG_MAX (__HANS_ATTR_MSG_MAX - 1)

enum {
	HANS_CMD_UNDEFINE = 0,
	HANS_CMD_GENL,
};

enum hans_msg_type {
	ASYNC_BINDER,
	SYNC_BINDER,
	FROZEN_TRANS,
	SIGNAL,
	PKG,
	SYNC_BINDER_CPUCTL,
	SIGNAL_CPUCTL,
	CPUCTL_TRANS,
	LOOP_BACK,
	TYPE_MAX
};

/* Layout must match the ColorOS native daemon */
struct hans_message {
	int type;
	int port;
	int caller_uid;
	int caller_pid;
	int target_pid;
	int target_uid;
	int pkg_cmd;
	int code;
	char rpc_name[INTERFACETOKEN_BUFF_SIZE];
	int persistent;
};

static atomic_t hans_daemon_port = ATOMIC_INIT(-1);
static struct genl_family hans_genl_family;

static int hans_report(int type, const char *rpc_name, int code)
{
	struct hans_message data = {
		.type = type,
		.port = NETLINK_PORT_HANS,
		.caller_uid = -1,
		.caller_pid = -1,
		.target_pid = -1,
		.target_uid = -1,
		.pkg_cmd = -1,
		.code = code,
	};
	int port = atomic_read(&hans_daemon_port);
	struct sk_buff *skb;
	void *head;

	if (port < 0)
		return -ENOTCONN;

	strlcpy(data.rpc_name, rpc_name, sizeof(data.rpc_name));

	skb = genlmsg_new(nla_total_size(sizeof(data)), GFP_KERNEL);
	if (!skb)
		return -ENOMEM;

	head = genlmsg_put(skb, port, 0, &hans_genl_family, 0, HANS_CMD_GENL);
	if (!head || nla_put(skb, HANS_ATTR_MSG_GENL, sizeof(data), &data)) {
		kfree_skb(skb);
		return -EMSGSIZE;
	}
	genlmsg_end(skb, head);

	return genlmsg_unicast(&init_net, skb, port);
}

static int hans_handler(struct sk_buff *skb, struct genl_info *info)
{
	const struct nlattr *nla = nlmsg_attrdata(info->nlhdr, GENL_HDRLEN);
	int len = nlmsg_attrlen(info->nlhdr, GENL_HDRLEN);
	const struct hans_message *data;

	/* The ofreezer 1.0 daemon omits the trailing 'persistent' field */
	if (len < NLA_HDRLEN || nla_type(nla) != HANS_ATTR_MSG_GENL ||
	    nla_len(nla) < (int)(sizeof(*data) - sizeof(int)))
		return -EINVAL;

	data = nla_data(nla);
	if (data->port < 0 || data->type < 0 || data->type >= TYPE_MAX)
		return -EINVAL;

	switch (data->type) {
	case LOOP_BACK:
		atomic_set(&hans_daemon_port, data->port);
		hans_report(LOOP_BACK, "loop back", CPUCTL_VERSION);
		hans_report(PKG, "PKG", HANS_USE_CGRPV2);
		pr_info("oplus_hans: handshake with port %d\n", data->port);
		break;
	case FROZEN_TRANS:
	case CPUCTL_TRANS:
		if (data->target_uid == CHECK_KERN_SUPPORT_CGRPV2)
			hans_report(PKG, "PKG", HANS_USE_CGRPV2);
		break;
	default:
		break;
	}
	return 0;
}

static const struct genl_ops hans_genl_ops[] = {
	{
		.cmd = HANS_CMD_GENL,
		.doit = hans_handler,
	},
};

static struct genl_family hans_genl_family = {
	.name = HANS_FAMILY,
	.version = HANS_FAMILY_VERSION,
	.maxattr = HANS_ATTR_MSG_MAX,
	.module = THIS_MODULE,
	.ops = hans_genl_ops,
	.n_ops = ARRAY_SIZE(hans_genl_ops),
};

static int __init oplus_hans_init(void)
{
	int ret = genl_register_family(&hans_genl_family);

	if (ret)
		pr_err("oplus_hans: genl_register_family failed: %d\n", ret);
	return ret;
}
device_initcall(oplus_hans_init);
