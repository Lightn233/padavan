/* 旧入口转换使用固定字段和标准地址解析，不把账号或地址拼成 shell 命令。 */
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char fields[12][4097];
static void fail(const char *message) { fprintf(stderr,"旧入口配置错误：%s\n",message); exit(1); }
static void read_fields(size_t n) {
    for(size_t i=0;i<n;i++) {
        size_t j=0; int ch;
        while((ch=getchar())!=EOF && ch!=0) {
            if(j>=sizeof(fields[i])-1) fail("字段过长");
            fields[i][j++]=(char)ch;
        }
        if(ch==EOF) fail("字段不完整");
        fields[i][j]=0;
    }
    if(getchar()!=EOF) fail("出现额外字段");
}
static unsigned number(const char *s,unsigned fallback,unsigned lo,unsigned hi) {
    if(!*s) return fallback;
    for(const char *p=s;*p;p++) if(!isdigit((unsigned char)*p)) fail("数值格式无效");
    errno=0; char *end; unsigned long v=strtoul(s,&end,10);
    if(errno || *end || v<lo || v>hi) fail("数值超出范围");
    return (unsigned)v;
}
static void json_string(const char *s) {
    putchar('"');
    for(const unsigned char *p=(const unsigned char *)s;*p;p++) {
        if(*p=='"' || *p=='\\') { putchar('\\'); putchar(*p); }
        else if(*p<32) printf("\\u%04x",*p);
        else putchar(*p);
    }
    putchar('"');
}
static int ip(const char *text,unsigned char *bytes) {
    char value[128];
    if(strlen(text)>=sizeof(value)) return 0;
    strcpy(value,text);
    char *zone=strchr(value,'%');
    if(zone) {
        *zone++=0;
        if(!*zone) return 0;
        for(char *p=zone;*p;p++) if(!isalnum((unsigned char)*p) && *p!='_' && *p!='-' && *p!='.') return 0;
        if(inet_pton(AF_INET6,value,bytes)!=1) return 0;
        return AF_INET6;
    }
    if(inet_pton(AF_INET,value,bytes)==1) return AF_INET;
    if(inet_pton(AF_INET6,value,bytes)==1) return AF_INET6;
    return 0;
}
static int local_address(const char *server,int family,const unsigned char *bytes) {
    if(family==AF_INET && bytes[0]==127) return 1;
    struct in6_addr v6;
    if(family==AF_INET6) {memcpy(&v6,bytes,sizeof(v6));if(IN6_IS_ADDR_LOOPBACK(&v6))return 1;}
    unsigned char check[16];
    for(char *s=strtok(fields[3]," \t\n");s;s=strtok(NULL," \t\n")) {
        char *slash=strchr(s,'/');if(slash)*slash=0;
        int kind=ip(s,check);
        if(kind==family && memcmp(bytes,check,kind==AF_INET ? 4 : 16)==0) return 1;
    }
    (void)server;
    return 0;
}
static void dns(void) {
    read_fields(4);
    const char *bind=*fields[0]?fields[0]:"127.0.0.1";
    unsigned bindport=number(fields[1],5353,1,65535), upstreamport=53;
    if(bindport==53 || bindport==5335) fail("不能占用 dnsmasq 或 AdGuardHome 的端口");
    unsigned char a[16],b[16];
    int family=ip(bind,a);
    if(!family) fail("监听地址必须为 IPv4 或 IPv6 地址");
    char server[4097];strcpy(server,fields[2]);
    char *host=server,*sep=NULL;
    if(*host=='[') {
        host++;char *end=strchr(host,']');if(!end)fail("IPv6 上游括号不完整");
        *end=0;
        if(end[1]==':' || end[1]=='#')sep=end+1;
        else if(end[1])fail("上游地址格式无效");
    } else if((sep=strchr(host,'#'))!=NULL) *sep=0;
    else if(strchr(host,':') && strchr(host,':')==strrchr(host,':')) {sep=strchr(host,':');*sep=0;}
    if(sep) upstreamport=number(sep+1,53,1,65535);
    int remote_family=ip(host,b);
    if(!remote_family) fail("上游必须为数字 IP，可附带端口");
    int self=local_address(host,remote_family,b);
    if(remote_family==family && memcmp(a,b,family==AF_INET?4:16)==0) self=1;
    if(self && (upstreamport==bindport || upstreamport==53 || upstreamport==5335)) fail("上游指向本机 DNS，可能形成循环");
    struct in6_addr v6;
    if(remote_family==AF_INET6)memcpy(&v6,b,sizeof(v6));
    if((remote_family==AF_INET && (b[0]==0 || b[0]>=224)) ||
       (remote_family==AF_INET6 && (IN6_IS_ADDR_UNSPECIFIED(&v6) || IN6_IS_ADDR_MULTICAST(&v6)))) fail("上游地址不是单播地址");
    printf("server-name dns-forwarder-compat\ncache-size 0\nspeed-check-mode none\nresponse-mode fastest-response\ndualstack-ip-selection no\n");
    printf("bind %s%s%s:%u\nbind-tcp %s%s%s:%u\n",family==AF_INET6?"[":"",bind,family==AF_INET6?"]":"",bindport,
           family==AF_INET6?"[":"",bind,family==AF_INET6?"]":"",bindport);
    printf("server-tcp %s%s%s:%u\n",remote_family==AF_INET6?"[":"",host,remote_family==AF_INET6?"]":"",upstreamport);
}
static void domain(char *out,size_t size,const char *base,const char *name) {
    if(!*base) {out[0]=0;return;}
    if(!*name)name="www";
    int n=strcmp(name,"@")==0?snprintf(out,size,"%s",base):snprintf(out,size,"%s.%s",name,base);
    if(n<0 || (size_t)n>=size || n>253)fail("域名过长");
    char *start=out;
    if(strncmp(start,"*.",2)==0)start+=2;
    size_t len=0;
    for(char *p=start;;p++) {
        if(*p=='.' || *p==0) {if(len==0 || len>63)fail("域名标签无效");len=0;if(!*p)break;}
        else {if(!isalnum((unsigned char)*p) && *p!='-' && *p!='_')fail("域名请使用 ASCII 或 punycode");len++;}
    }
}
static void ali(void) {
    read_fields(9);
    if(!*fields[0] || !*fields[1])fail("缺少阿里云账号密钥");
    char v4a[256],v4b[256],v6[256],cmd[512];
    domain(v4a,sizeof(v4a),fields[2],fields[3]);domain(v4b,sizeof(v4b),fields[4],fields[5]);domain(v6,sizeof(v6),fields[6],fields[7]);
    if(!*v4a && !*v4b && !*v6)fail("未填写域名");
    unsigned ttl=number(fields[8],600,1,86400);
    const char *root=getenv("LEGACY_COMPAT_ROOT");if(!root)root="";
    if(strlen(root)>350 || (*root && *root!='/'))fail("测试目录无效");
    for(const char *p=root;*p;p++)if(!isalnum((unsigned char)*p) && !strchr("/_.-",*p))fail("测试目录包含不支持的字符");
    printf("{\"dnsconf\":[{\"name\":\"Padavan AliDDNS 兼容入口\",\"dns\":{\"name\":\"alidns\",\"id\":");
    json_string(fields[0]);printf(",\"secret\":");json_string(fields[1]);
    printf("},\"ttl\":\"%u\",\"ipv4\":{\"enable\":%s,\"gettype\":\"cmd\",\"cmd\":",ttl,(*v4a || *v4b)?"true":"false");
    snprintf(cmd,sizeof(cmd),"timeout 20 %s/usr/bin/aliddns-ip.sh 4",root);json_string(cmd);
    printf(",\"domains\":[");if(*v4a)json_string(v4a);if(*v4b && strcmp(v4a,v4b)!=0){if(*v4a)putchar(',');json_string(v4b);}
    printf("]},\"ipv6\":{\"enable\":%s,\"gettype\":\"cmd\",\"cmd\":",*v6?"true":"false");
    snprintf(cmd,sizeof(cmd),"timeout 20 %s/usr/bin/aliddns-ip.sh 6",root);json_string(cmd);
    printf(",\"domains\":[");if(*v6)json_string(v6);
    printf("]}}],\"notallowwanaccess\":true,\"lang\":\"zh\"}\n");
}
int main(int argc,char **argv) {
    if(argc!=2)fail("缺少转换类型");
    if(strcmp(argv[1],"dns")==0)dns();
    else if(strcmp(argv[1],"aliddns")==0)ali();
    else fail("未知转换类型");
    return ferror(stdout)?1:0;
}
