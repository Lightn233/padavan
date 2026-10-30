include $(ROOTDIR)/rules.mk

PKG_NAME:=minieap
PKG_VERSION:=0.93
PKG_SOURCE:=minieap-9e10f320a9fce46c8f4286324a0fc70e572f61dc.tar.gz
PKG_HASH:=80fbdda586fe582b7fef32d4e5fea979d50f0c5529baa3cc535e75c8acbb7c1e
PKG_SOURCE_URL:=https://codeload.github.com/updateing/minieap/tar.gz
PKG_SOURCE_URL_FILE:=9e10f320a9fce46c8f4286324a0fc70e572f61dc

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) -j$(HOST_NCPU) CC="$(TARGET_CC)" \
		CUSTOM_CFLAGS="$(TARGET_CFLAGS) -std=gnu11" CUSTOM_LDFLAGS="$(TARGET_LDFLAGS)" LIBICONV_STANDALONE=false
endef

$(eval $(call BuildPackage,minieap))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(ROMFSINST) $(PKG_BUILD_DIR)/minieap /usr/bin/minieap
	$(ROMFSINST) $(PKG_BUILD_DIR)/minieap.conf /etc_ro/minieap.conf
