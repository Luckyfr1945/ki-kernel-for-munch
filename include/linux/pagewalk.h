/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_PAGEWALK_H
#define _LINUX_PAGEWALK_H

#include <linux/mm.h>

struct mm_walk_ops {
	int (*p4d_entry)(p4d_t *p4d, unsigned long addr,
			 unsigned long next, struct mm_walk *walk);
	int (*pud_entry)(pud_t *pud, unsigned long addr,
			 unsigned long next, struct mm_walk *walk);
	int (*pmd_entry)(pmd_t *pmd, unsigned long addr,
			 unsigned long next, struct mm_walk *walk);
	int (*pte_entry)(pte_t *pte, unsigned long addr,
			 unsigned long next, struct mm_walk *walk);
	int (*pte_hole)(unsigned long addr, unsigned long next,
			struct mm_walk *walk);
	int (*hugetlb_entry)(pte_t *pte, unsigned long hmask,
			     unsigned long addr, unsigned long next,
			     struct mm_walk *walk);
	int (*test_walk)(unsigned long addr, unsigned long next,
			struct mm_walk *walk);
};

static inline int walk_page_range_ops(struct mm_struct *mm,
				     unsigned long start, unsigned long end,
				     const struct mm_walk_ops *ops,
				     void *private)
{
	struct mm_walk walk = {
		.p4d_entry = ops ? ops->p4d_entry : NULL,
		.pud_entry = ops ? ops->pud_entry : NULL,
		.pmd_entry = ops ? ops->pmd_entry : NULL,
		.pte_entry = ops ? ops->pte_entry : NULL,
		.pte_hole = ops ? ops->pte_hole : NULL,
		.hugetlb_entry = ops ? ops->hugetlb_entry : NULL,
		.test_walk = ops ? ops->test_walk : NULL,
		.mm = mm,
		.private = private,
	};

	return walk_page_range(start, end, &walk);
}

#define walk_page_range(mm, start, end, ops, priv) \
	walk_page_range_ops(mm, start, end, ops, priv)

#endif /* _LINUX_PAGEWALK_H */
