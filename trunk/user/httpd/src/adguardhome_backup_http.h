/* 复用后台认证；删除另需 POST、同源页面取得的随机令牌和备份快照令牌。 */
static int agh_backup_post;
static char agh_backup_csrf[65];
static void do_agh_backup_post(const char *url, FILE *stream, int clen, char *boundary)
{
    agh_backup_post=0;
    do_html_apply_post(url,stream,clen,boundary);
    if (!http_input_error) agh_backup_post=1;
}
static void do_agh_backup(const char *url, FILE *stream)
{
    char cmd[640],body[2048]; unsigned char random[32];
    const char *csrf,*action,*token; size_t i,n; FILE *p;
    int post=agh_backup_post;
    (void)url;
    agh_backup_post=0;
    if(!agh_backup_csrf[0]) {
        p=fopen("/dev/urandom","rb");
        if(!p) {fputs("{\"backup\":{\"state\":\"unavailable\"}}",stream);return;}
        n=fread(random,1,sizeof(random),p);fclose(p);
        if(n!=sizeof(random)) {fputs("{\"backup\":{\"state\":\"unavailable\"}}",stream);return;}
        for(i=0;i<sizeof(random);i++) sprintf(agh_backup_csrf+i*2,"%02x",random[i]);
    }
    strcpy(cmd,"/usr/bin/adguardhome_backup.sh status");
    if(post) {
        csrf=get_cgi("csrf");action=get_cgi("action");token=get_cgi("token");
        if(!get_login_safe() || !csrf || strcmp(csrf,agh_backup_csrf) ||
            !action || strcmp(action,"clean") || !token || !*token || strlen(token)>511 ||
            strspn(token,"0123456789abcdef-")!=strlen(token)) {
            fputs("{\"backup\":{\"state\":\"forbidden\"}}",stream);return;
        }
        snprintf(cmd,sizeof(cmd),"/usr/bin/adguardhome_backup.sh clean %s",token);
    }
    p=popen(cmd,"r");
    if(!p) {fputs("{\"backup\":{\"state\":\"unavailable\"}}",stream);return;}
    n=fread(body,1,sizeof(body)-1,p);body[n]=0;pclose(p);
    if(n<2 || body[0]!='{' || !strchr(body,'}')) strcpy(body,"{\"state\":\"failed\"}");
    fprintf(stream,"{\"csrf\":\"%s\",\"backup\":%s}\n",agh_backup_csrf,body);
}
