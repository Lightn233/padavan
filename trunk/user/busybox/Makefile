include $(ROOTDIR)/rules.mk

PKG_NAME:=busybox
# RM2100 是本轮验证对象；其他机型继续使用原版本。
ifeq ($(subst ",,$(CONFIG_FIRMWARE_PRODUCT_ID)),RM2100)
PKG_VERSION:=1.38.0
SRC_DIR:=./busybox-1.38.0
else
PKG_VERSION:=1.24
SRC_DIR:=./busybox-1.24.x
endif

include $(INCLUDE_DIR)/package.mk

$(eval $(call BuildPackage,busybox))

# 配置更新必须触发重新准备，防止旧构建标记遗漏新增命令。
$(STAMP_PREPARED): $(SRC_DIR)/.config

romfs:
	$(MAKE) -C $(PKG_BUILD_DIR) \
		$(MAKE_FLAGS) \
		CONFIG_PREFIX=$(ROMFSDIR) \
		install
