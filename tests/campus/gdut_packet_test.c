/* 直接调用生产代码的报文日志和校验，检查大包及非对齐输入。 */
#include "auth.c"
#include <assert.h>
int main(int argc,char **argv){
    assert(argc==2);
    if(!strcmp(argv[1],"log")){
        unsigned char bytes[1024];memset(bytes,0x81,sizeof(bytes));
        logger=Logger_create();assert(logger);logger->fp=tmpfile();assert(logger->fp);
        pkt_data_log("sample",bytes,sizeof(bytes));Logger_free(logger);logger=NULL;
    }else if(!strcmp(argv[1],"crc")){
        unsigned char b[9]={0,1,2,3,4,5,6,7,8};uint32_t a,c;
        memcpy(&a,b+1,4);memcpy(&c,b+5,4);
        assert(drcomCRC32(b+1,8)==(a^c));
    }
    puts("PASS");return 0;
}
