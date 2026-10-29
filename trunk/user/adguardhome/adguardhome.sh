#!/bin/sh
umask 077
# AP 使用上级网络，跳过路由模式的启动、接管和自动恢复；保留用户启用设置。
case "${1:-}" in
    start|restart|recover|resume|rollback|rules|fallback)
        [ "$(nvram get sw_mode)" != 3 ] || exit 0
        ;;
esac
# 配置保存在 Storage，服务重启时保留 RAM 中的运行数据库。
RAM_DIR="/tmp/AdGuardHome"
EXE="/usr/bin/AdGuardHome"
WORK_DIR="$RAM_DIR"
RWFS_ROOT="/media/mtd_rwfs"
RWFS_WORK="$RWFS_ROOT/AdGuardHome"
PERSISTENT_FLAG="/etc/storage/adguardhome_persistent"
CONFIG_FILE="/etc/storage/AdGuardHome.yaml"
DNSMASQ_CONF="/etc/storage/dnsmasq/dnsmasq.conf"
SERVICE_LOCK="/tmp/.adguardhome_service_lock"
PREFIX_FILE=${ADG_PREFIX_FILE:-/etc/storage/adguardhome_ipv6_prefix}
WATCH_SCRIPT="/usr/bin/adguardhome_watch.sh"
[ -x "$WATCH_SCRIPT" ] || WATCH_SCRIPT="/etc/storage/adguardhome-fix/adguardhome_watch.sh"
STATE_DIR=/tmp/adguardhome-state
NET_HELPER=/usr/bin/adguardhome-net
[ -x "$NET_HELPER" ] || NET_HELPER=/etc/storage/adguardhome-fix/adguardhome-net
mkdir -p "$STATE_DIR"

service_lock()
{
    n=0
    while ! mkdir "$SERVICE_LOCK" 2>/dev/null; do
        owner=$(cat "$SERVICE_LOCK/pid" 2>/dev/null)
        case "$owner" in
            ''|*[!0-9]*) ;;
            *) if ! kill -0 "$owner" 2>/dev/null; then
                   rm -f "$SERVICE_LOCK/pid"
                   rmdir "$SERVICE_LOCK" 2>/dev/null
                   continue
               fi ;;
        esac
        n=$((n+1))
        [ "$n" -lt 30 ] || return 1
        sleep 1
    done
    echo $$ > "$SERVICE_LOCK/pid"
    trap 'rm -f "$SERVICE_LOCK/pid"; rmdir "$SERVICE_LOCK" 2>/dev/null' 0
    trap 'exit 1' 1 2 15
}


rwfs_mounted()
{
    [ "$(cat /sys/class/ubi/ubi10/mtd_num 2>/dev/null)" = 10 ] &&
        [ "$(cat /sys/class/ubi/ubi10_0/name 2>/dev/null)" = rwfs ] &&
        awk -v point="$RWFS_ROOT" '($1=="/dev/ubi10_0" || $1=="ubi10_0" || $1=="ubi10:rwfs") && $2==point && $3=="ubifs" && (","$4",") ~ /,rw,/ {found=1} END {exit !found}' /proc/mounts
}

runtime_matches()
{
    [ "$(cat "$PERSISTENT_FLAG" 2>/dev/null)" = 1 ] || return 0
    rwfs_mounted || return 1
    for runtime_pid in $(pidof AdGuardHome); do
        # 更新器重命名旧程序时，启动参数仍保持原路径，不能据 inode 路径误杀更新。
        grep -Fq "$RWFS_WORK/AdGuardHome" /proc/"$runtime_pid"/cmdline &&
            tr '\000' '\n' < /proc/"$runtime_pid"/cmdline | grep -Fxq "$RWFS_WORK" && return 0
    done
    return 1
}

