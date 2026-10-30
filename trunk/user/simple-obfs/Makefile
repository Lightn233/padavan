include $(ROOTDIR)/rules.mk

# 旧协议继续兼容；固定源码和子模块，避免每次编译得到不同版本。
PKG_NAME:=simple-obfs
PKG_VERSION:=486bebd9208539058e57e23a12f23103016e09b4
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/shadowsocks/simple-obfs/tar.gz
PKG_SOURCE_URL_FILE:=$(PKG_VERSION)
PKG_HASH:=d717dc3389955633a2155b53a280c3982e30f7f890df9b4a32961040282fbf26
CORK_VERSION:=f02984545061c924808e4b9ea7cc6749a41f1979
CORK_SOURCE:=libcork-$(CORK_VERSION).tar.gz
CORK_HASH:=0f1ede7bd23672718d1d10adbe9e4028515d029585b93092d7199e51a40b3fe4

include $(INCLUDE_DIR)/package.mk

define Download/libcork
  FILE:=$(CORK_SOURCE)
  URL:=https://codeload.github.com/shadowsocks/libcork/tar.gz
  URL_FILE:=$(CORK_VERSION)
  HASH:=$(CORK_HASH)
endef
$(eval $(call Download,libcork))

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	printf '%s  %s\n' '$(CORK_HASH)' '$(DL_DIR)/$(CORK_SOURCE)' | sha256sum -c -
	tar -xzf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	mkdir -p '$(PKG_BUILD_DIR)/libcork'
	tar -xzf '$(DL_DIR)/$(CORK_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)/libcork'
	$(Build/Patch)
	(cd '$(PKG_BUILD_DIR)' && autoreconf --install --force)
endef

EXTRA_CFLAGS += -std=gnu11
CONFIGURE_ARGS += --disable-documentation --disable-ssp
CONFIGURE_VARS += LIBS="-lpthread -lm"
MAKE_FLAGS += LIBS="-lpthread -lm"

$(eval $(call BuildPackage,simple-obfs))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/obfs-local $(ROMFSDIR)/usr/bin/obfs-local
