include $(ROOTDIR)/rules.mk

PKG_NAME:=libpcap
PKG_VERSION:=1.10.7
# 新版本构建后更新头文件和库，避免旧安装标记跳过新库。
PKG_INSTALL:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://www.tcpdump.org/release/
PKG_HASH:=68fa62cffb974f4275641ce14c2e2d75739251f30e00e6a0900903b247d76a03

include $(INCLUDE_DIR)/package.mk

CONFIGURE_ARGS += \
	--enable-static \
	--enable-shared \
	--disable-yydebug \
	--disable-dbus \
	--disable-usb \
	--disable-bluetooth \
	--with-pcap=linux \
	--without-flex \
	--without-bison \
	--without-dag \
	--without-septel \
	--without-libnl

CONFIGURE_VARS += ac_cv_netfilter_can_compile=no

$(eval $(call BuildPackage,libpcap))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/lib
	$(CP) $(PKG_INSTALL_DIR)/lib/libpcap.so* $(ROMFSDIR)/lib/