# 仅在服务已停止时恢复官方备份，程序与 YAML 必须配套。
restore_persistent_backup()
{
    [ "$WORK_DIR" = "$RWFS_WORK" ] || return 1
    backup_exe="$WORK_DIR/agh-backup/AdGuardHome"
    backup_conf="$WORK_DIR/agh-backup/AdGuardHome.yaml"
    [ -x "$backup_exe" ] && [ -s "$backup_conf" ] || return 1
    if [ -s "$WORK_DIR/.validated-backup.md5" ]; then
        (cd "$WORK_DIR/agh-backup" && md5sum -c "$WORK_DIR/.validated-backup.md5" >/dev/null 2>&1) || return 1
    elif [ "$1" != emergency ]; then
        # 正式程序仍在时，只使用已通过运行验收的备份对。
        return 1
    else
        logger -t AdGuardHome '正式程序缺失，按配置兼容检查尝试紧急恢复'
    fi
    check_conf="$RAM_DIR/recovery-config.$$"
    cp "$backup_conf" "$check_conf" || return 1
    if ! "$backup_exe" --config "$check_conf" --work-dir "$RAM_DIR" --check-config >/dev/null 2>&1; then
        rm -f "$check_conf"
        return 1
    fi
    rm -f "$check_conf"
    # 同一 RWFS 内用硬链接恢复，保留官方备份并避免复制整份程序。
    restore_link="$WORK_DIR/.restore-program.$$"
    if [ "$(stat -c '%d:%i' "$backup_exe")" != "$(stat -c '%d:%i' "$EXE" 2>/dev/null)" ]; then
        ln "$backup_exe" "$restore_link" || return 1
        chmod 700 "$restore_link"
    fi
    if ! cp "$backup_conf" "$CONFIG_FILE.restore"; then
        rm -f "$restore_link" "$CONFIG_FILE.restore"
        return 1
    fi
    chmod 600 "$CONFIG_FILE.restore"
    sync
    if [ -e "$restore_link" ]; then
        if ! mv "$restore_link" "$EXE"; then
            rm -f "$restore_link" "$CONFIG_FILE.restore"
            return 1
        fi
        rm -f "$restore_link"
    fi
    mv "$CONFIG_FILE.restore" "$CONFIG_FILE" || return 1
    sync
    restored_config=1
    logger -t AdGuardHome '已恢复官方备份中的程序和配套配置'
}

select_runtime()
{
    mkdir -p "$RAM_DIR/data" || return 1
    chmod 700 "$RAM_DIR" "$RAM_DIR/data"
    [ "$(cat "$PERSISTENT_FLAG" 2>/dev/null)" = 1 ] || return 0
    # 确认真实挂载，避免 RWFS 缺失时写进 /media 的小容量 RAM 目录。
    if ! rwfs_mounted; then
        logger -t AdGuardHome 'RWFS 未以可写 UBIFS 挂载，保留基础 DNS'
        return 1
    fi
    WORK_DIR="$RWFS_WORK"
    EXE="$WORK_DIR/AdGuardHome"
    mkdir -p "$WORK_DIR" || return 1
    chmod 700 "$WORK_DIR"
    if [ -L "$WORK_DIR/data" ]; then
        [ "$(ls -ld "$WORK_DIR/data" | sed -n 's/.* -> //p')" = "$RAM_DIR/data" ] || return 1
    elif [ -e "$WORK_DIR/data" ]; then
        logger -t AdGuardHome 'RWFS 中已有真实 data 目录，需要先迁移'
        return 1
    else
        ln -s "$RAM_DIR/data" "$WORK_DIR/data" || return 1
    fi
    # 更新中断可能留下缺失的正式程序；启动前恢复配套旧版本。
    [ -x "$EXE" ] || restore_persistent_backup emergency || return 1
}

