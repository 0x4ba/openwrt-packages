module("luci.controller.fan_control", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/fan_control") then
        return
    end

    entry({"admin", "services", "fan_control"}, cbi("fan_control"), _("Fan Control"), 90).dependent = true
end
