include $(ROOTDIR)/rules.mk

PKG_NAME:=dogcom
PKG_VERSION:=1.6.2-pdv
PKG_SOURCE:=dogcom-1.6.2-pdv.tar.gz
PKG_HASH:=a097139fa712cc008e485f5aaeddbb5b559db71da9ac770bacabdb6787e883b6

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	mkdir -p "$(DL_DIR)"
	[ -f "$(DL_DIR)/$(PKG_SOURCE)" ] || cp "$(CURDIR)/$(PKG_SOURCE)" "$(DL_DIR)/$(PKG_SOURCE)"
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) -j$(HOST_NCPU) CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) -std=gnu11" LDFLAGS="$(TARGET_LDFLAGS)"
endef

$(eval $(call BuildPackage,dogcom))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(ROMFSINST) $(PKG_BUILD_DIR)/dogcom /usr/bin/dogcom
	$(ROMFSINST) -d $(PKG_BUILD_DIR)/sample-p.conf /etc_ro/dogcom/sample-p.conf
	$(ROMFSINST) -d $(PKG_BUILD_DIR)/sample-d.conf /etc_ro/dogcom/sample-d.conf
