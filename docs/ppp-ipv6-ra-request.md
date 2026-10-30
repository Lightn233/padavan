# PPP IPv6 WAN 地址等待：候选修复

某些重拨时序下，IPv6CP 已建立 PPP 链路本地地址，RC 回调稍后才开启 `accept_ra=2`。Linux 4.4 的 DAD 完成路径不会因为之后改变 `accept_ra` 而重新发送最初的路由请求。此时 DHCPv6-PD 可以成功，WAN SLAAC 地址仍要等待上游周期 RA。实际现场手动补发 RS 后，上游立即返回 RA。

本修复只在原生动态 IPv6、允许 SLAAC 且接口名符合 `ppp<数字>` 时补发一个 RS。不改变 DHCPv6、RA 接收策略、DNS、NAT、IPv4 或用户配置；不删除或重建已有地址。发包失败只记录错误，继续原有 DHCPv6 流程。

实现位于 `trunk/user/rc/src/wan6_solicit.h`，由 `net_wan6.c` 的 `wan6_up()` 调用。使用绑定接口的 ICMPv6 raw socket，目标 `ff02::2`，Hop Limit 255，校验和由内核生成，不带不适用于 PPP 的源链路层选项。

验证范围：

- 原生和 MIPS 构建通过，MIPS RC 编译无警告。
- 8 个非法接口名检查在宿主及 MIPS/QEMU 中通过。
- 隔离 veth 模拟了链路本地地址先存在、内核不再发 RS 的条件；抓到格式正确的 8 字节 RS，模拟上游返回 RA，约 1.2 秒得到示例全局地址。
- **尚未将此自动调用写入当前运行固件，仍需真实 PPP 重拨验证。** veth 模拟不等同于 PPP 驱动全栈验证；单次 RS 丢包后仍依赖后续上游 RA，不宣称覆盖所有运营商问题。

无需 root 的回归：

```sh
cc -std=gnu17 -Wall -Wextra -Werror -I trunk/user/rc/src \
  tests/network/wan6-rs.c -o /tmp/padavan-wan6-rs-test
/tmp/padavan-wan6-rs-test
```

带接口名参数会实际发送 RS，须在已批准的隔离测试或设备验证中使用，不能把无参数单元测试和发包验证混为一项。
