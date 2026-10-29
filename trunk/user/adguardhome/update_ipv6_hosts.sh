#!/bin/sh
# 同步 LAN 的 IPv4/IPv6 名称；沿用旧文件名以兼容已保存的配置。
set -eu
umask 077
HOSTS_FILE=${ADG_HOSTS_FILE:-/etc/storage/dnsmasq/hosts_ipv6}
PTR_FILE=${ADG_PTR_FILE:-/etc/storage/dnsmasq/dnsmasq_ipv6_ptr}
LEASES=${ADG_LEASES_FILE:-/tmp/dnsmasq.leases}
SYSTEM_HOSTS=${ADG_SYSTEM_HOSTS_FILE:-/etc/hosts}
STATIC_HOSTS=${ADG_STATIC_HOSTS_FILE:-/etc/storage/dnsmasq/hosts}
RENDERER=${ADG_HOSTS_RENDERER:-/usr/bin/adguardhome_hosts.awk}
[ -r "$RENDERER" ] || RENDERER=/etc/storage/adguardhome-fix/adguardhome_hosts.awk
LOCK=${ADG_NAMES_LOCK:-/tmp/adguardhome-hosts.lock}
RESTART_SCRIPT=${ADG_RESTART_SCRIPT:-/sbin/restart_dhcpd}
TEST_MODE=${ADG_NAMES_TEST:-0}
CACHE=${ADG_NAMES_CACHE:-/tmp/adguardhome-names.cache}
CACHE_SAVE=/media/mtd_rwfs/adguardhome-names.cache
CACHE_STAMP=/tmp/adguardhome-names.last-save

if [ "$TEST_MODE" = 1 ]; then
    # 测试必须显式给出全部输入、输出；不向正式服务发送信号。
    : "${ADG_HOSTS_FILE:?}" "${ADG_PTR_FILE:?}" "${ADG_LEASES_FILE:?}"
    : "${ADG_SYSTEM_HOSTS_FILE:?}" "${ADG_STATIC_HOSTS_FILE:?}" "${ADG_NEIGH_FILE:?}"
    : "${ADG_HOSTS_RENDERER:?}" "${ADG_NAMES_LOCK:?}" "${ADG_LOCAL_DOMAIN?}" "${ADG_LAN6_FILE:?}"
    # 原有回归默认关闭缓存；启用时必须指向独立文件，禁止访问正式 RWFS。
    CACHE=${ADG_NAMES_CACHE:-}
    CACHE_SAVE=${ADG_NAMES_CACHE_SAVE:-}
    CACHE_STAMP=${ADG_NAMES_CACHE_STAMP:-}
    if [ -n "$CACHE" ]; then
        : "${ADG_LAN_IPV4:?}" "${ADG_LAN_MASK:?}" "${ADG_NEIGH4_FILE:?}"
        [ -z "$CACHE_SAVE" ] || : "${ADG_NAMES_CACHE_STAMP:?}" "${ADG_UPTIME_SECONDS:?}"
    fi
elif ! awk '$2=="/media/mtd_rwfs" && $3=="ubifs" && (","$4",") ~ /,rw,/ {found=1} END {exit !found}' /proc/mounts; then
    # RWFS 没有实际挂载时只使用 RAM，不能在挂载点下创建伪持久文件。
    CACHE_SAVE=
fi

if ! mkdir "$LOCK" 2>/dev/null; then
    owner=$(cat "$LOCK/pid" 2>/dev/null || :)
    case "$owner" in
        ''|*[!0-9]*) exit 1 ;;
        *) kill -0 "$owner" 2>/dev/null && exit 0 ;;
    esac
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null && mkdir "$LOCK" || exit 1
fi
echo $$ > "$LOCK/pid"
work="/tmp/adguardhome-names.$$"
# 固件的 BusyBox 未编入 mktemp，mkdir 负责拒绝复用已有目录。
if ! mkdir "$work"; then
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null || :
    exit 1
fi
cleanup()
{
    rm -f "$work/"*
    rmdir "$work" 2>/dev/null || :
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null || :
}
trap cleanup 0
trap 'exit 1' 1 2 15

