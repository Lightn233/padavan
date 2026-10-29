include $(ROOTDIR)/rules.mk

PKG_NAME:=softether
PKG_VERSION:=4.41-9787
PKG_SOURCE:=softether-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/SoftEtherVPN/SoftEtherVPN_Stable/tar.gz
PKG_SOURCE_URL_FILE:=refs/tags/v$(PKG_VERSION)-rtm
PKG_HASH:=42373b367686ac3c86e78d11fade74381d6173f36847b518910ba0092acd79cb

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
	cp build_hamcore.py $(PKG_BUILD_DIR)/build_hamcore.py
	mkdir -p $(PKG_BUILD_DIR)/tmp/objs/Mayaqua $(PKG_BUILD_DIR)/tmp/objs/Cedar $(PKG_BUILD_DIR)/tmp/as
	mkdir -p $(PKG_BUILD_DIR)/bin/vpnserver $(PKG_BUILD_DIR)/bin/vpnclient $(PKG_BUILD_DIR)/bin/vpnbridge $(PKG_BUILD_DIR)/bin/vpncmd
endef

define Build/Configure
	@true
endef

define Build/Compile
	$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) -f src/makefiles/linux_32bit.mak \
		CC="$(TARGET_CC)" AR="$(TARGET_AR)" RANLIB="$(TARGET_RANLIB)" \
		CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -fPIC -std=gnu11" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		bin/vpnserver/vpnserver bin/vpnclient/vpnclient bin/vpncmd/vpncmd
endef

$(eval $(call BuildPackage,softether))
$(STAMP_PREPARED): Makefile build_hamcore.py $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
ifeq ($(CONFIG_FIRMWARE_INCLUDE_SOFTETHERVPN_CMD),y)
	$(ROMFSINST) -d -p +x $(PKG_BUILD_DIR)/bin/vpncmd/vpncmd /etc_ro/softethervpn/vpncmd
endif
ifeq ($(CONFIG_FIRMWARE_INCLUDE_SOFTETHERVPN_CLIENT),y)
	$(ROMFSINST) -d -p +x $(PKG_BUILD_DIR)/bin/vpnclient/vpnclient /etc_ro/softethervpn/vpnclient
endif
ifeq ($(CONFIG_FIRMWARE_INCLUDE_SOFTETHERVPN_SERVER),y)
	$(ROMFSINST) -d -p +x $(PKG_BUILD_DIR)/bin/vpnserver/vpnserver /etc_ro/softethervpn/vpnserver
endif
	$(ROMFSINST) -d -S $(PKG_BUILD_DIR)/src/bin/BuiltHamcoreFiles/unix/hamcore.se2 /etc_ro/softethervpn/hamcore.se2
	$(ROMFSINST) -d -S $(PKG_BUILD_DIR)/tmp/objs/Mayaqua/libMayaqua.so /lib/libMayaqua.so
	$(ROMFSINST) -d -S $(PKG_BUILD_DIR)/tmp/objs/Cedar/libCedar.so /lib/libCedar.so
	$(ROMFSINST) softethervpn.sh /usr/bin/softethervpn.sh
