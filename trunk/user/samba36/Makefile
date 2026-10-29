include $(ROOTDIR)/rules.mk

# 保留原 samba36 构建入口，内部升级为受维护的 Samba 4。
PKG_NAME:=samba4-suite
PKG_VERSION:=4.25.1
PKG_SOURCE:=samba-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://download.samba.org/pub/samba/stable
PKG_HASH:=7f367545bca69aa96897628f82f0f04d4b66b3bcb36cb978b9bb952c4b4c428d
PKG_INSTALL:=1
PKG_INSTALL_DIR=$(PKG_BUILD_DIR)/install

include $(INCLUDE_DIR)/package.mk

define Download/gmp
  FILE:=gmp-6.3.0.tar.gz
  URL:=https://ftp.gnu.org/gnu/gmp
  HASH:=e56fd59d76810932a0555aa15a14b61c16bed66110d3c75cc2ac49ddaa9ab24c
endef
define Download/nettle
  FILE:=nettle-3.10.2.tar.gz
  URL:=https://ftp.gnu.org/gnu/nettle
  HASH:=fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5
endef
define Download/tasn1
  FILE:=libtasn1-4.21.0.tar.gz
  URL:=https://ftp.gnu.org/gnu/libtasn1
  HASH:=1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87
endef
define Download/gnutls
  FILE:=gnutls-3.8.12.tar.xz
  URL:=https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8
  HASH:=a7b341421bfd459acf7a374ca4af3b9e06608dcd7bd792b2bf470bea012b8e51
endef
$(eval $(call Download,gmp))
$(eval $(call Download,nettle))
$(eval $(call Download,tasn1))
$(eval $(call Download,gnutls))
SAMBA_DEPS:=gmp-6.3.0.tar.gz nettle-3.10.2.tar.gz libtasn1-4.21.0.tar.gz gnutls-3.8.12.tar.xz
SAMBA_ENV=SAMBA_CC='$(TARGET_CC)' SAMBA_CROSS='$(TARGET_CROSS)' \
	SAMBA_EXTERNAL_STAGE='$(STAGING_DIR)' SAMBA_JOBS='$(HOST_NCPU)' \
	SAMBA_CFLAGS='$(TARGET_CFLAGS)' SAMBA_QEMU='$(SAMBA_QEMU)'

define Build/Prepare
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	printf '%s  %s\n' 'e56fd59d76810932a0555aa15a14b61c16bed66110d3c75cc2ac49ddaa9ab24c' '$(DL_DIR)/gmp-6.3.0.tar.gz' 'fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5' '$(DL_DIR)/nettle-3.10.2.tar.gz' '1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87' '$(DL_DIR)/libtasn1-4.21.0.tar.gz' 'a7b341421bfd459acf7a374ca4af3b9e06608dcd7bd792b2bf470bea012b8e51' '$(DL_DIR)/gnutls-3.8.12.tar.xz' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' -C '$(PKG_BUILD_DIR)'
	set -e; $(foreach arc,$(SAMBA_DEPS),tar -xf '$(DL_DIR)/$(arc)' -C '$(PKG_BUILD_DIR)';)
	$(call PatchDir,$(PKG_BUILD_DIR)/samba-$(PKG_VERSION),./patches4)
endef
define Build/Configure
	$(SAMBA_ENV) python3 ./build-samba4.py '$(PKG_BUILD_DIR)' configure
endef
define Build/Compile
	$(SAMBA_ENV) python3 ./build-samba4.py '$(PKG_BUILD_DIR)' compile
endef
define Build/Install
	$(SAMBA_ENV) python3 ./build-samba4.py '$(PKG_BUILD_DIR)' install
endef
$(eval $(call BuildPackage,samba4-suite))
$(STAMP_PREPARED): Makefile build-samba4.py smbpasswd-compat.c $(wildcard patches4/*.patch) $(addprefix $(DL_DIR)/,$(SAMBA_DEPS))

romfs: $(STAMP_INSTALLED)
	$(SAMBA_ENV) SAMBA_ROMFS='$(ROMFSDIR)' SAMBA_SMBD='$(CONFIG_FIRMWARE_INCLUDE_SMBD)' \
	SAMBA_WINS='$(CONFIG_FIRMWARE_INCLUDE_WINS)' python3 ./build-samba4.py '$(PKG_BUILD_DIR)' romfs
