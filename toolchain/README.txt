Padavan 工具链（与固件源码同一 GitHub 项目）

固定版本：GCC 16.2.0、binutils 2.47、musl 1.2.6，MIPS 小端 o32 / MIPS32r2 / hard-float。
musl 补丁及 sys/queue.h 的来源摘要见 source-inputs.json。

普通固件编译仍在仓库根目录执行：
    make RM2100
其他机型继续使用 make 对应机型名称，不改变产品配置选择。

工具链入口先检查已有安装；没有安装时，Linux x86_64 默认从
Lightn233/padavan 自己的 Releases 取得固定 SHA256 的预编译包。
校验后先在临时目录验证编译与 ABI，再原子安装。校验失败不覆盖旧目录。
网络不可用时，可把同一 Release 的预编译包手动放入 toolchain/downloads。
不要把不同版本的包改成旧文件名规避校验。

不使用预编译包、直接从固定来源编译：
    make -C toolchain build SOURCE_JOBS=4
只准备并校验源码输入：
    make -C toolchain prepare
Release 同时提供 toolchain-source-inputs-20261030.tar，包含对应上游源码包、
本项目构建脚本、补丁和许可证；解包到仓库根目录后可使用 SOURCE_OFFLINE=1。
所需 Linux 内核头来自本仓库 trunk/linux-4.4.x，不要求另一份私人源码目录。

如果已存在不同工具链，入口会停止并保留它。需要切换时可使用独立 CT_PREFIX，
或明确执行 make -C toolchain build SOURCE_REPLACE=1；后者先把旧安装改名备份，再建立新入口。
不要直接删除当前正在使用的工具链。

宿主依赖仍需按项目说明安装。预编译包面向 Ubuntu 22.04 x86_64 或兼容系统；
其他宿主应走源码构建。QEMU 可选：安装 qemu-user 后会增加目标程序运行检查。

发布前检查包含：换目录安装、隐藏原构建/安装路径、C 的 o32/time64/off64/线程、
C++ 动态与静态链接的异常和线程。以上不能代替固件完整构建或路由器实机验收。

源码与工具链均归属同一仓库；大体积二进制和对应源码输入使用该仓库 Releases，
避免把生成物反复写入 Git 历史。上游作者版权与许可证继续保留。
