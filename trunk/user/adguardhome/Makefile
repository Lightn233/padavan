include $(ROOTDIR)/rules.mk

PKG_NAME:=AdGuardHome
PKG_VERSION:=v0.108.0-b.89

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/AdguardTeam/AdGuardHome/archive/refs/tags/
PKG_SOURCE_URL_FILE:=v$(PKG_VERSION).tar.gz
PKG_HASH:=4e5a1390395c8c89a4ce0758fcfc2fc29e51b5f120a5fc754042a39d5adabf1e

include $(INCLUDE_DIR)/package.mk

LD_FLAGS:= \
	-X github.com/AdguardTeam/AdGuardHome/internal/version.channel=release \
	-X github.com/AdguardTeam/AdGuardHome/internal/version.version=$(PKG_VERSION)

define Build/Configure
	(cd $(PKG_BUILD_DIR); \
		NODE_OPTIONS=--openssl-legacy-provider make js-deps js-build; \
		zip -r embed.zip build; \
	)
endef

define Build/Compile
	(cd $(PKG_BUILD_DIR); \
		GOOS=linux GOARCH=mipsle CGO_ENABLED=0 \
		go build -v -o AdGuardHome \
		-trimpath -ldflags "$(LD_FLAGS) -s -w -buildid=" \
		.; \
	)
endef

$(eval $(call BuildPackage,adguardhome))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) ./adguardhome.sh $(ROMFSDIR)/usr/bin/adguardhome.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/AdGuardHome $(ROMFSDIR)/usr/bin/AdGuardHome
