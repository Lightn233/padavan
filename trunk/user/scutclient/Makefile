include $(ROOTDIR)/rules.mk

PKG_NAME:=scutclient
PKG_VERSION:=a589968
PKG_SOURCE:=scutclient-a58996875c61d0cdf8ec435057befc1c87bd6863.tar.gz
PKG_HASH:=b4a572884782cc46651a19fe5fba8a1b87a4cec257d2d6f479a4c74ee0e074d5

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	mkdir -p "$(DL_DIR)"
	[ -f "$(DL_DIR)/$(PKG_SOURCE)" ] || cp "$(CURDIR)/$(PKG_SOURCE)" "$(DL_DIR)/$(PKG_SOURCE)"
	printf '%s  %s\n' '$(PKG_HASH)' '$(DL_DIR)/$(PKG_SOURCE)' | sha256sum -c -
	tar -xf '$(DL_DIR)/$(PKG_SOURCE)' --strip-components=1 -C '$(PKG_BUILD_DIR)'
	$(Build/Patch)
endef

define Build/Configure
	cmake -S $(PKG_BUILD_DIR) -B $(PKG_BUILD_DIR)/build \
		-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=mips -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_C_COMPILER="$(TARGET_CC)" -DCMAKE_C_FLAGS="$(TARGET_CFLAGS) -std=gnu11" \
		-DCMAKE_EXE_LINKER_FLAGS="$(TARGET_LDFLAGS)" -DCMAKE_BUILD_TYPE=Release
endef
define Build/Compile
	cmake --build $(PKG_BUILD_DIR)/build --parallel $(HOST_NCPU)
endef

$(eval $(call BuildPackage,scutclient))
$(STAMP_PREPARED): Makefile $(wildcard patches/*.patch)

romfs: $(STAMP_BUILT)
	$(ROMFSINST) $(CURDIR)/scripts/ /usr/bin/
	$(ROMFSINST) $(PKG_BUILD_DIR)/build/scutclient /usr/bin/bin_scutclient
