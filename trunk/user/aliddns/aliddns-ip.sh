#!/bin/sh
# 延用用户的取 IP 脚本，外层超时由 DDNS-Go 配置统一限制。
ROOT=${LEGACY_COMPAT_ROOT:-}
case "${1:-}" in 4) IPv6=0;; 6) IPv6=1;; *) exit 2;; esac
export IPv6
arIpAddress=
if [ -f "$ROOT/etc/storage/ddns_script.sh" ]; then
    # 脚本自己的提示不混入地址输出；只取约定的 arIpAddress 变量。
    . "$ROOT/etc/storage/ddns_script.sh" >/dev/null || exit 1
    [ -n "$arIpAddress" ] || exit 1
    printf '%s\n' "$arIpAddress" | awk 'NF {print $1;exit}'
elif [ "$IPv6" = 1 ]; then
    ip -6 -o addr show dev "$(nvram get wan0_ifname_t)" scope global | awk '!/deprecated|tentative/ {split($4,a,"/"); print a[1];exit}'
else
    curl --noproxy '*' --proto '=https' -4 -fsS --connect-timeout 4 --max-time 8 https://api.ipify.org
fi
