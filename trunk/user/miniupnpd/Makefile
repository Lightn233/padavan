include $(ROOTDIR)/rules.mk

PKG_NAME:=miniupnpd
PKG_VERSION:=2.3.11
PKG_SOURCE:=miniupnpd-$(PKG_VERSION)-git.tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/miniupnp/miniupnp/tar.gz/refs/tags/miniupnpd_2_3_11?
PKG_HASH:=25521370ec33b8c075ca7b073cda2a98a2d449e6c09b10acbe5a9d038bca1017

include $(INCLUDE_DIR)/package.mk

# 从所选内核源码读取版本，不使用 Ubuntu 宿主机的内核版本。
MINIUPNPD_KERNEL_VERSION = $(shell awk '/^VERSION =/ {v=$$3} /^PATCHLEVEL =/ {p=$$3} /^SUBLEVEL =/ {s=$$3} /^EXTRAVERSION =/ {e=$$3} END {print v "." p "." s e}' "$(ROOTDIR)/$(LINUXDIR)/Makefile")

# 继续使用 IGDv1、IPv4 iptables，保留原固件启用的功能。
CONFIGURE_ARGS = --firewall=iptables --host-os=Linux --host-os-version=$(MINIUPNPD_KERNEL_VERSION) \
 --host-machine=mips --disable-tests --leasefile --vendorcfg --portinuse --disable-pppconn
CONFIGURE_VARS += PKG_CONFIG_LIBDIR="$(STAGING_DIR)/lib/pkgconfig" PKG_CONFIG_PATH="$(STAGING_DIR)/lib/pkgconfig"
# 本项目使用 iptables 1.8 API，不探测宿主机的 iptables 版本。
CONFIGURE_VARS += IPTABLES_143=1
MAKE_FLAGS += -f Makefile.linux miniupnpd

define Build/Prepare
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=2 miniupnp-miniupnpd_2_3_11/miniupnpd
	$(Build/Patch)
endef

$(eval $(call BuildPackage,miniupnpd))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/miniupnpd $(ROMFSDIR)/usr/bin/miniupnpd
