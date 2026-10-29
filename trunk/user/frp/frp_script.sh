#!/bin/sh
# 此文件仅作为首次启用的默认模板，不覆盖 /etc/storage 中已有的用户脚本。
# 新配置保存为 /etc/storage/frp/frpc.toml、frps.toml；旧自定义 INI 脚本仍可使用。
umask 077
mkdir -p /etc/storage/frp /tmp/frp || exit 1
failed=0
for name in frpc frps; do
    [ "$(nvram get "${name}_enable")" = 1 ] || continue
    config="/etc/storage/frp/$name.toml"
    if [ ! -s "$config" ]; then
        logger -t frp "请先填写 $config，参考 /etc_ro/$name.toml.example"
        failed=1; continue
    fi
    "$name" verify -c "$config" >/dev/null 2>&1 || {
        logger -t frp "$name 配置校验失败，保留正在运行的进程"
        failed=1; continue
    }
    pidof "$name" >/dev/null 2>&1 && continue
    "$name" -c "$config" >/dev/null 2>&1 &
done
sleep 1
exit "$failed"
