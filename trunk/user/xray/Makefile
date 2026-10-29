include $(ROOTDIR)/rules.mk

PKG_NAME:=xray
PKG_VERSION:=26.10.21

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/XTLS/Xray-core/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=44ef4874529a03848c90f1fdcfb763350fbc5f1de741ec90e0024d651df25650

PKG_BUILD_DIR:=$(BUILD_DIR)/Xray-core-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Build/Configure
endef

define Build/Compile
	(cd $(PKG_BUILD_DIR); \
		GOOS=linux GOARCH=mipsle GOMIPS=softfloat CGO_ENABLED=0 GOTOOLCHAIN=go1.27.3 \
		go build -v -o xray \
		-trimpath -ldflags "-s -w -buildid=" \
		./main; \
	)
endef

$(eval $(call BuildPackage,xray))

# 配方变更时重新验证构建输入。
$(STAMP_PREPARED): Makefile

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/xray $(ROMFSDIR)/usr/bin/xray
