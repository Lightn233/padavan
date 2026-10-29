include $(ROOTDIR)/rules.mk

PKG_NAME:=iproute2
PKG_VERSION:=7.3.0

PKG_SOURCE:=iproute2-7.3.0.tar.xz
PKG_SOURCE_URL:=@KERNEL/linux/utils/net/iproute2
PKG_HASH:=5c1789d290bba048a6135ed1ab81b0402dd0fb528d1f1421765c42b1fc3d6289

include $(INCLUDE_DIR)/package.mk

SRC_DIR:=./src

# 此配置脚本只接收头文件目录，不接受通用 autoconf 参数。
CONFIGURE_ARGS:=$(PKG_BUILD_DIR)/include/uapi

MAKE_FLAGS += HOSTCC=gcc SUBDIRS="lib ip tc"

$(eval $(call BuildPackage,iproute2))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ip/ip $(ROMFSDIR)/bin/ip
ifeq ($(CONFIG_FIRMWARE_INCLUDE_SQM),y)
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tc/tc $(ROMFSDIR)/bin/tc
endif
