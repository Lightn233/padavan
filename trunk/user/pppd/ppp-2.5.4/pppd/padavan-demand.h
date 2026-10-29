#ifndef PADAVAN_DEMAND_H
#define PADAVAN_DEMAND_H
#include <stdint.h>
#include <string.h>
/* RFC 1624 增量校验；逐字节访问，兼容 MIPS 的未对齐限制。 */
static unsigned padavan_get16(const unsigned char *p) { return (p[0] << 8) | p[1]; }
static void padavan_put16(unsigned char *p, unsigned v) { p[0] = v >> 8; p[1] = v; }
static unsigned padavan_csum(unsigned sum, const unsigned char *oldip, const unsigned char *newip) {
    unsigned v = (~sum & 0xffff) + (~padavan_get16(oldip) & 0xffff) + padavan_get16(newip)
        + (~padavan_get16(oldip + 2) & 0xffff) + padavan_get16(newip + 2);
    while (v >> 16) v = (v & 0xffff) + (v >> 16);
    return ~v & 0xffff;
}
static int padavan_demand_remap(unsigned char *frame, int length, uint32_t newaddr) {
    unsigned char *ip, *transport, newip[4];
    unsigned ihl, total, frag, offset = 0, sum;
    if (length < 24) return 0;
    ip = frame + 4;
    ihl = (ip[0] & 15) * 4;
    total = padavan_get16(ip + 2);
    if ((ip[0] >> 4) != 4 || ihl < 20 || total < ihl || total > (unsigned)(length - 4)) return 0;
    frag = padavan_get16(ip + 6);
    if (!(frag & 0x1fff)) {
        if (ip[9] == 6) { if (total < ihl + 20) return 0; offset = 16; }
        else if (ip[9] == 17) { if (total < ihl + 8) return 0; offset = 6; }
    }
    memcpy(newip, &newaddr, 4);
    transport = ip + ihl;
    if (offset) {
        sum = padavan_get16(transport + offset);
        if (ip[9] != 17 || sum) {
            sum = padavan_csum(sum, ip + 12, newip);
            if (ip[9] == 17 && sum == 0) sum = 0xffff;
            padavan_put16(transport + offset, sum);
        }
    }
    padavan_put16(ip + 10, padavan_csum(padavan_get16(ip + 10), ip + 12, newip));
    memcpy(ip + 12, newip, 4);
    return 1;
}
#endif
