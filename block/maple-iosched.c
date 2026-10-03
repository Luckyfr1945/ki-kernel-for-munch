// SPDX-License-Identifier: GPL-2.0
/*
 * Maple I/O Scheduler
 * Based on Zen and SIO.
 *
 * Copyright (C) 2012 Brandon Berhent <frap129@gmail.com>
 *
 * An I/O scheduler tailored for flash memory devices (eMMC/UFS) on Android.
 * Favors synchronous read requests over asynchronous background flushes
 * to minimize UI freezes and application launch latencies.
 */
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/blkdev.h>
#include <linux/elevator.h>
#include <linux/bio.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/init.h>
#include <linux/compiler.h>
#include <linux/rbtree.h>

enum { ASYNC, SYNC };

static const int sync_expire = HZ / 4;    /* 250ms for sync requests (reads/interactive) */
static const int async_expire = 2 * HZ;   /* 2000ms for async requests (background writes) */
static const int writes_starved = 4;     /* Max times sync can starve async */
static const int fifo_batch = 16;        /* Batch dispatch size */

struct maple_data {
	struct rb_root sort_list[2];
	struct list_head fifo_list[2];

	struct request *next_rq[2];
	unsigned int batching;
	unsigned int starved;

	int fifo_expire[2];
	int fifo_batch;
	int writes_starved;
	int front_merges;
};

static inline struct rb_root *
maple_rb_root(struct maple_data *md, struct request *rq)
{
	return &md->sort_list[rq_is_sync(rq) ? SYNC : ASYNC];
}

static inline struct request *
maple_latter_request(struct request *rq)
{
	struct rb_node *node = rb_next(&rq->rb_node);

	if (node)
		return rb_entry_rq(node);

	return NULL;
}

static void
maple_add_rq_rb(struct maple_data *md, struct request *rq)
{
	struct rb_root *root = maple_rb_root(md, rq);

	elv_rb_add(root, rq);
}

static inline void
maple_del_rq_rb(struct maple_data *md, struct request *rq)
{
	const int sync = rq_is_sync(rq) ? SYNC : ASYNC;

	if (md->next_rq[sync] == rq)
		md->next_rq[sync] = maple_latter_request(rq);

	elv_rb_del(maple_rb_root(md, rq), rq);
}

static void
maple_add_request(struct request_queue *q, struct request *rq)
{
	struct maple_data *md = q->elevator->elevator_data;
	const int sync = rq_is_sync(rq) ? SYNC : ASYNC;

	maple_add_rq_rb(md, rq);

	rq->fifo_time = jiffies + md->fifo_expire[sync];
	list_add_tail(&rq->queuelist, &md->fifo_list[sync]);
}

static void
maple_remove_request(struct request_queue *q, struct request *rq)
{
	struct maple_data *md = q->elevator->elevator_data;

	list_del_init(&rq->queuelist);
	maple_del_rq_rb(md, rq);
}

static enum elv_merge
maple_merge(struct request_queue *q, struct request **rq, struct bio *bio)
{
	struct maple_data *md = q->elevator->elevator_data;
	struct request *__rq;
	int ret;

	if (md->front_merges) {
		sector_t sector = bio_end_sector(bio);

		__rq = elv_rb_find(&md->sort_list[bio_data_dir(bio)], sector);
		if (__rq) {
			BUG_ON(sector != blk_rq_pos(__rq));

			if (elv_bio_merge_ok(__rq, bio)) {
				ret = ELEVATOR_FRONT_MERGE;
				goto out;
			}
		}
	}

	return ELEVATOR_NO_MERGE;
out:
	*rq = __rq;
	return ret;
}

static void maple_merged_request(struct request_queue *q,
				 struct request *req, enum elv_merge type)
{
	struct maple_data *md = q->elevator->elevator_data;

	if (type == ELEVATOR_FRONT_MERGE) {
		elv_rb_del(maple_rb_root(md, req), req);
		maple_add_rq_rb(md, req);
	}
}

static void
maple_merged_requests(struct request_queue *q, struct request *req,
		      struct request *next)
{
	if (!list_empty(&req->queuelist) && !list_empty(&next->queuelist)) {
		if (time_before((unsigned long)next->fifo_time,
				(unsigned long)req->fifo_time)) {
			list_move(&req->queuelist, &next->queuelist);
			req->fifo_time = next->fifo_time;
		}
	}

	maple_remove_request(q, next);
}

