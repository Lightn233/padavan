include $(ROOTDIR)/rules.mk

PKG_NAME:=curl
PKG_VERSION:=8.23.0

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://curl.se/download
PKG_HASH:=8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5

include $(INCLUDE_DIR)/package.mk

TARGET_LDFLAGS += -Wl,-rpath-link=$(STAGEDIR)/lib

# 保留现有协议和同步解析模式；新版默认关闭的 SMB/NTLM 显式开启。
CONFIGURE_ARGS += \
	--disable-docs \
	--enable-smb \
	--enable-ntlm \
	--without-libpsl \
	--without-brotli \
	--without-zstd \
	--without-nghttp2 \
	--without-nghttp3 \
	--without-ngtcp2 \
	--without-quiche \
	--without-libssh \
	--enable-static \
	--enable-shared \
	--disable-gopher \
	--disable-ldap \
	--disable-ldaps \
	--disable-rtsp \
	--disable-telnet \
	--disable-tftp \
	--disable-smtp \
	--disable-pop3 \
	--disable-imap \
	--disable-sspi \
	--disable-dict \
	--disable-ares \
	--disable-debug \
	--disable-manual \
	--disable-verbose \
	--disable-libcurl-option \
	--disable-threaded-resolver \
	--without-gnutls \
	--without-libidn2 \
	--without-libssh2 \
	--without-ca-path \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
	--with-zlib=$(STAGING_DIR) \
	--with-openssl=$(STAGING_DIR)

define update_curl_config_prefix
	$(SED) 's,^\(prefix\|exec_prefix\)=.*,\1=$(STAGING_DIR)/usr,g' $(STAGING_DIR)/bin/curl-config
endef

Hooks/Install/Post += update_curl_config_prefix

$(eval $(call BuildPackage,curl))

romfs:
ifeq ($(CONFIG_FIRMWARE_INCLUDE_CURL),y)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/curl $(ROMFSDIR)/usr/bin/
endif
	$(INSTALL_DIR) $(ROMFSDIR)/lib
	$(CP) $(PKG_INSTALL_DIR)/lib/libcurl.so* $(ROMFSDIR)/lib/
