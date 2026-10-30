TOPDIR       = ${CURDIR}
SOURCE_DIR   = $(TOPDIR)/trunk
TEMPLATE_DIR = $(SOURCE_DIR)/configs/templates
PRODUCTS     = $(shell ls $(TEMPLATE_DIR) | sed 's/.config//g')
CONFIG       = $(SOURCE_DIR)/.config
TOOLCHAIN    := mipsel-linux-musl

all: build

# 配置菜单只保存个人选择，编译仍由 make <机型> 启动。
.PHONY: menuconfig config-show
menuconfig:
	@python3 scripts/build_config.py --menu "$(MODEL)"

config-show:
	@python3 scripts/build_config.py --show "$(MODEL)"

build:
	$(MAKE) -C $(TOPDIR)/toolchain download CT_TARGET=$(TOOLCHAIN)
	@if [ ! -f $(CONFIG) ]; then \
		echo "Please run 'make PRODUCT_NAME' to start build!"; \
		echo "Supported products: $(PRODUCTS)"; \
		exit 1; \
	fi
	$(MAKE) -C $(SOURCE_DIR)

clean:
	@if [ ! -f $(CONFIG) ]; then \
		echo "Project config file .config not found! Terminate."; \
		exit 1; \
	fi
	$(MAKE) -C $(SOURCE_DIR) clean
	@rm -f $(CONFIG)

.PHONY: $(PRODUCTS)
$(PRODUCTS):
	@echo "Preparing product $@"
	@python3 scripts/build_config.py --check-transition "$@"
	cp -f $(TEMPLATE_DIR)/$(@).config $(CONFIG)
	@echo 'CONFIG_BUILD_MODEL="$@"' >> $(CONFIG)
	@echo "CONFIG_CROSS_COMPILER_ROOT=$(TOPDIR)/toolchain/toolchain-mipsel" >> $(CONFIG)
	@echo "CONFIG_TOOLCHAIN=$(TOOLCHAIN)" >> $(CONFIG)
	@echo "CONFIG_CCACHE=y" >> $(CONFIG)
	# Apply overrides (if any) and normalize .config
	@./scripts/apply_overrides.sh $@ 
	@$(MAKE) build
