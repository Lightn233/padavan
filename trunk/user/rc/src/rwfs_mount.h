/* 只连接现有 RWFS，不格式化或创建卷；挂载失败留下原因并有限重试。 */
#ifndef RWFS_SYSFS
#define RWFS_SYSFS "/sys/class/ubi"
#endif
static int rwfs_attached_mtd(int ubi_num)
{
    char path[128];
    int mtd=-1;
    FILE *f;
    snprintf(path,sizeof(path),RWFS_SYSFS "/ubi%d/mtd_num",ubi_num);
    f=fopen(path,"r");
    if (!f) return errno==ENOENT ? -1 : -2;
    if (fscanf(f,"%d",&mtd)!=1) mtd=-2;
    fclose(f);
    return mtd;
}
static int mount_existing_rwfs(int mtd,const char *target)
{
    char device[32];
    int attempt, attached, saved_errno=0;
    snprintf(device,sizeof(device),"/dev/ubi%d_0",mtd);
    for (attempt=0;attempt<3;attempt++) {
        attached=rwfs_attached_mtd(mtd);
        if (attached==-1) {
            int status=doSystem("ubiattach -p /dev/mtd%d -d %d",mtd,mtd);
            attached=rwfs_attached_mtd(mtd);
            if (status!=0)
                logmessage("RWFS","连接 mtd%d 失败：状态 %d，第 %d 次",mtd,status,attempt+1);
        }
        /* 设备编号相同不保证底层分区相同，绝不挂载不匹配的分区。 */
        if (attached!=-1 && attached!=mtd) {
            logmessage("RWFS","拒绝挂载 ubi%d：实际 mtd 编号为 %d",mtd,attached);
            return -1;
        }
        if (attached==mtd) {
            if (mkdir(target,0755)<0 && errno!=EEXIST) {
                logmessage("RWFS","创建挂载目录失败：%s",strerror(errno));
                return -1;
            }
            if (mount(device,target,"ubifs",0,NULL)==0) return 0;
            saved_errno=errno;
            logmessage("RWFS","挂载 %s 失败：%s，第 %d 次",device,strerror(saved_errno),attempt+1);
            /* 设备节点可能尚未就绪；空间或文件系统错误不靠重复写入处理。 */
            if (saved_errno!=ENOENT && saved_errno!=ENODEV && saved_errno!=EAGAIN && saved_errno!=EBUSY) return -1;
        }
        if (attempt<2) usleep(250000);
    }
    logmessage("RWFS","挂载重试结束，保留原卷和数据");
    return -1;
}