same_file()
{
    [ -f "$1" ] && [ -f "$2" ] || return 1
    first=$(md5sum "$1" | cut -d' ' -f1)
    second=$(md5sum "$2" | cut -d' ' -f1)
    [ -n "$first" ] && [ "$first" = "$second" ]
}
read_cache()
{
    : > "$work/cache"
    [ -n "$CACHE" ] || return 0
    for cache_source in "$CACHE" "$CACHE_SAVE"; do
        [ -n "$cache_source" ] && [ -f "$cache_source" ] || continue
        [ "$(wc -c < "$cache_source")" -le 65536 ] || continue
        [ "$(head -n 1 "$cache_source")" = "$cache_header" ] || continue
        cp "$cache_source" "$work/cache"
        break
    done
}
publish_cache()
{
    [ -n "$CACHE" ] && [ "$now" -ge 1704067200 ] || return 0
    # 按 MAC 排序并限长，数据变更才写 RAM；原子替换避免留下半个文件。
    printf '%s\n' "$cache_header" > "$work/cache.new"
    LC_ALL=C sort -k2,2 "$work/cache.records" |
        awk 'NR<=256 && bytes+length($0)+1<=64000 {print; bytes+=length($0)+1}' >> "$work/cache.new"
    if ! same_file "$CACHE" "$work/cache.new"; then
        cp "$work/cache.new" "$CACHE.pending.$$"
        chmod 600 "$CACHE.pending.$$"
        mv "$CACHE.pending.$$" "$CACHE"
    fi
    [ -n "$CACHE_SAVE" ] || return 0
    same_file "$CACHE_SAVE" "$work/cache.new" && return 0
    up=${ADG_UPTIME_SECONDS:-$(cut -d. -f1 /proc/uptime)}
    last=$(cat "$CACHE_STAMP" 2>/dev/null || :)
    case "$last" in
        ''|*[!0-9]*) ;;
        *) [ "$up" -lt "$last" ] || [ $((up-last)) -ge 300 ] || return 0 ;;
    esac
    # 名称通常一天才刷新一次；变化频繁时，Flash 写入至少间隔五分钟。
    if cp "$work/cache.new" "$CACHE_SAVE.pending.$$"; then
        chmod 600 "$CACHE_SAVE.pending.$$"
        if mv "$CACHE_SAVE.pending.$$" "$CACHE_SAVE"; then
            printf '%s\n' "$up" > "$CACHE_STAMP"
        else
            rm -f "$CACHE_SAVE.pending.$$"
        fi
    fi
}
read_base()
{
    cp -p "$SYSTEM_HOSTS" "$work/system.original"
    awk '
      /^# BEGIN AdGuardHome (IPv6|LAN) names$/ {if (inside || seen++) exit 2; inside=1; next}
      /^# END AdGuardHome (IPv6|LAN) names$/ {if (!inside) exit 2; inside=0; next}
      !inside {print}
      END {if (inside) exit 2}
    ' "$work/system.original" > "$work/system.base"
}
render()
{
    read_base
    # DHCP 尚未生成租约文件，或此机没有开启 DHCP 时，仍保留静态解析。
    if [ -e "$LEASES" ]; then cp "$LEASES" "$work/leases"; else : > "$work/leases"; fi
    if [ -f "$STATIC_HOSTS" ]; then cp "$STATIC_HOSTS" "$work/static"; else : > "$work/static"; fi
    if [ -n "${ADG_NEIGH_FILE:-}" ]; then
        cp "$ADG_NEIGH_FILE" "$work/neigh"
    else
        ip -6 neigh show dev br0 > "$work/neigh"
    fi
    # 只读取当前 LAN 地址及有效期；旧邻居缓存不能证明前缀仍然有效。
    if [ -n "${ADG_LAN6_FILE:-}" ]; then
        cp "$ADG_LAN6_FILE" "$work/lan6"
    else
        ip -6 -o addr show dev br0 scope global > "$work/lan6"
    fi
    : > "$work/neigh4"
    if [ -n "$CACHE" ]; then
        if [ -n "${ADG_NEIGH4_FILE:-}" ]; then
            cp "$ADG_NEIGH4_FILE" "$work/neigh4"
        else
            ip -4 neigh show dev br0 > "$work/neigh4"
        fi
    fi
    read_cache
    : > "$work/cache.records"
    : > "$work/hosts"
    : > "$work/records"
    awk -v domain="$domain" -v clock_mode="${ADG_LEASE_CLOCK:-no-rtc}" -v now="$now" -v enforce_lan6=1 \
        -v lan_address="$lan_ip" -v lan_mask="$lan_mask" -v cache_out="$work/cache.records" \
        -v hosts_out="$work/hosts" -v system_out="$work/records" -f "$RENDERER" \
        mode=base "$work/system.base" mode=extra "$work/static" \
        mode=lan6 "$work/lan6" mode=cache "$work/cache" mode=leases "$work/leases" \
        mode=neigh4 "$work/neigh4" mode=neigh "$work/neigh"
    LC_ALL=C sort -u "$work/records" > "$work/records.sorted"
    # 同时包含两个地址族，避免同名的 IPv6 记录让 IPv4 查询成为空答复。
    cp "$work/records.sorted" "$work/hosts.new"
    cat "$work/system.base" > "$work/system.new"
    if [ -s "$work/records.sorted" ]; then
        printf '%s\n' '# BEGIN AdGuardHome LAN names' >> "$work/system.new"
        cat "$work/records.sorted" >> "$work/system.new"
        printf '%s\n' '# END AdGuardHome LAN names' >> "$work/system.new"
    fi
    # 生成期间若输入已变化则留待下一轮，避免盖回过时内容。
    same_file "$SYSTEM_HOSTS" "$work/system.original"
    if [ -e "$LEASES" ]; then same_file "$LEASES" "$work/leases"; else [ ! -s "$work/leases" ]; fi
    if [ -f "$STATIC_HOSTS" ]; then same_file "$STATIC_HOSTS" "$work/static"; else [ ! -s "$work/static" ]; fi
    if [ -n "${ADG_LAN6_FILE:-}" ]; then
        same_file "$ADG_LAN6_FILE" "$work/lan6"
    else
        # 比较地址和前缀，不比较会随时间递减的 valid_lft 数字。
        ip -6 -o addr show dev br0 scope global > "$work/lan6.check"
        awk '{for(i=1;i<NF;i++) if($i=="inet6") print $(i+1)}' "$work/lan6" > "$work/lan6.keys"
        awk '{for(i=1;i<NF;i++) if($i=="inet6") print $(i+1)}' "$work/lan6.check" > "$work/lan6.check.keys"
        same_file "$work/lan6.keys" "$work/lan6.check.keys"
    fi
}
publish()
{
    if ! same_file "$HOSTS_FILE" "$work/hosts.new"; then
        cp "$work/hosts.new" "$HOSTS_FILE.pending.$$"
        chmod 644 "$HOSTS_FILE.pending.$$"
        mv "$HOSTS_FILE.pending.$$" "$HOSTS_FILE"
        changed=1
    fi
    if [ "$(stat -c %a "$HOSTS_FILE")" != 644 ]; then chmod 644 "$HOSTS_FILE"; changed=1; fi
    if ! same_file "$SYSTEM_HOSTS" "$work/system.new"; then
        # 保留 /etc/hosts 的 inode，使 AdGuardHome 的文件监测继续有效。
        cat "$work/system.new" > "$SYSTEM_HOSTS"
        changed=1
    fi
    chmod 644 "$SYSTEM_HOSTS"
}

