# 旧插件入口兼容迁移（2026-10-30）

保留已有页面、节点、NVRAM 字段和机型选择。迁移使用独立配置和进程；没有修改默认 RM2100 配置、AdGuardHome、DNS 接管规则或现网参数。

| 旧入口 | 本批行为 | 保留的兼容路径 |
| --- | --- | --- |
| Trojan 节点 | 证书验证设置可等价转换且已安装 Xray 时，使用 Xray 的 Trojan 出站 | 特殊旧证书选项或未安装 Xray 时，继续使用独立 Trojan；无法满足条件时先报错，保留正在运行的服务 |
| simple-obfs | `simple-obfs` / `obfs-local` 节点别名统一到 `obfs-local`，保留 HTTP/TLS 旧协议 | 固定源码和 libcork 子模块；没有改成不兼容的新协议 |
| dns-forwarder | 由独立 SmartDNS 实例接收 UDP/TCP 查询，并使用 TCP 上游 | 保留旧监听地址、端口和上游字段；不共用或覆盖主 SmartDNS 配置 |
| AliDDNS | 安装兼容 DDNS-Go 核心后，将旧账号、域名、TTL 和取 IP 脚本转换到独立实例 | 未安装核心、明确选择旧后端或遇到已知不适配的旧核心时，保留原更新器 |

## AliDDNS 使用和程序包来源

旧 AliDDNS 配置继续有效，不要求手工导出密钥。兼容实例的配置在 `/var/run/legacy-aliddns`，每次从原字段生成，权限为 600。新 DDNS-Go 页面仍使用 RWFS 中自己的配置，两者互不覆盖。

可通过已有 DDNS-Go 安装入口安装兼容包，也可使用 `ddns-go.sh install /路径/程序包.tar.gz`。不启用服务、不清空账号；已运行的新旧实例更新时会分别暂停和恢复。仅保留一份核心回退包。

DDNS-Go 版本仍为 6.17.7，源码固定到官方提交 `7aad574de4ba1e4646f07648a38235d34bab6648`。本项目使用 Go 1.27.3 重编 linux/mipsle/softfloat，**不是官方发布的预编译二进制**。官方旧预编译包在本次 MIPS/QEMU 的正常 TLS 握手中出现未对齐访问；同源重编通过了对照。不能把模拟器结果写成已在所有路由器上确认的故障。

可复现构建入口：

```sh
make -C trunk/user/ddns-go ROOTDIR="$PWD/trunk" compat-package
```

需要 Python 3、Go 及网络可用的模块缓存。工具会固定源码 SHA-256、编译器版本、目标架构与归档元数据。可以通过 `GOCACHE`、`GOMODCACHE` 复用已有缓存。主程序保存在 RWFS，普通固件构建只内置管理入口。

官方 AdGuardHome 及其在线更新能力未改变。

## 本批修复和构建调整

- simple-obfs 的 TLS 长度和随机填充原来使用未对齐整数访问，正常 MIPS 传输会出现 SIGBUS；改为字节写入或 `memcpy`，保持协议内容。
- simple-obfs 与 libcork 均固定提交、下载包及 SHA-256，补齐单独启用 SSOBFS 时的 libev 依赖。
- Trojan 的旧 TCP、UDP、SOCKS 配置分别生成；所有节点先验证，再替换运行服务，停止操作只处理本入口拥有的进程。
- DNS 转发拒绝占用 53/5335，识别指向本机 DNS 的明显循环，端口冲突时恢复原配置和进程；不新增解析缓存或测速策略。
- AliDDNS 和 DNS 转发共用小型配置转换器及生命周期函数；明确进程 PID、启动时间、程序和配置路径。
- 旧 AliDDNS 后备查询保留 HTTPDNS 行为，等待时间有上限，不再全局结束 `nslookup`。

## 已通过的验证

| 层次 | 实际范围 |
| --- | --- |
| 宿主及 MIPS 配置回归 | 21 项转换检查分别在 ASan/UBSan 和 MIPS/QEMU 通过，另有可随源码运行的同一套测试 |
| Trojan | 27 项配置及本地真实 TCP/UDP 联调；Xray 原入口和 Trojan 兼容入口各 17 项生命周期检查 |
| simple-obfs | 修正版 MIPS 与未修改的原生版本双向配对，HTTP/TLS、不同大小和分段数据共 12 项通过 |
| DNS/DDNS 旧入口 | 实际 MIPS SmartDNS 的 UDP/TCP A/AAAA 查询、失败恢复及旧字段共 19 项检查 |
| DDNS-Go 安装 | 实际兼容核心的安装、重装、回退、失败恢复及配置保留共 14 项检查 |
| 阿里云 API 模拟 | 真实 MIPS DDNS-Go 对本地 HTTPS 模拟 API，验证请求签名、A/AAAA、根域名/二级域名/通配记录、TTL；加上新旧入口同时运行的更新/恢复，共 16 项 |
| 构建集成 | 五个组件的编译安装、五组依赖选择、已安装脚本的宿主与 MIPS BusyBox ash 语法检查 |

使用公开同仓库工具链 GCC 16.2.0 / binutils 2.47 / musl 1.2.6。测试使用独立目录和隔离网络，未重新复制或下载整个固件源码树。

## U12 整合与实机补验

完整构建已通过，U12 已在 RM2100 启动并保留用户配置，双栈 DNS/HTTPS、基础 UPnP 和用户反馈的两路 Wi-Fi 联网均通过。大型可选核心继续关闭；不能把 U12 启动成功当作所有可选协议都已实机通过。

旧 DNS/DDNS 入口在 U12 的独立临时目录和回环端口另做 21 项检查，涵盖真实 MIPS SmartDNS 的 UDP/TCP A/AAAA、重复启动、DNS 循环配置拒绝、端口冲突恢复、停止、旧 DDNS 字段导出和取 IP 脚本。使用虚构 NVRAM 与本地上游，没有改变真实 DNS 或账号。

这次实机检查发现目标 BusyBox 未包含 `cmp`，导致重复启动不必要地重启进程；现已改用固件已有的 SHA-256 比较配置，读取失败不视为相同。补充缺少 `cmp` 的 Ubuntu 回归 19 项、U12 回环 21 项及 DDNS-Go HTTPS 模拟器回归。此助手只由 AliDDNS / dns-forwarder 构建选项安装，U12 日常配置没有内置它；修正已在临时组件中验证并合入源码，不需要为了未启用的入口再刷一次同配置固件。

## 验收边界

没有真实阿里云账号、第三方代理服务、其他路由器机型或长期稳定性验收。AliDDNS 在实机验证了旧字段和启动分支，真实 DDNS-Go 的 HTTPS 签名、记录操作及更新恢复在隔离模拟 API 验证；这两类结果不混写。原有回退固件及当前配置保留。MentoHUST 的实际内核收发补验见校园组件文档。