static inline void
maple_move_to_dispatch(struct maple_data *md, struct request *rq)
{
	struct request_queue *q = rq->q;

	blk_req_zone_write_lock(rq);
	maple_remove_request(q, rq);
	elv_dispatch_add_tail(q, rq);
}

static void
maple_move_request(struct maple_data *md, struct request *rq)
{
	const int sync = rq_is_sync(rq) ? SYNC : ASYNC;

	md->next_rq[ASYNC] = NULL;
	md->next_rq[SYNC] = NULL;
	md->next_rq[sync] = maple_latter_request(rq);

	maple_move_to_dispatch(md, rq);
}

static inline int maple_check_fifo(struct maple_data *md, int sync)
{
	struct request *rq = rq_entry_fifo(md->fifo_list[sync].next);

	if (time_after_eq(jiffies, (unsigned long)rq->fifo_time))
		return 1;

	return 0;
}

static struct request *
maple_fifo_request(struct maple_data *md, int sync)
{
	struct request *rq;

	if (list_empty(&md->fifo_list[sync]))
		return NULL;

	rq = rq_entry_fifo(md->fifo_list[sync].next);
	if (!blk_queue_is_zoned(rq->q) || blk_req_can_dispatch_to_zone(rq))
		return rq;

	list_for_each_entry(rq, &md->fifo_list[sync], queuelist) {
		if (blk_req_can_dispatch_to_zone(rq))
			return rq;
	}

	return NULL;
}

static struct request *
maple_next_request(struct maple_data *md, int sync)
{
	struct request *rq = md->next_rq[sync];

	if (!rq)
		return NULL;

	if (!blk_queue_is_zoned(rq->q) || blk_req_can_dispatch_to_zone(rq))
		return rq;

	while ((rq = maple_latter_request(rq)) != NULL) {
		if (blk_req_can_dispatch_to_zone(rq))
			return rq;
	}

	return NULL;
}

static int maple_dispatch_requests(struct request_queue *q, int force)
{
	struct maple_data *md = q->elevator->elevator_data;
	struct request *rq = NULL;

	if (list_empty(&md->fifo_list[SYNC]) && list_empty(&md->fifo_list[ASYNC]))
		return 0;

	if (!list_empty(&md->fifo_list[SYNC])) {
		if (!list_empty(&md->fifo_list[ASYNC]) &&
		    (md->starved++ >= md->writes_starved))
			goto dispatch_async;

		if (maple_check_fifo(md, SYNC)) {
			rq = maple_fifo_request(md, SYNC);
			if (rq)
				goto dispatch_request;
		}

		if (md->batching < md->fifo_batch) {
			rq = maple_next_request(md, SYNC);
			if (rq) {
				md->batching++;
				goto dispatch_request;
			}
		}

		rq = maple_fifo_request(md, SYNC);
		if (rq) {
			md->batching = 1;
			goto dispatch_request;
		}
	}

dispatch_async:
	if (!list_empty(&md->fifo_list[ASYNC])) {
		md->starved = 0;

		if (maple_check_fifo(md, ASYNC)) {
			rq = maple_fifo_request(md, ASYNC);
			if (rq)
				goto dispatch_request;
		}

		if (md->batching < md->fifo_batch) {
			rq = maple_next_request(md, ASYNC);
			if (rq) {
				md->batching++;
				goto dispatch_request;
			}
		}

		rq = maple_fifo_request(md, ASYNC);
		if (rq) {
			md->batching = 1;
			goto dispatch_request;
		}
	}

	return 0;

dispatch_request:
	maple_move_request(md, rq);
	return 1;
}

static void maple_exit_queue(struct elevator_queue *e)
{
	struct maple_data *md = e->elevator_data;

	BUG_ON(!list_empty(&md->fifo_list[SYNC]));
	BUG_ON(!list_empty(&md->fifo_list[ASYNC]));

	kfree(md);
}

static int maple_init_queue(struct request_queue *q, struct elevator_type *e)
{
	struct maple_data *md;
	struct elevator_queue *eq;

	eq = elevator_alloc(q, e);
	if (!eq)
		return -ENOMEM;

	md = kzalloc_node(sizeof(*md), GFP_KERNEL, q->node);
	if (!md) {
		kobject_put(&eq->kobj);
		return -ENOMEM;
	}
	eq->elevator_data = md;

	INIT_LIST_HEAD(&md->fifo_list[SYNC]);
	INIT_LIST_HEAD(&md->fifo_list[ASYNC]);
	md->sort_list[SYNC] = RB_ROOT;
	md->sort_list[ASYNC] = RB_ROOT;
	md->fifo_expire[SYNC] = sync_expire;
	md->fifo_expire[ASYNC] = async_expire;
	md->writes_starved = writes_starved;
	md->front_merges = 1;
	md->fifo_batch = fifo_batch;

	spin_lock_irq(q->queue_lock);
	q->elevator = eq;
	spin_unlock_irq(q->queue_lock);
	return 0;
}

