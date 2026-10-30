#!/bin/sh
# 旧账号字段继续有效；DDNS-Go 使用独立配置，不覆盖用户在新页面创建的配置。
ROOT=${LEGACY_COMPAT_ROOT:-}
. "$ROOT/etc_ro/legacy-service.sh" || exit 1
compat_init aliddns || exit 1
BIN=$ROOT/media/mtd_rwfs/ddns-go/ddns-go
action=${1:-check}
case "$action" in
stop) compat_stop; compat_stop_legacy; exit $?;;
status) if compat_running; then echo running; elif [ -n "$(compat_legacy_pids)" ]; then echo legacy; else echo stopped; fi; exit 0;;
start|restart|check|keep|export) ;;
*) echo '用法：aliddns.sh start|stop|restart|check|keep|status|export' >&2; exit 2;;
esac
if [ "$action" != export ] && { [ "$(nvram get aliddns_enable)" != 1 ] || [ "$(nvram get sw_mode)" = 3 ]; }; then
    compat_stop; compat_stop_legacy; exit 0
fi
core_compatible=1
if [ "$action" != export ] && [ -x "$BIN" ] && ! compat_running && [ "$(sha256sum "$BIN" | awk '{print $1}')" = 0e4fb1db68ab5c85c4852289270bcd5c7cdb116b7fc9ee80b6cd46e4d8706a84 ]; then
    # 此旧预编译包在 MIPS TLS 联调中触发未对齐访问，暂用原更新器。
    core_compatible=0
fi
if [ "$action" != export ] && { [ ! -x "$BIN" ] || [ "$core_compatible" = 0 ] || [ "$(nvram get aliddns_backend)" = legacy ]; }; then
    # 未安装可选核心的旧固件继续可用，不因升级空置原来的 DDNS 配置。
    compat_stop
    [ -x "$ROOT/usr/bin/aliddns-legacy.sh" ] || exit 1
    exec "$ROOT/usr/bin/aliddns-legacy.sh" "$action" 9>&-
fi
candidate=$(mktemp "$RUN/config.XXXXXX") || exit 1
trap 'rm -f "$candidate"' EXIT HUP INT TERM
{
    for field in aliddns_ak aliddns_sk aliddns_domain aliddns_name aliddns_domain2 aliddns_name2 aliddns_domain6 aliddns_name6 aliddns_ttl; do
        printf '%s\0' "$(nvram get "$field")"
    done
} | "$ROOT/usr/bin/legacy-config" aliddns > "$candidate" || exit 1
if [ "$action" = export ]; then
    mv -f "$candidate" "$RUN/export.json"
    echo "$RUN/export.json"
    exit 0
fi
[ -x "$BIN" ] || { compat_fail '请先通过 DDNS-Go 安装入口安装兼容核心；旧账号和域名已保留'; exit 1; }
interval=$(nvram get aliddns_interval)
[ -n "$interval" ] || interval=600
case "$interval" in *[!0-9]*|'') compat_fail '更新周期无效'; exit 1;; esac
[ "${#interval}" -le 6 ] && [ "$interval" -ge 10 ] && [ "$interval" -le 86400 ] || { compat_fail '更新周期应为 10 至 86400 秒'; exit 1; }
if [ "$action" = restart ] || [ "$(cat "$RUN/interval" 2>/dev/null)" != "$interval" ]; then COMPAT_FORCE=1; fi
compat_stop_legacy
if compat_apply "$candidate" "$BIN" -noweb -c "$CONF" -f "$interval"; then
    printf '%s\n' "$interval" > "$RUN/interval"
    nvram set 'aliddns_last_act=DDNS-Go 兼容进程已启动，请核对域名解析结果'
else exit 1; fi
