#!/bin/sh
# 检查真实 DNS 应答；故障计数和重试预算只保存在 RAM。
umask 077
STATE=${ADG_STATE_DIR:-/tmp/adguardhome-state}
NET=${ADG_NET_HELPER:-/usr/bin/adguardhome-net}
SERVICE=${ADG_SERVICE_SCRIPT:-/usr/bin/adguardhome.sh}
TEST=${ADG_HEALTH_TEST_ROOT:-}
[ -x "$NET" ] || NET=/etc/storage/adguardhome-fix/adguardhome-net
# AP 没有本固件管理的 DNS 接管，不累计失败或触发恢复；用户设置不变。
if [ -z "$TEST" ] && [ "$(nvram get sw_mode)" = 3 ]; then
    exit 0
fi
mkdir -p "$STATE"

if [ -n "$TEST" ]; then
    # 隔离测试不调用服务、网络命令或系统日志。
    [ -n "${ADG_STATE_DIR:-}" ] && [ "$STATE" != /tmp/adguardhome-state ] || exit 2
    [ -d "$TEST" ] || exit 2
fi
number()
{
    value=$(cat "$STATE/$1" 2>/dev/null)
    case "$value" in ''|*[!0-9]*) value=0 ;; esac
    echo "$value"
}
set_status()
{
    [ "$(cat "$STATE/health.status" 2>/dev/null)" = "$1" ] && return 0
    echo "$1" > "$STATE/health.status"
    [ -n "$TEST" ] || logger -t AdGuardHome "$2"
}
action()
{
    if [ -n "$TEST" ]; then
        echo "$now $*" >> "$STATE/test-actions"
        case "$1" in fallback) : > "$STATE/health-fallback" ;; resume) rm -f "$STATE/health-fallback" ;; esac
        return 0
    fi
    "$SERVICE" "$1" >/dev/null 2>&1
}
read_input()
{
    if [ -n "$TEST" ]; then
        enabled=$(cat "$TEST/enabled")
        now=$(cat "$TEST/now")
        udp=$(cat "$TEST/udp")
        tcp=$(cat "$TEST/tcp")
        updating=$(cat "$TEST/updating")
        wan=$(cat "$TEST/wan")
        ra_ready=$(cat "$TEST/ra_ready")
        gateway=$(cat "$TEST/gateway")
        public=$(cat "$TEST/public")
        direct=$(cat "$TEST/direct")
        carrier=$(cat "$TEST/carrier")
        return 0
    fi
    enabled=$(nvram get adg_enable)
    now=$(cut -d. -f1 /proc/uptime)
    updating=0
    for update_dir in /media/mtd_rwfs/AdGuardHome/agh-update-*; do
        [ ! -d "$update_dir" ] || updating=1
    done
    udp=12; tcp=12
    if [ "$enabled" = 1 ] && [ ! -e "$STATE/manual-stop" ] && [ -x "$NET" ]; then
        lan_ip=$(nvram get lan_ipaddr)
        "$NET" dns 127.0.0.1 5335 udp my.router A "$lan_ip" >/dev/null 2>&1; udp=$?
        "$NET" dns 127.0.0.1 5335 tcp my.router A "$lan_ip" >/dev/null 2>&1; tcp=$?
    fi
    wan=$(nvram get wan0_ifname)
    ra_ready=0; gateway=0
    case "$wan" in ''|br0|lo|*[!a-zA-Z0-9_.:-]*) return 0 ;; esac
    carrier=$(cat "/sys/class/net/$wan/carrier" 2>/dev/null)
    ra_accept=$(cat "/proc/sys/net/ipv6/conf/$wan/accept_ra" 2>/dev/null)
    if [ "$carrier" = 1 ] && { [ "$ra_accept" = 1 ] || [ "$ra_accept" = 2 ]; } &&
        ip -6 addr show dev "$wan" scope global 2>/dev/null | grep -q 'inet6 '; then
        ra_ready=1
    fi
    ip -6 route show default dev "$wan" 2>/dev/null | grep -q '^default via ' && gateway=1
}
check_public_dns()
{
    last=$(number upstream.last)
    { [ "$last" = 0 ] || [ $((now-last)) -ge 300 ] || [ "$now" -lt "$last" ]; } || return 0
    echo "$now" > "$STATE/upstream.last"
    if [ -z "$TEST" ]; then
        # 只诊断，不用公网失败触发本地服务重启或改写用户的上游。
        "$NET" dns 127.0.0.1 5335 udp dns.alidns.com A >/dev/null 2>&1; public=$?
        direct=12
        if [ "$public" != 0 ]; then
            resolver=$(awk '$1=="nameserver" && $2!~/^(127\.|::1$)/ {print $2; exit}' /etc/resolv.conf)
            if [ -n "$resolver" ]; then
                "$NET" dns "$resolver" 53 udp dns.alidns.com A >/dev/null 2>&1; direct=$?
            fi
        fi
    fi
    if [ "$public" = 0 ]; then upstream=ok
    elif [ "$direct" = 0 ]; then upstream=adguard-upstream-or-rule
    elif [ "$carrier" != 1 ]; then upstream=wan-link-down
    else upstream=provider-dns-or-route
    fi
    if [ "$(cat "$STATE/upstream.status" 2>/dev/null)" != "$upstream" ]; then
        echo "$upstream" > "$STATE/upstream.status"
        [ -n "$TEST" ] || logger -t AdGuardHome "公网 DNS 检查：$upstream；本地服务按独立检查结果处理"
    fi
}
maintain_ra()
{
    if [ "$ra_ready" != 1 ] || [ "$gateway" = 1 ]; then
        rm -f "$STATE/ra.missing" "$STATE/ra.attempts" "$STATE/ra.window" "$STATE/ra.last"
        return 0
    fi
    missing=$(number ra.missing)
    missing=$((missing+1)); echo "$missing" > "$STATE/ra.missing"
    [ "$missing" -ge 2 ] || return 0
    window=$(number ra.window)
    if [ "$window" = 0 ] || [ $((now-window)) -ge 1800 ] || [ "$now" -lt "$window" ]; then
        echo "$now" > "$STATE/ra.window"
        echo 0 > "$STATE/ra.attempts"
        echo 0 > "$STATE/ra.last"
    fi
    attempts=$(number ra.attempts); last=$(number ra.last)
    [ "$attempts" -lt 3 ] || return 0
    { [ "$last" = 0 ] || [ $((now-last)) -ge 60 ]; } || return 0
    echo $((attempts+1)) > "$STATE/ra.attempts"
    echo "$now" > "$STATE/ra.last"
    if [ -n "$TEST" ]; then
        echo "$now rs $wan" >> "$STATE/test-actions"
    elif [ -x "$NET" ]; then
        "$NET" rs "$wan" >/dev/null 2>&1 &&
            logger -t AdGuardHome "IPv6 默认网关缺失，已在 $wan 发送一次 RS（本轮 $((attempts+1))/3）"
    fi
}
tick()
{
    [ -n "$TEST" ] || [ ! -d /tmp/.adguardhome_service_lock ] || return 0
    read_input
    case "$now" in ''|*[!0-9]*) return 2 ;; esac
    if [ "$enabled" != 1 ] || [ -e "$STATE/manual-stop" ]; then
        echo 0 > "$STATE/health.failures"
        echo 0 > "$STATE/health.good"
        set_status disabled '用户已停止 AdGuardHome，跳过自动恢复'
        return 0
    fi
    if [ -z "$TEST" ] && [ ! -x "$NET" ]; then
        set_status probe-unavailable '缺少 DNS 检查程序，暂不自动重启服务'
        return 1
    fi
    maintain_ra
    if [ "$udp" = 0 ] && [ "$tcp" = 0 ]; then
        echo 0 > "$STATE/health.failures"
        echo 0 > "$STATE/update.since"
        good=$(number health.good); good=$((good+1))
        echo "$good" > "$STATE/health.good"
        if [ -e "$STATE/health-fallback" ] && [ "$good" -ge 2 ]; then
            action resume || return 1
        fi
        if [ -e "$STATE/health-fallback" ]; then
            set_status recovering 'DNS 已恢复响应，等待下一轮确认后恢复接管'
        else
            set_status healthy 'AdGuardHome 本地 TCP/UDP 查询正常'
        fi
        check_public_dns
        return 0
    fi
    echo 0 > "$STATE/health.good"
    # 有效的负答复可能来自用户规则；不能据此反复重启或绕过过滤。
    if [ "$udp" = 10 ] || [ "$tcp" = 10 ]; then
        echo 0 > "$STATE/health.failures"
        set_status local-answer-mismatch 'DNS 有响应但本地名称答案不匹配，请检查本地规则；暂不自动重启'
        return 0
    fi
    if [ "$updating" = 1 ]; then
        since=$(number update.since)
        if [ "$since" = 0 ]; then since=$now; echo "$since" > "$STATE/update.since"; fi
        if [ $((now-since)) -lt 90 ]; then
            set_status updating '官方更新进行中，等待程序恢复'
            return 0
        fi
    else
        echo 0 > "$STATE/update.since"
    fi
    failures=$(number health.failures); failures=$((failures+1))
    echo "$failures" > "$STATE/health.failures"
    if [ "$failures" -lt 3 ]; then
        set_status suspect '本地 DNS 检查未通过，等待连续检查确认'
        return 0
    fi
    if [ ! -e "$STATE/health-fallback" ]; then action fallback || return 1; fi
    set_status fallback 'AdGuardHome 连续未响应，已撤销接管并恢复基础 DNS'
    # 官方更新目录仍存在时只做回退，不终止或重启更新进程。
    [ "$updating" != 1 ] || return 0
    window=$(number health.window)
    if [ "$window" = 0 ] || [ $((now-window)) -ge 1800 ] || [ "$now" -lt "$window" ]; then
        echo "$now" > "$STATE/health.window"
        echo 0 > "$STATE/health.attempts"
        echo 0 > "$STATE/health.last"
    fi
    attempts=$(number health.attempts); last=$(number health.last)
    [ "$attempts" -lt 3 ] || return 0
    { [ "$last" = 0 ] || [ $((now-last)) -ge 300 ]; } || return 0
    echo $((attempts+1)) > "$STATE/health.attempts"
    echo "$now" > "$STATE/health.last"
    action recover
}
tick
