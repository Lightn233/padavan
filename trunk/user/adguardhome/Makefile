include $(ROOTDIR)/rules.mk

PKG_NAME:=AdGuardHome

# 留空时自动计算；网络无法核对新版本时，可在 prebuilt.local.mk 手动填写。
PKG_HASH ?=
PKG_BINARY_HASH ?=
ADG_PACKAGE ?=
ADG_VERIFY_REMOTE ?=1
-include prebuilt.local.mk
ADG_MANUAL_PACKAGE_HASH:=$(PKG_HASH)
ADG_MANUAL_BINARY_HASH:=$(PKG_BINARY_HASH)
ADG_METADATA:=$(BUILD_DIR)/adguardhome-prebuilt/package-info.mk

# 生成信息文件：读取最近放入的有效程序包，实际版本不依赖文件名。
include $(ADG_METADATA)
$(ADG_METADATA): adguardhome-prebuilt-force prebuilt.py official-checksums.json
	python3 ./prebuilt.py resolve --download-dir '$(DL_DIR)' --metadata '$(ADG_METADATA)' \
		--archive '$(ADG_PACKAGE)' --package-hash '$(ADG_MANUAL_PACKAGE_HASH)' \
		--binary-hash '$(ADG_MANUAL_BINARY_HASH)' --remote '$(ADG_VERIFY_REMOTE)'

.PHONY: adguardhome-prebuilt-force
adguardhome-prebuilt-force:

ifneq ($(strip $(PKG_SOURCE)),)
PKG_SOURCE_URL:=https://github.com/AdguardTeam/AdGuardHome/releases/download/v$(PKG_VERSION)/
PKG_SOURCE_URL_FILE:=AdGuardHome_linux_mipsle_softfloat.tar.gz
endif

include $(INCLUDE_DIR)/package.mk

# 解包前再次核对归档，只提取程序和官方说明文件。
define Build/Prepare
	python3 ./prebuilt.py unpack --archive '$(DL_DIR)/$(PKG_SOURCE)' \
		--destination '$(PKG_BUILD_DIR)' --package-hash '$(PKG_HASH)'
endef

# 官方程序已内嵌网页资源，这两个阶段直接检查程序。
define Build/Configure
	chmod 0755 '$(PKG_BUILD_DIR)/AdGuardHome'
endef

define Build/Compile
	printf '%s  %s\n' '$(PKG_BINARY_HASH)' '$(PKG_BUILD_DIR)/AdGuardHome' | sha256sum -c -
endef

$(eval $(call BuildPackage,adguardhome))

# 版本、归档或规则变化时重新解包；增量构建继续复用正确版本。
$(STAMP_PREPARED): Makefile prebuilt.py $(ADG_METADATA)

ADG_NET:=$(PKG_BUILD_DIR)/adguardhome-net
$(ADG_NET): adguardhome_net.c $(STAMP_PREPARED)
	$(TARGET_CC) $(TARGET_CFLAGS) -std=c99 -Os -Wall -Wextra -Wconversion -Werror \
		-o '$@' '$<' $(TARGET_LDFLAGS)

ADG_BACKUP:=$(PKG_BUILD_DIR)/adguardhome-backup
$(ADG_BACKUP): adguardhome_backup.c $(STAMP_PREPARED)
	$(TARGET_CC) $(TARGET_CFLAGS) -std=c99 -Os -Wall -Wextra -Werror \
		-o '$@' '$<' $(TARGET_LDFLAGS)

all: $(ADG_NET) $(ADG_BACKUP)

romfs: $(STAMP_BUILT) $(ADG_NET) $(ADG_BACKUP)
	printf '%s  %s\n' '$(PKG_BINARY_HASH)' '$(PKG_BUILD_DIR)/AdGuardHome' | sha256sum -c -
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) ./adguardhome.sh $(ROMFSDIR)/usr/bin/adguardhome.sh
	$(INSTALL_BIN) ./update_ipv6_hosts.sh $(ROMFSDIR)/usr/bin/update_ipv6_hosts.sh
	$(INSTALL_DATA) ./adguardhome_hosts.awk $(ROMFSDIR)/usr/bin/adguardhome_hosts.awk
	$(INSTALL_BIN) ./adguardhome_watch.sh $(ROMFSDIR)/usr/bin/adguardhome_watch.sh
	$(INSTALL_BIN) ./adguardhome_health.sh $(ROMFSDIR)/usr/bin/adguardhome_health.sh
	$(INSTALL_BIN) $(ADG_BACKUP) $(ROMFSDIR)/usr/bin/adguardhome-backup
	$(INSTALL_BIN) ./adguardhome_backup.sh $(ROMFSDIR)/usr/bin/adguardhome_backup.sh
	$(INSTALL_BIN) ./adguardhome_rdns_collect.sh $(ROMFSDIR)/usr/bin/adguardhome_rdns_collect.sh
	$(INSTALL_BIN) ./adguardhome_rdns_retire.sh $(ROMFSDIR)/usr/bin/adguardhome_rdns_retire.sh
	$(INSTALL_BIN) ./adguardhome_rdns_restart.sh $(ROMFSDIR)/usr/bin/adguardhome_rdns_restart.sh
	$(INSTALL_DATA) ./adguardhome_rdns_snapshot.awk $(ROMFSDIR)/usr/bin/adguardhome_rdns_snapshot.awk
	$(INSTALL_BIN) $(ADG_NET) $(ROMFSDIR)/usr/bin/adguardhome-net
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/AdGuardHome $(ROMFSDIR)/usr/bin/AdGuardHome
