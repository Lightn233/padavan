include $(ROOTDIR)/rules.mk

PKG_NAME:=aria2
PKG_VERSION:=1.37.0
PKG_SOURCE:=aria2-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://github.com/aria2/aria2/releases/download/release-$(PKG_VERSION)
PKG_HASH:=60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b
ARIANG_VERSION:=1.3.15
ARIANG_SOURCE:=AriaNg-$(ARIANG_VERSION)-AllInOne.zip
ARIANG_HASH:=9918932af1ab0ae3924b938b1c5195b6491dacf15908ac0dc440fdba660ac280

include $(INCLUDE_DIR)/package.mk

CONFIGURE_ARGS += --disable-nls --disable-xmltest --disable-libaria2 \
	--without-libnettle --without-libgmp --without-libgcrypt --without-libexpat \
	--without-libcares --without-sqlite3 --without-gnutls \
	--with-libz --with-openssl --with-libxml2 --with-libiconv-prefix=$(STAGING_DIR)
CONFIGURE_VARS += ZLIB_CFLAGS="-I$(STAGING_DIR)/include" ZLIB_LIBS="-L$(STAGING_DIR)/lib -lz" \
	OPENSSL_CFLAGS="-I$(STAGING_DIR)/include" OPENSSL_LIBS="-L$(STAGING_DIR)/lib -lssl -lcrypto" \
	LIBXML2_CFLAGS="-I$(STAGING_DIR)/include/libxml2" LIBXML2_LIBS="-L$(STAGING_DIR)/lib -lxml2 -lm"
EXTRA_CFLAGS += -ffunction-sections -fdata-sections -fvisibility=hidden
EXTRA_LDFLAGS += -static-libstdc++ -static-libgcc -Wl,--gc-sections -Wl,-rpath-link,$(STAGING_DIR)/lib
$(eval $(call BuildPackage,aria2))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

ifeq ($(CONFIG_FIRMWARE_INCLUDE_ARIA_WEB_CONTROL),y)
define Download/ariang
  FILE:=$(ARIANG_SOURCE)
  URL:=https://github.com/mayswind/AriaNg/releases/download/$(ARIANG_VERSION)
  HASH:=$(ARIANG_HASH)
endef
$(eval $(call Download,ariang))
ARIANG_DIR:=$(BUILD_DIR)/AriaNg-$(ARIANG_VERSION)
$(ARIANG_DIR)/.prepared: $(DL_DIR)/$(ARIANG_SOURCE) Makefile
	printf '%s  %s\n' '$(ARIANG_HASH)' '$(DL_DIR)/$(ARIANG_SOURCE)' | sha256sum -c -
	mkdir -p '$(ARIANG_DIR)'
	unzip -o -q '$(DL_DIR)/$(ARIANG_SOURCE)' -d '$(ARIANG_DIR)'
	test -s '$(ARIANG_DIR)/index.html'
	touch '$@'
all: $(ARIANG_DIR)/.prepared
romfs: $(ARIANG_DIR)/.prepared
endif

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/aria2c $(ROMFSDIR)/usr/bin/aria2c
	$(INSTALL_BIN) ./aria.sh $(ROMFSDIR)/usr/bin/aria.sh
ifeq ($(CONFIG_FIRMWARE_INCLUDE_ARIA_WEB_CONTROL),y)
	$(INSTALL_DIR) $(ROMFSDIR)/www/ariaweb
	$(INSTALL_DATA) $(ARIANG_DIR)/index.html $(ROMFSDIR)/www/ariaweb/index.html
endif
