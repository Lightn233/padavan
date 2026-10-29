#!/bin/sh
# 身份和网络配置长期保留，运行状态只放在内存目录。
umask 077
PROG=/usr/bin/zerotier-one
PROGCLI=/usr/bin/zerotier-cli
PROGIDT=/usr/bin/zerotier-idtool
config_path=/etc/storage/zerotier-one
runtime=/var/run/zerotier
self=/usr/bin/zerotier.sh
mkdir -p "$runtime" || exit 1

valid_hex() {
    case "$1" in ''|*[!0-9a-fA-F]*) return 1;; esac
    [ "${#1}" -ge "$2" ] && [ "${#1}" -le "$3" ]
}

interfaces() {
    ip -o link show | awk -F ': ' '$2 ~ /^zt[a-zA-Z0-9]+(@|$)/ {sub(/@.*/, "", $2); print $2}'
}

zero_route() {
    route_count=$(nvram get zero_staticnum_x)
    case "$route_count" in ''|*[!0-9]*) return 0;; esac
    [ "$route_count" -le 128 ] || return 1
    route_index=0
    while [ "$route_index" -lt "$route_count" ]; do
        enabled=$(nvram get "zero_enable_x$route_index")
        destination=$(nvram get "zero_ip_x$route_index")
        gateway=$(nvram get "zero_route_x$route_index")
        route_index=$((route_index + 1))
        [ "$enabled" = 1 ] || continue
        # 字段分别传给 ip，不展开为命令；错误路由交给内核拒绝。
        case "$destination" in ''|*[!0-9./]*) continue;; esac
        case "$gateway" in ''|*[!0-9.]*) continue;; esac
        ip route "$1" "$destination" via "$gateway" dev "$zt0" 2>/dev/null
    done
    return 0
}

del_rules() {
    # 只清理本插件的专用链，不能冲刷用户的防火墙或 DNS 接管规则。
    iptables -D INPUT -j ZT_PADAVAN_IN 2>/dev/null
    iptables -D FORWARD -j ZT_PADAVAN_FW 2>/dev/null
    iptables -t nat -D POSTROUTING -j ZT_PADAVAN_NAT 2>/dev/null
    for chain in ZT_PADAVAN_IN ZT_PADAVAN_FW; do
        iptables -F "$chain" 2>/dev/null
        iptables -X "$chain" 2>/dev/null
    done
    iptables -t nat -F ZT_PADAVAN_NAT 2>/dev/null
    iptables -t nat -X ZT_PADAVAN_NAT 2>/dev/null
    if [ -f "$runtime/interfaces" ]; then
        while IFS= read -r zt0; do
            case "$zt0" in zt*[!a-zA-Z0-9]*|'') continue;; zt*) zero_route del;; esac
        done < "$runtime/interfaces"
        rm -f "$runtime/interfaces"
    fi
    return 0
}

rules() {
    # 等待在后台进行，未授权网络不能一直阻塞 WAN 启动流程。
    count=0
    while [ -z "$(interfaces)" ]; do
        pidof zerotier-one >/dev/null 2>&1 || return 1
        count=$((count + 1))
        if [ "$count" -ge 60 ]; then
            logger -t zerotier "60 秒内未出现已授权网卡，完成授权后请重新启动插件"
            return 1
        fi
        sleep 1
    done
    del_rules
    iptables -N ZT_PADAVAN_IN || return 1
    iptables -N ZT_PADAVAN_FW || { del_rules; return 1; }
    iptables -t nat -N ZT_PADAVAN_NAT || { del_rules; return 1; }
    interfaces > "$runtime/interfaces"
    nat_enable=$(nvram get zerotier_nat)
    while IFS= read -r zt0; do
        iptables -A ZT_PADAVAN_IN -i "$zt0" -j ACCEPT || { del_rules; return 1; }
        iptables -A ZT_PADAVAN_FW -i "$zt0" -j ACCEPT || { del_rules; return 1; }
        if [ "$nat_enable" = 1 ]; then
            iptables -t nat -A ZT_PADAVAN_NAT -o "$zt0" -j MASQUERADE || { del_rules; return 1; }
            for segment in $(ip -4 route show dev "$zt0" proto kernel | awk '$1 ~ /^[0-9]+\./ {print $1}'); do
                iptables -t nat -A ZT_PADAVAN_NAT -s "$segment" -j MASQUERADE || { del_rules; return 1; }
            done
            zero_route add
        fi
    done < "$runtime/interfaces"
    iptables -A INPUT -j ZT_PADAVAN_IN &&
    iptables -A FORWARD -j ZT_PADAVAN_FW &&
    iptables -t nat -A POSTROUTING -j ZT_PADAVAN_NAT || { del_rules; return 1; }
}

stop_worker() {
    if [ -r "$runtime/worker.pid" ]; then
        worker=$(cat "$runtime/worker.pid")
        case "$worker" in ''|*[!0-9]*) ;; *)
            # PID 可能已被复用，核对实际命令后才发送信号。
            if [ -r "/proc/$worker/cmdline" ] &&
               tr '\000' ' ' < "/proc/$worker/cmdline" | grep -F "$self rules" >/dev/null; then
                kill "$worker" 2>/dev/null
            fi;;
        esac
        rm -f "$runtime/worker.pid"
    fi
}

