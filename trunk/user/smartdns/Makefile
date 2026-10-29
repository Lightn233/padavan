include $(ROOTDIR)/rules.mk

PKG_NAME:=smartdns
PKG_VERSION:=48.4
PKG_SOURCE:=smartdns-Release$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/pymumu/smartdns/tar.gz
PKG_SOURCE_URL_FILE:=refs/tags/Release$(PKG_VERSION)
PKG_HASH:=b07abba99e921f262ba47588e12f5b36dd849f79c0145542440eb6b7eed80553

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xzf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

MAKE_FLAGS += VER=Release48.4 NO_GIT_VER=1 WITH_UI=0 WITH_ZLIB=1
EXTRA_CFLAGS += -ffunction-sections -fdata-sections
EXTRA_LDFLAGS += -Wl,--gc-sections
$(eval $(call BuildPackage,smartdns))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin $(ROMFSDIR)/etc_ro
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/smartdns $(ROMFSDIR)/usr/bin/smartdns
	$(INSTALL_BIN) ./smartdns.sh $(ROMFSDIR)/usr/bin/smartdns.sh
	$(INSTALL_DATA) ./conf/*.conf $(ROMFSDIR)/etc_ro/
