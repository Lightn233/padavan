include $(ROOTDIR)/rules.mk

PKG_NAME:=openssh
PKG_VERSION:=10.6p1
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable
PKG_HASH:=a9dc9565dffe8640f64d863cd29a32bc4a3dbdec0566a7fc44c5d6ee767d5f39
include $(INCLUDE_DIR)/package.mk

CONFIGURE_ARGS += \
	--prefix=/usr \
	--sysconfdir=/etc/storage/openssh \
	--libexecdir=/usr/libexec \
	--with-pid-dir=/var/run \
	--with-privsep-path=/var/empty \
	--with-privsep-user=sshd \
	--with-sandbox=no \
	--without-pam --without-selinux --without-bsd-auth --without-kerberos5 \
	--disable-strip --disable-etc-default-login --disable-lastlog \
	--disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx --disable-libutil
CONFIGURE_VARS += LD="$(TARGET_CC)"
# OpenSSH 的链接规则使用编译器参数，不能传给裸 ld。
MAKE_FLAGS += LD="$(TARGET_CC)"

$(eval $(call BuildPackage,openssh))

romfs:
ifeq ($(CONFIG_FIRMWARE_INCLUDE_OPENSSH),y)
	$(INSTALL_DIR) $(ROMFSDIR)/etc_ro/ssh $(ROMFSDIR)/usr/bin $(ROMFSDIR)/usr/sbin $(ROMFSDIR)/usr/libexec
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/moduli $(ROMFSDIR)/etc_ro/ssh/moduli
	for p in scp ssh ssh-keygen; do $(INSTALL_BIN) $(PKG_BUILD_DIR)/$$p $(ROMFSDIR)/usr/bin/$$p; done
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sshd $(ROMFSDIR)/usr/sbin/sshd
	$(INSTALL_BIN) ./sshd.sh $(ROMFSDIR)/usr/bin/sshd.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sshd-session $(ROMFSDIR)/usr/libexec/sshd-session
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sshd-auth $(ROMFSDIR)/usr/libexec/sshd-auth
endif
	$(INSTALL_DIR) $(ROMFSDIR)/usr/libexec
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sftp-server $(ROMFSDIR)/usr/libexec/sftp-server
