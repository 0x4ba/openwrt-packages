m = Map("fan_control", translate("Fan Control"), translate("Configure system fan speed based on temperature sensors"))

s = m:section(TypedSection, "fan_control", translate("Settings"))
s.anonymous = true
s.addremove = false

e = s:option(Flag, "enabled", translate("Enable"))
e.rmempty = false

-- Scan for sensors
local sensors = {}
local fans = {}
local sys = require "luci.sys"
local fs = require "nixio.fs"

local hwmon_dir = "/sys/class/hwmon"
if fs.access(hwmon_dir) then
    for file in fs.dir(hwmon_dir) do
        if file:match("hwmon%d+") then
            local path = hwmon_dir .. "/" .. file
            local name_file = path .. "/name"
            local name = "Unknown"
            if fs.access(name_file) then
                name = fs.readfile(name_file)
                if name then
                    name = name:gsub("\n", "")
                end
            end
            
            -- Check for temp input
            -- We assume if it has temp*_input it can be a sensor
            -- And if it has pwm* it can be a fan
            -- This is a simplification, but fits the requirement
            
            -- Check for any temp input
            local has_temp = false
            for subfile in fs.dir(path) do
                if subfile:match("temp%d+_input") then
                    has_temp = true
                    break
                end
            end
            
            if has_temp then
                sensors[path] = name .. " (" .. file .. ")"
            end
            
            -- Check for any pwm output
            local has_pwm = false
            for subfile in fs.dir(path) do
                if subfile:match("pwm%d+") then
                    has_pwm = true
                    break
                end
            end
            
            if has_pwm then
                fans[path] = name .. " (" .. file .. ")"
            end
        end
    end
end

sensor = s:option(ListValue, "sensor", translate("Temperature Sensor"))
for path, name in pairs(sensors) do
    sensor:value(path, name)
end

fan = s:option(ListValue, "fan", translate("Fan"))
for path, name in pairs(fans) do
    fan:value(path, name)
end

return m
