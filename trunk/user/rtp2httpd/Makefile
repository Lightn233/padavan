include $(ROOTDIR)/rules.mk

PKG_NAME:=rtp2httpd
PKG_VERSION:=3.17.2
PKG_SOURCE:=rtp2httpd-$(PKG_VERSION).tar.gz
PKG_HASH:=ce866091321a0d69dff7e8f7dda5d68be94e901659ed7d2ff4896029c8200ee6
PKG_SOURCE_URL:=https://codeload.github.com/stackia/rtp2httpd/tar.gz
PKG_SOURCE_URL_FILE:=v$(PKG_VERSION)
export RELEASE_VERSION:=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_OPTIONS += -DENABLE_AGGRESSIVE_OPT=OFF -DCMAKE_INSTALL_SYSCONFDIR=/etc

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xzf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

$(eval $(call BuildPackage,rtp2httpd))
$(STAMP_PREPARED): Makefile

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/rtp2httpd $(ROMFSDIR)/usr/bin/rtp2httpd

$(STAMP_PREPARED): $(wildcard patches/*.patch)
