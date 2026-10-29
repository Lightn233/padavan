/* 安装和回退只接受已登录页面的 POST 与随机令牌；下载不阻塞后台。 */
#include <sys/wait.h>
static int ddns_go_post;
static char ddns_go_csrf[65];

static void do_ddns_go_post(const char *url, FILE *stream, int clen, char *boundary)
{
    ddns_go_post = 0;
    do_html_apply_post(url, stream, clen, boundary);
    if (!http_input_error) ddns_go_post = 1;
}

static void do_ddns_go(const char *url, FILE *stream)
{
    unsigned char bytes[32];
    char state[32] = "absent", operation[32] = "idle";
    const char *action, *csrf, *arg;
    size_t i, n;
    FILE *file;
    int post = ddns_go_post, status;
    pid_t child;
    (void)url;
    ddns_go_post = 0;
    if (!ddns_go_csrf[0]) {
        file = fopen("/dev/urandom", "rb");
        if (!file) { fputs("{\"error\":\"unavailable\"}", stream); return; }
        n = fread(bytes, 1, sizeof(bytes), file); fclose(file);
        if (n != sizeof(bytes)) { fputs("{\"error\":\"unavailable\"}", stream); return; }
        for (i = 0; i < sizeof(bytes); ++i) sprintf(ddns_go_csrf + 2*i, "%02x", bytes[i]);
    }
    if (post) {
        action = get_cgi("action"); csrf = get_cgi("csrf");
        if (!get_login_safe() || !csrf || strcmp(csrf, ddns_go_csrf) || !action ||
            (strcmp(action, "install") && strcmp(action, "rollback"))) {
            fputs("{\"error\":\"forbidden\"}", stream); return;
        }
        arg = !strcmp(action, "install") ? "web-install" : "web-rollback";
        child = fork();
        if (child < 0) { fputs("{\"error\":\"unavailable\"}", stream); return; }
        if (!child) {
            long limit = sysconf(_SC_OPEN_MAX);
            int fd;
            setsid();
            child = fork();
            if (child < 0) _exit(1);
            if (child > 0) _exit(0);
            if (limit < 0) limit = 1024;
            for (fd = 3; fd < limit; ++fd) close(fd);
            if (!freopen("/dev/null", "r", stdin) || !freopen("/dev/null", "w", stdout) ||
                !freopen("/dev/null", "w", stderr)) _exit(1);
            execl("/usr/bin/ddns-go.sh", "ddns-go.sh", arg, (char *)NULL);
            _exit(1);
        }
        while (waitpid(child, &status, 0) < 0) {
            if (errno != EINTR) { fputs("{\"error\":\"unavailable\"}", stream); return; }
        }
        if (!WIFEXITED(status) || WEXITSTATUS(status)) { fputs("{\"error\":\"unavailable\"}", stream); return; }
        fputs("{\"operation\":\"queued\"}", stream); return;
    }
    file = popen("/usr/bin/ddns-go.sh status 2>/dev/null", "r");
    if (file) {
        if (!fgets(state, sizeof(state), file)) strcpy(state, "working");
        pclose(file); state[strcspn(state, "\r\n")] = 0;
    }
    if (strcmp(state,"running") && strcmp(state,"stopped") && strcmp(state,"absent")) strcpy(state,"working");
    file = fopen("/var/run/ddns-go/operation", "r");
    if (file) { if (!fgets(operation,sizeof(operation),file)) strcpy(operation,"idle"); fclose(file); }
    operation[strcspn(operation,"\r\n")] = 0;
    if (strcmp(operation,"success") && strcmp(operation,"failed") && strcmp(operation,"working")) strcpy(operation,"idle");
    fprintf(stream,"{\"csrf\":\"%s\",\"state\":\"%s\",\"operation\":\"%s\"}",ddns_go_csrf,state,operation);
}
