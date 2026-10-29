include $(ROOTDIR)/rules.mk

PKG_NAME:=ppp
PKG_VERSION:=2.5.4
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

SRC_DIR=./ppp-2.5.4
CONFIGURE_PREFIX:=/usr
CONFIGURE_ARGS += \
	--with-runtime-dir=/var/run \
	--with-logfile-dir=/var/log \
	--with-plugin-dir=/usr/lib/pppd \
	--disable-eaptls --disable-peap --without-openssl \
	--with-pam=no --without-pcap --without-atm

# 必须先成功生成新版构建文件，不能忽略 autoreconf 的失败。
define PPP/Autoreconf
	(cd $(PKG_BUILD_DIR) && autoreconf -fi)
endef
Hooks/Configure/Pre += PPP/Autoreconf

$(eval $(call BuildPackage,ppp))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/sbin $(ROMFSDIR)/usr/lib/pppd
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/pppd/pppd $(ROMFSDIR)/usr/sbin/pppd
	$(CP) $(PKG_BUILD_DIR)/pppd/plugins/pppoe/.libs/pppoe.so $(ROMFSDIR)/usr/lib/pppd/
	ln -sf pppoe.so $(ROMFSDIR)/usr/lib/pppd/rp-pppoe.so
	$(CP) $(PKG_BUILD_DIR)/pppd/plugins/pppol2tp/.libs/pppol2tp.so $(ROMFSDIR)/usr/lib/pppd/
	$(CP) $(PKG_BUILD_DIR)/pppd/plugins/pptp/.libs/pptp.so $(ROMFSDIR)/usr/lib/pppd/
