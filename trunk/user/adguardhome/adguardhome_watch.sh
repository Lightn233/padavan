#!/bin/sh
umask 077
CONFIG_FILE=${ADG_CONFIG_FILE:-/etc/storage/AdGuardHome.yaml}
STATE_DIR=${ADG_STATE_DIR:-/tmp/adguardhome-state}
SAVE_SCRIPT=${ADG_SAVE_SCRIPT:-/sbin/mtd_storage.sh}
POLL=${ADG_POLL_SECONDS:-15}
DEBOUNCE=${ADG_DEBOUNCE_SECONDS:-60}
PID_FILE="$STATE_DIR/watcher.pid"
# AP 不创建自动维护进程；隔离测试路径不读取实际设备模式。
ap_mode()
{
    [ "$CONFIG_FILE" = /etc/storage/AdGuardHome.yaml ] &&
        [ "$STATE_DIR" = /tmp/adguardhome-state ] && [ "$(nvram get sw_mode)" = 3 ]
}
case "${1:-}" in start|daemon) ap_mode && exit 0 ;; esac
mkdir -p "$STATE_DIR"

config_hash()
{
    [ -s "$CONFIG_FILE" ] || return 1
    md5sum "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f1
}

network_prefix()
{
    address=$(ip -6 addr show dev br0 2>/dev/null | awk '/inet6 / && /scope global/ {sub(/\/.*/, "", $2); print $2; exit}')
    [ -n "$address" ] || return 0
    echo "$address" | awk '
      {
        n=split(tolower($0), halves, "::")
        l=(halves[1]=="" ? 0 : split(halves[1], left, ":"))
        r=(n==2 && halves[2]!="" ? split(halves[2], right, ":") : 0)
        zeros=8-l-r
        if(n>2 || (n==1 && zeros!=0) || (n==2 && zeros<1)) exit 1
        full=""
        for(i=1;i<=l;i++) {p="0000"left[i]; full=full substr(p,length(p)-3)}
        for(i=1;i<=zeros;i++) full=full "0000"
        for(i=1;i<=r;i++) {p="0000"right[i]; full=full substr(p,length(p)-3)}
        print substr(full,1,4)":"substr(full,5,4)":"substr(full,9,4)":"substr(full,13,4)"::/64"
      }'
}

save_now()
{
    before=$(config_hash) || return 1
    [ -n "$before" ] || return 1
    if "$SAVE_SCRIPT" save > "$STATE_DIR/save.log" 2>&1; then
        after=$(config_hash)
        if [ "$before" = "$after" ]; then
            echo "$after" > "$STATE_DIR/saved.md5"
            logger -t AdGuardHome 'Settings saved to Flash'
            return 0
        fi
    fi
    logger -t AdGuardHome 'Settings save failed or configuration changed; will retry'
    return 1
}

running()
{
    pid=$(cat "$PID_FILE" 2>/dev/null)
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    grep -q 'adguardhome_watch.sh' /proc/"$pid"/cmdline 2>/dev/null
}

