include $(ROOTDIR)/rules.mk

PKG_NAME:=msd_lite
PKG_VERSION:=1.11.0
PKG_SOURCE:=msd_lite-fa68e131343fb58c67ad77b2d26f2cb7c49a2c95.tar.gz
PKG_HASH:=3452208a162ac3640745353918765fa26e7ef1c4f2d1c82683945344bed9f39d
PKG_SOURCE_URL:=https://codeload.github.com/rozhuk-im/msd_lite/tar.gz
PKG_SOURCE_URL_FILE:=fa68e131343fb58c67ad77b2d26f2cb7c49a2c95

# 主源码与子模块都固定提交和摘要，避免重复构建时取得不同版本。
LIBLCB_SOURCE:=liblcb-e2f420a2e545f7b04f3f7ffc13b3d9eaa92b5e8b.tar.gz
include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# 使用目标编译器定位 musl 的 pthread 兼容库，不能误找宿主库。
CMAKE_OPTIONS += -DPTHREAD_LIBRARY:FILEPATH=$(shell $(TARGET_CC) -print-file-name=libpthread.a)

define Download/liblcb
  FILE:=$(LIBLCB_SOURCE)
  URL:=https://codeload.github.com/rozhuk-im/liblcb/tar.gz
  URL_FILE:=e2f420a2e545f7b04f3f7ffc13b3d9eaa92b5e8b
  HASH:=b0e5c800b17944162c6d6a3fbb9a3791423b40837c110214f715f0df73fa5524
endef
$(eval $(call Download,liblcb))

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xzf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	mkdir -p '$(PKG_BUILD_DIR)/src/liblcb'
	printf '%s  %s\n' 'b0e5c800b17944162c6d6a3fbb9a3791423b40837c110214f715f0df73fa5524' '$(DL_DIR)/$(LIBLCB_SOURCE)' | sha256sum -c -
	tar -xzf '$(DL_DIR)/$(LIBLCB_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)/src/liblcb'
	$(Build/Patch)
endef

$(eval $(call BuildPackage,msd_lite))
$(STAMP_PREPARED): $(DL_DIR)/$(LIBLCB_SOURCE) Makefile

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin $(ROMFSDIR)/etc_ro
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/msd_lite $(ROMFSDIR)/usr/bin/msd_lite
	$(INSTALL_CONF) ./msd_lite.conf $(ROMFSDIR)/etc_ro/msd_lite.conf

$(STAMP_PREPARED): $(wildcard patches/*.patch)
