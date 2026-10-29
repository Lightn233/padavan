#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <net/if.h>
#include <netdb.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/* 单次查询有硬超时；只检查 DNS，不修改任何配置或路由。 */
enum { DNS_NEGATIVE = 10, DNS_IO = 12, DNS_BAD_PACKET = 13, USAGE = 64 };
static void expire(int sig) { (void)sig; _exit(DNS_IO); }
static unsigned int word(const unsigned char *p)
{
    return ((unsigned int)p[0] << 8) | p[1];
}
static void putword(unsigned char *p, unsigned int value)
{
    p[0] = (unsigned char)(value >> 8); p[1] = (unsigned char)value;
}

/* 遍历名称时限制指针跳转次数，并核对每次读写的边界。 */
static int name_end(const unsigned char *p, size_t size, size_t *offset)
{
    size_t pos = *offset, end = 0, expanded = 0;
    unsigned int hops = 0;
    while (pos < size && hops++ < 128) {
        unsigned int n = p[pos++];
        if ((n & 0xc0U) == 0xc0U) {
            if (pos >= size) return -1;
            if (!end) end = pos + 1;
            pos = ((size_t)(n & 0x3fU) << 8) | p[pos];
        } else {
            if (n & 0xc0U) return -1;
            if (!n) { *offset = end ? end : pos; return 0; }
            if (n > size - pos || (expanded += n + 1U) > 254) return -1;
            pos += n;
        }
    }
    return -1;
}

static int check_reply(const unsigned char *p, size_t size,
                       const unsigned char *query, size_t qsize,
                       const struct in_addr *expected)
{
    size_t pos;
    unsigned int answers, count;
    int found = 0;
    if (size < 12 || qsize < 17 || word(p) != word(query) ||
        (p[2] & 0xfaU) != 0x80U || word(p + 4) != 1)
        return DNS_BAD_PACKET;
    /* 本工具只发送一个标准 A 查询，响应问题区必须与其一致。 */
    if (size < qsize || memcmp(p + 12, query + 12, qsize - 12))
        return DNS_BAD_PACKET;
    pos = qsize;
    answers = word(p + 6);
    count = answers + word(p + 8) + word(p + 10);
    for (unsigned int i = 0; i < count; i++) {
        unsigned int type, klass, length;
        if (name_end(p, size, &pos) || size - pos < 10) return DNS_BAD_PACKET;
        type = word(p + pos); klass = word(p + pos + 2);
        length = word(p + pos + 8); pos += 10;
        if (length > size - pos) return DNS_BAD_PACKET;
        if (i < answers && type == 1 && klass == 1 && length == 4 &&
            (!expected || !memcmp(p + pos, expected, 4))) found = 1;
        pos += length;
    }
    if (pos != size) return DNS_BAD_PACKET;
    if ((p[3] & 0x0fU) || !found) return DNS_NEGATIVE;
    return 0;
}

