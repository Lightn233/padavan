#define NO_NOTIFY 1
#define NO_DYLOAD 1
#define main mentohust_program_main
#include "mentohust.c"
#undef main
#include <assert.h>
#include <stdint.h>

pcap_t *hPcap;
volatile int state=ID_START;
u_char *fillBuf;
const u_char *capBuf;
unsigned startMode,dhcpMode,maxFail;
u_char destMAC[6],gateMAC[6]={0xfe};
u_int32_t rip,gateway;
int lockfd=-1;
static int calls,echoes;
int switchState(int s){state=s;calls++;return 0;}
int restart(void){state=ID_START;calls++;return 0;}
char *formatHex(const void *p,int n){return "test";}
char *formatIP(u_int32_t p){return "127.0.0.1";}
char *gbk2utf(char *p,size_t n){char *r=malloc(n+1);assert(r);memcpy(r,p,n);r[n]=0;return r;}
void getEchoKey(const u_char *p){volatile unsigned v=p[0x1c+p[0x1b]+0x69+27];(void)v;echoes++;}
static u_char *packet(size_t n,unsigned code,unsigned type){
 u_char *p=calloc(n?n:1,1);assert(p);
 if(n>=14){p[12]=0x88;p[13]=0x8e;}
 if(n>=18){p[16]=(n-18)>>8;p[17]=(n-18)&255;}
 if(n>=22){p[18]=code;p[19]=77;p[20]=p[16];p[21]=p[17];}
 if(n>=23)p[22]=type;
 return p;
}
static void receive(u_char *p,size_t n){struct pcap_pkthdr h={{0,0},n,n};pcap_handle(NULL,&h,p);}
int main(int argc,char **argv){
 assert(argc==2);const char *c=argv[1];u_char *p;
 if(!strcmp(c,"short")){for(size_t n=0;n<22;n++){p=packet(n,1,1);receive(p,n);free(p);}assert(calls==0);}
 else if(!strcmp(c,"identity")){p=packet(23,1,1);receive(p,23);assert(state==ID_IDENTITY);free(p);}
 else if(!strcmp(c,"outer-length")){p=packet(24,1,1);p[16]=255;p[17]=255;receive(p,24);assert(!calls);free(p);}
 else if(!strcmp(c,"challenge")){p=packet(40,1,4);p[23]=16;receive(p,40);assert(state==ID_CHALLENGE);free(p);}
 else if(!strcmp(c,"short-challenge")){p=packet(30,1,4);p[23]=16;receive(p,30);assert(!calls);free(p);}
 else if(!strcmp(c,"short-success")){p=packet(22,3,0);receive(p,22);assert(!calls);free(p);}
 else if(!strcmp(c,"success")){p=packet(161,3,0);p[16]=0;p[17]=4;p[20]=0;p[21]=4;receive(p,161);assert(state==ID_ECHO&&echoes==1);free(p);}
 else if(!strcmp(c,"failure")){p=packet(22,4,0);startMode=2;receive(p,22);assert(calls==1);free(p);}
 else if(!strcmp(c,"rj-message")){p=packet(31,4,0);p[27]=3;memcpy(p+28,"abc",3);showRuijieMsg(p,31);free(p);}
 else if(!strcmp(c,"cernet-message")){p=packet(26,1,2);memcpy(p+23,"abc",3);receive(p,26);free(p);}
 else if(!strcmp(c,"saved-request")){p=packet(23,1,1);startMode=2;receive(p,23);memset(p,0,23);free(p);assert(capBuf[19]==77);}
 else if(!strcmp(c,"fuzz")){uint32_t seed=7;for(unsigned i=0;i<30000;i++){seed=1664525*seed+1013904223;size_t n=seed%260;p=malloc(n?n:1);for(size_t j=0;j<n;j++){seed=1664525*seed+1013904223;p[j]=seed>>24;}startMode=0;receive(p,n);free(p);}}
 else return 2;
 puts("PASS");return 0;
}
