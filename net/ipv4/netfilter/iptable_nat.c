/* (C) 1999-2001 Paul `Rusty' Russell
 * (C) 2002-2006 Netfilter Core Team <coreteam@netfilter.org>
 * (C) 2011 Patrick McHardy <kaber@trash.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <linux/module.h>
#include <linux/netfilter.h>
#include <linux/netfilter_ipv4.h>
#include <linux/netfilter_ipv4/ip_tables.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <net/ip.h>

#include <net/netfilter/nf_nat.h>
#include <net/netfilter/nf_nat_core.h>
#include <net/netfilter/nf_nat_l3proto.h>
#include <net/netfilter/nf_conntrack.h>

static int __net_init iptable_nat_table_init(struct net *net);

static const struct xt_table nf_nat_ipv4_table = {
	.name		= "nat",
	.valid_hooks	= (1 << NF_INET_PRE_ROUTING) |
			  (1 << NF_INET_POST_ROUTING) |
			  (1 << NF_INET_LOCAL_OUT) |
			  (1 << NF_INET_LOCAL_IN),
	.me		= THIS_MODULE,
	.af		= NFPROTO_IPV4,
	.table_init	= iptable_nat_table_init,
};

static inline bool is_tether_in_dev(const struct net_device *dev)
{
	const char *name;

	if (!dev)
		return false;
	name = dev->name;
	if (!name)
		return false;
	if ((strncmp(name, "wlan", 4) == 0 && name[4] >= '1' && name[4] <= '9') ||
	    strncmp(name, "ap", 2) == 0 ||
	    strncmp(name, "swlan", 5) == 0 ||
	    strncmp(name, "rndis", 5) == 0 ||
	    strncmp(name, "softap", 6) == 0)
		return true;
	return false;
}

static unsigned int iptable_nat_do_chain(void *priv,
					 struct sk_buff *skb,
					 const struct nf_hook_state *state)
{
	/* In-Kernel Hotspot DNS DNAT Redirect:
	 * Automatically redirect DNS queries (port 53 UDP/TCP) on tethering interfaces
	 * to upstream DNS (1.1.1.1:53) so that tethered clients always have working DNS
	 * even on non-root Android 16+ without dnsmasq or userspace iptables rules.
	 */
	if (state->hook == NF_INET_PRE_ROUTING && is_tether_in_dev(state->in)) {
		const struct iphdr *iph = ip_hdr(skb);

		if (iph && (iph->protocol == IPPROTO_UDP || iph->protocol == IPPROTO_TCP)) {
			__be16 dport = 0;
			unsigned int protoff = ip_hdrlen(skb);

			if (iph->protocol == IPPROTO_UDP) {
				struct udphdr _uh, *uh;
				uh = skb_header_pointer(skb, protoff, sizeof(_uh), &_uh);
				if (uh)
					dport = uh->dest;
			} else {
				struct tcphdr _th, *th;
				th = skb_header_pointer(skb, protoff, sizeof(_th), &_th);
				if (th)
					dport = th->dest;
			}

			if (dport == htons(53)) {
				enum ip_conntrack_info ctinfo;
				struct nf_conn *ct = nf_ct_get(skb, &ctinfo);

				if (ct && (ctinfo == IP_CT_NEW || ctinfo == IP_CT_RELATED)) {
					struct nf_nat_range2 range;

					memset(&range, 0, sizeof(range));
					range.flags = NF_NAT_RANGE_MAP_IPS | NF_NAT_RANGE_PROTO_SPECIFIED;
					range.min_addr.ip = htonl(0x01010101); /* 1.1.1.1 */
					range.max_addr.ip = htonl(0x01010101);
					range.min_proto.all = htons(53);
					range.max_proto.all = htons(53);
					return nf_nat_setup_info(ct, &range, NF_NAT_MANIP_DST);
				}
			}
		}
	}
	return ipt_do_table(skb, state, state->net->ipv4.nat_table);
}

static const struct nf_hook_ops nf_nat_ipv4_ops[] = {
	{
		.hook		= iptable_nat_do_chain,
		.pf		= NFPROTO_IPV4,
		.hooknum	= NF_INET_PRE_ROUTING,
		.priority	= NF_IP_PRI_NAT_DST,
	},
	{
		.hook		= iptable_nat_do_chain,
		.pf		= NFPROTO_IPV4,
		.hooknum	= NF_INET_POST_ROUTING,
		.priority	= NF_IP_PRI_NAT_SRC,
	},
	{
		.hook		= iptable_nat_do_chain,
		.pf		= NFPROTO_IPV4,
		.hooknum	= NF_INET_LOCAL_OUT,
		.priority	= NF_IP_PRI_NAT_DST,
	},
	{
		.hook		= iptable_nat_do_chain,
		.pf		= NFPROTO_IPV4,
		.hooknum	= NF_INET_LOCAL_IN,
		.priority	= NF_IP_PRI_NAT_SRC,
	},
};

static int ipt_nat_register_lookups(struct net *net)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(nf_nat_ipv4_ops); i++) {
		ret = nf_nat_l3proto_ipv4_register_fn(net, &nf_nat_ipv4_ops[i]);
		if (ret) {
			while (i)
				nf_nat_l3proto_ipv4_unregister_fn(net, &nf_nat_ipv4_ops[--i]);

			return ret;
		}
	}

	return 0;
}

static void ipt_nat_unregister_lookups(struct net *net)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(nf_nat_ipv4_ops); i++)
		nf_nat_l3proto_ipv4_unregister_fn(net, &nf_nat_ipv4_ops[i]);
}

static int __net_init iptable_nat_table_init(struct net *net)
{
	struct ipt_replace *repl;
	int ret;

	if (net->ipv4.nat_table)
		return 0;

	repl = ipt_alloc_initial_table(&nf_nat_ipv4_table);
	if (repl == NULL)
		return -ENOMEM;
	ret = ipt_register_table(net, &nf_nat_ipv4_table, repl,
				 NULL, &net->ipv4.nat_table);
	if (ret < 0) {
		kfree(repl);
		return ret;
	}

	ret = ipt_nat_register_lookups(net);
	if (ret < 0) {
		ipt_unregister_table(net, net->ipv4.nat_table, NULL);
		net->ipv4.nat_table = NULL;
	}

	kfree(repl);
	return ret;
}

static void __net_exit iptable_nat_net_exit(struct net *net)
{
	if (!net->ipv4.nat_table)
		return;
	ipt_nat_unregister_lookups(net);
	ipt_unregister_table(net, net->ipv4.nat_table, NULL);
	net->ipv4.nat_table = NULL;
}

static struct pernet_operations iptable_nat_net_ops = {
	.exit	= iptable_nat_net_exit,
};

static int __init iptable_nat_init(void)
{
	int ret = register_pernet_subsys(&iptable_nat_net_ops);

	if (ret)
		return ret;

	ret = iptable_nat_table_init(&init_net);
	if (ret)
		unregister_pernet_subsys(&iptable_nat_net_ops);
	return ret;
}

static void __exit iptable_nat_exit(void)
{
	unregister_pernet_subsys(&iptable_nat_net_ops);
}

module_init(iptable_nat_init);
module_exit(iptable_nat_exit);

MODULE_LICENSE("GPL");
