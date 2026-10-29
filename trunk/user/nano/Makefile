include $(ROOTDIR)/rules.mk

PKG_NAME:=nano
PKG_VERSION:=9.3

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://www.nano-editor.org/dist/v9
PKG_HASH:=a9affc52c9596ee0682bcdd4ceb3c0b235eb221d83d733dfd9b0dff45897cb0d

include $(INCLUDE_DIR)/package.mk

# 保留精简体积与中文编辑能力，使用公共下载校验及版本独立的构建目录。
CONFIGURE_ARGS += \
	--enable-tiny \
	--enable-utf8 \
	--disable-nls

$(eval $(call BuildPackage,nano))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/nano $(ROMFSDIR)/usr/bin/nano
