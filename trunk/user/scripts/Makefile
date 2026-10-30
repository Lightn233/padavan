include $(ROOTDIR)/rules.mk

PKG_NAME:=scripts

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	$(CP) ./files $(PKG_BUILD_DIR)/
	mkdir -p $(PKG_BUILD_DIR)/files/usr/share/terminfo
	tar -xzf ./terminfo.tar.gz -C $(PKG_BUILD_DIR)/files/usr/share
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call BuildPackage,scripts))

romfs:
	fakeroot ./makedevlinks $(ROMFSDIR)
	$(CP) $(PKG_BUILD_DIR)/files/* $(ROMFSDIR)/
	# 用当前源码覆盖旧缓存，确保增量编译包含最新脚本。
	# 保留上一步复制的构建生成文件，例如 terminfo。
	$(CP) ./files/* $(ROMFSDIR)/
	# 每次安装都重新生成，避免沿用前一个机型或上次编译的临时目录上限。
	python3 "$(ROOTDIR)/../scripts/build_config.py" --write-resources "$(PROJECT_CONFIG)" "$(ROMFSDIR)/etc_ro/build-resources.conf"
ifneq ($(STORAGE_ENABLED),y)
	rm -f $(ROMFSDIR)/sbin/automount.sh
endif
ifndef CONFIG_BLK_DEV_SD
	rm -f $(ROMFSDIR)/sbin/hddtune.sh
	rm -f $(ROMFSDIR)/sbin/spindown.sh
endif
ifndef CONFIG_MTD_UBI
	rm -f $(ROMFSDIR)/sbin/rwfs2ubi.sh
endif
