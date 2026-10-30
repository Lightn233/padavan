#include <assert.h>
#include <sys/socket.h>
#include <netinet/in.h>
static unsigned char captured[512];
static size_t captured_size;
static ssize_t test_send(int,const void *,size_t,int,const struct sockaddr *,socklen_t);
static ssize_t test_recv(int,void *,size_t,int,struct sockaddr *,socklen_t *);
#define sendto test_send
#define recvfrom test_recv
#include "auth.c"
#undef sendto
#undef recvfrom
struct config drcom_config;
char mode[10],bind_ip[20];char *log_path;
int verbose_flag,logging_flag,eternal_flag,eapol_flag;
static ssize_t test_send(int fd,const void *p,size_t n,int flags,const struct sockaddr *a,socklen_t l)
{assert(n<=sizeof(captured));memcpy(captured,p,n);captured_size=n;return n;}
static ssize_t test_recv(int fd,void *p,size_t n,int flags,struct sockaddr *a,socklen_t *l)
{struct sockaddr_in addr={.sin_family=AF_INET};assert(n>=100);memset(p,0,100);((unsigned char *)p)[0]=4;memcpy(a,&addr,sizeof(addr));*l=sizeof(addr);return 100;}
int main(void)
{
    unsigned char seed[4]={1,2,3,4},auth[16],input[101],digest[16];
    struct sockaddr_in addr={.sin_family=AF_INET};
    strcpy(drcom_config.username,"lab");strcpy(drcom_config.host_ip,"0.0.0.0");strcpy(drcom_config.PRIMARY_DNS,"0.0.0.0");strcpy(drcom_config.dhcp_server,"0.0.0.0");
    for(int ror=0;ror<2;ror++)for(int jlu=0;jlu<2;jlu++)for(int n=1;n<=(ror?16:19);n++) {
        drcom_config.ror_version=ror;memset(drcom_config.password,'p',n);drcom_config.password[n]=0;
        assert(dhcp_login(0,addr,seed,auth,jlu)==0);assert(captured_size>=330);
        memcpy(input,captured,97);memcpy(input+97,"\x14\x00\x07\x0b",4);MD5(input,sizeof(input),digest);
        assert(memcmp(captured+97,digest,8)==0);
    }
    puts("PASS");return 0;
}
