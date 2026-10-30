/* 无需 root 的接口名回归；成功发包另在隔离命名空间和实机验收。 */
#include <assert.h>
#include <stdio.h>
#include "wan6_solicit.h"

int main(int argc, char **argv)
{
    const char *bad[] = {NULL, "", "eth3", "br0", "ppp", "ppp0;reboot", "ppp0.1", "ppp1234567890123456"};
    unsigned int i;
    if (argc == 2) {
        if (wan6_solicit_ppp(argv[1]) < 0) {
            perror("RS");
            return 1;
        }
        return 0;
    }
    for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        errno = 0;
        assert(wan6_solicit_ppp(bad[i]) == -1);
        assert(errno == EINVAL);
    }
    puts("8 interface validation cases passed");
    return 0;
}
