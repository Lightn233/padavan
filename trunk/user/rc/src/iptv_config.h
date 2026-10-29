/* IPTV 运行配置仅在 RAM 中生成；读取和转换失败时保留上一份文件。 */
#include <ctype.h>
#include <limits.h>

static int iptv_valid_interface(const char *name)
{
    size_t n;
    if (!name || !(n = strlen(name)) || n >= IFNAMSIZ) return 0;
    return strspn(name, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-") == n;
}

static int iptv_msd_config(const char *source, const char *destination,
                           const char *interface, int port)
{
    char tmp[PATH_MAX], value[128], *line = NULL;
    const char *start, *end, *replacement;
    size_t cap = 0, total = 0;
    ssize_t length;
    FILE *in = NULL, *out = NULL;
    int fd = -1, ok = 0, seen_if = 0, seen_v4 = 0, seen_v6 = 0;
    if (!iptv_valid_interface(interface) || port < 1024 || port > 65535) return -1;
    if (snprintf(tmp, sizeof(tmp), "%s.XXXXXX", destination) >= (int)sizeof(tmp)) return -1;
    in = fopen(source, "r");
    if (!in) return -1;
    fd = mkstemp(tmp);
    if (fd < 0) goto done;
    out = fdopen(fd, "w");
    if (!out) { close(fd); goto done; }
    while ((length = getline(&line, &cap, in)) >= 0) {
        total += (size_t)length;
        if (total > 262144 || length > 65536) goto done;
        start = end = replacement = NULL;
        if ((start = strstr(line, "<ifName>"))) {
            start += strlen("<ifName>"); end = strstr(start, "</ifName>");
            replacement = interface; seen_if++;
        } else if ((start = strstr(line, "<address>0.0.0.0:"))) {
            start += strlen("<address>0.0.0.0:"); end = strstr(start, "</address>");
            snprintf(value, sizeof(value), "%d", port); replacement = value; seen_v4++;
        } else if ((start = strstr(line, "<address>[::]:"))) {
            start += strlen("<address>[::]:"); end = strstr(start, "</address>");
            snprintf(value, sizeof(value), "%d", port); replacement = value; seen_v6++;
        }
        if (replacement) {
            if (!end || fwrite(line, 1, start - line, out) != (size_t)(start - line) ||
                fputs(replacement, out) == EOF || fputs(end, out) == EOF) goto done;
        } else if (fwrite(line, 1, length, out) != (size_t)length) goto done;
    }
    if (ferror(in) || seen_if != 1 || seen_v4 != 1 || seen_v6 != 1) goto done;
    if (fflush(out) || fsync(fileno(out))) goto done;
    if (fclose(out)) { out = NULL; goto done; }
    out = NULL;
    if (rename(tmp, destination)) goto done;
    ok = 1;
done:
    if (out) fclose(out);
    if (in) fclose(in);
    free(line);
    if (!ok && fd >= 0) unlink(tmp);
    return ok ? 0 : -1;
}
