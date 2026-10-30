# 校园网组件回归测试

这些测试直接调用应用项目补丁后的真实 C 函数，并检查启动脚本生成的参数和配置。测试使用虚构账户和临时目录，不需要校园网账户，不操作路由器 NVRAM 或真实认证服务。

## 输入

先按照 `trunk/user/<组件>/Makefile` 中固定的版本和 SHA-256 准备源码并应用 `patches/`，或者使用项目构建生成的对应 `trunk/build/` 目录。不能把未经补丁的上游源码当作修复版本。

需要 Python 3、GCC、ASan/UBSan；MIPS 测试另需本项目工具链和 `qemu-mipsel`。五个源码路径分别用 `MINIEAP_SRC`、`GDUT_SRC`、`MENTOHUST_SRC`、`DOGCOM_SRC`、`SCUT_SRC` 表示。

```sh
python3 tests/campus/run_unit_tests.py \
  --minieap "$MINIEAP_SRC" --gdut-drcom "$GDUT_SRC" \
  --mentohust "$MENTOHUST_SRC" --dogcom "$DOGCOM_SRC" \
  --scutclient "$SCUT_SRC" --out /tmp/campus-native-results

python3 tests/campus/run_unit_tests.py \
  --minieap "$MINIEAP_SRC" --gdut-drcom "$GDUT_SRC" \
  --mentohust "$MENTOHUST_SRC" --dogcom "$DOGCOM_SRC" \
  --scutclient "$SCUT_SRC" --out /tmp/campus-mips-results \
  --mips --cc "$TOOLCHAIN/bin/mipsel-linux-musl-gcc" \
  --runner 'qemu-mipsel -cpu 24Kf'

python3 tests/campus/test_launchers.py \
  --source-root "$PWD" --out /tmp/campus-launcher-results
```

MIPS 单元测试使用静态链接；启动脚本测试可通过 `--shell` 指定提取出的固件 BusyBox ash 及 QEMU 命令。输出目录保存构建日志、每项结果和 `results.json`，任何失败均返回非零状态。

## 覆盖范围

- 71 项 C 函数测试：配置读取、长度边界、未对齐访问、分配失败、报文校验、消息输出、账户输入和密码长度组合。
- 15 项启动入口测试：密码字符保留、单行配置检查、原配置保留、文件权限、可选参数、启动失败状态、互斥及退出后的锁清理。
- 本机 C 测试启用 ASan/UBSan；MIPS 使用项目目标架构执行相同函数测试。

这些测试不能替代真实校园认证服务器、物理网卡、长时间运行和不同机型的验收。完整协议联调的阶段结果及未通过项目见 `docs/campus-validation-20261030.md`。

## 正常协议 TAP 检查器

`mentohust_tap_check.c` 用于补测 MentoHUST 的正常 libpcap 收发，创建不持久化的 `u12mento` TAP，不连接物理接口或 br0。它只发送正常身份、MD5、成功心跳与重新认证报文；退出时删除临时接口并停止自己的子进程。配置和 PID 写入通过私有挂载命名空间隔离。

在独立临时目录准备 `bin_mentohust`、其同架构依赖目录 `lib/`、`etc/storage/mentohust.conf` 和空 `run/`。测试配置使用虚构账户 `lab-user` / `lab-password`、接口 `u12mento`、关闭 DHCP 和后台运行。编译为对应目标架构后，以管理员权限运行 `tap-check /临时目录的绝对路径`；Ubuntu 优先再用 `unshare --net` 隔离。测试输出两轮响应摘要，需要与 `MD5(标识字节 + lab-password + 00..0f)` 比较。不得拿真实账号或现有配置目录作为测试目录。

本检查不是校园接入认证测试；物理校园网络及学校扩展仍需现场验证。
