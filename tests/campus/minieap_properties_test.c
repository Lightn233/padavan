/* 使用真实解析函数验证合法字段、旧服务器长度兼容和截断输入。 */
#include "packet_plugin_rjv3_prop.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

/* 在候选实际分配路径中注入失败，验证原记录与半成品的生命周期。 */
static int fail_after;
void *__real_malloc(size_t);
void *__real_calloc(size_t,size_t);
void *__wrap_malloc(size_t n) {
    if (fail_after>0 && --fail_after==0) return NULL;
    return __real_malloc(n);
}
void *__wrap_calloc(size_t n,size_t size) {
    if (fail_after>0 && --fail_after==0) return NULL;
    return __real_calloc(n,size);
}
static uint32_t saved_key;
void rjv3_set_keepalive_echokey(uint32_t key) { saved_key=key; }
void rjv3_set_keepalive_echono(uint32_t no) { (void)no; }
void rjv3_set_keepalive_dest_mac(uint8_t *mac) { (void)mac; }

void print_log(const char *level, const char *function, const char *format, ...) {
    (void)level; (void)function; (void)format;
}
void print_log_raw(const char *format, ...) { (void)format; }

static void parse_one(const unsigned char *input, size_t size, int bare, int expect) {
    unsigned char *buffer = malloc(size ? size : 1);
    LIST_ELEMENT *list = NULL;
    memcpy(buffer, input, size);
    RESULT result = parse_rjv3_buf_to_prop_list(&list, buffer, (int)size, bare);
    if (expect >= 0) assert(result == (expect ? SUCCESS : FAILURE));
    destroy_rjv3_prop_list(&list);
    free(buffer);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    unsigned char normal[] = {0x1a,12,0,0,0x13,0x11,0x18,6,1,2,3,4};
    if (!strcmp(argv[1], "valid")) {
        parse_one(normal,sizeof(normal),0,1);
        parse_one(normal+2,sizeof(normal)-2,1,1);
        LIST_ELEMENT *list=NULL;
        assert(append_rjv3_prop(&list,0x18,normal+8,4)==12);
        unsigned char output[12];
        assert(append_rjv3_prop_list_to_buffer(list,output,sizeof(output))==12);
        assert(!memcmp(output,normal,sizeof(output)));
        destroy_rjv3_prop_list(&list);
    } else if (!strcmp(argv[1], "legacy")) {
        unsigned char legacy[]={0,0,0x13,0x11,0,2,0x41,0x42,
                                0,0,0x13,0x11,0x18,3,0x55};
        LIST_ELEMENT *list=NULL;
        assert(parse_rjv3_buf_to_prop_list(&list,legacy,sizeof(legacy),1)==SUCCESS);
        RJ_PROP *first=find_rjv3_prop(list,0),*last=find_rjv3_prop(list,0x18);
        assert(first && last && PROP_TO_CONTENT_SIZE(first)==2 && last->content[0]==0x55);
        destroy_rjv3_prop_list(&list);
    } else if (!strcmp(argv[1], "truncated")) {
        unsigned char truncated[]={0,0,0x13,0x11,0x18,250};
        parse_one(truncated,sizeof(truncated),1,0);
    } else if (!strcmp(argv[1], "short-header")) {
        for(size_t i=1;i<8;i++) parse_one(normal,i,0,0);
    } else if (!strcmp(argv[1], "small-output")) {
        LIST_ELEMENT *list=NULL;
        assert(append_rjv3_prop(&list,0x18,normal+8,4)==12);
        assert(append_rjv3_prop(&list,0x19,normal+8,4)==12);
        unsigned char output[11];
        assert(append_rjv3_prop_list_to_buffer(list,output,sizeof(output))==-1);
        destroy_rjv3_prop_list(&list);
    } else if (!strcmp(argv[1], "negative")) {
        LIST_ELEMENT *list=NULL;
        assert(parse_rjv3_buf_to_prop_list(&list,normal,-1,0)==FAILURE);
        assert(append_rjv3_prop(&list,0x18,normal,-1)==-1);
        assert(append_rjv3_prop(&list,0x18,normal,256)==-1);
        destroy_rjv3_prop_list(&list);
    } else if (!strcmp(argv[1], "transaction")) {
        LIST_ELEMENT *list=NULL;
        assert(append_rjv3_prop(&list,0x25,normal+8,4)==12);
        LIST_ELEMENT *original=list;
        unsigned char input[sizeof(normal)+1];
        memcpy(input,normal,sizeof(normal)); input[sizeof(normal)]=0;
        assert(parse_rjv3_buf_to_prop_list(&list,input,sizeof(input),0)==FAILURE);
        assert(list==original && !list->next && !find_rjv3_prop(list,0x18));
        destroy_rjv3_prop_list(&list);
    } else if (!strcmp(argv[1], "allocation")) {
        for(int i=1;i<=3;i++) {
            LIST_ELEMENT *list=NULL;
            fail_after=i;
            assert(append_rjv3_prop(&list,0x18,normal+8,4)==-1 && !list);
            fail_after=0;
        }
        LIST_ELEMENT *list=NULL;
        assert(append_rjv3_prop(&list,0x18,normal+8,4)==12);
        RJ_PROP *prop=list->content;
        fail_after=1;
        assert(modify_rjv3_prop(list,0x18,normal+9,3)==-1);
        fail_after=0;
        assert(list->content==prop && !memcmp(prop->content,normal+8,4));
        unsigned char input[24];
        memcpy(input,normal,12); memcpy(input+12,normal,12);
        for(int i=1;i<=6;i++) {
            fail_after=i;
            assert(parse_rjv3_buf_to_prop_list(&list,input,sizeof(input),0)==FAILURE);
            fail_after=0;
            assert(list->content==prop && !list->next);
        }
        destroy_rjv3_prop_list(&list);
    } else if (!strcmp(argv[1], "boundary")) {
        unsigned char input[248]={0},output[255];
        LIST_ELEMENT *list=NULL;
        assert(append_rjv3_prop(&list,0x18,input,247)==255);
        assert(append_rjv3_prop_list_to_buffer(list,output,sizeof(output))==255);
        parse_one(output,sizeof(output),0,1);
        assert(append_rjv3_prop(&list,0x18,input,248)==-1);
        assert(modify_rjv3_prop(list,0x18,input,248)==-1);
        destroy_rjv3_prop_list(&list);
        unsigned char ending[]={0,0,0x13,0x11,0,2,0x41,0,0,0x13,0x11};
        parse_one(ending,sizeof(ending),1,0);
    } else if (!strcmp(argv[1], "remove")) {
        LIST_ELEMENT *list=NULL;
        assert(append_rjv3_prop(&list,0x18,normal+8,4)==12);
        assert(append_rjv3_prop(&list,0x19,normal+8,4)==12);
        assert(append_rjv3_prop(&list,0x18,normal+8,4)==12);
        remove_rjv3_prop(&list,0x18);
        assert(list && !list->next && find_rjv3_prop(list,0x19));
        remove_rjv3_prop(&list,0x19); assert(!list);
    } else if (!strcmp(argv[1], "echo-key")) {
        const size_t offset=sizeof(FRAME_HEADER)-1;
        for(size_t size=0;size<=12;size++) {
            unsigned char *input=calloc(1,offset+6+size);
            ETH_EAP_FRAME frame={.actual_len=offset+6+size,.buffer_len=offset+6+size,.content=input};
            frame.header->eap_hdr.code[0]=EAP_SUCCESS;
            unsigned char header[]={0,0,0x13,0x11,1,2};
            memcpy(input+offset,header,6);
            if(size>=10) {input[offset+12]=0;input[offset+13]=0xff;input[offset+14]=0x55;input[offset+15]=0xaa;}
            saved_key=0;
            RESULT result=rjv3_process_result_prop(&frame);
            assert(result==(size>=10?SUCCESS:FAILURE));
            if(size>=10) assert(saved_key==0xff0055aau);
            else assert(saved_key==0);
            free(input);
        }
    } else if (!strcmp(argv[1], "frame-bounds")) {
        for(size_t i=0;i<sizeof(FRAME_HEADER)-1;i++) {
            ETH_EAP_FRAME frame={.actual_len=i,.buffer_len=i,.content=calloc(1,i?i:1)};
            assert(rjv3_process_result_prop(&frame)==FAILURE);free(frame.content);
        }
        ETH_EAP_FRAME frame={.actual_len=100,.buffer_len=24,.content=calloc(1,24)};
        assert(rjv3_process_result_prop(&frame)==FAILURE);free(frame.content);
        assert(rjv3_process_result_prop(NULL)==FAILURE);
    } else if (!strcmp(argv[1], "fuzz")) {
        unsigned int seed=0x2100;
        for(int trial=0;trial<30000;trial++) {
            unsigned char input[300];
            seed=seed*1664525u+1013904223u;
            size_t length=seed%sizeof(input);
            for(size_t i=0;i<length;i++) {
                seed=seed*1664525u+1013904223u;
                input[i]=(unsigned char)(seed>>24);
            }
            int bare=trial&1;
            size_t offset=bare?0:2;
            if(length>=offset+6) {
                input[offset]=0;input[offset+1]=0;input[offset+2]=0x13;input[offset+3]=0x11;
                if(!bare) input[0]=0x1a;
            }
            parse_one(input,length,bare,-1);
        }
    } else return 2;
    puts("PASS");return 0;
}
