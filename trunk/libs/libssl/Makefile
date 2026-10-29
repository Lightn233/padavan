include $(ROOTDIR)/rules.mk

PKG_NAME:=openssl
PKG_VERSION:=4.1.0

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/openssl/openssl/releases/download/openssl-$(PKG_VERSION)/
PKG_HASH:=50c17baf54cb008f6ce42d50deb4b28050a1aad711636cabd4b241c7e90cc2fd

include $(INCLUDE_DIR)/package.mk

# 保留多线程调用所需的锁与原子操作；本轮不使用后台线程池。
# 保留旧程序仍在调用的 ENGINE 和弃用接口，兼容修改另行核验。
# 禁止动态加载后，必要的 legacy 实现会内建到 libcrypto。
OPENSSL_OPTIONS = threads no-thread-pool no-dso no-module \
  no-capieng no-padlockeng no-afalgeng no-devcryptoeng \
  no-cms no-rfc3779 no-seed no-ec2m no-idea no-rc5 no-rmd160 \
  no-md2 no-ts no-mdc2 no-cast no-whirlpool no-sctp no-srp \
  no-ssl3 no-ssl3-method no-async no-blake2 no-aria \
  no-tests no-docs no-sm2 no-sm3 no-sm4 no-comp \
  no-quic no-ml-kem no-ml-dsa no-slh-dsa

ifneq ($(CONFIG_FIRMWARE_INCLUDE_SSWAN),y)
OPENSSL_OPTIONS += no-rc2
endif

ifneq ($(CONFIG_FIRMWARE_INCLUDE_OPENSSL_EC),y)
OPENSSL_OPTIONS += no-ec
endif

# 编译产物中的路径属于目标系统；安装时才加隔离 staging 前缀。
CONFIGURE_CMD = ./Configure
CONFIGURE_ARGS = \
	linux-mips32 \
	shared \
	--prefix=/ \
	--libdir=lib \
	--openssldir=/etc/ssl \
	$(OPENSSL_OPTIONS)

define Build/Install
	$(MAKE) -C $(PKG_BUILD_DIR)/$(MAKE_PATH) \
		$(MAKE_FLAGS) \
		DESTDIR=$(STAGING_DIR) \
		install_sw install_ssldirs
	$(INSTALL_DATA) ./openssl.cnf $(STAGING_DIR)/etc/ssl/openssl.cnf
	# 本项目未全局设置 pkg-config 的 sysroot，只修改交叉构建元数据。
	$(SED) 's,^prefix=.*,prefix=$(STAGING_DIR),g' \
		$(STAGING_DIR)/lib/pkgconfig/openssl.pc \
		$(STAGING_DIR)/lib/pkgconfig/libssl.pc \
		$(STAGING_DIR)/lib/pkgconfig/libcrypto.pc
endef

$(eval $(call BuildPackage,openssl))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/lib
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/lib/libssl.so.4 $(ROMFSDIR)/lib/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/lib/libcrypto.so.4 $(ROMFSDIR)/lib/
	# 保留原固件的无版本库链接，目标随本轮升级切换到 .so.4。
	ln -sf libssl.so.4 $(ROMFSDIR)/lib/libssl.so
	ln -sf libcrypto.so.4 $(ROMFSDIR)/lib/libcrypto.so
	# 只有目标库确实引用 libatomic 时才打包；缺库时终止，不能生成缺依赖镜像。
	@if $(TARGET_CROSS)readelf -d $(PKG_INSTALL_DIR)/lib/libcrypto.so.4 | grep -q 'NEEDED.*libatomic.so.1'; then \
		atomic_lib="$$($(TARGET_CC_NOCACHE) -print-file-name=libatomic.so.1)"; \
		test -f "$$atomic_lib" || { echo "错误：交叉工具链缺少 libatomic.so.1"; exit 1; }; \
		$(INSTALL_BIN) "$$atomic_lib" $(ROMFSDIR)/lib/libatomic.so.1; \
	fi
	$(INSTALL_DIR) $(ROMFSDIR)/etc_ro
	$(INSTALL_DATA) ./openssl.cnf $(ROMFSDIR)/etc_ro/openssl.cnf
ifeq ($(CONFIG_FIRMWARE_INCLUDE_OPENSSL_EXE),y)
	$(INSTALL_DIR) $(ROMFSDIR)/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/openssl $(ROMFSDIR)/bin/
endif
