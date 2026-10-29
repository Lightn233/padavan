/* 清理只针对上一版官方备份，不提交本页的服务和 DNS 设置。 */
var aghBackupState = null;
var aghBackupCsrf = '';
var aghBackupBusy = false;
function aghBackupText(text) {
    document.getElementById('agh_backup_status').textContent = text;
}
function aghBackupRender(data) {
    aghBackupCsrf = data.csrf || '';
    aghBackupState = data.backup || {state:'failed'};
    var state = aghBackupState.state;
    var button = document.getElementById('agh_backup_clean');
    button.disabled = aghBackupBusy || state !== 'ready' || !aghBackupCsrf;
    var messages = {
        absent:'暂无上一版备份', busy:'维护操作进行中，稍后刷新',
        updating:'官方更新进行中，暂不可清理', unsafe:'备份结构异常，未执行清理',
        changed:'备份已变化，请刷新后重新确认', unverified:'当前程序尚未完成运行核验，暂不可清理',
        'service-not-ready':'服务未就绪，暂不可清理', forbidden:'请求未通过校验，请刷新页面',
        unavailable:'备份维护不可用', failed:'操作未完成，请刷新状态',
        'cleanup-incomplete':'部分清理未完成，已保留隔离备份，请检查日志', cleaned:'上一版备份已清理'
    };
    if (state === 'ready') {
        aghBackupText('上一版官方备份：' + (Number(aghBackupState.bytes)/1048576).toFixed(1) +
            ' MiB（文件逻辑大小；实际释放空间以文件系统为准）');
    } else aghBackupText(messages[state] || messages.failed);
}
function aghBackupRefresh() {
    if (aghBackupBusy) return;
    $j.ajax({url:'/adguardhome_backup.asp',dataType:'json',cache:false,timeout:10000,
        success:aghBackupRender,error:function(){aghBackupRender({backup:{state:'failed'}});}});
}
function aghBackupClean() {
    if (aghBackupBusy || !aghBackupState || aghBackupState.state !== 'ready' || !aghBackupCsrf) return;
    if (!confirm('确定清理上一版 AdGuardHome 备份吗？\n清理后无法再用这份备份回退。当前程序、设置、统计和查询记录会保留。')) return;
    aghBackupBusy = true;
    document.getElementById('agh_backup_clean').disabled = true;
    aghBackupText('正在清理上一版备份…');
    $j.ajax({url:'/adguardhome_backup.asp',type:'POST',dataType:'json',timeout:10000,
        data:{action:'clean',csrf:aghBackupCsrf,token:aghBackupState.token},
        success:function(data){
            aghBackupBusy=false;aghBackupRender(data);
            if(data.backup && data.backup.state==='cleaned') aghBackupRefresh();
        },error:function(){
            aghBackupBusy=false;aghBackupRender({backup:{state:'failed'}});
        }});
}