stop_zero() {
    stop_worker
    if pidof zerotier-one >/dev/null 2>&1; then
        killall -TERM zerotier-one 2>/dev/null
        count=0
        while pidof zerotier-one >/dev/null 2>&1 && [ "$count" -lt 5 ]; do
            sleep 1; count=$((count + 1))
        done
        pidof zerotier-one >/dev/null 2>&1 && killall -KILL zerotier-one 2>/dev/null
    fi
    del_rules
    # 不删除 identity.secret、networks.d、moons.d 和用户的 local.conf。
}

prepare_identity() {
    mkdir -p "$config_path/networks.d" || return 1
    chmod 700 "$config_path" "$config_path/networks.d"
    secret=$(nvram get zerotier_secret)
    if [ -n "$secret" ]; then
        printf '%s\n' "$secret" > "$config_path/identity.secret.new"
        "$PROGIDT" getpublic "$config_path/identity.secret.new" > "$config_path/identity.public.new" || {
            rm -f "$config_path/identity.secret.new" "$config_path/identity.public.new"; return 1;
        }
        mv -f "$config_path/identity.secret.new" "$config_path/identity.secret"
        mv -f "$config_path/identity.public.new" "$config_path/identity.public"
    elif [ -s "$config_path/identity.secret" ]; then
        "$PROGIDT" getpublic "$config_path/identity.secret" > "$config_path/identity.public.new" || return 1
        mv -f "$config_path/identity.public.new" "$config_path/identity.public"
    else
        "$PROGIDT" generate "$config_path/identity.secret" "$config_path/identity.public" >/dev/null || return 1
    fi
    chmod 600 "$config_path/identity.secret"
    if [ -z "$secret" ]; then
        nvram set "zerotier_secret=$(cat "$config_path/identity.secret")"
        nvram commit
    fi
}

creat_moon() {
    moonip=$(nvram get zerotiermoon_ip)
    [ -n "$moonip" ] || moonip=$(nvram get wan0_ipaddr)
    printf '%s\n' "$moonip" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1}' || return 1
    "$PROGIDT" initmoon "$config_path/identity.public" > "$config_path/moon.json" || return 1
    sed -i "s/\[\]/[ \"$moonip\/9993\" ]/" "$config_path/moon.json" || return 1
    (cd "$config_path" && "$PROGIDT" genmoon moon.json) || return 1
    mkdir -p "$config_path/moons.d" || return 1
    for moon in "$config_path"/*.moon; do
        [ -f "$moon" ] || continue
        mv "$moon" "$config_path/moons.d/" || return 1
    done
    moonid=$(sed -n 's/^[[:space:]]*"id"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F]*\)".*/\1/p' "$config_path/moon.json" | head -n 1)
    valid_hex "$moonid" 10 16 || return 1
    nvram set "zerotiermoon_id=$moonid"
    nvram commit
}

remove_moon() {
    moonid=$(nvram get zerotiermoon_id)
    [ -n "$moonid" ] || return 0
    valid_hex "$moonid" 10 16 || return 1
    # 文件名固定为十六进制世界编号，不使用可展开为路径的输入。
    padded=$(printf '%016s' "$moonid" | tr ' ' 0)
    rm -f "$config_path/moons.d/$padded.moon" "$config_path/moon.json"
    nvram set zerotiermoon_id=
    nvram commit
}

start_zero() {
    if [ -d "$config_path/controller.d" ]; then
        logger -t zerotier "检测到旧内置控制器数据；新版客户端不带该控制器，请先迁移控制器，现有数据已保留"
        return 1
    fi
    network=$(nvram get zerotier_id)
    [ -z "$network" ] || valid_hex "$network" 16 16 || {
        logger -t zerotier "网络编号必须是 16 位十六进制"; return 1;
    }
    pidof zerotier-one >/dev/null 2>&1 && return 0
    prepare_identity || { logger -t zerotier "身份校验失败，未启动服务"; return 1; }
    [ -z "$network" ] || touch "$config_path/networks.d/$network.conf"
    case "$(nvram get zerotiermoon_enable)" in
        1) creat_moon || return 1;;
        0) remove_moon || return 1;;
    esac
    (exec 9>&-; exec "$PROG" "$config_path") >/dev/null 2>&1 &
    sleep 1
    pidof zerotier-one >/dev/null 2>&1 || return 1
    moonid=$(nvram get zerotier_moonid)
    if [ -n "$moonid" ] && valid_hex "$moonid" 10 16; then
        timeout 5 "$PROGCLI" "-D$config_path" orbit "$moonid" "$moonid" >/dev/null 2>&1
    fi
    stop_worker
    (exec 9>&-; exec /bin/sh "$self" rules) >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$runtime/worker.pid"
}

case "$1" in
    rules) rules; exit $?;;
    start|stop|restart) ;;
    *) echo "用法：$0 start|stop|restart" >&2; exit 2;;
esac
exec 9>"$runtime/service.lock"
flock -w 10 9 || exit 1
case "$1" in
    start) start_zero;;
    stop) stop_zero;;
    restart) stop_zero && start_zero;;
esac
