include $(ROOTDIR)/rules.mk

PKG_NAME:=shared
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

$(eval $(call BuildPackage,shared))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/lib
	$(CP) $(PKG_BUILD_DIR)/libshared.so $(ROMFSDIR)/lib/
# 本地源码、编译开关变更时重建暂存目录，避免旧构建戳漏掉修复。
$(STAMP_PREPARED): $(shell find src -type f) ../cflags.mk $(ROOTDIR)/.config
