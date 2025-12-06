include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Fan Control
LUCI_DEPENDS:=+luci-base +luci-mod-admin-full +uci +luci-lib-jsonc +luci-lib-nixio +luci-lib-ip +kmod-hwmon-pwmfan +kmod-hwmon-gpiofan +kmod-hwmon-gsc
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-fan-control
PKG_VERSION:=1.0
PKG_RELEASE:=4

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Antigravity <antigravity@google.com>

# Set executable permissions for scripts
PKG_FILE_MODES:=/etc/init.d/fan_control:0755 /usr/bin/fan_control.sh:0755

include $(TOPDIR)/feeds/luci/luci.mk

# Override install to include root directory files
define Package/luci-app-fan-control/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luasrc/model/cbi/*.lua $(1)/usr/lib/lua/luci/model/cbi/
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/fan_control.sh $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/fan_control $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/fan_control $(1)/etc/config/
endef

# call BuildPackage - OpenWrt buildroot signature
