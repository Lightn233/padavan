include $(ROOTDIR)/rules.mk

PKG_NAME:=readline
PKG_VERSION:=8.3
PKG_SOURCE:=readline-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://ftp.gnu.org/gnu/readline
PKG_HASH:=fe5383204467828cd495ee8d1d3c037a7eba1389c22bc6a041f627976f9061cc
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

# GNU 官方补丁使用 -p0，保留原补丁内容和顺序。
define Build/Patch
	set -e; for p in patches/*.patch; do $(PATCH) --batch --forward -d '$(PKG_BUILD_DIR)' -p0 < "$$$$p"; done
endef

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

# 静态库需可链接到 SoftEther 共享库；不增加路由器端共享库版本依赖。
EXTRA_CFLAGS += -fPIC
CONFIGURE_ARGS += --disable-shared --enable-static --with-curses
# 上游也使用 BUILD_DIR，不能继承固件的组件父目录。
MAKE_FLAGS += BUILD_DIR="$(PKG_BUILD_DIR)"

$(eval $(call BuildPackage,readline))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs:
	@true
