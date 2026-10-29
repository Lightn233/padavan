include $(ROOTDIR)/rules.mk

PKG_NAME:=ipset
PKG_VERSION:=7.24

PKG_FIXUP:=autoreconf

PKG_SOURCE:=ipset-7.24.tar.bz2
PKG_SOURCE_URL:=https://www.netfilter.org/pub/ipset
PKG_HASH:=fbe3424dff222c1cb5e5c34d38b64524b2217ce80226c14fdcbb13b29ea36112

include $(INCLUDE_DIR)/package.mk

# 用户态与内核模块分开维护；Linux 4.4 不具备新版模块依赖的 pre_exit 接口。
# kernel.mk 保留 7.11 模块与 depmod.sh 已有路径，不改网络命名空间销毁顺序。

CONFIGURE_ARGS += \
	--enable-static \
	--disable-shared \
	--with-kmod=no \
	--with-kbuild=$(ROOTDIR)/$(LINUXDIR)

define Build/Compile
	$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) $(MAKE_FLAGS)
endef

$(eval $(call BuildPackage,ipset))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/ipset $(ROMFSDIR)/sbin/ipset

# 模块作为独立依赖构建，不依赖用户态的缓存状态。
.PHONY: kernel-build kernel-clean
all: kernel-build
kernel-build:
	$(MAKE) -f kernel.mk

# 给已有 clean 增加依赖，保留 package.mk 清理用户态目录的原有命令。
clean: kernel-clean
kernel-clean:
	$(MAKE) -f kernel.mk clean
