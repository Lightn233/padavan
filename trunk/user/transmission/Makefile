include $(ROOTDIR)/rules.mk

PKG_NAME:=transmission
PKG_VERSION:=4.1.4
PKG_SOURCE:=transmission-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://github.com/transmission/transmission/releases/download/$(PKG_VERSION)
PKG_HASH:=86e7aa020cdf64826447034bc85f4d3b7c848d8c0891d9dc9b9fddfb2c805d22
CMAKE_BINARY_SUBDIR:=build

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# 复用固件的 TLS 和 curl；无桌面界面，仅构建守护进程和远程控制客户端。
CMAKE_OPTIONS += -DENABLE_DAEMON=ON -DENABLE_CLI=OFF -DENABLE_UTILS=OFF \
	-DENABLE_GTK=OFF -DENABLE_QT=OFF -DENABLE_MAC=OFF -DENABLE_NLS=OFF \
	-DENABLE_TESTS=OFF -DINSTALL_DOC=OFF -DINSTALL_WEB=ON -DREBUILD_WEB=OFF \
	-DWITH_SYSTEMD=OFF -DWITH_INOTIFY=ON -DWITH_CRYPTO=openssl \
	-DRUN_CLANG_TIDY=OFF -DUSE_SYSTEM_EVENT2=OFF -DUSE_SYSTEM_DEFLATE=OFF \
	-DUSE_SYSTEM_DHT=OFF -DUSE_SYSTEM_MINIUPNPC=OFF -DUSE_SYSTEM_NATPMP=OFF \
	-DUSE_SYSTEM_UTP=OFF -DUSE_SYSTEM_B64=OFF -DUSE_SYSTEM_PSL=OFF \
	-DCMAKE_EXE_LINKER_FLAGS="$(TARGET_LDFLAGS) -static-libstdc++ -static-libgcc -Wl,--gc-sections -Wl,-rpath-link,$(STAGING_DIR)/lib"
EXTRA_CFLAGS += -ffunction-sections -fdata-sections -fvisibility=hidden

$(eval $(call BuildPackage,transmission))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin $(ROMFSDIR)/usr/share/transmission/web
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/build/daemon/transmission-daemon $(ROMFSDIR)/usr/bin/transmission-daemon
	$(INSTALL_BIN) ./transmission.sh $(ROMFSDIR)/usr/bin/transmission.sh
	$(CP) $(PKG_BUILD_DIR)/web/public_html/. $(ROMFSDIR)/usr/share/transmission/web/
