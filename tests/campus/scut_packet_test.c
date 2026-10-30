#include <assert.h>
#include <stdarg.h>
#include <sys/socket.h>
#include <arpa/inet.h>
static unsigned char incoming[2048];
static size_t incoming_len;
static int wrong_peer;
static ssize_t fixture_recv(int fd, void *buf, size_t cap, int flags);
static ssize_t fixture_recvfrom(int fd, void *buf, size_t cap, int flags, struct sockaddr *peer, socklen_t *length);
#define recv fixture_recv
#define recvfrom fixture_recvfrom
#include "auth.c"
#undef recv
#undef recvfrom
LOGLEVEL cloglev = NONE;
int LogWrite(LOGTYPE type, LOGLEVEL level, char *fmt, ...) {return 0;}
uint32_t drcom_crc32(uint8_t *data, int length);
static ssize_t fixture_recv(int fd, void *buf, size_t cap, int flags)
{
    size_t n=incoming_len<cap?incoming_len:cap;
    memcpy(buf,incoming,n);return n;
}
static ssize_t fixture_recvfrom(int fd, void *buf, size_t cap, int flags, struct sockaddr *peer, socklen_t *length)
{
    struct sockaddr_in addr=serv_addr;
    if(wrong_peer)addr.sin_port=htons(1234);
    memcpy(peer,&addr,sizeof(addr));*length=sizeof(addr);
    return fixture_recv(fd,buf,cap,flags);
}
static void eap(unsigned code,unsigned type,unsigned length)
{
    memset(incoming,0,sizeof(incoming));
    memset(EthHeader+6,2,6);memset(incoming,2,6);
    incoming[12]=0x88;incoming[13]=0x8e;incoming[14]=1;
    incoming[16]=length>>8;incoming[17]=length;
    incoming[18]=code;incoming[20]=length>>8;incoming[21]=length;incoming[22]=type;
    incoming_len=18+length;
}
int main(int argc,char **argv)
{
    unsigned char out[ETH_FRAME_LEN], digest[16], seed[16]={0};
    assert(argc==2);memset(out,0xa5,sizeof(out));
    if(!strcmp(argv[1],"password")) {
        char pass[201];memset(pass,'a',200);pass[200]=0;
        FillMD5Area(digest,7,pass,seed);
        for(int i=0;i<16;i++)printf("%02x",digest[i]);puts("");
    } else if(!strcmp(argv[1],"hex")) {
        unsigned char v[64];memset(v,0x55,sizeof(v));
        assert(hexStrToByte("GG",v,64)<0 && v[0]==0x55);
        assert(hexStrToByte("123",v,64)<0);
        assert(hexStrToByte("01ab",v,1)<0);
        assert(hexStrToByte("01ab",v,64)==2 && v[0]==1 && v[1]==0xab);
    } else if(!strcmp(argv[1],"crc")) {
        unsigned char raw[14]={0};for(int i=1;i<14;i++)raw[i]=i;
        uint32_t expected=(0x04030201u^0x08070605u^0x0c0b0a09u)*19680126u;
        assert(drcom_crc32(raw+1,12)==expected);
    } else if(!strcmp(argv[1],"username")) {
        UserName="123456789012345678901234567890123";
        assert(Drcom_MISC_INFO_Setter(out,incoming)==0);
    } else if(!strcmp(argv[1],"eap")) {
        eap(1,1,5);assert(auth_8021x_Receiver(out)==1);
        incoming_len=14;assert(auth_8021x_Receiver(out)==0);
        eap(1,1,5);incoming[17]=255;assert(auth_8021x_Receiver(out)==0);
        eap(1,4,6);incoming[23]=16;assert(auth_8021x_Receiver(out)==0);
        eap(1,4,22);incoming[23]=16;assert(auth_8021x_Receiver(out)==1);
        incoming[23]=17;assert(auth_8021x_Receiver(out)==0);
        eap(4,0,4);assert(auth_8021x_Receiver(out)==1);
    } else if(!strcmp(argv[1],"udp")) {
        serv_addr.sin_family=AF_INET;serv_addr.sin_port=htons(61440);serv_addr.sin_addr.s_addr=htonl(0x7f000001);
        incoming[0]=7;incoming[4]=4;incoming_len=5;assert(auth_UDP_Receiver(out)==0);
        incoming_len=32;assert(auth_UDP_Receiver(out)==1);
        wrong_peer=1;assert(auth_UDP_Receiver(out)==0);wrong_peer=0;
        incoming[4]=0x0b;incoming[5]=2;incoming_len=19;assert(auth_UDP_Receiver(out)==0);
        incoming_len=20;assert(auth_UDP_Receiver(out)==1);
        memset(incoming,'x',sizeof(incoming));incoming[0]=0x4d;incoming[1]=0x38;incoming_len=ETH_FRAME_LEN-1;
        assert(auth_UDP_Receiver(out)==1 && out[ETH_FRAME_LEN-1]==0);
    } else return 2;
    puts("PASS");return 0;
}
