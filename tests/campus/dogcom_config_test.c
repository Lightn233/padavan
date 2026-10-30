#include <assert.h>
#include <string.h>
#include "configparse.c"
int main(int argc, char **argv)
{
    assert(argc == 4);
    strcpy(mode, argv[2]);
    strcpy(drcom_config.server, "before");
    struct config before = drcom_config;
    int rc = config_parse(argv[1]);
    if (!strcmp(argv[3], "reject")) {
        assert(rc != 0);
        assert(!memcmp(&before, &drcom_config, sizeof(before)));
    } else {
        assert(rc == 0);
        assert(!strcmp(drcom_config.server, "127.0.0.2"));
        if (!strcmp(argv[3], "flag")) assert(drcom_config.keepalive1_mod == 1);
        if (!strcmp(argv[3], "space")) assert(!strcmp(drcom_config.host_name, "test host"));
    }
    puts("PASS");
    return 0;
}