static int transfer(int fd, unsigned char *p, size_t length, int sending)
{
    while (length) {
        ssize_t n = sending ? send(fd, p, length, 0) : recv(fd, p, length, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        p += (size_t)n; length -= (size_t)n;
    }
    return 0;
}

static int probe(int argc, char **argv)
{
    unsigned char query[272] = {0}, response[4096], prefix[2];
    struct addrinfo hints, *address = NULL;
    struct in_addr expected, *want = NULL;
    size_t qsize = 12;
    int fd, random_fd, stream, result = DNS_IO;
    const char *label;
    if (argc != 7 && argc != 8) return USAGE;
    stream = !strcmp(argv[4], "tcp");
    if (!stream && strcmp(argv[4], "udp")) return USAGE;
    if (strcmp(argv[6], "A")) return USAGE;
    if (argc == 8) {
        if (inet_pton(AF_INET, argv[7], &expected) != 1) return USAGE;
        want = &expected;
    }
    if (!*argv[5] || strlen(argv[5]) > 253) return USAGE;
    label = argv[5];
    while (*label) {
        const char *dot = strchr(label, '.');
        size_t length = dot ? (size_t)(dot - label) : strlen(label);
        if (!length || length > 63 || qsize + length + 6 > sizeof(query)) return USAGE;
        query[qsize++] = (unsigned char)length;
        memcpy(query + qsize, label, length); qsize += length;
        if (!dot) break;
        label = dot + 1;
    }
    query[qsize++] = 0;
    putword(query + qsize, 1); qsize += 2;
    putword(query + qsize, 1); qsize += 2;
    query[2] = 1; query[5] = 1;
    random_fd = open("/dev/urandom", O_RDONLY);
    if (random_fd < 0) return DNS_IO;
    ssize_t random_read = read(random_fd, query, 2);
    close(random_fd);
    if (random_read != 2) return DNS_IO;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = stream ? SOCK_STREAM : SOCK_DGRAM;
    hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;
    if (getaddrinfo(argv[2], argv[3], &hints, &address)) return USAGE;
    fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
    if (fd < 0) { freeaddrinfo(address); return DNS_IO; }
    if (connect(fd, address->ai_addr, address->ai_addrlen)) goto done;
    if (stream) {
        putword(prefix, (unsigned int)qsize);
        if (transfer(fd, prefix, 2, 1) || transfer(fd, query, qsize, 1) ||
            transfer(fd, prefix, 2, 0)) goto done;
        size_t length = word(prefix);
        if (length < 12 || length > sizeof(response)) { result = DNS_BAD_PACKET; goto done; }
        if (transfer(fd, response, length, 0)) goto done;
        result = check_reply(response, length, query, qsize, want);
    } else {
        if (send(fd, query, qsize, 0) != (ssize_t)qsize) goto done;
        ssize_t length = recv(fd, response, sizeof(response), MSG_TRUNC);
        if (length <= 0) goto done;
        result = (size_t)length > sizeof(response) ? DNS_BAD_PACKET :
            check_reply(response, (size_t)length, query, qsize, want);
    }
done:
    close(fd); freeaddrinfo(address);
    return result;
}

/* 仅请求重新发布 RA；网关仍由运营商 RA 决定。 */
static int solicit(const char *name)
{
    unsigned int index = if_nametoindex(name);
    struct sockaddr_in6 dst;
    const unsigned char packet[8] = {133, 0, 0, 0, 0, 0, 0, 0};
    int fd, hops = 255, result = DNS_IO;
    if (!index) return USAGE;
    fd = socket(AF_INET6, SOCK_RAW, IPPROTO_ICMPV6);
    if (fd < 0) return DNS_IO;
    if (setsockopt(fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, &index, sizeof(index)) ||
        setsockopt(fd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, &hops, sizeof(hops))) goto done;
    memset(&dst, 0, sizeof(dst)); dst.sin6_family = AF_INET6; dst.sin6_scope_id = index;
    if (inet_pton(AF_INET6, "ff02::2", &dst.sin6_addr) != 1) goto done;
    if (sendto(fd, packet, sizeof(packet), 0, (struct sockaddr *)&dst, sizeof(dst)) ==
        (ssize_t)sizeof(packet)) result = 0;
done:
    close(fd); return result;
}

int main(int argc, char **argv)
{
    struct sigaction sa;
    int result;
    memset(&sa, 0, sizeof(sa)); sa.sa_handler = expire; sigemptyset(&sa.sa_mask);
    if (sigaction(SIGALRM, &sa, NULL)) return DNS_IO;
    signal(SIGPIPE, SIG_IGN);
    alarm(3);
    if (argc >= 2 && !strcmp(argv[1], "dns")) result = probe(argc, argv);
    else if (argc == 3 && !strcmp(argv[1], "rs")) result = solicit(argv[2]);
    else result = USAGE;
    alarm(0);
    if (result == USAGE) fprintf(stderr,
        "Usage: %s dns ADDRESS PORT udp|tcp NAME A [EXPECTED_IPV4]\n"
        "       %s rs INTERFACE\n", argv[0], argv[0]);
    return result;
}
