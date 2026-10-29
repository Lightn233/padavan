include $(ROOTDIR)/rules.mk

PKG_NAME:=httpd

include $(INCLUDE_DIR)/package.mk

TARGET_CFLAGS += \
	-I$(STAGING_DIR)/include/shared \
	$(if $(STORAGE_ENABLED),-I$(STAGING_DIR)/include/libdisk,)
TARGET_LDFLAGS += -L$(STAGING_DIR)/lib

$(eval $(call BuildPackage,httpd))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/httpd $(ROMFSDIR)/usr/sbin/httpd
ifeq ($(CONFIG_FIRMWARE_INCLUDE_HTTPS),y)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) ./https-cert.sh $(ROMFSDIR)/usr/bin/https-cert.sh
endif
# 本地源码、编译开关变更时重建暂存目录，避免旧构建戳漏掉修复。
$(STAMP_PREPARED): $(shell find src -type f) ../cflags.mk $(ROOTDIR)/.config
