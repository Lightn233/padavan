#!/bin/sh
pidfile="/var/scutclient.sh.pid"
scutclient_exec="bin_scutclient"
LOG="$2"

# 一次性启动脚本互斥执行，不能按旧 PID 文件杀死可能已复用该编号的进程。
lockdir="${pidfile}.lock"
if ! mkdir "$lockdir" 2>/dev/null; then
	# 只清理已退出的持有者留下的标记；新持有者的标记不会被删除。
	owner=$(find "$lockdir" -maxdepth 1 -type f 2>/dev/null)
	case "${owner##*/}" in
	''|*[!0-9]*) echo "已有服务操作正在执行，稍后重试。" >&2; exit 1 ;;
	esac
	if kill -0 "${owner##*/}" 2>/dev/null ||
	   ! rm -f "$owner" || ! rmdir "$lockdir" 2>/dev/null ||
	   ! mkdir "$lockdir" 2>/dev/null; then
		echo "已有服务操作正在执行，稍后重试。" >&2
		exit 1
	fi
fi
touch "$lockdir/$$" || { rmdir "$lockdir"; exit 1; }
trap 'rm -f "$lockdir/$$"; rmdir "$lockdir" 2>/dev/null' 0
trap 'exit 1' 1 2 15

func_log(){
	[ "$LOG" != "nolog" ] && logger -st "scutclient" "$1"
}

get_arg_debug(){
	[ "$(nvram get scutclient_debug)" = "1" ] && echo "-D"
}

get_arg_skip_udp_hb(){
	[ "$(nvram get scutclient_skip_udp_hb)" = "1" ] && echo "-b"
}

func_start(){
#	[ "$(mtk_esw 11)" = "WAN ports link state: 0" ] && func_log "WAN has no link!" && exit 1
	auth_hook=$(nvram get scutclient_auth_exec)
	fail_hook=$(nvram get scutclient_fail_exec)
	sysdns=$(nvram get wan_dns1_x | cut -d ' ' -f 1)
	echo -n "Starting scutclient:..."
	# 使用位置参数保存每个值，关闭的开关不生成空参数。
	set -- -u "$(nvram get scutclient_username)" -p "$(nvram get scutclient_password)" \
		-i "$(nvram get wan_ifname)" -n "${sysdns:-114.114.114.114}"
	local value
	value=$(nvram get scutclient_hostname); [ -z "$value" ] || set -- "$@" -H "$value"
	value=$(nvram get scutclient_server_auth_ip); [ -z "$value" ] || set -- "$@" -s "$value"
	value=$(nvram get scutclient_version); [ -z "$value" ] || set -- "$@" -c "$value"
	value=$(nvram get scutclient_hash); [ -z "$value" ] || set -- "$@" -h "$value"
	[ "$(nvram get scutclient_debug)" != 1 ] || set -- "$@" -D
	[ "$(nvram get scutclient_skip_udp_hb)" != 1 ] || set -- "$@" -b
	set -- "$@" -E "${auth_hook:-echo 0 > /tmp/scutclient_status}" \
		-Q "${fail_hook:-echo 1 > /tmp/scutclient_status}"
	start-stop-daemon -S -b -x "$scutclient_exec" -- "$@"

	if [ $? -eq 0 ] ; then
		echo "[  OK  ]"
		func_log "Daemon is started"
		return 0
	else
		echo "[FAILED]"
		return 1
	fi
}

func_stop(){
	echo -n "Stopping scutclient:..."
	killall -q -9 $scutclient_exec
	$scutclient_exec -o -i "$(nvram get wan_ifname)" >/dev/null 2>&1
	echo "[  OK  ]"
	func_log "Stopped"
}

case "$1" in
start)
	func_start
	;;
stop)
	func_stop
	;;
restart)
	func_stop
	func_start
	;;
*)
	echo "Usage: $0 { start | stop | restart }"
	;;
esac
result=$?
exit "$result"