[ -f "$SYSTEM_HOSTS" ] && [ -r "$RENDERER" ]
domain=${ADG_LOCAL_DOMAIN-$(nvram get lan_domain)}
now=${ADG_NOW_EPOCH:-$(date +%s)}
if [ "$TEST_MODE" = 1 ]; then
    lan_ip=${ADG_LAN_IPV4-}
    lan_mask=${ADG_LAN_MASK-}
else
    lan_ip=${ADG_LAN_IPV4-$(nvram get lan_ipaddr)}
    lan_mask=${ADG_LAN_MASK-$(nvram get lan_netmask)}
fi
cache_header="# ADG_NAMES_CACHE_V1 $lan_ip/$lan_mask/$domain"
changed=0
render
migration=0
[ ! -s "$PTR_FILE" ] || migration=1
publish
publish_cache
# 旧 ptr-record 属于启动配置，只在迁移时清空并重启一次。
# 后续 hosts 中的首个名称同时提供 PTR，SIGHUP 即可重载。
: > "$PTR_FILE"
chmod 644 "$PTR_FILE"
if [ "$TEST_MODE" != 1 ]; then
    if [ "$migration" = 1 ]; then
        "$RESTART_SCRIPT"
        # Padavan 的重启流程会重建 /etc/hosts，重新保留其最新系统记录。
        render
        publish
    fi
    if [ "$changed" = 1 ] || [ "$migration" = 1 ]; then
        dns_pid=$(cat /var/run/dnsmasq.pid 2>/dev/null || :)
        case "$dns_pid" in
            ''|*[!0-9]*) ;;
            *) if [ "$(cat /proc/"$dns_pid"/comm 2>/dev/null || :)" = dnsmasq ]; then kill -HUP "$dns_pid"; fi ;;
        esac
    fi
fi
printf 'changed=%s\none_time_ptr_migration=%s\n' "$changed" "$migration"
