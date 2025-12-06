include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Fan Control
LUCI_DEPENDS:=+luci-base +luci-mod-admin-full +uci +luci-lib-jsonc +luci-lib-nixio +luci-lib-ip +luci-theme-bootstrap +kmod-hwmon-pwmfan +kmod-hwmon-gpiofan +kmod-hwmon-emc2305 +kmod-hwmon-gsc
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-fan-control
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Antigravity <antigravity@google.com>

include ../../feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
