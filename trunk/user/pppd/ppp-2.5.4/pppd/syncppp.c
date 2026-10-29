/* 多拨同步使用短期文件锁；进程退出会释放锁，不遗留有主信号量。 */
#include "syncppp.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifndef SYNCPPP_STATE_PATH
#define SYNCPPP_STATE_PATH "/var/run/ppp-sync.state"
#endif
#define SYNC_MAGIC 0x50505032U
#define SYNC_TIMEOUT_NS UINT64_C(5000000000)
struct sync_state {
    uint32_t magic, participants, released;
    int32_t pid[255];
    uint64_t joined[255];
};

static uint64_t monotonic_ns(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts)) return 0;
    return (uint64_t)ts.tv_sec * UINT64_C(1000000000) + ts.tv_nsec;
}

int syncppp(int participants)
{
    struct sync_state state;
    struct stat st;
    const struct timespec pause = {0, 10000000};
    uint64_t started, now;
    int fd, own = -1, result = -1, saved = 0;
    pid_t me = getpid();
    if (participants < 2 || participants > 255) { errno = EINVAL; return -1; }
    started = monotonic_ns();
    if (!started) return -1;
    fd = open(SYNCPPP_STATE_PATH, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) return -1;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_nlink != 1 ||
        st.st_uid != geteuid() || (st.st_mode & 077)) { saved = EPERM; goto out; }
    for (;;) {
        int active = 0, free_slot = -1, finish = 0;
        ssize_t got;
        now = monotonic_ns();
        if (!now) { saved = errno; break; }
        if (flock(fd, LOCK_EX | LOCK_NB)) {
            if (errno != EWOULDBLOCK && errno != EINTR) { saved = errno; break; }
            if (now - started >= SYNC_TIMEOUT_NS) { saved = ETIMEDOUT; break; }
            nanosleep(&pause, 0);
            continue;
        }
        /* 加锁前可能被调度出去，不能用旧时间判断新加入的进程已超时。 */
        now = monotonic_ns();
        if (!now) { saved = errno; flock(fd, LOCK_UN); break; }
        got = pread(fd, &state, sizeof(state), 0);
        if (got < 0) { saved = errno; flock(fd, LOCK_UN); break; }
        if (got != (ssize_t)sizeof(state)) {
            memset(&state, 0, sizeof(state));
            state.magic = SYNC_MAGIC;
        } else if (state.magic != SYNC_MAGIC) {
            saved = EPROTO; flock(fd, LOCK_UN); break;
        }
        /* 清除已退出或超时的参与者，不按残留计数放行下一轮。 */
        for (int i = 0; i < 255; ++i) {
            if (state.pid[i] && ((kill(state.pid[i], 0) && errno == ESRCH) ||
                (now >= state.joined[i] && now - state.joined[i] >= SYNC_TIMEOUT_NS))) state.pid[i] = 0;
            if (state.pid[i]) ++active;
            else if (free_slot < 0) free_slot = i;
        }
        if (own >= 0 && state.pid[own] != me) {
            saved = ETIMEDOUT; finish = 1;
        } else if (own >= 0 && state.released) {
            result = 0; finish = 1;
        } else if (now - started >= SYNC_TIMEOUT_NS) {
            saved = ETIMEDOUT; finish = 1;
        } else {
            if (!active) { state.released = 0; state.participants = participants; }
            if (own < 0 && !state.released && state.participants == (unsigned)participants && free_slot >= 0) {
                own = free_slot; state.pid[own] = me; state.joined[own] = now; ++active;
            }
            if (own >= 0 && active >= participants) {
                state.released = 1; result = 0; finish = 1;
            }
        }
        if (finish && own >= 0 && state.pid[own] == me) state.pid[own] = 0;
        if (pwrite(fd, &state, sizeof(state), 0) != (ssize_t)sizeof(state)) {
            saved = errno ? errno : EIO; result = -1; finish = 1;
        }
        flock(fd, LOCK_UN);
        if (finish) break;
        nanosleep(&pause, 0);
    }
out:
    close(fd);
    errno = saved;
    return result;
}
