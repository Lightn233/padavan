/* 普通重启的兜底进程：配置保存完成后才启动，不参与刷机和关机。 */
#ifndef RC_SHUTDOWN_GUARD_H
#define RC_SHUTDOWN_GUARD_H
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/reboot.h>
#include <time.h>
#include <unistd.h>

#ifndef SHUTDOWN_GUARD_SYSRQ
#define SHUTDOWN_GUARD_SYSRQ "/proc/sysrq-trigger"
#endif
#ifndef SHUTDOWN_GUARD_NOTICE
#define SHUTDOWN_GUARD_NOTICE "/dev/kmsg"
#endif
#ifndef SHUTDOWN_GUARD_SYNC
#define SHUTDOWN_GUARD_SYNC() sync()
#endif
#ifndef SHUTDOWN_GUARD_REBOOT
#define SHUTDOWN_GUARD_REBOOT() reboot(RB_AUTOBOOT)
#endif

static void shutdown_guard_write(int fd, const char *data, size_t size)
{
    while (size) {
        ssize_t written=write(fd,data,size);
        if (written<0 && errno==EINTR) continue;
        if (written<=0) break;
        data+=written;
        size-=written;
    }
}

static pid_t start_shutdown_guard(int level, unsigned int seconds)
{
    pid_t pid;
    struct timespec remaining, rest;
    sigset_t blocked, previous;
    int fd, saved_errno;
    long max_fd;
    const char notice[]="RM2100: graceful reboot timed out after settings save; emergency restart\n";

    /* level 1 是关机，level 2 是固件刷写前清理；两者绝不能启动定时重启。 */
    if (level != 0 || seconds == 0) return -1;
    /* 先屏蔽再 fork，避免子进程来不及设置忽略策略就被正常退出信号杀掉。 */
    sigemptyset(&blocked);
    sigaddset(&blocked,SIGTERM);
    sigaddset(&blocked,SIGHUP);
    sigaddset(&blocked,SIGINT);
    sigaddset(&blocked,SIGQUIT);
    if (sigprocmask(SIG_BLOCK,&blocked,&previous)<0) return -1;
    pid=fork();
    if (pid != 0) {
        saved_errno=errno;
        (void)sigprocmask(SIG_SETMASK,&previous,NULL);
        errno=saved_errno;
        return pid;
    }
    setsid();
    /* 正常退出流程会向所有进程发 SIGTERM，兜底进程应活到内核真正重启。 */
    signal(SIGTERM,SIG_IGN);
    signal(SIGHUP,SIG_IGN);
    signal(SIGINT,SIG_IGN);
    signal(SIGQUIT,SIG_IGN);
    (void)sigprocmask(SIG_SETMASK,&previous,NULL);
    /* 不把父进程打开的目录、文件或套接字留到超时，标准终端描述符保留。 */
    max_fd=sysconf(_SC_OPEN_MAX);
    if (max_fd<0) max_fd=1024;
    for (fd=3;fd<max_fd;fd++) close(fd);
    remaining.tv_sec=seconds;
    remaining.tv_nsec=0;
    while (nanosleep(&remaining,&rest)<0 && errno==EINTR) remaining=rest;

    fd=open(SHUTDOWN_GUARD_NOTICE,O_WRONLY|O_NONBLOCK);
    if (fd>=0) { shutdown_guard_write(fd,notice,sizeof(notice)-1); close(fd); }
    /* 普通 reboot 可能再次等待已卡住的设备关闭路径；先同步，再走内核紧急重启。 */
    SHUTDOWN_GUARD_SYNC();
    fd=open(SHUTDOWN_GUARD_SYSRQ,O_WRONLY);
    if (fd>=0) { shutdown_guard_write(fd,"b",1); close(fd); }
    (void)SHUTDOWN_GUARD_REBOOT();
    _exit(1);
}
#endif