/*
 * sysfs interface
 */
static ssize_t
maple_var_show(int var, char *page)
{
	return snprintf(page, PAGE_SIZE, "%d\n", var);
}

static void
maple_var_store(int *var, const char *page)
{
	char *p = (char *) page;

	*var = simple_strtol(p, &p, 10);
}

#define SHOW_FUNCTION(__FUNC, __VAR, __CONV)				\
static ssize_t __FUNC(struct elevator_queue *e, char *page)		\
{									\
	struct maple_data *md = e->elevator_data;			\
	int __data = __VAR;						\
	if (__CONV)							\
		__data = jiffies_to_msecs(__data);			\
	return maple_var_show(__data, (page));				\
}
SHOW_FUNCTION(maple_sync_expire_show, md->fifo_expire[SYNC], 1);
SHOW_FUNCTION(maple_async_expire_show, md->fifo_expire[ASYNC], 1);
SHOW_FUNCTION(maple_writes_starved_show, md->writes_starved, 0);
SHOW_FUNCTION(maple_front_merges_show, md->front_merges, 0);
SHOW_FUNCTION(maple_fifo_batch_show, md->fifo_batch, 0);
#undef SHOW_FUNCTION

#define STORE_FUNCTION(__FUNC, __PTR, MIN, MAX, __CONV)			\
static ssize_t __FUNC(struct elevator_queue *e, const char *page, size_t count)	\
{									\
	struct maple_data *md = e->elevator_data;			\
	int __data;							\
	maple_var_store(&__data, (page));				\
	if (__data < (MIN))						\
		__data = (MIN);						\
	else if (__data > (MAX))					\
		__data = (MAX);						\
	if (__CONV)							\
		*(__PTR) = msecs_to_jiffies(__data);			\
	else								\
		*(__PTR) = __data;					\
	return count;							\
}
STORE_FUNCTION(maple_sync_expire_store, &md->fifo_expire[SYNC], 0, INT_MAX, 1);
STORE_FUNCTION(maple_async_expire_store, &md->fifo_expire[ASYNC], 0, INT_MAX, 1);
STORE_FUNCTION(maple_writes_starved_store, &md->writes_starved, INT_MIN, INT_MAX, 0);
STORE_FUNCTION(maple_front_merges_store, &md->front_merges, 0, 1, 0);
STORE_FUNCTION(maple_fifo_batch_store, &md->fifo_batch, 0, INT_MAX, 0);
#undef STORE_FUNCTION

#define MAPLE_ATTR(name) \
	__ATTR(name, 0644, maple_##name##_show, maple_##name##_store)

static struct elv_fs_entry maple_attrs[] = {
	MAPLE_ATTR(sync_expire),
	MAPLE_ATTR(async_expire),
	MAPLE_ATTR(writes_starved),
	MAPLE_ATTR(front_merges),
	MAPLE_ATTR(fifo_batch),
	__ATTR_NULL
};

static struct elevator_type iosched_maple = {
	.ops.sq = {
		.elevator_merge_fn = 		maple_merge,
		.elevator_merged_fn =		maple_merged_request,
		.elevator_merge_req_fn =	maple_merged_requests,
		.elevator_dispatch_fn =		maple_dispatch_requests,
		.elevator_add_req_fn =		maple_add_request,
		.elevator_former_req_fn =	elv_rb_former_request,
		.elevator_latter_req_fn =	elv_rb_latter_request,
		.elevator_init_fn =		maple_init_queue,
		.elevator_exit_fn =		maple_exit_queue,
	},

	.elevator_attrs = maple_attrs,
	.elevator_name = "maple",
	.elevator_owner = THIS_MODULE,
};

static int __init maple_init(void)
{
	return elv_register(&iosched_maple);
}

static void __exit maple_exit(void)
{
	elv_unregister(&iosched_maple);
}

module_init(maple_init);
module_exit(maple_exit);

MODULE_AUTHOR("Brandon Berhent <frap129@gmail.com>");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Maple IO scheduler");
