include $(ROOTDIR)/rules.mk

PKG_NAME:=lz4
PKG_VERSION:=1.10.0
PKG_SOURCE:=lz4-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/lz4/lz4/tar.gz
PKG_SOURCE_URL_FILE:=refs/tags/v$(PKG_VERSION)
PKG_HASH:=537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b
MAKE_PATH:=lib

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

# 静态链接所需函数，固件不附带独立压缩工具。
MAKE_FLAGS += BUILD_SHARED=no BUILD_STATIC=yes PREFIX=

$(eval $(call BuildPackage,lz4))
$(STAMP_PREPARED): Makefile

romfs:
