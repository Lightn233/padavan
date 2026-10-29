# RM2100 / Padavan 维护版

这是 Lightn233 正在维护的 Padavan 源码，主要在 Redmi RM2100 上验证。仓库保留多机型构建入口，使用 `make RM2100` 选择 RM2100，其他机型仍使用 `make <机型名称>`。

**当前是开发源码，不是所有机型、插件都已验收的稳定发行版。** 这次上传整合了截至 2026-10-29 的源码工作树。RM2100 日常运行基线为 U9，U10 可选插件适配也保留在源码中；验证边界见 [测试状态](docs/validation.md)。

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

首次没有已验证工具链或离线包时，会从固定版本源码构建工具链。此步骤需要下载和额外磁盘空间；不会把本维护者电脑上的绝对路径写入你的安装位置。后续构建复用校验通过的工具链。

配置入口：

- `trunk/configs/templates/RM2100.config`：RM2100 模板。
- `hello/common.override`：现有公共覆盖项。当前保留维护者选择，包括 CPU 超频配置；换机型或用于未改装设备前应检查这些选项。
- `scripts/apply_overrides.sh`：按机型应用覆盖项，保留原 `make <机型>` 方式。
- `toolchain/source-inputs.json`：工具链源码、补丁来源和摘要。

切换到另一机型前执行 `make clean`，再执行对应的 `make <机型名称>`。固件输出位于 `trunk/images/`。

选择需要源码编译的 Go 软件包时，还需安装符合对应包要求的 Go；本轮测试使用 Go 1.27.3。AdGuardHome 默认使用官方 MIPS little-endian softfloat 预编译包，保留程序包版本识别及校验，不能用任意改名的程序代替。

## 构建与验证边界

此源码保留的功能并不代表已在所有支持机型上实际运行。USB、硬盘和部分组网功能目前只有交叉编译或虚拟机结果。透明代理整网接管、部分真实账号接入及长期稳定性仍需补验，不能从基础联网成功推断这些功能已全部通过。

GitHub Actions 只提供手动触发的构建入口，不会在源码上传时自动发布固件。新整理的云端构建流程尚需独立运行验收；本地构建记录与云端 CI 结果分别记录。

仓库不携带本地工具链安装目录、下载缓存、`build`、`romfs`、固件镜像、运行时账号或路由器配置备份。少量原有包明确依赖的预置库或源码归档继续随源码保留。

## 来源与许可

本项目在 [tsl0922/padavan](https://github.com/tsl0922/padavan) 及其上游 [hanwckf/rt-n56u](https://github.com/hanwckf/rt-n56u) 基础上维护，包含 Linux、厂商驱动及各软件包。保留各文件已有版权说明和许可证；整体源码中的许可说明见 [trunk/License](trunk/License)，各组件还需遵循其自己的许可文件。
