#define SEM_BLOCK_NAME  "block"
#define SEM_COUNT_NAME  "count"
#define SYNCPPP_TIMEOUT 5

/* 多进程拨号同步接口，供 PAP 和 CHAP 共用。 */
int syncppp(int nproc);
