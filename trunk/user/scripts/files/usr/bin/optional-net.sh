#!/bin/sh
# 可选核心独立管理：默认不启用，不修改 DNS、透明代理或系统启动配置。
set -eu
umask 077
NAME=${1:-};ACTION=${2:-status}
case "$NAME" in sing-box|mihomo|tailscale) ;; *) echo '用法：optional-net.sh sing-box|mihomo|tailscale install|start|stop|restart|check|status|rollback|config [文件]' >&2;exit 2;; esac
BASE=${OPTIONAL_NET_BASE:-/media/mtd_rwfs/optional-net}
RUNROOT=${OPTIONAL_NET_RUN:-/var/run/optional-net}
case "$BASE:$RUNROOT" in /*:/*) ;; *) echo '数据和运行目录必须为绝对路径' >&2;exit 2;; esac
case "$BASE" in /|/etc|/tmp|/media|/media/mtd_rwfs) echo '请使用独立数据子目录' >&2;exit 2;; esac
case "$BASE/$RUNROOT/" in *'/../'*|*'/./'*|*' '*|*'\'*) echo '路径不能包含相对段、空格或反斜杠' >&2;exit 2;; esac
DIR=$BASE/$NAME;RUN=$RUNROOT/$NAME;CURRENT=$DIR/current
STAGE=;DOWNLOAD=
fail() { echo "$*" >&2; exit 1; }
cleanup() {
    if [ -n "$STAGE" ]; then case "$STAGE" in "$DIR"/.stage.*) rm -rf "$STAGE";; esac; fi
    [ -z "$DOWNLOAD" ] || rm -f "$DOWNLOAD"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
for d in "$BASE" "$DIR" "$RUNROOT" "$RUN"; do [ ! -L "$d" ] || fail '数据目录不能是符号链接'; done
mkdir -p "$RUN";chmod 700 "$RUN"
exec 9>"$RUN/lock"
flock -n 9 || fail '已有同一核心的管理操作正在执行'
case "$NAME" in
sing-box)
    VERSION=1.14.4;ARCHIVE=sing-box-1.14.4-linux-mipsle-softfloat.tar.gz
    URL=https://github.com/SagerNet/sing-box/releases/download/v1.14.4/$ARCHIVE
    HASH=4abf94c284462bca0d9d23966b26e5675a2c0137b7945534f0fa1b0fc309b298
    BINHASH=2ebe1bea84d0cf34372e03a1ae98ee0b872d208bc451c6e9a8bf835ee584792c
    SIZE=84803741;MEMBER=sing-box-1.14.4-linux-mipsle-softfloat/sing-box;CONF=$DIR/config.json;EXE=sing-box;;
mihomo)
    VERSION=1.19.33;ARCHIVE=mihomo-linux-mipsle-softfloat-v1.19.33.gz
    URL=https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/$ARCHIVE
    HASH=ad6b3837db8dff2a6853a3c1604b82ee2f7e4019f626a5ab61f46b7c565871c4
    BINHASH=c246ff6d3a0da9b01e75c73a04d7ce66bc8644703c8a59353d222fedadf0f362
    SIZE=63701149;CONF=$DIR/config.yaml;EXE=mihomo;;
tailscale)
    VERSION=1.104.4;ARCHIVE=tailscale_1.104.4_mipsle.tgz
    URL=https://pkgs.tailscale.com/stable/$ARCHIVE
    HASH=34ec037b1f56690fcd383a67bec48f06ccb49036642228e2dc864bbdf55df17d
    BINHASH=7cf9efeb16fb09c0696c468a64e4d83000308674abaae6c93ebb3700af1a4fa3
    CLIHASH=f6712bddf591ffb331753a7d3c7dd898b02e3ba619c3ecba5c038973ae52bf50
    SIZE=76466211;CONF=$DIR/tailscale.state;EXE=tailscaled;;
esac
runbin() { if [ -n "${OPTIONAL_NET_RUNNER:-}" ]; then "$OPTIONAL_NET_RUNNER" "$@";else "$@";fi; }
uptime_seconds() { read -r service_uptime service_idle < /proc/uptime;printf '%s\n' "${service_uptime%%.*}"; }
timed_check() {
    # 旧机型 BusyBox 使用 -t，当前版本与 GNU 使用位置参数；管理锁只由父进程持有。
    help=$(timeout --help 2>&1 || :)
    case "$help" in *'[-t SECS]'*) set -- timeout -s KILL -t 30 "$@";; *) set -- timeout -s KILL 30 "$@";; esac
    (exec 9>&-;exec "$@")
}
verify() { actual=$(sha256sum "$1" | awk '{print $1}');[ "$actual" = "$2" ]; }
storage_ready() {
    mkdir -p "$DIR";chmod 700 "$DIR"
    [ -w "$DIR" ] || fail '数据目录不可写'
    # 不把大程序写入 RAM 文件系统；选择路径所处的最长匹配挂载点。
    awk -v path="$DIR/" 'index(path,$2 "/")==1 || $2=="/" {if(length($2)>best){best=length($2);type=$3;opts=$4}} END {exit !(type!="tmpfs" && type!="ramfs" && opts ~ /(^|,)rw(,|$)/)}' /proc/mounts || fail '请选择已挂载的可写持久存储'
    [ ! -L "$CONF" ] || fail '配置文件不能是符号链接'
}
running() {
    [ -f "$RUN/pid" ] && [ ! -L "$RUN/pid" ] || return 1
    read -r PID START <"$RUN/pid" || return 1
    case "$PID:$START" in *[!0-9:]*|:*|*:) return 1;; esac
    [ "$PID" -gt 1 ] && [ -r "/proc/$PID/stat" ] || return 1
    [ "$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null)" = "$START" ] || return 1
    tr '\000' '\n' 2>/dev/null <"/proc/$PID/cmdline" | grep -Fqx "$CURRENT/$EXE" || return 1
    kill -0 "$PID" 2>/dev/null
}
stop_service() {
    if running; then
        kill -TERM "$PID"
        stop_deadline=$(( $(uptime_seconds) + 5 ))
        while running && [ "$(uptime_seconds)" -lt "$stop_deadline" ];do sleep 0.1;done
        if running;then kill -KILL "$PID";fi
    fi
    rm -f "$RUN/pid"
}
check_config() {
    core=$1;cfg=$2
    [ "$NAME" = tailscale ] && return 0
    [ -s "$cfg" ] && [ ! -L "$cfg" ] || { echo '缺少有效配置文件' >&2;return 1; }
    case "$NAME" in
    sing-box) set -- "$core/sing-box" check -c "$cfg" -D "$DIR" ;;
    mihomo) set -- "$core/mihomo" -t -d "$DIR" -f "$cfg" ;;
    esac
    if [ -n "${OPTIONAL_NET_RUNNER:-}" ];then timed_check "$OPTIONAL_NET_RUNNER" "$@" || return 1;else timed_check "$@" || return 1;fi
    if [ "$NAME" = mihomo ];then
        # 管理 API 可在代理绑定失败后继续存活，必须从块式 YAML 取出要求的代理端口。
        # 无法识别的端口格式明确拒绝，避免把 API 监听误判为代理启动成功。
        awk '
        /^(port|socks-port|mixed-port|redir-port|tproxy-port):/ {
            value=$0;sub(/^[^:]+:[ \t]*/,"",value);sub(/[ \t]+#.*/,"",value);sub(/[ \t\r]+$/,"",value)
            if(value !~ /^[0-9]+$/ || value+0>65535){bad=1;next}
            if(value+0>0){printf "%04X ",value+0;count++}
        }
        END{if(bad || !count)exit 1;print ""}' "$cfg" >"$RUN/required-ports" || {
            echo '管理脚本需要块式 YAML 中明确的非零 port、socks-port 或 mixed-port 等代理端口' >&2;return 1;
        }
    fi
}
has_listener() {
    owned=$(ls -l /proc/"$PID"/fd 2>/dev/null | sed -n 's/.* -> socket:\[\([0-9]*\)\]$/\1/p' | tr '\n' ' ')
    [ -n "$owned" ] || return 1
    ports=
    [ "$NAME" != mihomo ] || ports=$(cat "$RUN/required-ports")
    awk -v owned=" $owned" -v ports="$ports" '
    BEGIN{count=split(ports,p," ");for(i=1;i<=count;i++)if(p[i]!="")required[p[i]]=1}
    $4=="0A" && index(owned," " $10 " "){ok=1;split($2,a,":");delete required[a[2]]}
    END{for(k in required)exit 1;exit !ok}' /proc/net/tcp /proc/net/tcp6
}
start_service() {
    if running;then echo '已运行';return 0;fi
    storage_ready
    [ -x "$CURRENT/$EXE" ] || fail '尚未安装核心'
    check_config "$CURRENT" "$CONF" >"$RUN/check.log" 2>&1 || { tail -c 2048 "$RUN/check.log" >&2;return 1; }
    # 日志交给系统环形日志；不在 RAM 中积累无限增长的普通文件。
    rm -f "$RUN/log.pipe";mkfifo -m 600 "$RUN/log.pipe"
    (exec 9>&-;exec logger -t "optional-$NAME") <"$RUN/log.pipe" &
    case "$NAME" in
    sing-box) set -- "$CURRENT/sing-box" run -c "$CONF" -D "$DIR" ;;
    mihomo) set -- "$CURRENT/mihomo" -d "$DIR" -f "$CONF" ;;
    tailscale) set -- "$CURRENT/tailscaled" --tun=userspace-networking --state="$CONF" --socket="$RUN/tailscale.sock" --port=0 ;;
    esac
    # PID 对应 exec 后的真实核心；后台进程关闭管理锁。
    (exec 9>&-;if [ -n "${OPTIONAL_NET_RUNNER:-}" ];then exec "$OPTIONAL_NET_RUNNER" "$@";else exec "$@";fi) </dev/null >"$RUN/log.pipe" 2>&1 &
    PID=$!;START=$(awk '{print $22}' "/proc/$PID/stat");printf '%s %s\n' "$PID" "$START" >"$RUN/pid"
    # 给 exec 留出调度时间，避免把启动包装进程误认作旧 PID。
    sleep 0.2
    # 按单调运行时间限时，不能把慢 CPU 上的检查开销误算成固定循环次数。
    ready=0;start_deadline=$(( $(uptime_seconds) + 30 ))
    while [ "$(uptime_seconds)" -lt "$start_deadline" ];do
        if ! running;then echo '核心已退出，请查看系统日志' >&2;rm -f "$RUN/pid";return 1;fi
        if [ "$NAME" = tailscale ];then
            if [ -S "$RUN/tailscale.sock" ] && runbin "$CURRENT/tailscale" --socket="$RUN/tailscale.sock" status --json >"$RUN/status.json" 2>/dev/null && grep -q 'BackendState' "$RUN/status.json";then ready=1;break;fi
        elif has_listener;then
            # 监听出现后再等一轮核心初始化，避免首次请求碰到尚未装载的规则。
            sleep 1
            if running && has_listener;then ready=1;break;fi
        fi
        sleep 0.1
    done
    if [ "$ready" != 1 ];then stop_service;echo '核心未就绪，未修改 DNS 或防火墙' >&2;return 1;fi
    [ "$NAME" = tailscale ] || cp "$CONF" "$RUN/active-config"
    echo '核心已启动并监听；远端节点连通性需要另行检查'
}
restart_service() {
    storage_ready;check_config "$CURRENT" "$CONF" || return 1
    restore=0
    if [ "$NAME" != tailscale ] && running && [ -f "$RUN/active-config" ];then
        cp "$RUN/active-config" "$RUN/restart-config";restore=1
    fi
    stop_service
    if start_service;then rm -f "$RUN/restart-config";return 0;fi
    if [ "$restore" = 1 ];then
        cp "$CONF" "$CONF.failed"
        cp "$RUN/restart-config" "$CONF"
        if start_service;then echo '新配置启动失败，已恢复上一次运行配置；失败配置另存为 .failed' >&2;fi
    fi
    return 1
}
install_core() {
    storage_ready
    running && fail '请先停止该核心，再安装；现有进程与配置已保留'
    free=$(df -Pk "$DIR" | awk 'NR==2{print $4}')
    need=$((SIZE/1024+32768))
    [ "$free" -ge "$need" ] || fail "可用空间不足，需要至少 ${need} KiB 以保留回退版本"
    archive=${3:-}
    if [ -z "$archive" ];then DOWNLOAD=$DIR/.download-$$;archive=$DOWNLOAD;curl -fL --retry 2 --connect-timeout 15 --max-time 600 -o "$archive" "$URL" || fail '下载失败，可指定本地官方压缩包重试';fi
    [ -f "$archive" ] && verify "$archive" "$HASH" || fail '压缩包 SHA-256 不符，未替换程序'
    STAGE=$(mktemp -d "$DIR/.stage.XXXXXX")
    case "$NAME" in
    sing-box) tar -xzOf "$archive" "$MEMBER" >"$STAGE/sing-box" ;;
    mihomo) gzip -dc "$archive" >"$STAGE/mihomo" ;;
    tailscale)
        tar -xzOf "$archive" "tailscale_${VERSION}_mipsle/tailscaled" >"$STAGE/tailscaled"
        tar -xzOf "$archive" "tailscale_${VERSION}_mipsle/tailscale" >"$STAGE/tailscale"
        verify "$STAGE/tailscale" "$CLIHASH" || fail '命令行程序校验失败';chmod 755 "$STAGE/tailscale" ;;
    esac
    verify "$STAGE/$EXE" "$BINHASH" || fail '核心程序校验失败'
    chmod 755 "$STAGE/$EXE"
    if [ -f "$CONF" ];then check_config "$STAGE" "$CONF" || fail '现有配置不兼容；旧核心和配置均保留，请先迁移';fi
    dest=$DIR/$VERSION
    if [ -e "$dest" ];then verify "$dest/$EXE" "$BINHASH" || fail '同版本目录内容不一致，请先检查';rm -f "$STAGE/$EXE" "$STAGE/tailscale";rmdir "$STAGE";STAGE=
    else mv "$STAGE" "$dest";STAGE=;fi
    # 保留旧链接用于回退，不删除旧配置或旧版本目录。
    if [ -L "$CURRENT" ] && [ "$CURRENT/$EXE" -ef "$dest/$EXE" ];then echo '已安装此版本，回退记录保留';return 0;fi
    if [ -L "$CURRENT" ];then cp -P "$CURRENT" "$DIR/.previous.new";mv -Tf "$DIR/.previous.new" "$DIR/previous";fi
    rm -f "$DIR/.current.new";ln -s "$VERSION" "$DIR/.current.new";mv -Tf "$DIR/.current.new" "$CURRENT"
    echo "$NAME $VERSION 已安装，未启动"
}
case "$ACTION" in
install) install_core "$@" ;;
start) start_service ;;
stop) stop_service ;;
restart) restart_service ;;
check) check_config "$CURRENT" "$CONF" ;;
status) if running;then echo "running pid=$PID";else echo stopped;fi ;;
config)
    [ "$NAME" != tailscale ] || fail 'Tailscale 使用自己的登录与状态文件'
    storage_ready;input=${3:-};[ -f "$input" ] || fail '请指定配置文件'
    STAGE=$(mktemp -d "$DIR/.stage.XXXXXX");cp "$input" "$STAGE/config.$([ "$NAME" = sing-box ] && echo json || echo yaml)"
    candidate=$STAGE/config.$([ "$NAME" = sing-box ] && echo json || echo yaml)
    check_config "$CURRENT" "$candidate" || fail '候选配置检查失败，当前配置保留'
    [ ! -f "$CONF" ] || cp -p "$CONF" "$CONF.previous"
    mv "$candidate" "$CONF";echo '配置已保存，运行进程未重启' ;;