maintain_network()
{
    # 隔离测试的监测进程不操作实际路由器的网络。
    [ "$CONFIG_FILE" = /etc/storage/AdGuardHome.yaml ] &&
        [ "$STATE_DIR" = /tmp/adguardhome-state ] || return 0
    [ "$(nvram get adg_enable)" = 1 ] || return 0
    [ -x /usr/bin/adguardhome.sh ] && [ -x /usr/bin/update_ipv6_hosts.sh ] || return 0
    [ ! -d /tmp/.adguardhome_service_lock ] || return 0
    [ ! -e "$STATE_DIR/manual-stop" ] || return 0

    # 前缀维护由监测进程发起，避免名称脚本在启动锁内递归启动服务。
    prefix=$(network_prefix)
    stored_prefix=$(cat /etc/storage/adguardhome_ipv6_prefix 2>/dev/null)
    if [ -n "$prefix" ] && [ "$prefix" != "$stored_prefix" ] && [ ! -e "$STATE_DIR/health-fallback" ]; then
        /usr/bin/adguardhome.sh start >/dev/null 2>&1 || return 1
    fi

    # 即使保存的 /64 前缀未变，IPv6 地址也可能在 AGH 启动后才出现。
    address_key=$(ip addr show dev br0 2>/dev/null |
        awk '$1=="inet" || $1=="inet6" {print $1" "$2}' |
        sort | md5sum | cut -d' ' -f1)
    if [ "$address_key" != "$previous_addresses" ]; then
        if /usr/bin/adguardhome.sh rules >/dev/null 2>&1; then
            previous_addresses="$address_key"
        fi
    fi
    hosts_key=$({
        echo "$address_key"
        nvram get lan_domain
        cat /var/run/dnsmasq.pid 2>/dev/null
        cat /etc/storage/dnsmasq/hosts 2>/dev/null
        ip -6 neigh show dev br0 2>/dev/null | awk '
          !/FAILED|INCOMPLETE/ {
            for(i=1;i<NF;i++) if($i=="lladdr") {
              print tolower($1)" "tolower($(i+1)); break
            }
          }'
        awk '{print tolower($2)" "$3" "$4}' /tmp/dnsmasq.leases 2>/dev/null
        cat /etc/hosts
    } | sort | md5sum | cut -d' ' -f1)
    if [ "$hosts_key" != "$previous_hosts" ]; then
        if /usr/bin/update_ipv6_hosts.sh >/dev/null 2>&1; then
            previous_hosts="$hosts_key"
        fi
    fi
}


# 稳定期间先比较 inode、长度和修改/变更时间；缓存只写 RAM，最长五分钟重验一次。
# 元数据变化或读取过程中发生替换时立即失效，不依赖版本号判断是否更新。
update_file_signature()
{
    [ -f "$1" ] || return 1
    stat -L -c '%d:%i:%s:%f:%u:%g:%y:%z' "$1" 2>/dev/null
}

update_file_hash()
(
    hash_file=$1
    hash_slot=$2
    hash_now=$3
    case "$hash_slot" in current|running|backup) ;; *) return 1 ;; esac
    case "$hash_now" in ''|*[!0-9]*|0[0-9]*) return 1 ;; esac
    [ "${#hash_now}" -le 10 ] || return 1
    hash_cache="$STATE_DIR/update-hash-$hash_slot"
    hash_signature=$(update_file_signature "$hash_file") || return 1
    hash_when=0
    hash_value=''
    if [ -f "$hash_cache" ]; then
        IFS=' ' read -r hash_when hash_value < "$hash_cache"
        hash_saved_signature=$(sed -n '2p' "$hash_cache")
        case "$hash_when" in ''|*[!0-9]*|0[0-9]*) hash_when=0; hash_value='' ;; esac
        if [ "${#hash_when}" -gt 10 ]; then hash_when=0; hash_value=''; fi
        case "$hash_value" in *[!0-9a-f]*|'') hash_value='' ;; esac
        if [ "${#hash_value}" = 32 ] && [ "$hash_signature" = "$hash_saved_signature" ] &&
            [ "$hash_now" -ge "$hash_when" ] && [ $((hash_now-hash_when)) -lt 300 ]; then
            printf '%s\n' "$hash_value"
            return 0
        fi
    fi
    hash_value=$(md5sum "$hash_file" 2>/dev/null | cut -d' ' -f1)
    case "$hash_value" in *[!0-9a-f]*|'') return 1 ;; esac
    [ "${#hash_value}" = 32 ] || return 1
    [ "$hash_signature" = "$(update_file_signature "$hash_file")" ] || return 1
    if ! { printf '%s %s\n%s\n' "$hash_now" "$hash_value" "$hash_signature" > "$hash_cache.pending.$$" &&
           mv "$hash_cache.pending.$$" "$hash_cache"; }; then
        rm -f "$hash_cache.pending.$$"
        return 1
    fi
    printf '%s\n' "$hash_value"
)

