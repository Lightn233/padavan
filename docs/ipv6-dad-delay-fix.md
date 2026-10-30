# IPv6 DAD 初始化延时单位修复

厂商代码为 `eth3` 和 `br0` 设置了 `delay = 6000`，注释表达的是毫秒。但该参数传入延迟任务接口时以 jiffies 为单位；本配置 `CONFIG_HZ=100`，实际等待为 60 秒。

本次改为 `msecs_to_jiffies(6000)`，保留原来 6 秒的设计意图、DAD 地址冲突检测及其他接口行为。未修改 IPv6、PD、RA、DHCPv6、DNS 或无线设置，也没有升级工具链、库和应用程序版本。

## 回归测试

在源码根目录执行：

```sh
python3 tests/kernel/test_ipv6_dad_delay.py --source . --output /tmp/dad-native.json
```

已有 MIPS 工具链和 qemu-mipsel 时，补充目标架构测试：

```sh
python3 tests/kernel/test_ipv6_dad_delay.py --source . --mips-cc ./toolchain/toolchain-mipsel/bin/mipsel-linux-musl-gcc --output /tmp/dad-mips.json
```

测试直接提取实际调度函数，以模拟计时器核对 `br0`、`eth3` 和其他接口在 HZ=100/250/1000 的行为。原始代码在 HZ=100 下两项预期失败，修正后共 20 项原生/MIPS 检查通过。这属于函数级验证，不表示完整内核在 QEMU 启动。

## 构建与 RM2100 实测

完成 `make clean` 后通过现有 `make RM2100` 入口构建。实际固件中的函数已核验为 600 个节拍，内核配置与修复前一致。包内 MIPS 依赖、现有程序运行和 AdGuardHome 官方程序来源均通过核对。

本次个人日常版使用 U9 插件选择，仍沿用当前已验证组件；这不是回刷带旧错误的历史 U9 镜像。公开仓库的 CPU、内存默认值和其他机型选择方式保持不变。

RM2100 首次启动和一次普通重启通过。绑定有线接口检查 IPv4/IPv6、53/5335、UDP/TCP 共 8 项 DNS；同条件普通重启首次全部成功时间从 117.58 秒缩短至 75.89 秒，提前约 42 秒。实际机内正常运行后双栈 HTTPS、SSDP/UPnP 查询通过，配置和官方 AdGuardHome 程序保持一致。

首次成功时间包含服务启动、网络配置和探测采样等过程，不能称为整机 6 秒启动。启动早期仍有短暂未通过的探测记录。两路无线接口及 DFS 完成已检查。无线终端补验：用户在本次 U9D1 刷写及重启后确认，ASUS（2.4 GHz）和 ASUS_5G（5 GHz）两路均能正常上网。 长期稳定性仍需观察，不据此宣称所有机型或插件已经实机验收。
