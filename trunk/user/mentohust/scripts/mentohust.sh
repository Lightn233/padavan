#!/bin/sh

pidfile="/var/sh_mentohust.pid"
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

mentohust_exec="bin_mentohust"
conf_file="/var/mentohust.conf"
bin_conf_file="/etc/storage/mentohust.conf"

mentohust_vars="username password nic ip mask gw dns pinghost timeout interval \
	restart_wait maxfail startmode dhcp daemon ver datafile dhcpscript service"

mentohust_conf_vars="Username Password Nic IP Mask Gateway DNS PingHost Timeout EchoInterval \
	RestartWait MaxFail StartMode DhcpMode DaemonMode Version DataFile DhcpScript Service"

func_log(){
	logger -st "mentohust" "$1"
}

func_gen_conf(){
	local tmp key c value nic cr
	umask 077
	tmp=$(mktemp "${conf_file}.XXXXXX") || return 1
	cr=$(printf '\r')
	nic=$(nvram get mentohust_nic)
	[ -n "$nic" ] || nic=$(nvram get wan_ifname)
	printf '[MentoHUST]\n' >"$tmp" || { rm -f "$tmp"; return 1; }
	set -- $mentohust_conf_vars
	for c in $mentohust_vars; do
		key=$1
		shift
		value=$(nvram get "mentohust_${c}")
		[ "$c" != nic ] || value=$nic
		# 每个配置项只占一行；按原值写入，不把密码当作 sed 表达式。
		case "$value" in
		*"$cr"*|*'
'*) func_log "配置项 $key 包含换行，保留旧配置。"; rm -f "$tmp"; return 1 ;;
		esac
		printf '%s=%s\n' "$key" "$value" >>"$tmp" || { rm -f "$tmp"; return 1; }
	done
	chmod 600 "$tmp" && mv -f "$tmp" "$conf_file" || { rm -f "$tmp"; return 1; }
	ln -sf "$conf_file" "$bin_conf_file"
}

func_start(){
	if [ -f $bin_conf_file ] && [ ! -L $bin_conf_file ]; then
		func_log "Using existed conf: $bin_conf_file"
	else
		func_gen_conf || return 1
	fi

	echo -n "Starting mentohust:..."
	start-stop-daemon -S -b -x "$mentohust_exec"
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
	echo -n "Stopping mentohust:..."
	killall -q -9 $mentohust_exec
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

