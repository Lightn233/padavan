include $(ROOTDIR)/rules.mk

PKG_NAME:=libxml2
PKG_VERSION:=2.15.4
PKG_SOURCE:=libxml2-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://download.gnome.org/sources/libxml2/2.15
PKG_HASH:=98087fd181d9070724f3fbc65c7377db03038eb92bd882374daff44940138821
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

# 作为目标程序的静态依赖；保留 aria2 所需的推送式 XML 解析。
CONFIGURE_ARGS += --enable-static --disable-shared --without-python \
	--without-programs --without-debug --without-iconv --without-lzma
EXTRA_CFLAGS += -ffunction-sections -fdata-sections
EXTRA_LDFLAGS += -Wl,--gc-sections
$(eval $(call BuildPackage,libxml2))
$(STAMP_PREPARED): Makefile

romfs:
