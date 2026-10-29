TOPDIR := $(CURDIR)
CT_PREFIX ?= $(TOPDIR)/toolchain-mipsel
CT_TARGET ?= mipsel-linux-musl
SOURCE_WORK ?= $(TOPDIR)/.source-build
SOURCE_CACHE ?= $(TOPDIR)/downloads
SOURCE_JOBS ?= 4
SOURCE_KERNEL ?= $(TOPDIR)/../trunk/linux-4.4.x
SOURCE_REPLACE ?= 0
SOURCE_OFFLINE ?= 0
TOOLCHAIN_ARCHIVE ?= $(TOPDIR)/downloads/toolchain-mipsel-gcc16.2.0-binutils2.47-musl1.2.6.tar.xz
ENTRY_ARGS = --prefix "$(CT_PREFIX)" --work "$(SOURCE_WORK)" --kernel "$(SOURCE_KERNEL)" --cache "$(SOURCE_CACHE)" --archive "$(TOOLCHAIN_ARCHIVE)" --jobs "$(SOURCE_JOBS)"
ENTRY_ARGS += $(if $(filter 1,$(SOURCE_REPLACE)),--replace-existing) $(if $(filter 1,$(SOURCE_OFFLINE)),--offline)

.PHONY: all build download prepare verify clean
all: build

# 原 build 入口现在从校验后的源码构建当前工具链。
build download prepare verify clean:
	@test "$(CT_TARGET)" = "mipsel-linux-musl" || { echo "不支持的工具链目标：$(CT_TARGET)"; exit 1; }
	python3 "$(TOPDIR)/toolchain_entry.py" $(if $(filter download,$@),ensure,$@) $(ENTRY_ARGS)
