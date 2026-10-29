/* Derived from Padavan xl2tpd.c; GPL-2.0-or-later.
 * Copyright (C) 1998 Adtran, Inc.; Mark Spencer <markster@marko.net>.
 * Copyright (C) 2002 Jeff McAdams.
 * 保留原 Padavan 的服务器路由选择，避免 VPN 默认路由递归。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>
#include <errno.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/route.h>
#include <netinet/in.h>
#define sin_addr(s) (((struct sockaddr_in *)(s))->sin_addr)
/* Route manipulation */
static int
route_ctrl(int ctrl, struct rtentry *rt)
{
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    int result;
    if (fd < 0) return errno;
    result = ioctl(fd, ctrl, rt) < 0 ? errno : 0;
    close(fd);
    return result;
}

/* static */ int
route_del(struct rtentry *rt)
{
	if (rt->rt_dev) {
		route_ctrl(SIOCDELRT, rt);
		free(rt->rt_dev);
	}

	memset(rt, 0, sizeof(*rt));

	return 0;
}

/* static */ int
route_add(const struct in_addr inetaddr, int any_dgw, struct rtentry *rt)
{
	char buf[256], dev[64], rdev[64];
	u_int32_t dest, mask, gateway, flags, bestmask = 0;
	u_int32_t metric, metric_min = UINT_MAX;

	FILE *fp = fopen("/proc/net/route", "r");
	if (!fp) {
		/* route_msg("%s: /proc/net/route: %s", strerror(errno), __FUNCTION__); */
		return -1;
	}

	rt->rt_gateway.sa_family = 0;

	while (fgets(buf, sizeof(buf), fp)) {
		if (sscanf(buf, "%63s %x %x %x %*s %*s %u %x",
			dev, &dest, &gateway, &flags, &metric, &mask) != 6)
			continue;
		
		if ((flags & RTF_UP) != RTF_UP)
			continue;
		
		if (!any_dgw) {
			/* use only physical WAN/MAN interface */
			if (strncmp(dev, "eth", 3) != 0 &&
			    strncmp(dev, "apcli", 5) != 0 &&
			    strncmp(dev, "wwan", 4) != 0 &&
			    strncmp(dev, "weth", 4) != 0)
				continue;
			
			if ( (inetaddr.s_addr & mask) == dest && gateway ) {
				if ((mask | bestmask) == bestmask && rt->rt_gateway.sa_family)
					continue;
				
				bestmask = mask;
				
				sin_addr(&rt->rt_gateway).s_addr = gateway;
				rt->rt_gateway.sa_family = AF_INET;
				rt->rt_flags = flags;
				rt->rt_metric = (dest) ? metric : 0;
				strncpy(rdev, dev, sizeof(rdev));
				
				if (mask == INADDR_BROADCAST)
					break;
			}
		} else {
			/* skip lo and LAN */
			if (strcmp(dev, "lo") == 0 ||
			    strcmp(dev, "br0") == 0)
				continue;
			
			if ( !dest && !mask && gateway && metric < metric_min ) {
				metric_min = metric;
				
				sin_addr(&rt->rt_gateway).s_addr = gateway;
				rt->rt_gateway.sa_family = AF_INET;
				rt->rt_flags = flags;
				rt->rt_metric = 0;
				strncpy(rdev, dev, sizeof(rdev));
			}
		}
	}

	fclose(fp);

	/* check for no route */
	if (rt->rt_gateway.sa_family != AF_INET) 
	{
		/* route_msg("%s: no route to host", __FUNCTION__); */
		return -1;
	}

	/* check for existing route to this host,
	 * add if missing based on the existing routes */
	if (rt->rt_flags & RTF_HOST)
	{
		/* route_msg("%s: not adding existing route", __FUNCTION__); */
		return -1;
	}

	sin_addr(&rt->rt_dst) = inetaddr;
	rt->rt_dst.sa_family = AF_INET;

	sin_addr(&rt->rt_genmask).s_addr = INADDR_BROADCAST;
	rt->rt_genmask.sa_family = AF_INET;

	rt->rt_flags &= RTF_GATEWAY;
	rt->rt_flags |= RTF_UP | RTF_HOST;

	rt->rt_metric++;
	rt->rt_dev = strdup(rdev);

	if (!rt->rt_dev)
	{
		/* route_msg("%s: no memory", __FUNCTION__); */
		return -1;
	}

	if (!route_ctrl(SIOCADDRT, rt))
		return 0;

	free(rt->rt_dev);
	memset(rt, 0, sizeof(*rt));

	return -1;
}
