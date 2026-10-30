include $(ROOTDIR)/rules.mk

PKG_NAME:=gdut-drcom
PKG_VERSION:=1.6.8
PKG_SOURCE:=gdut-drcom-c71eadbb802c08b9265b830f61d4c91530929ae3.tar.gz
PKG_HASH:=065fc9533789a62d4b8fa7b01d113b6e689c3e17c694f8387b5a00aeda214e10
PKG_SOURCE_URL:=https://codeload.github.com/xnhw01/gdut-drcom/tar.gz
PKG_SOURCE_URL_FILE:=c71eadbb802c08b9265b830f61d4c91530929ae3

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src -j$(HOST_NCPU) CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) -std=gnu11 -Wall -DVERSION=$(PKG_VERSION)" LIBS="$(TARGET_LDFLAGS)"
endef

$(eval $(call BuildPackage,gdut-drcom))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(ROMFSINST) $(PKG_BUILD_DIR)/src/gdut-drcom /usr/bin/gdut-drcom
	$(ROMFSINST) -d $(PKG_BUILD_DIR)/src/gdut-drcom.conf /etc_ro/gdut-drcom/gdut-drcom.conf
