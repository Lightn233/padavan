#!/bin/sh
# 兼容入口只管理自己的进程、候选配置与锁，不使用 killall。
compat_fail() { echo "$*" >&2; return 1; }
compat_init() {
    ROOT=${LEGACY_COMPAT_ROOT:-}
    case "$ROOT" in ''|/*) ;; *) return 1;; esac
    RUN=$ROOT/var/run/legacy-$1
    [ ! -L "$RUN" ] || return 1
    umask 077
    mkdir -p "$RUN" || return 1
    chmod 700 "$RUN" || return 1
    CONF=$RUN/config
    PIDFILE=$RUN/pid
    exec 9>"$RUN/lock"
    flock -n 9 || { compat_fail '已有同一服务操作正在执行'; return 1; }
}
compat_running() {
    [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] || return 1
    read -r proc_id proc_start < "$PIDFILE" || return 1
    case "$proc_id:$proc_start" in *[!0-9:]*|:*|*:) return 1;; esac
    [ "$proc_id" -gt 1 ] && [ -r "/proc/$proc_id/stat" ] || return 1
    [ "$(awk '{print $22}' "/proc/$proc_id/stat")" = "$proc_start" ] || return 1
    tr '\000' '\n' < "/proc/$proc_id/cmdline" | grep -Fqx "$CONF" || return 1
    tr '\000' '\n' < "/proc/$proc_id/cmdline" | grep -Fqx "$BIN" || return 1
    kill -0 "$proc_id" 2>/dev/null
}
compat_legacy_pids() {
    local entry pid
    for entry in /proc/[0-9]*/cmdline; do
        [ -r "$entry" ] || continue
        pid=${entry#/proc/}; pid=${pid%/cmdline}
        [ "$pid" != "$$" ] || continue
        tr '\000' '\n' < "$entry" 2>/dev/null | grep -Fqx "$ROOT/usr/bin/aliddns-legacy.sh" && printf '%s\n' "$pid"
    done
}
compat_stop_legacy() {
    local pid n=0
    for pid in $(compat_legacy_pids); do kill -TERM "$pid" 2>/dev/null; done
    while [ "$n" -lt 20 ] && [ -n "$(compat_legacy_pids)" ]; do usleep 100000; n=$((n+1)); done
    for pid in $(compat_legacy_pids); do kill -KILL "$pid" 2>/dev/null; done
    return 0
}
compat_stop() {
    if compat_running; then
        kill -TERM "$proc_id" 2>/dev/null
        local n=0
        while [ "$n" -lt 30 ] && compat_running; do usleep 100000; n=$((n+1)); done
        if compat_running; then kill -KILL "$proc_id" 2>/dev/null; fi
    fi
    rm -f "$PIDFILE"
}
compat_launch() {
    local output=/dev/null
    [ -z "${LEGACY_COMPAT_ROOT:-}" ] || output=$RUN/test.log
    if [ -n "${LEGACY_COMPAT_RUNNER:-}" ]; then
        "$LEGACY_COMPAT_RUNNER" "$@" </dev/null >"$output" 2>&1 9>&- &
    else
        "$@" </dev/null >"$output" 2>&1 9>&- &
    fi
    local child=$!
    [ -r "/proc/$child/stat" ] || return 1
    printf '%s %s\n' "$child" "$(awk '{print $22}' "/proc/$child/stat")" > "$PIDFILE"
    sleep 1
    compat_running && compat_ready
}
compat_ready() { return 0; }
# 精简 BusyBox 不一定包含 cmp；使用固件已有的 SHA-256，读取失败不能视为相同。
compat_same_file() {
    local first second
    first=$(sha256sum "$1") || return 1
    second=$(sha256sum "$2") || return 1
    [ "${first%% *}" = "${second%% *}" ]
}
compat_apply() {
    local candidate="$1"; shift
    if compat_running && compat_same_file "$candidate" "$CONF" && [ "${COMPAT_FORCE:-0}" != 1 ]; then
        rm -f "$candidate"; return 0
    fi
    local restore=0
    if compat_running; then restore=1; fi
    [ ! -f "$CONF" ] || cp -p "$CONF" "$RUN/previous"
    compat_stop
    mv -f "$candidate" "$CONF" || return 1
    chmod 600 "$CONF"
    if compat_launch "$@"; then return 0; fi
    compat_stop
    if [ -f "$RUN/previous" ]; then
        mv -f "$RUN/previous" "$CONF"
        if [ "$restore" = 1 ]; then compat_launch "$@" || true; fi
    fi
    compat_fail '新进程启动失败，已保留或恢复上一份配置'
}
