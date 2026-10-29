include $(ROOTDIR)/rules.mk

PKG_NAME:=mtr
PKG_VERSION:=0.96

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://www.bitwizard.nl/mtr/files
PKG_HASH:=ffd19a9f8d5f616c1ea2f0da9fbf9d1239bcecdf5a68912e831966d20929037a

# 正式发布包已含 configure；重跑 autoreconf 会引用未打包的 git-version-gen。

include $(INCLUDE_DIR)/package.mk

CONFIGURE_ARGS += --without-gtk

$(eval $(call BuildPackage,mtr))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mtr $(ROMFSDIR)/usr/bin/mtr
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mtr-packet $(ROMFSDIR)/usr/bin/mtr-packet
