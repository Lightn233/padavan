#!/bin/sh
# 启停与配置开关分离；保留用户脚本，只维护本服务的定时任务。
frpc_enable=$(nvram get frpc_enable)
frps_enable=$(nvram get frps_enable)
http_username=$(nvram get http_username)
storage=/etc/storage
runtime=/var/run

case "$http_username" in ''|.|..|*[!a-zA-Z0-9_.-]*)
    logger -t frp "管理用户名无效，未修改定时任务"; exit 1;;
esac
mkdir -p "$runtime" || exit 1
exec 9>"$runtime/frp.lock"
flock -w 5 9 || exit 1

cron_update() {
    mkdir -p "$storage/cron/crontabs" || return 1
    cron="$storage/cron/crontabs/$http_username"
    [ -f "$cron" ] || : > "$cron"
    # 仅移除旧版和当前版本的完整守护命令，不按 frp 关键词删行。
    awk '!($6 == "/bin/sh" && $7 == "/usr/bin/frp.sh" && $8 == "C") &&
         !($6 == "/usr/bin/frp.sh" && $7 == "C")' "$cron" > "$cron.frp.$$" || return 1
    if [ "$1" = add ]; then
        printf '%s\n' '*/1 * * * * /bin/sh /usr/bin/frp.sh C >/dev/null 2>&1' >> "$cron.frp.$$"
    fi
    chmod 600 "$cron.frp.$$"
    mv -f "$cron.frp.$$" "$cron"
}

stop_process() {
    pidof "$1" >/dev/null 2>&1 || return 0
    killall -TERM "$1" >/dev/null 2>&1
    count=0
    while pidof "$1" >/dev/null 2>&1 && [ "$count" -lt 5 ]; do
        sleep 1; count=$((count + 1))
    done
    pidof "$1" >/dev/null 2>&1 && killall -KILL "$1" >/dev/null 2>&1
    return 0
}

frp_stop() {
    cron_update del || return 1
    # stop 必须真正停止，不能依赖网页已先把启用开关改成零。
    stop_process frpc
    stop_process frps
}

frp_start() {
    if [ "$frpc_enable" != 1 ] && [ "$frps_enable" != 1 ]; then
        frp_stop
        return
    fi
    [ -r "$storage/frp_script.sh" ] || {
        logger -t frp "缺少启动配置脚本"; return 1;
    }
    # 用户脚本也有执行时限；后台服务不能继承本次启停锁。
    (exec 9>&-; timeout 20 /bin/sh "$storage/frp_script.sh") || {
        logger -t frp "启动脚本失败或超过 20 秒，请检查配置"; return 1;
    }
    cron_update add || return 1
    failed=0
    for name in frpc frps; do
        case "$name" in frpc) enabled=$frpc_enable;; frps) enabled=$frps_enable;; esac
        if [ "$enabled" = 1 ] && ! pidof "$name" >/dev/null 2>&1; then
            logger -t frp "$name 未运行，请检查配置和日志"; failed=1
        fi
    done
    return "$failed"
}

case "$1" in
    start) frp_start;;
    stop) frp_stop;;
    restart) frp_stop && frp_start;;
    C)
        # 连接远端失败时由 FRP 自身重连；不要求外网必须回应 ICMP。
        if { [ "$frpc_enable" = 1 ] && ! pidof frpc >/dev/null 2>&1; } ||
           { [ "$frps_enable" = 1 ] && ! pidof frps >/dev/null 2>&1; }; then
            frp_start
        fi;;
    *) echo "用法：$0 start|stop|restart|C" >&2; exit 2;;
esac
