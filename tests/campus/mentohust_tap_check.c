#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/if_tun.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* 仅向临时 TAP 投递正常认证交互，不接入任何物理接口或网桥。 */
static int tap = -1;
static pid_t client = -1;
static const unsigned char cm[6] = {2,0,0,0,0x82,2};
static const unsigned char sm[6] = {2,0,0,0,0x82,1};

static void cleanup(void)
{
    if (client > 0) {
        kill(client, SIGTERM);
        for (int n=0;n<50;n++) {
            if (waitpid(client, NULL, WNOHANG) == client) { client=-1; break; }
            usleep(100000);
        }
        if (client > 0) { kill(client,SIGKILL); waitpid(client,NULL,0); }
    }
    if (tap >= 0) close(tap);
}

static void fail(const char *what)
{
    fprintf(stderr,"FAIL %s: %s\n",what,strerror(errno));
    exit(1);
}

static void path(char *dst, size_t size, const char *root, const char *leaf)
{
    int n=snprintf(dst,size,"%s/%s",root,leaf);
    if(n<0 || (size_t)n>=size) fail("path");
}

static int receive(unsigned char *buf, int kind, int code, int type)
{
    struct timespec start,now;
    clock_gettime(CLOCK_MONOTONIC,&start);
    for (;;) {
        struct pollfd p={tap,POLLIN,0};
        clock_gettime(CLOCK_MONOTONIC,&now);
        if(now.tv_sec-start.tv_sec>=9) {errno=ETIMEDOUT;fail("normal response");}
        if(poll(&p,1,150)<=0) continue;
        int n=read(tap,buf,4096);
        if(n<18 || memcmp(buf+6,cm,6) || buf[12]!=0x88 || buf[13]!=0x8e || buf[15]!=kind) continue;
        if(code>=0 && (n<22 || buf[18]!=code)) continue;
        if(type>=0 && (n<23 || buf[22]!=type)) continue;
        return n;
    }
}

static void send_eap(int code,int id,const unsigned char *body,size_t len,size_t tail)
{
    unsigned char b[256]={0};
    if(22+len+tail>sizeof(b)) fail("test frame length");
    memcpy(b,cm,6); memcpy(b+6,sm,6);
    b[12]=0x88;b[13]=0x8e;b[14]=1;b[15]=0;
    b[16]=(len+4)>>8;b[17]=len+4;
    b[18]=code;b[19]=id;b[20]=(len+4)>>8;b[21]=len+4;
    if(len) memcpy(b+22,body,len);
    size_t size=22+len+tail;
    if(write(tap,b,size)!=(ssize_t)size) fail("write tap");
}

int main(int argc,char **argv)
{
    char file[512],libs[512];
    unsigned char b[4096];
    struct ifreq r;
    if(argc!=2 || argv[1][0]!='/') return 2;
    setvbuf(stdout,NULL,_IOLBF,0);
    atexit(cleanup);
    tap=open("/dev/net/tun",O_RDWR|O_CLOEXEC);
    if(tap<0) fail("open tun");
    memset(&r,0,sizeof(r));strcpy(r.ifr_name,"u12mento");r.ifr_flags=IFF_TAP|IFF_NO_PI;
    if(ioctl(tap,TUNSETIFF,&r)<0) fail("create tap");
    int ctl=socket(AF_INET,SOCK_DGRAM|SOCK_CLOEXEC,0);
    if(ctl<0) fail("control socket");
    r.ifr_hwaddr.sa_family=ARPHRD_ETHER;memcpy(r.ifr_hwaddr.sa_data,cm,6);
    if(ioctl(ctl,SIOCSIFHWADDR,&r)<0) fail("tap mac");
    struct sockaddr_in *addr=(struct sockaddr_in *)&r.ifr_addr;
    memset(addr,0,sizeof(*addr));addr->sin_family=AF_INET;
    inet_pton(AF_INET,"10.239.82.2",&addr->sin_addr);
    if(ioctl(ctl,SIOCSIFADDR,&r)<0) fail("tap address");
    inet_pton(AF_INET,"255.255.255.0",&addr->sin_addr);
    if(ioctl(ctl,SIOCSIFNETMASK,&r)<0) fail("tap netmask");
    r.ifr_flags=IFF_UP;
    if(ioctl(ctl,SIOCSIFFLAGS,&r)<0) fail("tap up");
    close(ctl);
    client=fork();
    if(client<0) fail("fork");
    if(client==0) {
        /* 挂载变化只存在于测试子进程，配置和 PID 文件不会写入真实 /etc 或 /var/run。 */
        if(unshare(CLONE_NEWNS)<0) _exit(101);
        if(mount(NULL,"/",NULL,MS_REC|MS_PRIVATE,NULL)<0) _exit(102);
        path(file,sizeof(file),argv[1],"etc");
        if(mount(file,"/etc",NULL,MS_BIND,NULL)<0) _exit(103);
        path(file,sizeof(file),argv[1],"run");
        if(mount(file,"/var/run",NULL,MS_BIND,NULL)<0) _exit(104);
        path(file,sizeof(file),argv[1],"client.log");
        int log=open(file,O_WRONLY|O_CREAT|O_TRUNC,0600);
        if(log<0) _exit(105);
        dup2(log,STDOUT_FILENO);dup2(log,STDERR_FILENO);close(log);
        path(libs,sizeof(libs),argv[1],"lib");setenv("LD_LIBRARY_PATH",libs,1);
        path(file,sizeof(file),argv[1],"bin_mentohust");
        execl(file,file,"-ulab-user","-plab-password","-nu12mento","-b0","-d0","-a0","-t2","-e1","-r1","-v0.0",(char *)NULL);
        _exit(106);
    }
    receive(b,1,-1,-1);puts("PASS start");
    for(int cycle=0;cycle<2;cycle++) {
        int id=31+cycle*10;
        unsigned char body[18]={4,16};
        const unsigned char identity=1;
        send_eap(1,id,&identity,1,0);
        int n=receive(b,0,2,1);
        if(n<31 || b[19]!=id || memcmp(b+23,"lab-user",8)) fail("identity");
        printf("PASS identity-%d\n",cycle);
        for(int i=0;i<16;i++) body[i+2]=i;
        send_eap(1,id+1,body,sizeof(body),0);
        n=receive(b,0,2,4);
        if(n<40 || b[19]!=id+1 || b[23]!=16) fail("challenge response");
        printf("MD5 %d ",id+1);for(int i=24;i<40;i++)printf("%02x",b[i]);puts("");
        send_eap(3,id+1,NULL,0,139);
        receive(b,0xbf,-1,-1);printf("PASS heartbeat-%d\n",cycle);
        if(!cycle) {send_eap(4,id+2,NULL,0,0);receive(b,1,-1,-1);puts("PASS reauth");}
    }
    kill(client,SIGTERM);
    int status;
    for(int n=0;n<50;n++) {
        if(waitpid(client,&status,WNOHANG)==client) {
            client=-1;
            if(!WIFEXITED(status)||WEXITSTATUS(status)!=0) fail("graceful exit");
            puts("PASS graceful-stop");return 0;
        }
        usleep(100000);
    }
    errno=ETIMEDOUT;fail("stop deadline");
    return 1;
}