clear_adg_rules()
{
    for tool in iptables ip6tables; do
        $tool -t nat -D PREROUTING -i br0 -j ADGHOME 2>/dev/null
        $tool -t nat -F ADGHOME 2>/dev/null
        $tool -t nat -X ADGHOME 2>/dev/null
        ${tool}-save -t nat 2>/dev/null | grep 'REDIRECT.*--to-ports 5335' | while read rule; do
            $tool -t nat -D ${rule#-A } 2>/dev/null
        done
    done
}

del_dns()
{
    [ -f "$DNSMASQ_CONF" ] || return 0
    tmp_conf="/tmp/adguardhome-dnsmasq.$$"
    legacy=0
    grep -q '^server=127\.0\.0\.1#5335$' "$DNSMASQ_CONF" && legacy=1
    awk -v legacy="$legacy" '
      /^# BEGIN AdGuardHome forward$/ {owned=1; next}
      /^# END AdGuardHome forward$/ {owned=0; next}
      owned {next}
      legacy && /^server=127\.0\.0\.1#5335$/ {next}
      legacy && /^no-resolv$/ {next}
      {print}
    ' "$DNSMASQ_CONF" > "$tmp_conf" || return 1
    if [ "$(md5sum "$tmp_conf" | cut -d' ' -f1)" != "$(md5sum "$DNSMASQ_CONF" | cut -d' ' -f1)" ]; then
        cat "$tmp_conf" > "$DNSMASQ_CONF"
        [ "$1" = defer ] || /sbin/restart_dhcpd
    fi
    rm -f "$tmp_conf"
}

configure_dns()
{
    before_dns=$(md5sum "$DNSMASQ_CONF" | cut -d' ' -f1)
    del_dns defer || return 1
    if [ "$(nvram get adg_redirect)" = 1 ]; then
        cat >> "$DNSMASQ_CONF" <<'DNS_FORWARD'
# BEGIN AdGuardHome forward
no-resolv
server=127.0.0.1#5335
# END AdGuardHome forward
DNS_FORWARD
    fi
    after_dns=$(md5sum "$DNSMASQ_CONF" | cut -d' ' -f1)
    [ "$before_dns" = "$after_dns" ] || /sbin/restart_dhcpd
}

ensure_firewall_hook()
{
    hook=/etc/storage/post_iptables_script.sh
    hook_changed=0
    grep -q '^# BEGIN AdGuardHome rules restore$' "$hook" 2>/dev/null && return 0
    tmp_hook="/tmp/adguardhome-firewall-hook.$$"
    {
        if head -n 1 "$hook" 2>/dev/null | grep -q '^#!'; then
            head -n 1 "$hook"
        else
            echo '#!/bin/sh'
        fi
        echo '# BEGIN AdGuardHome rules restore'
        echo '/usr/bin/adguardhome.sh rules >/dev/null 2>&1 &'
        echo '# END AdGuardHome rules restore'
        if head -n 1 "$hook" 2>/dev/null | grep -q '^#!'; then
            tail -n +2 "$hook"
        elif [ -f "$hook" ]; then
            cat "$hook"
        fi
    } > "$tmp_hook" || return 1
    chmod 700 "$tmp_hook"
    mv "$tmp_hook" "$hook" || return 1
    hook_changed=1
}

finish_start()
{
    configure_dns && set_adg_rules || return 1
    /usr/bin/update_ipv6_hosts.sh || return 1
    if [ -x "$WATCH_SCRIPT" ]; then
        "$WATCH_SCRIPT" start
        { [ "$hook_changed" = 0 ] && [ "${restored_config:-0}" = 0 ]; } || "$WATCH_SCRIPT" save-now || return 1
    fi
}

set_adg_rules()
{
    mode=$(nvram get adg_redirect)
    clear_adg_rules
    case "$mode" in 2|3) ;; *) return 0 ;; esac
    for tool in iptables ip6tables; do
        $tool -t nat -N ADGHOME 2>/dev/null || continue
        if [ "$mode" = 3 ]; then
            for proto in tcp udp; do
                $tool -t nat -A ADGHOME -p "$proto" --dport 53 -j REDIRECT --to-ports 5335 || return 1
            done
        else
            if [ "$tool" = iptables ]; then
                addresses=$(ip -4 addr show dev br0 | awk '/inet / {sub(/\/.*/, "", $2); print $2}')
            else
                addresses=$(ip -6 addr show dev br0 | awk '/inet6 / {sub(/\/.*/, "", $2); print $2}')
            fi
            for address in $addresses; do
                for proto in tcp udp; do
                    $tool -t nat -A ADGHOME -d "$address" -p "$proto" --dport 53 -j REDIRECT --to-ports 5335 || return 1
                done
            done
        fi
        $tool -t nat -I PREROUTING 1 -i br0 -j ADGHOME || return 1
    done
}

