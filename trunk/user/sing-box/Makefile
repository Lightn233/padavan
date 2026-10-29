include $(ROOTDIR)/rules.mk

PKG_NAME:=sing-box
PKG_VERSION:=1.14.4
PKG_SOURCE:=sing-box-$(PKG_VERSION)-linux-mipsle-softfloat.tar.gz
PKG_SOURCE_URL:=https://github.com/SagerNet/sing-box/releases/download/v$(PKG_VERSION)
PKG_HASH:=4abf94c284462bca0d9d23966b26e5675a2c0137b7945534f0fa1b0fc309b298
PKG_BINARY_HASH:=2ebe1bea84d0cf34372e03a1ae98ee0b872d208bc451c6e9a8bf835ee584792c

include $(INCLUDE_DIR)/package.mk

# 固定官方 MIPS 小端软浮点版本，避免宿主 Go 默认浮点方式改变目标兼容性。
define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xzf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
endef
define Build/Configure
endef
define Build/Compile
	printf '%s  %s\n' '$(PKG_BINARY_HASH)' '$(PKG_BUILD_DIR)/sing-box' | sha256sum -c -
	test -x '$(PKG_BUILD_DIR)/sing-box'
endef
$(eval $(call BuildPackage,sing-box))
$(STAMP_PREPARED): Makefile

# 仅在原有机型开关选中时内置；默认机型开关不变。
romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sing-box $(ROMFSDIR)/usr/bin/sing-box
