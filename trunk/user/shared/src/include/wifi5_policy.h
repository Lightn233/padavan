/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef PADAVAN_WIFI5_POLICY_H
#define PADAVAN_WIFI5_POLICY_H

/* RM2100/MT7615 的共同信道依据；页面、配置生成和驱动共用，避免各自维护名单。
 * 依据 wireless-regdb 2026.09.03，与本机射频/驱动支持范围取交集。
 * 尚未验证的 U-NII-4、欧盟低功率 SRD 扩展以及 6 GHz 不在此表内。
 * 本表不替代主板 EEPROM 功率校准，也不提高发射功率。
 */
struct wifi5_region {
	const char *cc;
	const char *rd;
	unsigned long channels;
};

static const struct wifi5_region wifi5_regions[] = {
	{"US", "FCC", 0x01ffffffUL},
	{"AU", "CE",  0x01ff1fffUL},
	{"NO", "CE",  0x0007ffffUL},
	{"FR", "CE",  0x0007ffffUL},
	{"GB", "CE",  0x01ffffffUL},
	{"TW", "FCC", 0x01ffffffUL},
	{"CN", "FCC", 0x01f000ffUL},
	{"KR", "JAP", 0x01f7ffffUL},
	{"JP", "JAP", 0x000fffffUL}
};
#define WIFI5_REGION_COUNT (sizeof(wifi5_regions) / sizeof(wifi5_regions[0]))
#define WIFI5_CHANNEL_COUNT 25

static inline unsigned int wifi5_channel_at(unsigned int i)
{
	if (i < 8) return 36 + 4 * i;
	if (i < 20) return 100 + 4 * (i - 8);
	if (i < 25) return 149 + 4 * (i - 20);
	return 0;
}

static inline const struct wifi5_region *wifi5_region_find(const char *cc)
{
	unsigned int i;
	if (!cc || !cc[0] || !cc[1]) return 0;
	for (i = 0; i < WIFI5_REGION_COUNT; ++i)
		if (cc[0] == wifi5_regions[i].cc[0] && cc[1] == wifi5_regions[i].cc[1])
			return &wifi5_regions[i];
	return 0;
}

static inline int wifi5_channel_allowed(const char *cc, unsigned int ch)
{
	unsigned int i;
	const struct wifi5_region *r = wifi5_region_find(cc);
	/* 未知区域只保留基础的室内低频信道，禁止借 Debug 绕过区域表。 */
	unsigned long mask = r ? r->channels : 0x0fUL;
	for (i = 0; i < WIFI5_CHANNEL_COUNT; ++i)
		if (wifi5_channel_at(i) == ch) return !!(mask & (1UL << i));
	return 0;
}

/* 返回完整连续带宽组的第一个 20 MHz 子信道；0 表示硬件组合不支持。 */
static inline unsigned int wifi5_group_first(unsigned int ch, unsigned int mhz)
{
	unsigned int base, count, first;
	if (ch >= 36 && ch <= 64 && ch % 4 == 0) base = 36;
	else if (ch >= 100 && ch <= 144 && ch % 4 == 0) base = 100;
	else if (ch >= 149 && ch <= 165 && (ch - 149) % 4 == 0) base = 149;
	else return 0;
	if (mhz != 20 && mhz != 40 && mhz != 80 && mhz != 160) return 0;
	count = mhz / 20;
	first = base + ((ch - base) / (4 * count)) * (4 * count);
	if (mhz == 160 && (base == 149 || first != base)) return 0;
	if (base == 149 && first + 4 * (count - 1) > 165) return 0;
	if (base == 100 && first + 4 * (count - 1) > 144) return 0;
	return first;
}

static inline int wifi5_bw_allowed(const char *cc, unsigned int ch, unsigned int mhz)
{
	unsigned int i, first = wifi5_group_first(ch, mhz);
	if (!first) return 0;
	for (i = 0; i < mhz / 20; ++i)
		if (!wifi5_channel_allowed(cc, first + 4 * i)) return 0;
	return 1;
}

static inline int wifi5_bw_needs_dfs(unsigned int ch, unsigned int mhz)
{
	unsigned int i, c, first = wifi5_group_first(ch, mhz);
	if (!first) return 0;
	for (i = 0; i < mhz / 20; ++i) {
		c = first + 4 * i;
		if ((c >= 52 && c <= 64) || (c >= 100 && c <= 144)) return 1;
	}
	return 0;
}

static inline unsigned int wifi5_effective_bw(const char *cc, unsigned int ch, unsigned int mode)
{
	unsigned int mhz;
	if (mode > 4) return 0;
	if (mode == 4) return wifi5_bw_allowed(cc, ch, 160) ? 160 : 0;
	for (mhz = 20U << mode; mhz >= 20; mhz >>= 1)
		if (wifi5_bw_allowed(cc, ch, mhz)) return mhz;
	return 0;
}

static inline int wifi5_config_valid(const char *cc, unsigned int ch,
	unsigned int mode, unsigned int gmode)
{
	if (!wifi5_region_find(cc) || mode > 4 || gmode > 5) return 0;
	/* 3、4、5 分别为含 802.11ac/ax 的模式；旧 a/n 模式不接受 VHT 带宽。 */
	if (mode >= 2 && gmode < 3) return 0;
	return ch == 0 || wifi5_effective_bw(cc, ch, mode) != 0;
}
#endif
