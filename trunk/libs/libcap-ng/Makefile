include $(ROOTDIR)/rules.mk

PKG_NAME:=libcap-ng
PKG_VERSION:=0.9.6
PKG_SOURCE:=libcap-ng-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/stevegrubb/libcap-ng/tar.gz
PKG_SOURCE_URL_FILE:=refs/tags/v$(PKG_VERSION)
PKG_HASH:=399040138e0ca62fa2bcabd63da9af4431a246ef7a654561a0ca3cb00010a539
MAKE_PATH:=src

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

define Build/Configure
	cd $(PKG_BUILD_DIR) && sh autogen.sh
	$(call Build/Configure/Default)
endef

# 固件只需权限管理库，不引入 Python 或 BPF 审计工具。
CONFIGURE_ARGS += --disable-shared --enable-static --without-python --disable-cap-audit

$(eval $(call BuildPackage,libcap-ng))
$(STAMP_PREPARED): Makefile

romfs:
