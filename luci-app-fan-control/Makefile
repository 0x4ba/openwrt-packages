include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Fan Control
LUCI_DEPENDS:=+luci-base +luci-mod-admin-full +uci +luci-lib-jsonc +luci-lib-nixio +luci-lib-ip +kmod-hwmon-pwmfan +kmod-hwmon-gpiofan +kmod-hwmon-gsc
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-fan-control
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Antigravity <antigravity@google.com>

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/fan_control.sh $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/fan_control $(1)/etc/init.d/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/fan_control $(1)/etc/config/
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
