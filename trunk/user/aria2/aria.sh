#!/bin/sh

#######################################################################
# (1) run process from superuser root (less security)
# (0) run process from unprivileged user "nobody" (more security)
SVC_ROOT=0

# process priority (0-normal, 19-lowest)
SVC_PRIORITY=3
#######################################################################

SVC_NAME="Aria2"
SVC_PATH="/usr/bin/aria2c"
DIR_LINK="/mnt/aria"

# 同一服务的启停串行执行；守护进程不继承锁文件描述符。
exec 9>/var/run/aria2-service.lock || exit 1
flock -x 9 || exit 1

func_start()
{
	# Make sure already running
	if [ -n "`pidof aria2c`" ] ; then
		return 0
	fi

	echo -n "Starting $SVC_NAME:."

	if [ ! -d "${DIR_LINK}" ] ; then
		echo "[FAILED]"
		logger -t "$SVC_NAME" "Cannot start: unable to find target dir!"
		return 1
	fi

	DIR_CFG="${DIR_LINK}/config"
	DIR_DL1="`cd \"$DIR_LINK\"; dirname \"$(pwd -P)\"`/Downloads"
	[ ! -d "$DIR_DL1" ] && DIR_DL1="${DIR_LINK}/downloads"

	[ ! -d "$DIR_CFG" ] && mkdir -p "$DIR_CFG"

	FILE_CONF="$DIR_CFG/aria2.conf"
	FILE_LIST="$DIR_CFG/incomplete.lst"

	touch "$FILE_LIST"

	aria_pport=`nvram get aria_pport`
	aria_rport=`nvram get aria_rport`
	aria_user=`nvram get http_username`
	aria_pass=`nvram get http_passwd`

	[ -z "$aria_rport" ] && aria_rport="6800"
	[ -z "$aria_pport" ] && aria_pport="16888"

	if [ ! -f "$FILE_CONF" ] ; then
		# 新配置必须有认证；已有配置保留原样。
		[ -n "$aria_pass" ] || { logger -t "$SVC_NAME" "后台密码为空，无法生成 RPC 密钥"; return 1; }
		umask 077
		[ ! -d "$DIR_DL1" ] && mkdir -p "$DIR_DL1"
		chmod -R 777 "$DIR_DL1"
		# 在目标盘完整写入后再替换，避免磁盘写入失败留下半份配置。
		aria_tmp=$(mktemp "$DIR_CFG/.aria2.conf.XXXXXX") || return 1
		if ! cat > "$aria_tmp" <<EOF

### XML-RPC
rpc-listen-all=true
rpc-allow-origin-all=true
# RPC 密钥初始使用后台密码；可改成独立密钥，并在 AriaNg 中填写相同值。
rpc-secret=$aria_pass
#rpc-user=$aria_user
#rpc-passwd=$aria_pass

### Common
dir=$DIR_DL1
max-download-limit=0
max-overall-download-limit=0
disable-ipv6=false

### File
file-allocation=trunc
#file-allocation=falloc
#file-allocation=none
no-file-allocation-limit=10M
allow-overwrite=false
auto-file-renaming=true

### Bittorent
bt-enable-lpd=false
#bt-lpd-interface=eth2.2
bt-max-peers=50
bt-max-open-files=100
bt-request-peer-speed-limit=100K
bt-stop-timeout=0
enable-dht=true
#enable-dht6=false
enable-peer-exchange=true
seed-ratio=1.5
#seed-time=60
max-upload-limit=0
max-overall-upload-limit=0

### FTP/HTTP
ftp-pasv=true
ftp-type=binary
timeout=120
connect-timeout=60
split=8
max-concurrent-downloads=3
max-connection-per-server=8
min-split-size=1M
check-certificate=true
ca-certificate=/etc/ssl/certs/ca-certificates.crt

### Log
log=$DIR_CFG/aria2.log
log-level=notice

EOF
		then
			rm -f "$aria_tmp"
			logger -t "$SVC_NAME" "写入默认配置失败，未启动服务"
			return 1
		fi
		mv "$aria_tmp" "$FILE_CONF" || return 1
	fi

	# aria2 needed home dir
	export HOME="$DIR_CFG"

	if [ "`nvram get http_proto`" != "0" ]; then
		SVC_ROOT=1
		SSL_OPT="--rpc-secure=true --rpc-certificate=/etc/storage/https/server.crt --rpc-private-key=/etc/storage/https/server.key"
	else
		SSL_OPT=
	fi

	svc_user=""

	if [ $SVC_ROOT -eq 0 ] ; then
		chmod 777 "${DIR_LINK}"
		chown -R nobody "$DIR_CFG"
		svc_user=" -c nobody"
	fi

	start-stop-daemon -S -N $SVC_PRIORITY$svc_user -x $SVC_PATH -- \
		-D --enable-rpc=true --conf-path="$FILE_CONF" --input-file="$FILE_LIST" --save-session="$FILE_LIST" \
		--rpc-listen-port="$aria_rport" --listen-port="$aria_pport" --dht-listen-port="$aria_pport" $SSL_OPT 9>&-

	if [ $? -eq 0 ] ; then
		echo "[  OK  ]"
		logger -t "$SVC_NAME" "daemon is started"
	else
		echo "[FAILED]"
	fi
}

func_stop()
{
	# Make sure not running
	if [ -z "`pidof aria2c`" ] ; then
		return 0
	fi

	echo -n "Stopping $SVC_NAME:."

	# stop daemon
	killall -q aria2c

	# gracefully wait max 15 seconds while aria2c stopped
	i=0
	while [ -n "`pidof aria2c`" ] && [ $i -le 15 ] ; do
		echo -n "."
		i=$(( $i + 1 ))
		sleep 1
	done

	aria_pid=`pidof aria2c`
	if [ -n "$aria_pid" ] ; then
		# force kill (hungup?)
		killall -KILL aria2c >/dev/null 2>&1
		sleep 1
		echo "[KILLED]"
		logger -t "$SVC_NAME" "Cannot stop: Timeout reached! Force killed."
	else
		echo "[  OK  ]"
	fi
}

func_reload()
{
	aria_pid=`pidof aria2c`
	if [ -n "$aria_pid" ] ; then
		echo -n "Reload $SVC_NAME config:."
		killall -HUP aria2c >/dev/null 2>&1
		echo "[  OK  ]"
	else
		echo "Error: $SVC_NAME is not started!"
	fi
}

case "$1" in
start)
	func_start
	;;
stop)
	func_stop
	;;
reload)
	func_reload
	;;
restart)
	func_stop
	func_start
	;;
*)
	echo "Usage: $0 {start|stop|reload|restart}"
	exit 1
	;;
esac