migrate)
    [ "$NAME" = sing-box ] || fail '自动字段迁移仅用于 Sing-box；Mihomo 继续使用原 YAML 配置'
    storage_ready;input=${3:-};[ -f "$input" ] || fail '请指定原配置文件'
    lua -v >/dev/null 2>&1 || fail '此固件未包含 Lua；请在 Ubuntu 执行随源码提供的迁移工具，再导入结果'
    STAGE=$(mktemp -d "$DIR/.stage.XXXXXX");candidate=$STAGE/config.json
    lua /etc_ro/optional-net/sing-box-migrate.lua "$input" >"$candidate" || fail '配置无法安全自动迁移，原文件保留'
    check_config "$CURRENT" "$candidate" || fail '迁移结果未通过当前核心检查，原文件保留'
    mv "$candidate" "$DIR/config.migrated.json";echo "$DIR/config.migrated.json：已生成并校验，尚未导入或重启" ;;
rollback)
    running && fail '请先停止核心再回退'
    [ -L "$DIR/previous" ] && [ -x "$DIR/previous/$EXE" ] || fail '没有上一版程序'
    check_config "$DIR/previous" "$CONF" || fail '当前配置不兼容上一版，未切换'
    cp -P "$DIR/previous" "$DIR/.current.new";mv -Tf "$DIR/.current.new" "$CURRENT";echo '已回退，未启动' ;;
*) fail '未知操作' ;;
esac
