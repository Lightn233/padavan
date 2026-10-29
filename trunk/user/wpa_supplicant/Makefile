include $(ROOTDIR)/rules.mk

PKG_NAME:=wpa_supplicant
PKG_VERSION:=2.12
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://w1.fi/releases
PKG_HASH:=08e23937e16d0155e55cab2b51f51fbe10d80a1aa91c4e15442645059b737ef6
SRC_DIR:=./no-source-overlay

include $(INCLUDE_DIR)/package.mk

CONFIGS :=
ifeq ($(CONFIG_FIRMWARE_INCLUDE_EAP_PEAP),y)
CONFIGS += \
	CONFIG_EAP_TTLS=y \
	CONFIG_EAP_PEAP=y \
	CONFIG_EAP_MSCHAPV2=y
else ifeq (,$(wildcard $(STAGING_DIR)/lib/pkgconfig/openssl.pc))
CONFIGS += \
	CONFIG_TLS=internal \
	CONFIG_CRYPTO=internal \
	CONFIG_INTERNAL_LIBTOMMATH=y \
	CONFIG_INTERNAL_RC4=y
endif

define Build/Configure
	(cd $(PKG_BUILD_DIR)/wpa_supplicant; \
	cp -f .config.def .config; \
	$(foreach c,$(CONFIGS),echo $(c) >> .config;) \
	)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/wpa_supplicant $(MAKE_FLAGS) all
endef

$(eval $(call BuildPackage,wpa_supplicant))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/wpa_supplicant/wpa_cli $(ROMFSDIR)/usr/sbin/wpa_cli
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/wpa_supplicant/wpa_supplicant $(ROMFSDIR)/usr/sbin/wpa_supplicant