dns_ready()
{
    netstat -lnp 2>/dev/null | awk '
      /AdGuardHome/ && $4 ~ /:5335$/ {if ($1=="tcp") t=1; if ($1=="udp") u=1}
      END {exit !(t && u)}' || return 1
    # 监听端口不等于可用；必须收到本地名称的正确 TCP/UDP 答案。
    [ -x "$NET_HELPER" ] || return 1
    local_lan_ip=$(nvram get lan_ipaddr)
    "$NET_HELPER" dns 127.0.0.1 5335 udp my.router A "$local_lan_ip" &&
        "$NET_HELPER" dns 127.0.0.1 5335 tcp my.router A "$local_lan_ip"
}

terminate_adg()
{
    killall -TERM AdGuardHome 2>/dev/null
    n=0
    while pidof AdGuardHome >/dev/null 2>&1; do
        n=$((n+1))
        if [ "$n" -ge 15 ]; then
            logger -t AdGuardHome 'Graceful shutdown timed out; forcing exit'
            killall -KILL AdGuardHome 2>/dev/null
            sleep 1
            break
        fi
        sleep 1
    done
}

update_private_networks()
{
    [ -n "$network_prefix" ] || return 0
    old_prefix=$(cat "$PREFIX_FILE" 2>/dev/null)
    awk -v current="$network_prefix" -v previous="$old_prefix" '
      function identity(value, p, halves, left, right, groups, lc, rc, n, i, idx, part, result) {
        gsub(/[\047\042]/, "", value)
        value=tolower(value)
        if (split(value,p,"/")!=2 || p[2]!="64" || p[1]!~/:/) return value
        n=split(p[1],halves,"::")
        lc=(halves[1]=="" ? 0 : split(halves[1],left,":"))
        rc=(n==2 && halves[2]!="" ? split(halves[2],right,":") : 0)
        if (n>2 || (n==1 && lc!=8) || (n==2 && lc+rc>=8)) return value
        idx=1
        for(i=1;i<=lc;i++) groups[idx++]=left[i]
        if(n==2) for(i=0;i<8-lc-rc;i++) groups[idx++]="0"
        for(i=1;i<=rc;i++) groups[idx++]=right[i]
        result=""
        for(i=1;i<=4;i++) {
          part=groups[i]; sub(/^0+/,"",part); if(part=="") part="0"
          result=sprintf("%s%s%s",result,(i==1 ? "" : ":"),part)
        }
        return result "/64"
      }
      BEGIN {current_key=identity(current); previous_key=identity(previous)}
      /^  private_networks:[ \t]*(\[\])?[ \t]*$/ {
        print "  private_networks:"
        print "    - "current
        inside=1; found=1; next
      }
      inside && /^    - / {
        key=identity($2)
        if (key!=current_key && (previous=="" || key!=previous_key)) print
        next
      }
      {inside=0; print}
      END {if(!found) exit 1}
    ' "$CONFIG_FILE" > /tmp/adguardhome-prefix.$$ || return 1
    chmod 600 /tmp/adguardhome-prefix.$$
    mv /tmp/adguardhome-prefix.$$ "$CONFIG_FILE" || return 1
    echo "$network_prefix" > "$PREFIX_FILE"
}

