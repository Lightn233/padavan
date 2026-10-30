# 只内置管理入口，可选主程序按需安装到 RWFS。
all:

romfs:
	$(ROMFSINST) -p +x ddns-go.sh /usr/bin/ddns-go.sh

clean:

.PHONY: all romfs clean

# 可选核心单独构建并保存在 RWFS，普通固件编译不包含它。
compat-package:
	python3 ./build-compat.py --cache-dir "$(ROOTDIR)/download" --work-dir "$(ROOTDIR)/build/ddns-go-compat" --output-dir "$(ROOTDIR)/images/optional"

.PHONY: compat-package