# 新程序实际执行并连续两次正常监听后，记录官方备份的配对校验值。
# 官方更新器不会使用外部锁；这里只核验，不清理或移动其目录。
maintain_update_backup()
(
    [ "$CONFIG_FILE" = /etc/storage/AdGuardHome.yaml ] &&
        [ "$STATE_DIR" = /tmp/adguardhome-state ] || return 0
    # 备份核验与清理、回退共用服务锁，避免核验结果写回已经清理的目录。
    backup_lock=/tmp/.adguardhome_service_lock
    mkdir "$backup_lock" 2>/dev/null || return 0
    echo $$ > "$backup_lock/pid"
    trap 'rm -f "$backup_lock/pid"; rmdir "$backup_lock" 2>/dev/null || :' 0
    trap 'exit 1' 1 2 15
    local update_root update_work update_exe update_candidate update_pid
    local update_hash update_running_hash update_previous update_key update_backup
    local update_backup_hash update_config_hash update_check_conf update_snapshot
    local update_after_hash update_after_config update_manifest update_pending
    local update_now update_disk_signature update_running_signature
    update_root=/media/mtd_rwfs
    update_work="$update_root/AdGuardHome"
    update_exe="$update_work/AdGuardHome"
    update_candidate="$STATE_DIR/update-validation.candidate"
    if [ "$CONFIG_FILE" != /etc/storage/AdGuardHome.yaml ] ||
        [ "$STATE_DIR" != /tmp/adguardhome-state ] ||
        [ "$(cat /etc/storage/adguardhome_persistent 2>/dev/null)" != 1 ] ||
        [ "$(cat /sys/class/ubi/ubi10/mtd_num 2>/dev/null)" != 10 ] ||
        ! awk -v point="$update_root" '
          ($1=="/dev/ubi10_0" || $1=="ubi10_0" || $1=="ubi10:rwfs") &&
          $2==point && $3=="ubifs" && (","$4",") ~ /,rw,/ {found=1}
          END {exit !found}' /proc/mounts ||
        [ ! -x "$update_exe" ]; then
        rm -f "$update_candidate"
        return 0
    fi

    # 配置检查的子进程不会被误当成已经提供 DNS 的正式服务。
    set -- $(pidof AdGuardHome 2>/dev/null)
    if [ "$#" != 1 ]; then
        rm -f "$update_candidate"
        return 0
    fi
    update_pid=$1
    update_now=$(cut -d. -f1 /proc/uptime)
    # 读取失败也会中断连续成功，必须清除上一轮的候选标记。
    update_disk_signature=$(update_file_signature "$update_exe") || { rm -f "$update_candidate"; return 0; }
    update_running_signature=$(update_file_signature "/proc/$update_pid/exe") || { rm -f "$update_candidate"; return 0; }
    update_hash=$(update_file_hash "$update_exe" current "$update_now") || { rm -f "$update_candidate"; return 0; }
    if [ "$update_disk_signature" = "$update_running_signature" ]; then
        # 路径和运行进程引用同一个文件时，不重复读取整份程序。
        update_running_hash=$update_hash
    else
        update_running_hash=$(update_file_hash "/proc/$update_pid/exe" running "$update_now") || { rm -f "$update_candidate"; return 0; }
    fi
    if [ "$update_disk_signature" != "$(update_file_signature "$update_exe")" ] ||
        [ "$update_running_signature" != "$(update_file_signature "/proc/$update_pid/exe")" ]; then
        rm -f "$update_candidate"
        return 0
    fi
    if [ -z "$update_hash" ] || [ "$update_hash" != "$update_running_hash" ] ||
        ! netstat -lnp 2>/dev/null | awk -v pid="$update_pid" '
          $NF ~ ("^"pid"/") && $4 ~ /:5335$/ {
            if ($1 ~ /^tcp/) t=1
            if ($1 ~ /^udp/) u=1
          }
          END {exit !(t && u)}'; then
        rm -f "$update_candidate"
        return 0
    fi
    update_backup="$update_work/agh-backup"
    update_manifest="$update_work/.validated-backup.md5"
    if [ "$update_hash" = "$(cat "$update_work/.validated-current" 2>/dev/null)" ]; then
        # 同版本重新安装也会更换官方备份，须同时核对程序与配置清单。
        if [ ! -e "$update_backup/AdGuardHome" ] && [ ! -e "$update_backup/AdGuardHome.yaml" ]; then
            rm -f "$update_candidate"
            return 0
        fi
        if [ -x "$update_backup/AdGuardHome" ] && [ -s "$update_backup/AdGuardHome.yaml" ] &&
            [ -s "$update_manifest" ]; then
            update_backup_hash=$(update_file_hash "$update_backup/AdGuardHome" backup "$update_now") || { rm -f "$update_candidate"; return 0; }
            update_config_hash=$(md5sum "$update_backup/AdGuardHome.yaml" 2>/dev/null | cut -d' ' -f1)
            update_snapshot=$(printf '%s  AdGuardHome\n%s  AdGuardHome.yaml\n' "$update_backup_hash" "$update_config_hash")
            if [ -n "$update_snapshot" ] &&
                [ "$update_snapshot" = "$(cat "$update_manifest" 2>/dev/null)" ]; then
                rm -f "$update_candidate"
                return 0
            fi
        fi
    fi

    update_key="$update_hash:$update_pid"
    update_previous=$(cat "$update_candidate" 2>/dev/null)
    if [ "$update_key" != "$update_previous" ]; then
        printf '%s\n' "$update_key" > "$update_candidate.pending.$$" &&
            mv "$update_candidate.pending.$$" "$update_candidate"
        return 0
    fi

    # 连续运行检查还需包含实际 DNS 答案，不能只凭监听端口确认更新成功。
    update_probe=/usr/bin/adguardhome-net
    [ -x "$update_probe" ] || update_probe=/etc/storage/adguardhome-fix/adguardhome-net
    if [ ! -x "$update_probe" ] ||
        ! "$update_probe" dns 127.0.0.1 5335 udp my.router A "$(nvram get lan_ipaddr)" ||
        ! "$update_probe" dns 127.0.0.1 5335 tcp my.router A "$(nvram get lan_ipaddr)"; then
        rm -f "$update_candidate"
        return 0
    fi

    update_pending="$update_manifest.pending.$$"
    if [ -e "$update_backup/AdGuardHome" ] || [ -e "$update_backup/AdGuardHome.yaml" ]; then
        # 单独存在的程序或配置不能当作完整回退副本。
        if [ ! -x "$update_backup/AdGuardHome" ] || [ ! -s "$update_backup/AdGuardHome.yaml" ]; then
            rm -f "$update_candidate"
            return 0
        fi
        update_backup_hash=$(md5sum "$update_backup/AdGuardHome" 2>/dev/null | cut -d' ' -f1)
        update_config_hash=$(md5sum "$update_backup/AdGuardHome.yaml" 2>/dev/null | cut -d' ' -f1)
        update_check_conf="$STATE_DIR/backup-check-config.$$"
        if [ -z "$update_backup_hash" ] || [ -z "$update_config_hash" ] ||
            ! cp "$update_backup/AdGuardHome.yaml" "$update_check_conf"; then
            rm -f "$update_candidate" "$update_check_conf"
            return 0
        fi
        update_snapshot=$(md5sum "$update_check_conf" 2>/dev/null | cut -d' ' -f1)
        if [ "$update_snapshot" != "$update_config_hash" ] ||
            ! "$update_backup/AdGuardHome" --config "$update_check_conf" \
                --work-dir /tmp/AdGuardHome --check-config >/dev/null 2>&1; then
            rm -f "$update_candidate" "$update_check_conf"
            logger -t AdGuardHome '官方备份尚未通过配套配置检查，暂不标记可回退'
            return 0
        fi
        rm -f "$update_check_conf"
        update_after_hash=$(md5sum "$update_backup/AdGuardHome" 2>/dev/null | cut -d' ' -f1)
        update_after_config=$(md5sum "$update_backup/AdGuardHome.yaml" 2>/dev/null | cut -d' ' -f1)
        if [ "$update_backup_hash" != "$update_after_hash" ] ||
            [ "$update_config_hash" != "$update_after_config" ] ||
            [ "$update_hash" != "$(md5sum "$update_exe" 2>/dev/null | cut -d' ' -f1)" ] ||
            [ "$update_hash" != "$(md5sum "/proc/$update_pid/exe" 2>/dev/null | cut -d' ' -f1)" ]; then
            rm -f "$update_candidate"
            return 0
        fi
        {
            printf '%s  AdGuardHome\n' "$update_backup_hash"
            printf '%s  AdGuardHome.yaml\n' "$update_config_hash"
        } > "$update_pending" || return 0
        if ! mv "$update_pending" "$update_manifest"; then
            rm -f "$update_pending"
            return 0
        fi
        sync
    else
        # 首次安装没有上一代备份；只记录已正常执行的当前程序。
        if [ "$update_hash" != "$(md5sum "$update_exe" 2>/dev/null | cut -d' ' -f1)" ] ||
            [ "$update_hash" != "$(md5sum "/proc/$update_pid/exe" 2>/dev/null | cut -d' ' -f1)" ]; then
            rm -f "$update_candidate"
            return 0
        fi
    fi

    printf '%s\n' "$update_hash" > "$update_work/.validated-current.pending.$$" || return 0
    if mv "$update_work/.validated-current.pending.$$" "$update_work/.validated-current"; then
        sync
        rm -f "$update_candidate"
        logger -t AdGuardHome '已核验当前程序运行状态及可用的官方配套备份'
    fi
)