init_config()
{


if [ ! -f "$CONFIG_FILE" ]; then


cat > "$CONFIG_FILE" << EOF
http:
  address: 0.0.0.0:3000

users:
- name: adguardhome
  password: \$2y\$10\$O8iqsCH8j3Rdd8nxDJCbQexl31MXgoGYt9jgZUBLnUqGuDPkaOYta
  

session_ttl: 720h


auth_attempts: 10
block_auth_min: 1


dns:
  bind_hosts:
    - 0.0.0.0

  port: 5335

  protection_enabled: true

  filtering_enabled: true

  blocking_mode: nxdomain


  upstream_dns:
    - 223.5.5.5
    - 119.29.29.29

  bootstrap_dns:
    - 223.5.5.5
    - 119.29.29.29
    
  use_private_ptr_resolvers: true

  local_ptr_upstreams:
    - 192.168.2.1

  private_networks:
    - 192.168.2.0/24 

filters:

  - enabled: true

    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt

    name: AdGuard Simplified Domain Names filter

    id: 1



querylog:
  enabled: true
  file_enabled: false
  size_memory: 1000
  interval: 24h
statistics:
  enabled: true
  interval: 24h
log:
  enabled: true
  file: /tmp/AdGuardHome.log
  max_size: 1
  max_backups: 1
  max_age: 3
  compress: false
  verbose: false


schema_version: 34

EOF


chmod 600 "$CONFIG_FILE"


fi


}





start_adg()
{
    # 官方替换目录存在且程序仍在运行时，延后自动启动，避免中断更新。
    if [ "$(cat "$PERSISTENT_FLAG" 2>/dev/null)" = 1 ] && runtime_matches; then
        for update_dir in "$RWFS_WORK"/agh-update-*; do
            if [ -d "$update_dir" ]; then
                logger -t AdGuardHome '官方更新正在进行，延后启动处理'
                return 0
            fi
        done
    fi
    ensure_firewall_hook || return 1
    network_prefix=''
    [ ! -x "$WATCH_SCRIPT" ] || network_prefix=$("$WATCH_SCRIPT" network-prefix)
    old_prefix=$(cat "$PREFIX_FILE" 2>/dev/null)
    crontab -l 2>/dev/null > /tmp/adguardhome-watch-cron.$$
    if [ -x "$WATCH_SCRIPT" ] && ! grep -q 'adguardhome_watch.sh.*start' /tmp/adguardhome-watch-cron.$$; then
        echo "* * * * * $WATCH_SCRIPT start >/dev/null 2>&1" >> /tmp/adguardhome-watch-cron.$$
        crontab /tmp/adguardhome-watch-cron.$$
    fi
    rm -f /tmp/adguardhome-watch-cron.$$
    if pidof AdGuardHome >/dev/null 2>&1 && dns_ready && runtime_matches && { [ -z "$network_prefix" ] || [ "$network_prefix" = "$old_prefix" ]; }; then
        finish_start
        return $?
    fi
    clear_adg_rules
    del_dns
    terminate_adg
    select_runtime || return 1
    mkdir -p "$WORK_DIR"
    chmod 700 "$WORK_DIR"
    init_config
    chmod 600 "$CONFIG_FILE"

    # 保留用户设置的网段，仅替换本脚本管理的 IPv6 前缀。
    update_private_networks || { logger -t AdGuardHome 'Could not update LAN IPv6 prefix'; return 1; }
    /usr/bin/update_ipv6_hosts.sh
    crontab -l 2>/dev/null > /tmp/adguardhome-cron.$$
    if ! grep -q 'update_ipv6_hosts.sh' /tmp/adguardhome-cron.$$; then
        echo '*/5 * * * * /usr/bin/update_ipv6_hosts.sh >/dev/null 2>&1' >> /tmp/adguardhome-cron.$$
        crontab /tmp/adguardhome-cron.$$
    fi
    rm -f /tmp/adguardhome-cron.$$
    changed=0
    for line in 'addn-hosts=/etc/storage/dnsmasq/hosts_ipv6' 'conf-file=/etc/storage/dnsmasq/dnsmasq_ipv6_ptr'; do
        if ! grep -Fxq "$line" "$DNSMASQ_CONF"; then
            echo "$line" >> "$DNSMASQ_CONF"
            changed=1
        fi
    done
    [ "$changed" = 0 ] || /sbin/restart_dhcpd

    set -- --config "$CONFIG_FILE" --work-dir "$WORK_DIR" --logfile /tmp/AdGuardHome.log
    # 调试时取消下一行的注释；日志轮转限制仍然生效。
    # set -- "$@" --verbose
    if ! "$EXE" "$@" --check-config >/dev/null 2>&1; then
        if [ "$WORK_DIR" != "$RWFS_WORK" ] || ! restore_persistent_backup || ! update_private_networks ||
            ! "$EXE" "$@" --check-config >/dev/null 2>&1; then
            logger -t AdGuardHome '配置检查失败，DNS 重定向保持关闭'
            return 1
        fi
    fi
    "$EXE" "$@" >/dev/null 2>&1 &
    n=0
    had_dns_ready=0
    while [ "$n" -lt 30 ]; do
        if dns_ready; then
            had_dns_ready=1
            if finish_start; then
                logger -t AdGuardHome 'DNS ready; redirection configured'
                return 0
            fi
            break
        fi
        pidof AdGuardHome >/dev/null 2>&1 || break
        sleep 1
        n=$((n+1))
    done
    clear_adg_rules
    del_dns
    terminate_adg
    # 新程序运行失败时最多回退一次，避免重复恢复或无限重启。
    if [ "$had_dns_ready" = 0 ] && [ "$WORK_DIR" = "$RWFS_WORK" ] && [ "${rollback_attempted:-0}" = 0 ]; then
        rollback_attempted=1
        if restore_persistent_backup; then
            start_adg
            return $?
        fi
    fi
    logger -t AdGuardHome '启动失败，DNS 重定向保持关闭'
    return 1
}

