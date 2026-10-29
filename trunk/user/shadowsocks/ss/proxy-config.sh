#!/bin/sh
# 先生成并验证候选配置，全部通过后才允许停止旧服务或接管流量。

proxy_json_write() {
	local kind="$1" target="$2" generator="$3" tmp error bin work
	shift 3
	case "$1" in ''|*[!0-9]*) log "节点编号无效，保留当前配置。"; return 1 ;; esac
	if [ -n "$SS_PENDING_DIR" ]; then target="$SS_PENDING_DIR/${target##*/}"; fi
	umask 077
	work=$(mktemp -d "${target}.XXXXXX") || return 1
	# 核心按扩展名识别配置，随机目录内保留 .json 文件名。
	tmp="$work/config.json"
	error="$work/error"
	if ! lua "$generator" "$@" >"$tmp" 2>"$error" ||
	   ! lua -e 'local c=require("cjson"); local t=c.decode(io.read("*a")); assert(type(t)=="table")' <"$tmp" 2>>"$error"; then
		log "代理配置生成失败：$(head -c 1024 "$error")"
		rm -f "$tmp" "$error"
		rmdir "$work"
		return 1
	fi
	case "$kind" in
	xray|v2ray)
		bin=$(find_bin "$kind")
		if [ ! -x "$bin" ]; then
			log "找不到 $kind 程序，未更改流量接管。"
			rm -f "$tmp" "$error"
			rmdir "$work"
			return 1
		fi
		case "${bin##*/}" in
		xray) "$bin" run -test -format json -config "$tmp" >"$error" 2>&1 ;;
		*) "$bin" test -format json -config "$tmp" >"$error" 2>&1 ;;
		esac
		if [ "$?" != 0 ]; then
			log "代理配置检查失败：$(tail -c 1536 "$error")"
			rm -f "$tmp" "$error"
			rmdir "$work"
			return 1
		fi
		;;
	esac
	if ! mv -f "$tmp" "$target"; then rm -f "$tmp" "$error"; rmdir "$work"; return 1; fi
	rm -f "$error"
	rmdir "$work"
}

proxy_run_core() {
	local bin="$1" config="$2" port="$3" proto="$4"
	run_bin "$bin" run -config "$config"
	proxy_wait_listener "$PROXY_RUN_PID" "$port" "$proto"
}

proxy_core_owned() {
	local pid="$1"
	[ -r "/proc/$pid/cmdline" ] || return 1
	tr '\000' '\n' <"/proc/$pid/cmdline" | grep -qxE '/tmp/(v2-redir|v2-ssr-reudp|v2-ssr-local)\.json'
}

proxy_stop_cores() {
	local pid n
	# 只停止本服务配置启动的核心，保留用户独立运行的 Xray/V2Ray。
	for pid in $(pidof v2ray 2>/dev/null; pidof xray 2>/dev/null); do
		case "$pid" in ''|*[!0-9]*) continue ;; esac
		proxy_core_owned "$pid" || continue
		kill -TERM "$pid" 2>/dev/null
		n=0
		while [ "$n" -lt 20 ] && proxy_core_owned "$pid"; do
			usleep 100000
			n=$((n + 1))
		done
		if proxy_core_owned "$pid"; then kill -KILL "$pid" 2>/dev/null; fi
	done
}

proxy_any_core_running() {
	local pid
	for pid in $(pidof v2ray 2>/dev/null; pidof xray 2>/dev/null); do
		case "$pid" in ''|*[!0-9]*) continue ;; esac
		proxy_core_owned "$pid" && return 0
	done
	return 1
}

proxy_dns_remove_owned() {
	local config=/etc/storage/dnsmasq/dnsmasq.conf tmp
	[ -f "$config" ] || return 0
	tmp=$(mktemp "${config}.XXXXXX") || return 1
	# 按完整配置项匹配，不能因一行包含 cdn 或 gfwlist 就删掉。
	awk '
		$0 == "conf-dir=/etc/storage/dnsmasq.oversea" {next}
		$0 == "conf-file=/etc/storage/dnsmasq-ss.d" {next}
		$0 == "conf-dir=/tmp/cdn" {next}
		{print}' "$config" >"$tmp" || { rm -f "$tmp"; return 1; }
	cat "$tmp" >"$config"
	local result=$?
	rm -f "$tmp"
	return "$result"
}

