include $(ROOTDIR)/rules.mk

PKG_NAME:=util-linux
PKG_VERSION:=2.42.4
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=@KERNEL/linux/utils/$(PKG_NAME)/v2.42
PKG_HASH:=fbd62a100ab7bb8746ba0661255c3c48185b1e9021507c624da01fbc696330ec
PKG_INSTALL:=1
include $(INCLUDE_DIR)/package.mk

# Meson 只构建原固件使用的磁盘识别程序和两个库。
define Build/Configure
	$(CONFIGURE_VARS) python3 ./build.py configure --source $(PKG_BUILD_DIR) --stage $(STAGING_DIR)
endef
define Build/Compile
	python3 ./build.py compile --source $(PKG_BUILD_DIR) --stage $(STAGING_DIR)
endef
define Build/Install
	python3 ./build.py install --source $(PKG_BUILD_DIR) --stage $(STAGING_DIR)
endef
$(eval $(call BuildPackage,util-linux))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/sbin $(ROMFSDIR)/lib
	$(INSTALL_BIN) $(STAGING_DIR)/sbin/blkid $(ROMFSDIR)/sbin/blkid
	$(CP) $(STAGING_DIR)/lib/libblkid.so* $(ROMFSDIR)/lib/
	$(CP) $(STAGING_DIR)/lib/libuuid.so* $(ROMFSDIR)/lib/
