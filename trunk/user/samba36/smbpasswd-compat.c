/* 兼容原固件的用户名/密码参数；密码通过匿名临时文件传给新版工具。 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/wait.h>
#ifndef SMBPASSWD_REAL
#define SMBPASSWD_REAL "/usr/bin/smbpasswd4"
#endif
int main(int argc, char **argv)
{
    FILE *input;
    pid_t child, waited;
    int status;
    if (argc != 3 || !argv[1][0] || argv[1][0] == '-' ||
        strpbrk(argv[1], "\r\n") || strpbrk(argv[2], "\r\n")) {
        fputs("无效的共享账号参数\n", stderr);
        return 2;
    }
    input = tmpfile();
    if (!input) return 1;
    if (fprintf(input, "%s\n%s\n", argv[2], argv[2]) < 0 || fflush(input)) {
        fclose(input); return 1;
    }
    rewind(input);
    child = fork();
    if (child < 0) { fclose(input); return 1; }
    if (!child) {
        if (dup2(fileno(input), STDIN_FILENO) < 0) _exit(126);
        fclose(input);
        execl(SMBPASSWD_REAL, "smbpasswd4", "-s", "-a", argv[1], (char *)NULL);
        _exit(127);
    }
    fclose(input);
    do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
    return waited == child && WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
