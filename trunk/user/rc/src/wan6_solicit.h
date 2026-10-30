/* PPP 已建立链路本地地址后再开启 RA 接收，需要主动请求一次路由通告。 */
#ifndef WAN6_SOLICIT_H
#define WAN6_SOLICIT_H

#include <sys/socket.h>
#include <net/if.h>
#include <netinet/icmp6.h>
#include <arpa/inet.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>

static int wan6_solicit_ppp(const char *ifname)
{
	struct sockaddr_in6 dst;
	struct nd_router_solicit request;
	unsigned int index;
	int fd, hops = 255, saved;
	const char *p;

	/* 不影响以太网原有的内核 RS 流程，也不接受任意接口名称。 */
	if (!ifname || strncmp(ifname, "ppp", 3) || !ifname[3] ||
	    strnlen(ifname, IFNAMSIZ) >= IFNAMSIZ) {
		errno = EINVAL;
		return -1;
	}
	for (p = ifname + 3; *p; ++p)
		if (*p < '0' || *p > '9') {
			errno = EINVAL;
			return -1;
		}
	index = if_nametoindex(ifname);
	if (!index)
		return -1;
	fd = socket(AF_INET6, SOCK_RAW | SOCK_CLOEXEC, IPPROTO_ICMPV6);
	if (fd < 0)
		return -1;
	if (setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, ifname, strlen(ifname) + 1) ||
	    setsockopt(fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, &index, sizeof(index)) ||
	    setsockopt(fd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, &hops, sizeof(hops)))
		goto fail;
	memset(&dst, 0, sizeof(dst));
	dst.sin6_family = AF_INET6;
	dst.sin6_scope_id = index;
	inet_pton(AF_INET6, "ff02::2", &dst.sin6_addr);
	memset(&request, 0, sizeof(request));
	request.nd_rs_type = ND_ROUTER_SOLICIT;
	/* ICMPv6 校验和由内核计算；没有源链路层选项，适用于 PPP。 */
	if (sendto(fd, &request, sizeof(request), MSG_DONTWAIT,
	           (struct sockaddr *)&dst, sizeof(dst)) != sizeof(request))
		goto fail;
	close(fd);
	return 0;
fail:
	saved = errno;
	close(fd);
	errno = saved;
	return -1;
}

#endif
