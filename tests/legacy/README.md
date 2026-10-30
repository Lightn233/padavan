# 旧入口配置回归

从仓库根目录运行宿主机 ASan/UBSan 检查：

```sh
python3 tests/legacy/run_config_tests.py
```

同时运行 MIPS 版本：

```sh
python3 tests/legacy/run_config_tests.py \
  --mips-cc "$PWD/toolchain/toolchain-mipsel/bin/mipsel-linux-musl-gcc" \
  --qemu qemu-mipsel
```

需要 Python 3、宿主 GCC，第二条另需 MIPS 工具链和 QEMU user。程序只编译小型配置转换器，用合成配置进行检查，不修改任何路由器或网络设置，不使用真实账号。

协议联调、服务启停和固件集成的实际范围见 `docs/legacy-entry-migration-20261030.md`。本脚本通过不能代替协议或实机验收。
