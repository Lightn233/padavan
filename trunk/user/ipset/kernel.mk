include $(ROOTDIR)/rules.mk

PKG_NAME:=ipset
PKG_VERSION:=7.11
PKG_FIXUP:=autoreconf
PATCH_DIR:=./kernel-patches
include $(INCLUDE_DIR)/package.mk
SRC_DIR:=./ipset-7.11

CONFIGURE_ARGS += --enable-static --disable-shared --with-kmod=yes --with-kbuild=$(ROOTDIR)/$(LINUXDIR)

define Build/Compile
	$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) $(MAKE_FLAGS) LDFLAGS= modules
endef

$(eval $(call BuildPackage,ipset))

# 内核版本、配置、导出符号或构建位置变化时，重新配置并编译外部模块。
# 比较内容后再更新标记，避免每次 make 都无条件重编。
IPSET_KERNEL_DIR := $(abspath $(ROOTDIR)/$(LINUXDIR))
IPSET_KERNEL_CONTEXT := $(PKG_BUILD_DIR)/.kernel-context
.PHONY: ipset-kernel-context-force
$(IPSET_KERNEL_CONTEXT): ipset-kernel-context-force $(STAMP_PREPARED)
	@set -e; { \
		printf '%s\n' '$(IPSET_KERNEL_DIR)' '$(TARGET_CC_NOCACHE)'; \
		$(TARGET_CC_NOCACHE) -dumpfullversion -dumpversion; \
		sha256sum '$(IPSET_KERNEL_DIR)/.config' \
			'$(IPSET_KERNEL_DIR)/include/config/kernel.release' \
			'$(IPSET_KERNEL_DIR)/Module.symvers'; \
	} > '$@.tmp'; \
	if cmp -s '$@.tmp' '$@'; then rm -f '$@.tmp'; else mv -f '$@.tmp' '$@'; fi

$(STAMP_CONFIGURED): $(IPSET_KERNEL_CONTEXT)
$(STAMP_BUILT): $(IPSET_KERNEL_CONTEXT)
