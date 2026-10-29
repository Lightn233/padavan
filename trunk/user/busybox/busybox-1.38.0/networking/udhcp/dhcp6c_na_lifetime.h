/* IA_NA 的有效期交给内核计时，避免客户端异常退出后留下永久地址。
 * 仅用于 /128；委派到 LAN 的前缀继续沿用原有管理流程。
 */
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/if_addr.h>
#include <poll.h>

static int na_lifetime_apply(int remove_addr, const char *ifname,
	const struct in6_addr *addr, uint32_t preferred, uint32_t valid)
{
	struct {
		struct nlmsghdr n;
		struct ifaddrmsg a;
		struct { struct rtattr r; struct in6_addr address; } ip;
		struct { struct rtattr r; struct ifa_cacheinfo cache; } lifetime;
	} req;
	struct sockaddr_nl peer;
	struct pollfd pfd;
	union { struct nlmsghdr align; char data[4096]; } reply;
	struct nlmsghdr *n;
	struct nlmsgerr *ack;
	socklen_t peerlen;
	unsigned index;
	int fd, len, saved, rc = -1;

	index = if_nametoindex(ifname);
	if (!index) { errno = ENODEV; return -1; }
	if (!remove_addr && preferred > valid) { errno = EINVAL; return -1; }
	/* 有效期为零表示撤回；内核可能已经按期限删除，因此允许重复撤回。 */
	remove_addr = remove_addr || valid == 0;
	memset(&req, 0, sizeof(req));
	req.n.nlmsg_len = NLMSG_LENGTH(sizeof(req.a)) + sizeof(req.ip);
	req.n.nlmsg_type = remove_addr ? RTM_DELADDR : RTM_NEWADDR;
	req.n.nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
	if (!remove_addr) req.n.nlmsg_flags |= NLM_F_CREATE | NLM_F_REPLACE;
	req.n.nlmsg_seq = 1;
	req.a.ifa_family = AF_INET6;
	req.a.ifa_prefixlen = 128;
	req.a.ifa_scope = RT_SCOPE_UNIVERSE;
	req.a.ifa_index = index;
	req.ip.r.rta_type = IFA_ADDRESS;
	req.ip.r.rta_len = RTA_LENGTH(sizeof(*addr));
	req.ip.address = *addr;
	if (!remove_addr) {
		req.lifetime.r.rta_type = IFA_CACHEINFO;
		req.lifetime.r.rta_len = RTA_LENGTH(sizeof(req.lifetime.cache));
		req.lifetime.cache.ifa_prefered = preferred;
		req.lifetime.cache.ifa_valid = valid;
		req.n.nlmsg_len += sizeof(req.lifetime);
	}
	fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);
	if (fd < 0) return -1;
	memset(&peer, 0, sizeof(peer));
	peer.nl_family = AF_NETLINK;
	if (sendto(fd, &req, req.n.nlmsg_len, 0,
		(struct sockaddr *)&peer, sizeof(peer)) != (ssize_t)req.n.nlmsg_len)
		goto out;
	pfd.fd = fd;
	pfd.events = POLLIN;
	/* 独立套接字不订阅事件，只等待本次内核确认，等待上限为一秒。 */
	if (poll(&pfd, 1, 1000) <= 0) { errno = ETIMEDOUT; goto out; }
	peerlen = sizeof(peer);
	len = recvfrom(fd, reply.data, sizeof(reply.data), MSG_DONTWAIT,
		(struct sockaddr *)&peer, &peerlen);
	if (len < 0) goto out;
	if (peerlen != sizeof(peer) || peer.nl_pid != 0) { errno = EPROTO; goto out; }
	for (n = (struct nlmsghdr *)reply.data; NLMSG_OK(n, len); n = NLMSG_NEXT(n, len)) {
		if (n->nlmsg_seq != 1 || n->nlmsg_type != NLMSG_ERROR) continue;
		if (n->nlmsg_len < NLMSG_LENGTH(sizeof(*ack))) break;
		ack = (struct nlmsgerr *)NLMSG_DATA(n);
		if (!ack->error || (remove_addr &&
			(ack->error == -EADDRNOTAVAIL || ack->error == -ENOENT))) rc = 0;
		else errno = -ack->error;
		goto out;
	}
	errno = EPROTO;
out:
	saved = errno;
	close(fd);
	errno = saved;
	return rc;
}
