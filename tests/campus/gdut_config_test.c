/* 使用真实配置解析器验证边界及配置提交行为。 */
#include "config.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(int argc,char **argv){
    assert(argc==3);strcpy(drcom_config.remote_ip,"192.0.2.1");
    struct config_s before=drcom_config;
    int result=parse_config(argv[2]);
    if(!strcmp(argv[1],"valid")){
        assert(result==0 && !strcmp(drcom_config.remote_ip,"192.0.2.2") && drcom_config.remote_port==61440);
        assert(drcom_config.keep_alive1_flag==0xdc && drcom_config.enable_crypt==1);
    }else if(!strcmp(argv[1],"empty")){
        assert(result==0 && !memcmp(&before,&drcom_config,sizeof(before)));
    }else {
        assert(result!=0 && !memcmp(&before,&drcom_config,sizeof(before)));
    }
    puts("PASS");return 0;
}