stop_adg()
{
    clear_adg_rules
    del_dns
    terminate_adg
    # 停止或重启服务时保留数据库和缓存；整机重启会清空 /tmp。
    [ -x "$WATCH_SCRIPT" ] && "$WATCH_SCRIPT" save-now
    logger -t AdGuardHome 'Stopped; configuration and runtime files preserved'
}

service_lock || exit 1
case "$1" in
    start)
        rm -f "$STATE_DIR/manual-stop"
        start_adg && rm -f "$STATE_DIR/health-fallback"
        ;;
    stop)
        : > "$STATE_DIR/manual-stop"
        stop_adg
        ;;
    restart)
        rm -f "$STATE_DIR/manual-stop"
        stop_adg
        start_adg && rm -f "$STATE_DIR/health-fallback"
        ;;
    fallback)
        : > "$STATE_DIR/health-fallback"
        clear_adg_rules
        del_dns && /usr/bin/update_ipv6_hosts.sh
        ;;
    recover|resume)
        [ "$(nvram get adg_enable)" = 1 ] && [ ! -e "$STATE_DIR/manual-stop" ] || exit 0
        if [ "$1" = recover ]; then
            start_adg && rm -f "$STATE_DIR/health-fallback"
        elif dns_ready; then
            finish_start && rm -f "$STATE_DIR/health-fallback"
        fi
        ;;
    rollback)
        stop_adg
        select_runtime && restore_persistent_backup && start_adg && "$WATCH_SCRIPT" save-now
        ;;
    rules)
        if [ "$(nvram get adg_enable)" = 1 ] && [ ! -e "$STATE_DIR/manual-stop" ] &&
            [ ! -e "$STATE_DIR/health-fallback" ] && pidof AdGuardHome >/dev/null 2>&1 && dns_ready; then
            set_adg_rules
        else
            clear_adg_rules
        fi
        ;;
    *) echo 'Usage: adguardhome.sh {start|stop|restart|rules|rollback|fallback|recover|resume}'; exit 1 ;;
esac
