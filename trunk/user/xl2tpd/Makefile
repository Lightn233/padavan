include $(ROOTDIR)/rules.mk

PKG_NAME:=xl2tpd
PKG_VERSION:=1.3.20

include $(INCLUDE_DIR)/package.mk

# 固件仅使用拨号服务及控制程序，不构建依赖 libpcap 的独立 pfc 工具。
define Build/Compile
	$(call Build/Compile/Default,xl2tpd xl2tpd-control)
endef

$(eval $(call BuildPackage,xl2tpd))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/xl2tpd $(ROMFSDIR)/usr/sbin/xl2tpd
