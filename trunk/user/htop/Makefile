include $(ROOTDIR)/rules.mk

PKG_NAME:=htop
PKG_VERSION:=3.5.2

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/htop-dev/htop/tar.gz/$(PKG_VERSION)?
PKG_HASH:=a66a62bbd1eba59889c68f868b643e53320eea93da19f43ba13c822a826d82ba

PKG_FIXUP:=autoreconf

include $(INCLUDE_DIR)/package.mk

CONFIGURE_ARGS += \
	--enable-unicode \
	HTOP_NCURSESW_CONFIG_SCRIPT="$(STAGEDIR)/bin/ncursesw6-config"

$(eval $(call BuildPackage,htop))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/htop $(ROMFSDIR)/usr/bin/htop
