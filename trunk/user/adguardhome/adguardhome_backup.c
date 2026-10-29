#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <dirent.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#ifndef AGH_ROOT
#define AGH_ROOT "/media/mtd_rwfs/AdGuardHome"
#endif
/* 仅由已认证的维护入口调用；服务锁由入口持有，路径不能来自请求参数。 */
static int walk(int fd, unsigned depth, uint64_t *bytes, unsigned *count, int erase)
{
    DIR *dir;
    struct dirent *e;
    struct stat st;
    int copy, sub, child_rc, rc = -1;
    if (depth > 8 || (copy = dup(fd)) < 0) return -1;
    dir = fdopendir(copy);
    if (!dir) { close(copy); return -1; }
    rewinddir(dir);
    while ((e = readdir(dir))) {
        if (!strcmp(e->d_name,".") || !strcmp(e->d_name,"..")) continue;
        if (++*count > 256 || fstatat(fd,e->d_name,&st,AT_SYMLINK_NOFOLLOW)) goto done;
        if (S_ISREG(st.st_mode)) {
            *bytes += (uint64_t)st.st_size;
            if (erase && unlinkat(fd,e->d_name,0)) goto done;
        } else if (S_ISDIR(st.st_mode)) {
            sub = openat(fd,e->d_name,O_DIRECTORY|O_NOFOLLOW|O_RDONLY|O_CLOEXEC);
            if (sub < 0) goto done;
            child_rc = walk(sub,depth+1,bytes,count,erase); close(sub);
            if (child_rc || (erase && unlinkat(fd,e->d_name,AT_REMOVEDIR))) goto done;
        } else { rc=-1; goto done; }
    }
    rc=0;
done:
    closedir(dir); return rc;
}
static int updating(int root)
{
    DIR *d = fdopendir(dup(root)); struct dirent *e; int found=0;
    if (!d) return 1;
    rewinddir(d);
    while ((e=readdir(d))) if (!strncmp(e->d_name,"agh-update",10)) {found=1;break;}
    closedir(d); return found;
}
static int unfinished_cleanup(int root)
{
    DIR *d=fdopendir(dup(root)); struct dirent *e; int found=0;
    if(!d) return 1;
    rewinddir(d);
    while((e=readdir(d))) if(!strncmp(e->d_name,".agh-retired-",13)) {found=1;break;}
    closedir(d);return found;
}
static int snapshot(int fd, char *out, size_t size, uint64_t *bytes)
{
    const char *files[]={".","AdGuardHome","AdGuardHome.yaml"};
    struct stat s; size_t used=0; unsigned i,count=0; int n;
    *bytes=0;
    if (walk(fd,0,bytes,&count,0)) return -1;
    for(i=0;i<3;i++) {
        if (fstatat(fd,files[i],&s,AT_SYMLINK_NOFOLLOW) ||
            (i==0 ? !S_ISDIR(s.st_mode) : !S_ISREG(s.st_mode))) return -1;
        n=snprintf(out+used,size-used,"%jx-%jx-%jx-%jx-%jx-%jx-",
            (uintmax_t)s.st_dev,(uintmax_t)s.st_ino,(uintmax_t)s.st_size,
            (uintmax_t)s.st_mtim.tv_sec,(uintmax_t)s.st_mtim.tv_nsec,
            (uintmax_t)s.st_ctim.tv_nsec);
        if(n<0 || (size_t)n>=size-used) return -1;
        used+=(size_t)n;
    }
    return 0;
}
static int same_executable(pid_t pid, int root)
{
    struct stat a,b; char path[64];
    snprintf(path,sizeof(path),"/proc/%ld/exe",(long)pid);
    return !stat(path,&a) && !fstatat(root,"AdGuardHome",&b,AT_SYMLINK_NOFOLLOW) &&
        S_ISREG(b.st_mode) && a.st_dev==b.st_dev && a.st_ino==b.st_ino;
}
static int task_stopped(const char *path)
{
    char line[512]; FILE *f; int yes=0;
    f=fopen(path,"r"); if(!f) return 0;
    while(fgets(line,sizeof(line),f)) if(!strncmp(line,"State:",6)) {
        yes=strchr(line,'T')!=NULL; break;
    }
    fclose(f); return yes;
}
static int stopped(pid_t pid)
{
    char path[128]; DIR *d; struct dirent *e; unsigned count=0; int all=1;
    snprintf(path,sizeof(path),"/proc/%ld/task",(long)pid);
    d=opendir(path); if(!d) return 0;
    while((e=readdir(d))) {
        if(e->d_name[0]=='.') continue;
        if(strlen(e->d_name)>12) {all=0;break;}
        snprintf(path,sizeof(path),"/proc/%ld/task/%.12s/status",(long)pid,e->d_name);
        if(!task_stopped(path)) {all=0;break;}
        count++;
    }
    closedir(d); return all && count>0;
}
static void result(const char *state) { printf("{\"state\":\"%s\"}\n",state); }
int main(int argc,char **argv)
{
    int root=-1,backup=-1,pipefd[2]={-1,-1},rc=1,held=0,detached=0;
    pid_t pid=0,watchdog=-1,parent=getpid(); unsigned tries,count; uint64_t bytes;
    char token[512],after[512],retired[64],*end;
    struct stat st; const char *state="unsafe";
    if(argc!=2 && argc!=4) {result("invalid");return 2;}
    root=open(AGH_ROOT,O_DIRECTORY|O_NOFOLLOW|O_RDONLY|O_CLOEXEC);
    if(root<0) {result("unavailable");return 0;}
    if(updating(root)) {state="updating";goto out;}
    if(unfinished_cleanup(root)) {state="cleanup-incomplete";goto out;}
    backup=openat(root,"agh-backup",O_DIRECTORY|O_NOFOLLOW|O_RDONLY|O_CLOEXEC);
    if(backup<0) {state=errno==ENOENT?"absent":"unsafe";goto out;}
    if(snapshot(backup,token,sizeof(token),&bytes)) goto out;
    if(!strcmp(argv[1],"status") && argc==2) {
        printf("{\"state\":\"ready\",\"bytes\":%" PRIu64 ",\"token\":\"%s\"}\n",bytes,token);
        rc=0; goto close_out;
    }
    if(strcmp(argv[1],"clean") || argc!=4 || strcmp(argv[2],token)) {state="changed";goto out;}
    errno=0; pid=(pid_t)strtol(argv[3],&end,10);
    if(errno || *end || pid<=1 || !same_executable(pid,root)) goto out;
    if(pipe(pipefd)) goto out;
    watchdog=fork();
    if(watchdog<0) goto out;
    if(watchdog==0) {
        struct pollfd p={pipefd[0],POLLIN,0};
        close(pipefd[1]);
        /* 父进程异常退出或卡住，也恢复原进程；不让清理故障长期阻塞 DNS。 */
        if(poll(&p,1,2000)==0) (void)kill(parent,SIGKILL);
        if(same_executable(pid,root)) (void)kill(pid,SIGCONT);
        _exit(0);
    }
    close(pipefd[0]);pipefd[0]=-1;
    if(kill(pid,SIGSTOP)) goto out;
    held=1;
#ifdef AGH_BACKUP_TEST_PAUSE
    /* 仅隔离测试构建：模拟维护进程卡死，验证看护进程恢复 DNS。 */
    raise(SIGSTOP);
#endif
    for(tries=0;tries<100 && !stopped(pid);tries++) usleep(1000);
    if(!stopped(pid) || !same_executable(pid,root) || updating(root)) {state="busy";goto out;}
    /* 停住更新器后再次核对用户看到的那份备份，只移动目录，不在暂停期间读大文件。 */
    if(snapshot(backup,after,sizeof(after),&bytes) || strcmp(token,after)) {state="changed";goto out;}
    snprintf(retired,sizeof(retired),".agh-retired-%ld",(long)getpid());
    if(!fstatat(root,retired,&st,AT_SYMLINK_NOFOLLOW) || errno!=ENOENT) goto out;
    if(renameat(root,"agh-backup",root,retired)) goto out;
    detached=1;
    /* 配套校验清单跟随旧目录隔离；新更新随后可独立创建新的 agh-backup。 */
    if(renameat(root,".validated-backup.md5",backup,".validated-backup.md5") && errno!=ENOENT) {
        state="cleanup-incomplete";goto out;
    }
    (void)kill(pid,SIGCONT);held=0;
    close(pipefd[1]);pipefd[1]=-1;
    (void)waitpid(watchdog,NULL,0);watchdog=-1;
    count=0;bytes=0;
    if(walk(backup,0,&bytes,&count,1) || unlinkat(root,retired,AT_REMOVEDIR)) {state="cleanup-incomplete";goto out;}
    state="cleaned";rc=0;
out:
    if(held) (void)kill(pid,SIGCONT);
    if(pipefd[1]>=0) close(pipefd[1]);
    if(pipefd[0]>=0) close(pipefd[0]);
    if(watchdog>0) (void)waitpid(watchdog,NULL,0);
    /* 失败后保留隔离目录供检查，绝不对活动目录继续尝试递归删除。 */
    if(detached && rc) fprintf(stderr,"backup retained at %s/%s\n",AGH_ROOT,retired);
    result(state);
close_out:
    if(backup>=0) close(backup);
    if(root>=0) close(root);
    return rc;
}
