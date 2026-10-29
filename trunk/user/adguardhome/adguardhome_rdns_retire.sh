#!/bin/sh
# 只接受完整、带进程身份的动态地址失效快照，动作由独立适配器执行。
# 没有动作适配器时只记录待清理地址，不停止任何服务。
set -eu
umask 077
state=$1
manifest=$2
action=${3:-}
now=${ADG_RDNS_NOW:-$(cut -d. -f1 /proc/uptime)}
debounce=${ADG_RDNS_DEBOUNCE:-300}
cooldown=${ADG_RDNS_COOLDOWN:-3600}
service_lock=${ADG_RDNS_SERVICE_LOCK:-/tmp/.adguardhome_service_lock}
names_lock=${ADG_RDNS_NAMES_LOCK:-/tmp/adguardhome-hosts.lock}
case "$state" in /tmp/*|/home/*) ;; *) exit 2 ;; esac
for number in "$now" "$debounce" "$cooldown"; do case "$number" in ''|*[!0-9]*) exit 2 ;; esac; done
[ -s "$manifest" ] && [ "$(wc -c < "$manifest")" -le 65536 ] || exit 2
mkdir -p "$state"
mkdir "$state/tick.lock" 2>/dev/null || exit 0
work="$state/tick.lock"
locked=0
cleanup() {
    if [ "$locked" = 1 ]; then rm -f "$service_lock/pid"; rmdir "$service_lock"; fi
    rm -f "$work/"*
    rmdir "$work"
}
trap cleanup 0
trap 'exit 1' 1 2 15
cp "$manifest" "$work/input"
# 地址必须先规范化为 32 位小写十六进制；只允许全局单播和 ULA。
# protected 包括用户静态地址，其优先级高于 expired。
awk '
 NR==1 {if(NF!=3 || $1!="ADG_RDNS_V1" || $2!~/^[A-Za-z0-9:_-]+$/ || $3!~/^[0-9]+$/) bad=1; next}
 {if(NF!=2 || ($1!="live" && $1!="expired" && $1!="protected") || length($2)!=32 || $2~/[^0-9a-f]/ || $2!~/^(2|3|fc|fd)/) bad=1; if(++count>512) bad=1}
 END {exit bad}' "$work/input" || exit 2
identity=$(awk 'NR==1 {print $2}' "$work/input")
stamp=$(awk 'NR==1 {print $3}' "$work/input")
# 过期或倒退的快照不可据以清理，时间来自单调开机秒数。
[ "$stamp" -le "$now" ] && [ $((now-stamp)) -le 60 ] || exit 2
last_now=$(cat "$state/last-now" 2>/dev/null || echo 0)
if [ "$(cat "$state/identity" 2>/dev/null || :)" != "$identity" ] || [ "$now" -lt "$last_now" ]; then
    : > "$state/pending"
    : > "$state/done"
    # 进程换代不能绕过限频；只有开机时间倒退时才丢弃旧时间基准。
    [ "$now" -ge "$last_now" ] || rm -f "$state/last-attempt"
    printf '%s\n' "$identity" > "$state/identity"
fi
printf '%s\n' "$now" > "$state/last-now"
[ -f "$state/pending" ] || : > "$state/pending"
[ -f "$state/done" ] || : > "$state/done"
# 恢复的地址立即取消等待；无关地址增减不重置其他地址的等待时长。
awk -v now="$now" '
 FILENAME==ARGV[1] {old[$1]=$2; next}
 FILENAME==ARGV[2] {done[$1]=1; next}
 FNR>1 {if($1=="expired") expired[$2]=1; else live[$2]=1}
 END {for(ip in expired) if(!live[ip] && !done[ip]) print ip, (ip in old ? old[ip] : now)}
' "$state/pending" "$state/done" "$work/input" | LC_ALL=C sort > "$work/pending"
awk 'FILENAME==ARGV[1] {done[$1]=1; next} FNR>1 {if($1=="expired") expired[$2]=1; else live[$2]=1} END {for(ip in done) if(expired[ip] && !live[ip]) print ip}' "$state/done" "$work/input" | LC_ALL=C sort > "$work/done"
mv "$work/pending" "$state/pending"
mv "$work/done" "$state/done"
awk -v now="$now" -v delay="$debounce" 'now-$2>=delay {print $1}' "$state/pending" > "$work/due"
[ -s "$work/due" ] || exit 0
[ -n "$action" ] || { echo 'pending-observation-only'; exit 0; }
case "$action" in /*) [ -x "$action" ] || exit 2 ;; *) exit 2 ;; esac
for guard in manual-stop updating disabled unhealthy; do [ ! -e "$state/$guard" ] || exit 0; done
[ ! -d "$names_lock" ] || exit 0
last=$(cat "$state/last-attempt" 2>/dev/null || echo -1000000)
[ $((now-last)) -ge "$cooldown" ] || exit 0
mkdir "$service_lock" 2>/dev/null || exit 0
locked=1
echo $$ > "$service_lock/pid"
# 获锁后再检查；适配器还必须复核原进程、更新状态和实际服务健康。
for guard in manual-stop updating disabled unhealthy; do [ ! -e "$state/$guard" ] || exit 0; done
[ ! -d "$names_lock" ] || exit 0
# 现机 BusyBox 未启用 cmp；校验输入摘要，读取失败时不执行动作。
current_digest=$(sha256sum "$manifest" 2>/dev/null) || exit 0
snapshot_digest=$(sha256sum "$work/input" 2>/dev/null) || exit 0
[ "${current_digest%% *}" = "${snapshot_digest%% *}" ] || exit 0
printf '%s\n' "$now" > "$state/last-attempt"
if "$action" "$identity" "$work/due" "$work/input"; then
    # 整个进程缓存已清空，当前等待中的地址一并标记；失败不会谎报成功。
    { cat "$state/done"; awk '{print $1}' "$state/pending"; } | LC_ALL=C sort -u > "$work/done"
    mv "$work/done" "$state/done"
    : > "$state/pending"
    printf '%s\n' "$now" > "$state/last-success"
    echo 'retired'
else
    echo 'action-failed' >&2
    exit 1
fi