proxy_local_config() {
	local node="$1" type="$2" port="$3"
	case "$type" in
	xray) proxy_json_write xray /tmp/v2-ssr-local.json /etc_ro/ss/genxrayconfig.lua "$node" tcp 0 "$port" ;;
	v2ray) proxy_json_write v2ray /tmp/v2-ssr-local.json /etc_ro/ss/genv2config.lua "$node" tcp 0 "$port" ;;
	trojan) proxy_json_write trojan /tmp/trojan-ssr-local.json /etc_ro/ss/gentrojanconfig.lua "$node" client "$port" ;;
	ss|ssr) gen_config_file "$node" 3 "$port" ;;
	*) return 0 ;;
	esac
}

proxy_pending_remove() {
	case "$SS_PENDING_DIR" in /tmp/ssr-preflight.*) rm -rf "$SS_PENDING_DIR" ;; esac
	SS_PENDING_DIR=""
}

proxy_preflight() {
	local node type bin f
	[ "$SS_CONFIG_READY" = 1 ] && return 0
	SS_PENDING_DIR=$(mktemp -d /tmp/ssr-preflight.XXXXXX) || return 1
	chmod 700 "$SS_PENDING_DIR"
	UDP_RELAY_SERVER=$(nvram get udp_relay_server)
	[ "$UDP_RELAY_SERVER" = same ] && UDP_RELAY_SERVER="$GLOBAL_SERVER"
	[ -n "$UDP_RELAY_SERVER" ] || UDP_RELAY_SERVER=nil
	if [ -n "$GLOBAL_SERVER" ] && [ "$GLOBAL_SERVER" != nil ]; then
		if ! gen_config_file "$GLOBAL_SERVER" 0 1080; then proxy_pending_remove; return 1; fi
		if [ "$UDP_RELAY_SERVER" != nil ] && ! gen_config_file "$UDP_RELAY_SERVER" 1 1080; then
			proxy_pending_remove; return 1
		fi
	fi
	node=$(nvram get socks5_enable)
	[ "$node" = same ] && node="$GLOBAL_SERVER"
	if [ -n "$node" ] && [ "$node" != nil ]; then
		if ! proxy_local_config "$node" "$(nvram get s5_type)" "$(nvram get socks5_port)"; then
			proxy_pending_remove; return 1
		fi
	fi
	# 所有节点检查通过才发布；候选与运行配置均在 /tmp，可原子更名。
	for f in "$SS_PENDING_DIR"/*.json; do
		[ -f "$f" ] || continue
		case "${f##*/}" in
		shadowsocksr.json|shadowsocksr_u.json|shadowsocksr_s.json|v2-redir.json|tj-redir.json|v2-ssr-reudp.json|trojan-ssr-reudp.json|v2-ssr-local.json|trojan-ssr-local.json) ;;
		*) proxy_pending_remove; return 1 ;;
		esac
		if ! mv -f "$f" "/tmp/${f##*/}"; then proxy_pending_remove; return 1; fi
	done
	proxy_pending_remove
	SS_CONFIG_READY=1
}

proxy_wait_listener() {
	local pid="$1" port="$2" proto="$3" n=0 sockets hex
	case "$pid" in ''|*[!0-9]*) return 1 ;; esac
	case "$port" in ''|*[!0-9]*) return 1 ;; esac
	case "$proto" in tcp|udp) ;; *) return 1 ;; esac
	hex=$(printf '%04X' "$port") || return 1
	while [ "$n" -lt 100 ]; do
		kill -0 "$pid" 2>/dev/null || return 1
		# 按 socket inode 核实端口属于本次子进程，不能把别人的监听算成成功。
		sockets="$(ls -l /proc/"$pid"/fd 2>/dev/null | sed -n 's/.* -> socket:\[\([0-9]*\)\]$/\1/p' | tr '\n' ' ')"
		if [ -n "$sockets" ] && awk -v owned=" $sockets" -v port="$hex" -v proto="$proto" '
			{split($2, addr, ":")}
			addr[2] == port && ((proto == "tcp" && $4 == "0A") || (proto == "udp" && $4 == "07")) &&
			index(owned, " " $10 " ") {found=1}
			END {exit !found}' /proc/net/"$proto" /proc/net/"${proto}6" 2>/dev/null; then return 0; fi
		usleep 100000
		n=$((n + 1))
	done
	log "代理进程未按时监听 $proto/$port，未启用流量接管。"
	return 1
}
