module("luci.controller.fan_control", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/fan_control") then
		return
	end

	-- 使用原生 CBI 组件，无需自定义 HTML 和 REST API
	entry({"admin", "services", "fan_control"},
	      cbi("fan_control"),
	      _("Fan Control"),
	      90).dependent = true
end
