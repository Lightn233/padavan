include $(ROOTDIR)/rules.mk

PKG_NAME:=openvpn
PKG_VERSION:=2.7.8
PKG_SOURCE:=openvpn-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/OpenVPN/openvpn/tar.gz
PKG_SOURCE_URL_FILE:=refs/tags/v$(PKG_VERSION)
PKG_HASH:=daf18f81040137fc4d3d843088954ae68f6c86c10d3860114078b9c256a3516f

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

define Build/Configure
	cd $(PKG_BUILD_DIR) && autoreconf -fi
	$(call Build/Configure/Default)
endef

EXTRA_CFLAGS += -fvisibility=hidden
CONFIGURE_VARS += IFCONFIG=/sbin/ifconfig ROUTE=/sbin/route NETSTAT=/bin/netstat

# 目标内核没有 DCO；保留现有 TUN、LZO 和 LZ4 兼容路径。
CONFIGURE_ARGS += \
	--disable-debug --disable-plugins --disable-pkcs11 \
	--disable-selinux --disable-systemd --disable-dco --disable-iproute2 \
	--disable-unit-tests --disable-management --disable-dns-updown-by-default \
	--enable-small --with-crypto-library=openssl

$(eval $(call BuildPackage,openvpn))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(ROMFSINST) $(PKG_BUILD_DIR)/src/openvpn/openvpn /usr/sbin/openvpn
	$(ROMFSINST) /usr/bin/openvpn-cert.sh
