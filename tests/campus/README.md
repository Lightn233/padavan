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