maintain_rdns()
{
    [ "$CONFIG_FILE" = /etc/storage/AdGuardHome.yaml ] &&
        [ "$STATE_DIR" = /tmp/adguardhome-state ] || return 0
    [ "$(nvram get adg_enable)" = 1 ] || return 0
    [ ! -e "$STATE_DIR/manual-stop" ] && [ ! -d /tmp/.adguardhome_service_lock ] || return 0
    [ -x /usr/bin/adguardhome_rdns_collect.sh ] &&
        [ -x /usr/bin/adguardhome_rdns_retire.sh ] &&
        [ -x /usr/bin/adguardhome_rdns_restart.sh ] || return 0
    /usr/bin/adguardhome_rdns_collect.sh || return 0
    [ -s /tmp/adguardhome-rdns/manifest ] || return 0
    # 默认等待五分钟并限制每小时最多一次；前缀恢复、更新或手动停用时延期。
    /usr/bin/adguardhome_rdns_retire.sh /tmp/adguardhome-rdns \
        /tmp/adguardhome-rdns/manifest /usr/bin/adguardhome_rdns_restart.sh \
        >/tmp/adguardhome-rdns/last-action.log 2>&1 || :
}

daemon()
{
    mkdir "$STATE_DIR/daemon.lock" 2>/dev/null || return 1
    echo $$ > "$PID_FILE"
    trap 'rm -f "$PID_FILE"; rmdir "$STATE_DIR/daemon.lock" 2>/dev/null' 0
    trap 'exit 0' 1 2 15
    previous=''
    previous_addresses=''
    previous_hosts=''
    stable=0
    while :; do
        ap_mode && return 0
        if [ "$CONFIG_FILE" = /etc/storage/AdGuardHome.yaml ] &&
            [ "$STATE_DIR" = /tmp/adguardhome-state ]; then
            health_script=/usr/bin/adguardhome_health.sh
            [ -x "$health_script" ] || health_script=/etc/storage/adguardhome-fix/adguardhome_health.sh
            [ ! -x "$health_script" ] || "$health_script"
        fi
        maintain_network
        maintain_rdns
        maintain_update_backup
        current=$(config_hash)
        saved=$(cat "$STATE_DIR/saved.md5" 2>/dev/null)
        if [ -n "$current" ] && [ "$current" != "$saved" ]; then
            if [ "$current" = "$previous" ]; then stable=$((stable+POLL)); else stable=0; fi
            if [ "$stable" -ge "$DEBOUNCE" ]; then
                save_now
                stable=0
            fi
        else
            stable=0
        fi
        previous="$current"
        sleep "$POLL"
    done
}

case "$1" in
    start)
        running && exit 0
        rm -f "$PID_FILE"
        rmdir "$STATE_DIR/daemon.lock" 2>/dev/null
        "$0" daemon >/dev/null 2>&1 &
        n=0
        while ! running && [ "$n" -lt 3 ]; do sleep 1; n=$((n+1)); done
        running
        ;;
    stop)
        if running; then
            kill -TERM "$pid"
            n=0
            while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 30 ]; do sleep 1; n=$((n+1)); done
            if kill -0 "$pid" 2>/dev/null; then exit 1; fi
        fi
        ;;
    save-now) save_now ;;
    network-prefix) network_prefix ;;
    daemon) daemon ;;
    *) echo 'Usage: adguardhome_watch.sh {start|stop|save-now|daemon}'; exit 1 ;;
esac
