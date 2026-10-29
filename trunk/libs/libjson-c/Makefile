include $(ROOTDIR)/rules.mk

PKG_NAME:=json-c
PKG_VERSION:=0.19

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION)-nodoc.tar.gz
PKG_SOURCE_URL:=https://s3.amazonaws.com/json-c_releases/releases/
PKG_HASH:=704927172443309a8efeb162060bb215548e1286e5568514007dd2cc35a0a164

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_OPTIONS += -DDISABLE_EXTRA_LIBS=TRUE -DBUILD_TESTING=OFF

$(eval $(call BuildPackage,json-c))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/lib
	$(CP) $(PKG_INSTALL_DIR)/lib/libjson-c.so* $(ROMFSDIR)/lib/
