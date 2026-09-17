// SPDX-License-Identifier: GPL-2.0
/*
 * Sound Control 3.x Driver for POCO F4 (munch) & SM8250
 * Exposes /sys/kernel/sound_control_3/
 *   - headphone_gain (L R)
 *   - mic_gain
 *   - speaker_gain (L R)
 *   - high_perf_mode
 *   - version
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/string.h>
#include <linux/mutex.h>
#include <linux/sound_control.h>

static int hph_l_gain = 20;
static int hph_r_gain = 20;
static int mic_gain_val = 12;
static int spk_l_gain = 0;
static int spk_r_gain = 0;
static int high_perf_mode_val = 0;

static DEFINE_MUTEX(sound_control_mutex);

int sound_control_get_hph_l_gain(void)
{
	return hph_l_gain;
}
EXPORT_SYMBOL_GPL(sound_control_get_hph_l_gain);

int sound_control_get_hph_r_gain(void)
{
	return hph_r_gain;
}
EXPORT_SYMBOL_GPL(sound_control_get_hph_r_gain);

int sound_control_get_mic_gain(void)
{
	return mic_gain_val;
}
EXPORT_SYMBOL_GPL(sound_control_get_mic_gain);

int sound_control_get_speaker_gain(void)
{
	return spk_l_gain;
}
EXPORT_SYMBOL_GPL(sound_control_get_speaker_gain);

int sound_control_get_high_perf_mode(void)
{
	return high_perf_mode_val;
}
EXPORT_SYMBOL_GPL(sound_control_get_high_perf_mode);

/* --- headphone_gain --- */
static ssize_t headphone_gain_show(struct kobject *kobj,
				   struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d %d\n", hph_l_gain, hph_r_gain);
}

static ssize_t headphone_gain_store(struct kobject *kobj,
				    struct kobj_attribute *attr,
				    const char *buf, size_t count)
{
	int l, r;
	int ret;

	ret = sscanf(buf, "%d %d", &l, &r);
	if (ret == 1) {
		r = l;
	} else if (ret != 2) {
		return -EINVAL;
	}

	if (l < -20)
		l = -20;
	if (l > 24)
		l = 24;
	if (r < -20)
		r = -20;
	if (r > 24)
		r = 24;

	mutex_lock(&sound_control_mutex);
	hph_l_gain = l;
	hph_r_gain = r;
	mutex_unlock(&sound_control_mutex);

	return count;
}
static struct kobj_attribute headphone_gain_attr =
	__ATTR(headphone_gain, 0664, headphone_gain_show, headphone_gain_store);

/* --- mic_gain --- */
static ssize_t mic_gain_show(struct kobject *kobj,
			     struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", mic_gain_val);
}

static ssize_t mic_gain_store(struct kobject *kobj,
			      struct kobj_attribute *attr,
			      const char *buf, size_t count)
{
	int val;

	if (kstrtoint(buf, 10, &val))
		return -EINVAL;

	if (val < -20)
		val = -20;
	if (val > 20)
		val = 20;

	mutex_lock(&sound_control_mutex);
	mic_gain_val = val;
	mutex_unlock(&sound_control_mutex);

	return count;
}
static struct kobj_attribute mic_gain_attr =
	__ATTR(mic_gain, 0664, mic_gain_show, mic_gain_store);

/* --- speaker_gain --- */
static ssize_t speaker_gain_show(struct kobject *kobj,
				 struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d %d\n", spk_l_gain, spk_r_gain);
}

static ssize_t speaker_gain_store(struct kobject *kobj,
				  struct kobj_attribute *attr,
				  const char *buf, size_t count)
{
	int l, r;
	int ret;

	ret = sscanf(buf, "%d %d", &l, &r);
	if (ret == 1) {
		r = l;
	} else if (ret != 2) {
		return -EINVAL;
	}

	if (l < -20)
		l = -20;
	if (l > 20)
		l = 20;
	if (r < -20)
		r = -20;
	if (r > 20)
		r = 20;

	mutex_lock(&sound_control_mutex);
	spk_l_gain = l;
	spk_r_gain = r;
	mutex_unlock(&sound_control_mutex);

	return count;
}
static struct kobj_attribute speaker_gain_attr =
	__ATTR(speaker_gain, 0664, speaker_gain_show, speaker_gain_store);

/* --- high_perf_mode --- */
static ssize_t high_perf_mode_show(struct kobject *kobj,
				   struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", high_perf_mode_val);
}

static ssize_t high_perf_mode_store(struct kobject *kobj,
				    struct kobj_attribute *attr,
				    const char *buf, size_t count)
{
	int val;

	if (kstrtoint(buf, 10, &val))
		return -EINVAL;

	mutex_lock(&sound_control_mutex);
	high_perf_mode_val = !!val;
	mutex_unlock(&sound_control_mutex);

	return count;
}
static struct kobj_attribute high_perf_mode_attr =
	__ATTR(high_perf_mode, 0664, high_perf_mode_show, high_perf_mode_store);

/* --- version --- */
static ssize_t version_show(struct kobject *kobj,
			    struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%s\n", SOUND_CONTROL_VERSION);
}
static struct kobj_attribute version_attr =
	__ATTR_RO(version);

static struct attribute *sound_control_attrs[] = {
	&headphone_gain_attr.attr,
	&mic_gain_attr.attr,
	&speaker_gain_attr.attr,
	&high_perf_mode_attr.attr,
	&version_attr.attr,
	NULL,
};

static const struct attribute_group sound_control_attr_group = {
	.attrs = sound_control_attrs,
};

static struct kobject *sound_control_kobj;

static int __init sound_control_init(void)
{
	int ret;

	sound_control_kobj = kobject_create_and_add("sound_control_3", kernel_kobj);
	if (!sound_control_kobj) {
		pr_err("sound_control: Failed to create sound_control_3 kobject\n");
		return -ENOMEM;
	}

	ret = sysfs_create_group(sound_control_kobj, &sound_control_attr_group);
	if (ret) {
		pr_err("sound_control: Failed to create sysfs attributes, err=%d\n", ret);
		kobject_put(sound_control_kobj);
		return ret;
	}

	pr_info("sound_control: Initialized Sound Control v%s successfully\n",
		SOUND_CONTROL_VERSION);
	return 0;
}

static void __exit sound_control_exit(void)
{
	if (sound_control_kobj) {
		sysfs_remove_group(sound_control_kobj, &sound_control_attr_group);
		kobject_put(sound_control_kobj);
	}
}

module_init(sound_control_init);
module_exit(sound_control_exit);

MODULE_AUTHOR("Ki-Kernel Team");
MODULE_DESCRIPTION("Sound Control 3.x Driver for POCO F4 / SM8250");
MODULE_LICENSE("GPL v2");
