#!/bin/sh
# DDNS-Go 可选运行入口：程序与配置保存在 RWFS，不修改 DNS 或防火墙。
set -eu
umask 077
ROOT=${DDNSGO_ROOT:-}
case "$ROOT" in ''|/*) ;; *) echo '测试根目录必须为绝对路径' >&2; exit 2;; esac
RWFS=$ROOT/media/mtd_rwfs
BASE=$RWFS/ddns-go
BIN=$BASE/ddns-go
CONF=$BASE/ddns_go_config.yaml
RUN=$ROOT/var/run/ddns-go
PIDFILE=$RUN/pid
VERSION=6.17.7
ARCHIVE_HASH=f7afd1a3cfd54c3667db74cc80491bfe48e1ba4ffa08a992366d0229c72f1f85
BINARY_HASH=732367ed8a956038fd92c423e9208afa7285e91b561b0997132b8bd331acc0fc
STAGE=
DOWNLOAD=

fail() { echo "$*" >&2; exit 1; }
run_binary() {
    if [ -n "${DDNSGO_RUNNER:-}" ]; then "$DDNSGO_RUNNER" "$@"; else "$@"; fi
}
cleanup() {
    [ -z "$DOWNLOAD" ] || rm -f "$DOWNLOAD"
    if [ -n "$STAGE" ]; then
        # 仅清理本次在固定数据目录创建的暂存目录。
        case "$STAGE" in "$BASE"/.install.*) rm -rf "$STAGE";; esac
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
[ ! -L "$RUN" ] || fail '运行目录不能是符号链接'
mkdir -p "$RUN"
chmod 700 "$RUN"
exec 9>"$RUN/lock"
flock -n 9 || fail '已有 DDNS-Go 操作正在执行，请稍后重试'

storage_ready() {
    [ ! -L "$RWFS" ] && [ ! -L "$BASE" ] || fail '数据路径不能是符号链接'
    awk -v target="$RWFS" '$2 == target && $4 ~ /(^|,)rw(,|$)/ && $3 != "tmpfs" {found=1} END {exit !found}' /proc/mounts || fail 'RWFS 尚未挂载为可写持久存储'
    mkdir -p "$BASE"
    chmod 700 "$BASE"
    [ ! -L "$CONF" ] && [ ! -L "$BIN" ] || fail '程序或配置不能是符号链接'
}
is_running() {
    [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] || return 1
    read -r proc_id proc_start < "$PIDFILE" || return 1
    case "$proc_id:$proc_start" in *[!0-9:]*|:*|*:) return 1;; esac
    [ "$proc_id" -gt 1 ] || return 1
    [ -r "/proc/$proc_id/stat" ] && [ -r "/proc/$proc_id/cmdline" ] || return 1
    [ "$(awk '{print $22}' "/proc/$proc_id/stat")" = "$proc_start" ] || return 1
    tr '\000' '\n' < "/proc/$proc_id/cmdline" | grep -F -x "$BIN" >/dev/null || return 1
    tr '\000' '\n' < "/proc/$proc_id/cmdline" | grep -F -x "$CONF" >/dev/null || return 1
    kill -0 "$proc_id" 2>/dev/null
}
stop_service() {
    if is_running; then
        kill -TERM "$proc_id"
        attempts=0
        while is_running && [ "$attempts" -lt 5 ]; do
            sleep 1
            attempts=$((attempts + 1))
        done
        if is_running; then kill -KILL "$proc_id"; fi
    fi
    rm -f "$PIDFILE"
}
start_service() (
    if is_running; then return 0; fi
    [ "$(nvram get ddns_enable_x)" = 1 ] || return 0
    [ "$(nvram get ddns_engine)" = ddns-go ] || return 0
    [ "$(nvram get sw_mode)" != 3 ] || return 0
    storage_ready
    [ -x "$BIN" ] || fail 'DDNS-Go 尚未安装，请先安装可选程序包'
    lan=$(nvram get lan_ipaddr)
    printf '%s\n' "$lan" | awk -F. 'NF != 4 {exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || length($i)>3 || $i>255) exit 1; if($1==0 || $1>=224) exit 1}' || fail 'LAN 地址无效'
    port=$(nvram get ddns_go_port)
    [ -n "$port" ] || port=9876
    case "$port" in *[!0-9]*|'') fail '管理端口无效';; esac
    [ "${#port}" -le 5 ] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || fail '管理端口应为 1024 至 65535'
    if [ ! -f "$CONF" ]; then
        printf 'dnsconf: []\nnotallowwanaccess: true\nlang: zh\n' > "$BASE/.config.new"
        mv "$BASE/.config.new" "$CONF"
    fi
    chmod 600 "$CONF"
    # 后台进程关闭锁描述符；不把持续运行日志写入有限的 /tmp。
    if [ -n "${DDNSGO_RUNNER:-}" ]; then
        "$DDNSGO_RUNNER" "$BIN" -c "$CONF" -l "$lan:$port" -f 300 </dev/null >/dev/null 2>&1 9>&- &
    else
        "$BIN" -c "$CONF" -l "$lan:$port" -f 300 </dev/null >/dev/null 2>&1 9>&- &
    fi
    child=$!
    sleep 1
    [ -r "/proc/$child/stat" ] || fail 'DDNS-Go 启动失败'
    printf '%s %s\n' "$child" "$(awk '{print $22}' "/proc/$child/stat")" > "$RUN/pid.new"
    mv "$RUN/pid.new" "$PIDFILE"
    attempts=0
    while [ "$attempts" -lt 5 ]; do
        if is_running && curl --noproxy '*' -fsS --connect-timeout 1 --max-time 1 "http://$lan:$port/login" -o /dev/null 2>/dev/null; then
            echo 'DDNS-Go 已启动，管理页面仅绑定 LAN 地址'
            return 0
        fi
        attempts=$((attempts + 1)); sleep 1
    done
    stop_service
    echo 'DDNS-Go 管理页面启动检查失败' >&2
    return 1
)
# 同一主程序可供新页面和旧 AliDDNS 入口使用；只暂停正在运行的兼容实例。
compat_pause() {
    ali_was_running=0
    if [ -x "$ROOT/usr/bin/aliddns.sh" ] && [ "$(LEGACY_COMPAT_ROOT="$ROOT" "$ROOT/usr/bin/aliddns.sh" status 2>/dev/null)" = running ]; then
        LEGACY_COMPAT_ROOT="$ROOT" "$ROOT/usr/bin/aliddns.sh" stop || return 1
        ali_was_running=1
    fi
}
compat_resume() {
    [ "${ali_was_running:-0}" != 1 ] || LEGACY_COMPAT_ROOT="$ROOT" "$ROOT/usr/bin/aliddns.sh" start
}
install_package() {
    storage_ready
    available=$(df -Pk "$BASE" | awk 'END {print $4}')
    [ "$available" -ge 14336 ] || fail 'RWFS 空间不足，至少需要 14 MiB 空闲空间暂存程序'
    archive=${1:-}
    if [ -z "$archive" ]; then
        mkdir -p "$ROOT/tmp"
        DOWNLOAD=$(mktemp "$ROOT/tmp/ddns-go-download.XXXXXX")
        # 官方同版本源码以新版 Go 重编，修正 MIPS TLS 运行时对齐问题。
        url=https://github.com/Lightn233/padavan/releases/download/legacy-compat-20261030/ddns-go_6.17.7_linux_mipsle_softfloat_padavan-go1.27.3.tar.gz
        curl --noproxy '*' --proto '=https' --tlsv1.2 -fL --connect-timeout 12 --max-time 180 --max-filesize 6000000 "$url" -o "$DOWNLOAD" || fail '兼容包下载失败，可使用 install 加本地程序包路径'
        archive=$DOWNLOAD
    fi
    [ -f "$archive" ] || fail '程序包不存在'
    actual=$(sha256sum "$archive" | awk '{print $1}')
    [ "$actual" = "$ARCHIVE_HASH" ] || fail '程序包校验失败，已保留原程序'
    STAGE=$(mktemp -d "$BASE/.install.XXXXXX")
    tar -xzf "$archive" -C "$STAGE" ddns-go LICENSE
    [ -f "$STAGE/ddns-go" ] && [ ! -L "$STAGE/ddns-go" ] || fail '程序包内容无效'
    [ "$(sha256sum "$STAGE/ddns-go" | awk '{print $1}')" = "$BINARY_HASH" ] || fail '主程序校验失败'
    chmod 755 "$STAGE/ddns-go"
    [ "$(run_binary "$STAGE/ddns-go" -v)" = "v$VERSION" ] || fail '兼容程序版本或目标架构不匹配'
    if [ -f "$BIN" ]; then
        [ ! -e "$CONF" ] || cp -p "$CONF" "$BASE/config.previous"
        sha256sum "$BIN" | awk '{print $1}' > "$BASE/previous.sha256"
    fi
    compat_pause || fail '旧 AliDDNS 实例未能停止，未替换程序'
    was_running=0
    if is_running; then was_running=1; stop_service; fi
    if [ -f "$BIN" ]; then
        mv -f "$BIN" "$BASE/ddns-go.previous"
    fi
    mv "$STAGE/ddns-go" "$BIN"
    mv "$STAGE/LICENSE" "$BASE/LICENSE"
    if ! { { [ "$was_running" != 1 ] || start_service; } && compat_resume; }; then
        stop_service
        if [ "$ali_was_running" = 1 ]; then LEGACY_COMPAT_ROOT="$ROOT" "$ROOT/usr/bin/aliddns.sh" stop || true; fi
        if [ -f "$BASE/ddns-go.previous" ]; then
            mv -f "$BASE/ddns-go.previous" "$BIN"
            [ ! -f "$BASE/config.previous" ] || cp -p "$BASE/config.previous" "$CONF"
            [ "$was_running" != 1 ] || start_service || true
            compat_resume || true
        fi
        fail '新程序启动失败，已尝试恢复上一版'
    fi
    echo "DDNS-Go v$VERSION 兼容构建安装完成，原 DDNS 账号和开关保持不变"
}
rollback_package() {
    storage_ready
    previous=$BASE/ddns-go.previous
    [ -f "$previous" ] && [ ! -L "$previous" ] && [ -f "$BASE/previous.sha256" ] || fail '没有可用回退程序'
    [ "$(sha256sum "$previous" | awk '{print $1}')" = "$(cat "$BASE/previous.sha256")" ] || fail '回退程序校验失败'
    run_binary "$previous" -v >/dev/null || fail '回退程序不能执行'
    STAGE=$(mktemp -d "$BASE/.install.XXXXXX")
    [ ! -f "$CONF" ] || cp -p "$CONF" "$STAGE/config.current"
    compat_pause || fail '旧 AliDDNS 实例未能停止，未替换程序'
    was_running=0
    if is_running; then was_running=1; stop_service; fi
    mv "$BIN" "$STAGE/current"
    mv -f "$previous" "$BIN"
    [ ! -f "$BASE/config.previous" ] || cp -p "$BASE/config.previous" "$CONF"
    if ! { { [ "$was_running" != 1 ] || start_service; } && compat_resume; }; then
        stop_service
        if [ "$ali_was_running" = 1 ]; then LEGACY_COMPAT_ROOT="$ROOT" "$ROOT/usr/bin/aliddns.sh" stop || true; fi
        mv -f "$BIN" "$previous"
        mv "$STAGE/current" "$BIN"
        [ ! -f "$STAGE/config.current" ] || cp -p "$STAGE/config.current" "$CONF"
        [ "$was_running" != 1 ] || start_service || true
        compat_resume || true
        fail '回退版本启动失败，已尝试恢复当前版本'
    fi
    rm -f "$BASE/previous.sha256"
    echo 'DDNS-Go 已恢复上一版'
}
case "${1:-status}" in
    start) start_service;;
    stop) stop_service;;
    restart) stop_service; start_service;;
    install) install_package "${2:-}";;
    rollback) rollback_package;;
    web-install|web-rollback)
        printf 'working\n' > "$RUN/operation"
        if (trap cleanup EXIT; if [ "$1" = web-install ]; then install_package; else rollback_package; fi) > "$RUN/operation.log" 2>&1; then
            printf 'success\n' > "$RUN/operation"
        else
            printf 'failed\n' > "$RUN/operation"
            exit 1
        fi;;
    status)
        if is_running; then echo running
        elif [ -x "$BIN" ]; then echo stopped
        else echo absent; fi;;
    *) echo '用法：ddns-go.sh start|stop|restart|status|install [兼容程序包路径]|rollback' >&2; exit 2;;
esac
