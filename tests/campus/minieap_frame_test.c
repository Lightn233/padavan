/* 检查真实帧缓冲区的复制、追加、分配失败及通知解码。 */
#include "packet_util.h"
/* 上游头文件声明与实际实现不一致，基线测试按真实实现调用。 */
void gbk2utf8(char *in, size_t inlen, char *out, size_t outlen);
void pr_info_gbk(char *in, size_t inlen);
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <iconv.h>
static int fail_after;
static int iconv_fail;
void *__real_malloc(size_t);
void *__real_calloc(size_t,size_t);
void *__wrap_malloc(size_t n){if(fail_after>0 && --fail_after==0)return NULL;return __real_malloc(n);}
void *__wrap_calloc(size_t n,size_t s){if(fail_after>0 && --fail_after==0)return NULL;return __real_calloc(n,s);}
iconv_t __real_iconv_open(const char *, const char *);
iconv_t __wrap_iconv_open(const char *to,const char *from){return iconv_fail?(iconv_t)-1:__real_iconv_open(to,from);}
void print_log(const char *level,const char *function,const char *format,...){(void)level;(void)function;char b[512];va_list a;va_start(a,format);vsnprintf(b,sizeof(b),format,a);va_end(a);}
void print_log_raw(const char *format,...){(void)format;}
int main(int argc,char **argv){
    assert(argc==2);
    if(!strcmp(argv[1],"duplicate-capacity")){
        uint8_t b[64]={0}; ETH_EAP_FRAME f={.content=b,.actual_len=22,.buffer_len=64};
        ETH_EAP_FRAME *c=frame_duplicate(&f);assert(c && c->actual_len==22 && c->buffer_len==64);
        uint8_t data[42];memset(data,0x55,sizeof(data));
        assert(append_to_frame(c,data,sizeof(data))==SUCCESS && c->actual_len==64);
        assert(append_to_frame(c,data,1)==FAILURE);free_frame(&c);assert(!c);
    }else if(!strcmp(argv[1],"duplicate-allocation")){
        uint8_t b[32]={0}; ETH_EAP_FRAME f={.content=b,.actual_len=22,.buffer_len=32};
        for(int n=1;n<=2;n++){fail_after=n;assert(frame_duplicate(&f)==NULL);fail_after=0;}
    }else if(!strcmp(argv[1],"append-invalid")){
        uint8_t b[64]={0}; ETH_EAP_FRAME f={.content=b,.actual_len=22,.buffer_len=64};
        assert(append_to_frame(&f,b,-1)==FAILURE && f.actual_len==22);
        f.actual_len=65;assert(append_to_frame(&f,b,1)==FAILURE);
        assert(frame_duplicate(&f)==NULL);
        assert(append_to_frame(NULL,b,1)==FAILURE);
        assert(frame_duplicate(NULL)==NULL);
    }else if(!strcmp(argv[1],"message-allocation")){
        char text[2]={0x41,0x42};fail_after=1;pr_info_gbk(text,sizeof(text));fail_after=0;
    }else if(!strcmp(argv[1],"message-output")){
        char *out=malloc(2);char text[4]={'a','b','c','d'};
        gbk2utf8(text,sizeof(text),out,2);free(out);
        pr_info_gbk(text,sizeof(text));pr_info_gbk(NULL,0);
    }else if(!strcmp(argv[1],"message-iconv-failure")){
        char *out=malloc(2);char text[4]={'a','b','c','d'};iconv_fail=1;
        gbk2utf8(text,sizeof(text),out,2);assert(!memcmp(out,"ab",2));free(out);
#ifdef FIXED
    }else if(!strcmp(argv[1],"receive-bounds")){
        unsigned char b[256]={0};ETH_EAP_FRAME f={.content=b,.buffer_len=sizeof(b)};
        assert(frame_validate_received(NULL)==FAILURE);
        for(size_t n=0;n<22;n++){f.actual_len=n;assert(frame_validate_received(&f)==FAILURE);}
        f.actual_len=22;b[18]=EAP_SUCCESS;assert(frame_validate_received(&f)==SUCCESS);
        b[18]=EAP_REQUEST;assert(frame_validate_received(&f)==FAILURE);
        f.actual_len=23;b[22]=IDENTITY;assert(frame_validate_received(&f)==SUCCESS);
        b[22]=MD5_CHALLENGE;
        for(size_t n=23;n<40;n++){f.actual_len=n;assert(frame_validate_received(&f)==FAILURE);}
        f.actual_len=40;b[23]=16;assert(frame_validate_received(&f)==SUCCESS);
        b[23]=17;assert(frame_validate_received(&f)==FAILURE);
        b[15]=EAPOL_START;f.actual_len=18;assert(frame_validate_received(&f)==SUCCESS);
        unsigned int seed=0x1758;
        for(int i=0;i<30000;i++){
            seed=seed*1664525u+1013904223u;size_t n=seed%257;
            unsigned char *p=malloc(n?n:1);
            for(size_t j=0;j<n;j++){seed=seed*1664525u+1013904223u;p[j]=seed>>24;}
            ETH_EAP_FRAME fuzz={.content=p,.actual_len=n,.buffer_len=n};
            frame_validate_received(&fuzz);free(p);
        }
#endif
    }else return 2;
    puts("PASS");return 0;
}
