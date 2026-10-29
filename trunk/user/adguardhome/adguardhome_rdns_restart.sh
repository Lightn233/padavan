#!/bin/sh
# 只清理官方进程的内存缓存；调用者持有服务锁，不改配置、规则或持久数据。
set -eu
umask 077
# AP 不执行缓存维护重启，返回延期而非伪报清理成功。
[ "$(nvram get sw_mode)" != 3 ] || exit 1
expected=${1:-}
root=/media/mtd_rwfs/AdGuardHome
conf=/etc/storage/AdGuardHome.yaml
state=/tmp/adguardhome-state
lock=/tmp/.adguardhome_service_lock
net=/usr/bin/adguardhome-net
digest() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
identity() { printf '%s:%s:%s:%s' "$(cat /proc/sys/kernel/random/boot_id)" "$1" "$(awk '{print $22}' /proc/"$1"/stat)" "$(stat -Lc '%d:%i' /proc/$1/exe)"; }
no_update() { for path in "$root"/agh-update*; do [ ! -e "$path" ] || return 1; done; }
admin_idle() {
    # 更新下载完成前尚无 agh-update 目录；管理连接活动时延后自动清理。
    admin_pid=$(single) || return 1
    listeners=$(netstat -ltnp 2>/dev/null) || return 1
    admin_ports=$(printf '%s\n' "$listeners" | awk -v pid="$admin_pid" '$NF ~ ("^"pid"/") {port=$4;sub(/^.*:/,"",port);if(port!="5335") print port}')
    [ -n "$admin_ports" ] || return 1
    connections=$(netstat -tn 2>/dev/null) || return 1
    printf '%s\n' "$connections" | awk -v ports="$admin_ports" '
      BEGIN {n=split(ports,a,/\n/);for(i=1;i<=n;i++) known[a[i]]=1}
      {port=$4;sub(/^.*:/,"",port);if((port in known) && ($6=="ESTABLISHED" || $6=="SYN_RECV")) busy=1}
      END {exit busy}'
}
single() { set -- $(pidof AdGuardHome || :); [ "$#" = 1 ] && printf '%s' "$1"; }
healthy() {
    "$net" dns 127.0.0.1 5335 udp my.router A "$(nvram get lan_ipaddr)" &&
    "$net" dns 127.0.0.1 5335 tcp my.router A "$(nvram get lan_ipaddr)"
}
[ -x "$net" ] && [ -x "$root/AdGuardHome" ] && [ ! -L "$root/AdGuardHome" ]
[ -d "$lock" ] && [ "$(cat "$lock/pid")" = "$PPID" ]
[ ! -d /tmp/adguardhome-hosts.lock ]
[ "$(nvram get adg_enable)" = 1 ] && [ ! -e "$state/manual-stop" ]
no_update
admin_idle
old=$(single)
[ "$(identity "$old")" = "$expected" ]
program_hash=$(digest "$root/AdGuardHome")
[ -n "$program_hash" ] && [ "$program_hash" = "$(digest /proc/$old/exe)" ]
work="$lock/rdns-action.$$"
mkdir "$work"
trap 'rm -f "$work/"*; rmdir "$work" 2>/dev/null || :' 0
trap 'exit 1' 1 2 15
# 仅接受固件已知的原参数，不将任意 cmdline 作为 shell 代码执行。
printf '%s\000' "$root/AdGuardHome" --config "$conf" --work-dir "$root" --logfile /tmp/AdGuardHome.log > "$work/argv"
[ "$(digest /proc/$old/cmdline)" = "$(digest "$work/argv")" ]
healthy >/dev/null 2>&1
no_update
admin_idle
[ "$(identity "$old")" = "$expected" ]
[ "$program_hash" = "$(digest /proc/$old/exe)" ] && [ "$program_hash" = "$(digest "$root/AdGuardHome")" ]
kill -TERM "$old"
n=0
while [ -r /proc/$old/stat ] && [ "$(identity "$old")" = "$expected" ]; do
    n=$((n+1)); [ "$n" -le 15 ] || exit 1
    sleep 1
done
# 官方更新可能在最后一次检查后开始；若已换代，绝不再拉起第二个程序。
new=$(single || :)
if [ -z "$new" ]; then
    no_update
    [ "$program_hash" = "$(digest "$root/AdGuardHome")" ] || exit 1
    [ "$(nvram get adg_enable)" = 1 ] && [ ! -e "$state/manual-stop" ]
    nohup "$root/AdGuardHome" --config "$conf" --work-dir "$root" --logfile /tmp/AdGuardHome.log </dev/null >"$state/rdns-relaunch.log" 2>&1 &
    new=$!
fi
n=0
until healthy >/dev/null 2>&1; do
    kill -0 "$new" 2>/dev/null || exit 1
    n=$((n+1)); [ "$n" -le 15 ] || exit 1
    sleep 1
done
[ "$(single)" = "$new" ] && [ "$(digest /proc/$new/cmdline)" = "$(digest "$work/argv")" ]
logger -t AdGuardHome "旧前缀缓存已淘汰，进程 $old -> $new，配置和网络规则未改写" || :
