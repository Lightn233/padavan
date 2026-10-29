/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef PADAVAN_WIFI24_POLICY_H
#define PADAVAN_WIFI24_POLICY_H

/* 与本机 2.4 GHz 页面已有国家选项一致；固定带宽不接受 Debug 或未知区域。 */
static inline unsigned int wifi24_channel_max(const char *cc)
{
	static const char * const regions[] = {"US", "TW", "CN", "JP", "AU", "GB", "RU"};
	unsigned int i;
	if (!cc || !cc[0] || !cc[1] || cc[2]) return 0;
	for (i = 0; i < sizeof(regions) / sizeof(regions[0]); ++i)
		if (cc[0] == regions[i][0] && cc[1] == regions[i][1]) return i < 2 ? 11 : 13;
	return 0;
}

static inline int wifi24_fixed40_valid(const char *cc, unsigned int ch, unsigned int above)
{
	unsigned int max = wifi24_channel_max(cc);
	/* 固定 40 MHz 使用明确的主、扩展信道，避免自动选信道后悄悄退到 20 MHz。 */
	if (!max || ch < 1 || ch > max || above > 1) return 0;
	return above ? ch + 4 <= max : ch >= 5;
}
#endif
