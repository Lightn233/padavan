#!/bin/sh
# 保留旧页面与 NVRAM 字段，使用独立 SmartDNS 实例完成 TCP 上游转发。
ROOT=${LEGACY_COMPAT_ROOT:-}
. "$ROOT/etc_ro/legacy-service.sh" || exit 1
compat_init dns-forwarder || exit 1
BIN=$ROOT/usr/bin/smartdns
compat_ready() {
    local n=0 sockets hex ready port
    port=$(awk '$1 == "bind" {n=split($2,a,":");print a[n];exit}' "$CONF")
    hex=$(printf '%04X' "$port") || return 1
    while [ "$n" -lt 30 ] && compat_running; do
        sockets="$(ls -l /proc/"$proc_id"/fd 2>/dev/null | sed -n 's/.* -> socket:\[\([0-9]*\)\]$/\1/p' | tr '\n' ' ')"
        if [ -n "$sockets" ]; then
            ready=$(awk -v owned=" $sockets" -v port="$hex" '
                {split($2, addr, ":")}
                addr[2] == port && index(owned, " " $10 " ") {
                    if(FILENAME ~ /\/udp6?$/ && $4 == "07") udp=1;
                    if(FILENAME ~ /\/tcp6?$/ && $4 == "0A") tcp=1
                } END {print udp+tcp}' /proc/net/udp /proc/net/udp6 /proc/net/tcp /proc/net/tcp6 2>/dev/null)
            [ "$ready" = 2 ] && return 0
        fi
        usleep 100000; n=$((n+1))
    done
    compat_fail 'DNS 转发监听未就绪，可能端口被占用'
}
case "${1:-start}" in
stop) compat_stop; exit $?;;
status) if compat_running; then echo running; else echo stopped; fi; exit 0;;
start|restart) ;;
*) echo '用法：dns-forwarder.sh start|stop|restart|status' >&2; exit 2;;
esac
[ -x "$BIN" ] || { compat_fail '未安装 SmartDNS 核心'; exit 1; }
candidate=$(mktemp "$RUN/config.XXXXXX") || exit 1
trap 'rm -f "$candidate"' EXIT HUP INT TERM
{
    printf '%s\0' "$(nvram get dns_forwarder_bind)" "$(nvram get dns_forwarder_port)" "$(nvram get dns_forwarder_server)"
    printf '%s\0' "$(ip -o addr show 2>/dev/null | awk '{print $4}') $(nvram get lan_ipaddr)"
} | "$ROOT/usr/bin/legacy-config" dns > "$candidate" || exit 1
[ "${1:-start}" != restart ] || COMPAT_FORCE=1
compat_apply "$candidate" "$BIN" -f -c "$CONF" -p "$RUN/core.pid"
