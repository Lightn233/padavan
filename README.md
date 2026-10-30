# RM2100 / Padavan 维护版

这是 Lightn233 正在维护的 Padavan 源码，主要在 Redmi RM2100 上验证。仓库保留多机型构建入口，使用 `make RM2100` 选择 RM2100，其他机型仍使用 `make <机型名称>`。

**2026-10-30 源码维护版已整合工具链、校园组件和旧插件入口迁移。** RM2100 的 U12 已完成启动、配置保留、有线双栈和两路 Wi-Fi 联网验证；可选组件的模拟、临时实机和真实服务商验收范围分别记录。这不是所有机型、账号和长期负载均已通过的保证。见 [U12 整合记录](docs/maintenance-2026-10-30-u12.md)、[测试状态](docs/validation.md) 和 [旧入口兼容说明](docs/legacy-entry-migration-20261030.md)。

## 主要维护内容

- 工具链：GCC 16.2.0、binutils 2.47、musl 1.2.6，保留源码摘要校验及源码构建入口。
- 内核：Linux 4.4.302 基线及已经移植、验证的 CIP 修复；不等同于原样采用某个完整 CIP 发布树。
- RM2100 的 MT7615 驱动、无线关闭与恢复、区域信道及 DFS 页面提示修复。
- 模式切换确认、取消和重启等待流程，以及 DHCP、UPnP、旧 IPv6 名称记录处理。
- 保留官方 AdGuardHome 程序及在线更新；增加可写目录运行、更新备份清理和名称记录维护。
- DDNS-Go、IPTV 和可选代理、远程组网、存储插件的升级适配；未使用的可选核心默认关闭。

## 在 Ubuntu 中构建

建议使用 Ubuntu 22.04 的 Linux 文件系统。源码包含符号链接及 Windows 保留文件名，不建议直接在 Windows 文件系统检出并编译。

安装宿主依赖：

```sh
sudo apt update
sudo apt install build-essential git python3 python3-docutils unzip zip xz-utils \
  libtool-bin curl cmake gperf gawk flex bison xxd fakeroot kmod cpio bc ccache \
  gettext automake autopoint texinfo help2man pkg-config zlib1g-dev \
  libgmp-dev libmpc-dev libmpfr-dev libncurses-dev libltdl-dev wget libc-dev-bin
```

获取源码并选择机型：

```sh
git clone https://github.com/Lightn233/padavan.git
cd padavan
make RM2100
```

先校验已有工具链；未安装时，Linux x86_64 默认从本仓库 Releases 下载固定摘要的预编译包并验证后安装。网络不便时可手动放入 `toolchain/downloads`。对应工具链源码输入、构建脚本和许可证也在同一仓库的 Release 中；需要从源码构建时执行 `make -C toolchain build SOURCE_JOBS=4`。详见 [工具链说明](toolchain/README.txt)，不需要另找作者的私人仓库。

配置入口：

- `trunk/configs/templates/RM2100.config`：RM2100 模板。
- `hello/common.override`：现有公共覆盖项。当前保留维护者选择，包括 CPU 超频配置；换机型或用于未改装设备前应检查这些选项。
- `scripts/apply_overrides.sh`：按机型应用覆盖项，保留原 `make <机型>` 方式。
- `toolchain/source-inputs.json`：工具链源码、补丁来源和摘要。

切换到另一机型前执行 `make clean`，再执行对应的 `make <机型名称>`。固件输出位于 `trunk/images/`。

选择需要源码编译的 Go 软件包时，还需安装符合对应包要求的 Go；本轮测试使用 Go 1.27.3。AdGuardHome 默认使用官方 MIPS little-endian softfloat 预编译包，保留程序包版本识别及校验，不能用任意改名的程序代替。

## 构建与验证边界

此源码保留的功能并不代表已在所有支持机型上实际运行。USB、硬盘和部分组网功能目前只有交叉编译或虚拟机结果。透明代理已有指定终端的 IPv4 REDIRECT/TPROXY 验收；IPv6 接管、实际服务商账号、硬件加速组合下大流量及长期稳定性仍需补验，不能从基础联网成功推断这些功能已全部通过。

GitHub Actions 只提供手动触发的构建入口，不会在源码上传时自动发布固件。新整理的云端构建流程尚需独立运行验收；本地构建记录与云端 CI 结果分别记录。

仓库不携带本地工具链安装目录、下载缓存、`build`、`romfs`、固件镜像、运行时账号或路由器配置备份。少量原有包明确依赖的预置库或源码归档继续随源码保留。

## 来源与许可

本项目在 [tsl0922/padavan](https://github.com/tsl0922/padavan) 及其上游 [hanwckf/rt-n56u](https://github.com/hanwckf/rt-n56u) 基础上维护，包含 Linux、厂商驱动及各软件包。保留各文件已有版权说明和许可证；整体源码中的许可说明见 [trunk/License](trunk/License)，各组件还需遵循其自己的许可文件。
