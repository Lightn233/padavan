include $(ROOTDIR)/rules.mk

PKG_NAME:=libuv
PKG_VERSION:=1.53.0

PKG_SOURCE:=$(PKG_NAME)-v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://dist.libuv.org/dist/v$(PKG_VERSION)/
PKG_HASH:=cb0d6dd2128d5a95bd242c6cc982a24fe608fa93da57b6b4ec763b0018c53e64
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-v$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_OPTIONS += -DBUILD_TESTING=OFF

$(eval $(call BuildPackage,libuv))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/lib
	$(CP) $(PKG_INSTALL_DIR)/lib/libuv.so* $(ROMFSDIR)/lib/
