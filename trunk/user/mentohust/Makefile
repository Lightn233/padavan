include $(ROOTDIR)/rules.mk

PKG_NAME:=mentohust
PKG_VERSION:=0.3.1-ca76db5
PKG_SOURCE:=mentohust-ca76db502d793be5cbd45ce5fb63eb62a5df7deb.tar.gz
PKG_HASH:=ce56993be111b3f71edf36d8096dcaf3cf76626999b639e5dd71cd566e3b236d
PKG_SOURCE_URL:=https://codeload.github.com/hanwckf/mentohust-1/tar.gz
PKG_SOURCE_URL_FILE:=ca76db502d793be5cbd45ce5fb63eb62a5df7deb

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
# musl 已提供 iconv；按原方案链接 libpcap，不依赖桌面通知或交互输入密码。
EXTRA_CFLAGS += -std=gnu11
CONFIGURE_ARGS += --with-pcap=dylib --disable-notify --disable-encodepass --disable-nls

$(eval $(call BuildPackage,mentohust))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(ROMFSINST) $(PKG_BUILD_DIR)/src/mentohust /usr/bin/bin_mentohust
	$(ROMFSINST) $(CURDIR)/scripts/mentohust.sh /usr/bin/mentohust.sh
