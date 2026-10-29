// 旧服务商字段只在切换后的提交中停用，原有凭据继续留在 NVRAM。
var ddnsGoToken = '';
function ddnsGoMode() {
    return support_ddns_go() && document.form.ddns_engine.value === 'ddns-go';
}
function ddnsGoRefresh() {
    if (!support_ddns_go()) return;
    $j.getJSON('/ddns_go.asp', function(data) {
        ddnsGoToken = data.csrf || '';
        var states = {running:'运行中', stopped:'已安装，未运行', absent:'未安装', working:'正在操作'};
        var ops = {failed:'操作失败，可在终端查看 /var/run/ddns-go/operation.log', success:'最近一次操作成功', working:'正在安装或回退'};
        $j('#ddns_go_status').text((states[data.state] || '状态读取失败') + (ops[data.operation] ? '；' + ops[data.operation] : ''));
        $j('#ddns_go_link').attr('href', 'http://' + location.hostname + ':' + (document.form.ddns_go_port.value || '9876') + '/');
    });
}
function ddnsGoAction(action) {
    if (!ddnsGoToken || !confirm(action === 'install' ? '安装官方 DDNS-Go v6.17.7？需要 RWFS 至少 14 MiB 空闲空间，原 DDNS 开关保持不变。' : '恢复安装前的 DDNS-Go 程序与配置？')) return;
    $j.post('/ddns_go.asp', {csrf:ddnsGoToken, action:action}, function(data) {
        if (data.error) $j('#ddns_go_status').text('操作被拒绝，请刷新页面后重试');
        else { $j('#ddns_go_status').text('请求已提交，正在处理'); setTimeout(ddnsGoRefresh, 1500); }
    }, 'json');
}
function changeDdnsEngine() {
    if (!document.form.ddns_go_port.value) document.form.ddns_go_port.value = '9876';
    if (!support_ddns_go()) {
        document.form.ddns_engine.value = 'inadyn';
        $j('#row_ddns_engine').hide();
    }
    if (ddnsGoMode()) ddns_disable();
    else if (document.form.ddns_enable_x[0].checked) ddns_enable(0);
    else ddns_disable();
    $j('#row_ddns_go').toggle(!!ddnsGoMode());
    ddnsGoRefresh();
}
function ddnsGoPreserveLegacy() {
    if (!ddnsGoMode()) return;
    $j(document.form).find('input,select').each(function() {
        if ((/^ddns2?_/.test(this.name) && !/^(ddns_enable_x|ddns_engine|ddns_go_port)$/.test(this.name)) || this.name === 'DDNSName') this.disabled = true;
    });
}
