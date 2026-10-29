#!/bin/sh
# 收集名称发布结果和当前 LAN 前缀；只写 RAM 快照，不操作网络和服务。
set -eu
umask 077
state=/tmp/adguardhome-rdns
lock=/tmp/adguardhome-hosts.lock
renderer=/usr/bin/adguardhome_rdns_snapshot.awk
[ -r "$renderer" ] || exit 1
[ "$(nvram get adg_enable)" = 1 ] || exit 0
[ ! -e /tmp/adguardhome-state/manual-stop ] || exit 0
[ ! -d /tmp/.adguardhome_service_lock ] || exit 0
set -- $(pidof AdGuardHome || :)
[ "$#" = 1 ] || exit 0
pid=$1
identity="$(cat /proc/sys/kernel/random/boot_id):$pid:$(awk '{print $22}' /proc/$pid/stat):$(stat -Lc '%d:%i' /proc/$pid/exe)"
mkdir -p "$state"
mkdir "$lock" 2>/dev/null || exit 0
echo $$ > "$lock/pid"
work="$state/collect.$$"
mkdir "$work" || { rm -f "$lock/pid"; rmdir "$lock"; exit 1; }
cleanup() { rm -f "$work/"*; rmdir "$work"; rm -f "$lock/pid"; rmdir "$lock"; }
trap cleanup 0
trap 'exit 1' 1 2 15
: > "$work/tracked"
if [ -f "$state/manifest" ] && [ "$(awk 'NR==1 {print $2}' "$state/manifest")" = "$identity" ]; then
    sed '1d' "$state/manifest" > "$work/tracked"
fi
# 只将自动发布文件当作动态地址来源；两个静态来源始终受保护。
cp /etc/storage/dnsmasq/hosts_ipv6 "$work/current"
awk '/^# BEGIN AdGuardHome LAN names$/ {inside=1;next} /^# END AdGuardHome LAN names$/ {inside=0;next} !inside {print} END {if(inside) exit 2}' /etc/hosts > "$work/static"
if [ -f /etc/storage/dnsmasq/hosts ]; then cat /etc/storage/dnsmasq/hosts >> "$work/static"; fi
ip -6 -o addr show dev br0 scope global > "$work/lan6"
awk -v enforce_lan6=1 -f "$renderer" mode=tracked "$work/tracked" mode=current "$work/current" mode=static "$work/static" mode=lan6 "$work/lan6" > "$work/rows"
# 进程已更换或地址集合变化时舍弃快照，下轮重新收集。
[ -r /proc/$pid/stat ] || exit 0
[ "$identity" = "$(cat /proc/sys/kernel/random/boot_id):$pid:$(awk '{print $22}' /proc/$pid/stat):$(stat -Lc '%d:%i' /proc/$pid/exe)" ] || exit 0
ip -6 -o addr show dev br0 scope global > "$work/lan6-after"
for file in lan6 lan6-after; do
    awk '{for(i=1;i<NF;i++) if($i=="inet6") print $(i+1)}' "$work/$file" | sort > "$work/$file.keys"
done
[ "$(sha256sum "$work/lan6.keys" | cut -d' ' -f1)" = "$(sha256sum "$work/lan6-after.keys" | cut -d' ' -f1)" ] || exit 0
{
    printf 'ADG_RDNS_V1 %s %s\n' "$identity" "$(cut -d. -f1 /proc/uptime)"
    LC_ALL=C sort -u "$work/rows"
} > "$work/manifest"
mv "$work/manifest" "$state/manifest"
