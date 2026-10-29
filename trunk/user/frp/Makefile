include $(ROOTDIR)/rules.mk

PKG_NAME:=frp
PKG_VERSION:=0.71.1
PKG_SOURCE:=frp_$(PKG_VERSION)_linux_mipsle.tar.gz
PKG_SOURCE_URL:=https://github.com/fatedier/frp/releases/download/v$(PKG_VERSION)
PKG_HASH:=2eaa97e6b42a0cbd672b079b59d5682bb64a766f9a9564d7c4bbbd3ca79ec694

include $(INCLUDE_DIR)/package.mk

# 官方 MIPS 小端软浮点程序；下载、解包、安装依赖有序且核验摘要。
define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xzf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
endef
define Build/Configure
endef
define Build/Compile
	test -x '$(PKG_BUILD_DIR)/frpc' -a -x '$(PKG_BUILD_DIR)/frps'
endef
$(eval $(call BuildPackage,frp))
$(STAMP_PREPARED): Makefile

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin $(ROMFSDIR)/etc_ro
ifeq ($(CONFIG_FIRMWARE_INCLUDE_FRPC),y)
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/frpc $(ROMFSDIR)/usr/bin/frpc
endif
ifeq ($(CONFIG_FIRMWARE_INCLUDE_FRPS),y)
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/frps $(ROMFSDIR)/usr/bin/frps
endif
	$(INSTALL_BIN) ./frp.sh $(ROMFSDIR)/usr/bin/frp.sh
	$(INSTALL_BIN) ./frp_script.sh $(ROMFSDIR)/etc_ro/frp_script.sh
	$(INSTALL_CONF) ./frpc.toml.example $(ROMFSDIR)/etc_ro/frpc.toml.example
	$(INSTALL_CONF) ./frps.toml.example $(ROMFSDIR)/etc_ro/frps.toml.example
