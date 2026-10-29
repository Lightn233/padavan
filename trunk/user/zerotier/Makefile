include $(ROOTDIR)/rules.mk

PKG_NAME:=zerotier
PKG_VERSION:=1.16.2
PKG_SOURCE:=zerotier-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/zerotier/ZeroTierOne/tar.gz
PKG_SOURCE_URL_FILE:=refs/tags/$(PKG_VERSION)
PKG_HASH:=2c607f573c6e38815433af289d364a689a203b18b51125f06c4472014d0657f0

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xzf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 --exclude='*/ext/libpqxx-*/install/*' -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

# 仅构建上游 MPL 客户端与 Moon 功能；新版独立授权的控制器不纳入公共固件。
MAKE_FLAGS += ZT_EMBEDDED=1 ZT_CONTROLLER=0 ZT_NONFREE=0 ZT_SSO_SUPPORTED=0
EXTRA_CFLAGS += -ffunction-sections -fdata-sections
EXTRA_LDFLAGS += -static-libstdc++ -static-libgcc -Wl,--gc-sections
$(eval $(call BuildPackage,zerotier))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/zerotier-one $(ROMFSDIR)/usr/bin/zerotier-one
	$(INSTALL_BIN) ./zerotier.sh $(ROMFSDIR)/usr/bin/zerotier.sh
	ln -sf zerotier-one $(ROMFSDIR)/usr/bin/zerotier-cli
	ln -sf zerotier-one $(ROMFSDIR)/usr/bin/zerotier-idtool
