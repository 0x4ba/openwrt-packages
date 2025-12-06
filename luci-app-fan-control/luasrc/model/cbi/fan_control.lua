local fs = require "nixio.fs"

m = Map("fan_control", translate("Fan Control"), translate("Control fan speed based on temperature"))

-- Basic settings
s = m:section(TypedSection, "fan_control", translate("Settings"))
s.anonymous = true
s.addremove = false

e = s:option(Flag, "enabled", translate("Enable"))
e.rmempty = false
e.description = translate("Enable automatic fan control")

-- Scan for sensors and fans
local sensors = {}
local fans = {}

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

fan = s:option(ListValue, "fan", translate("Fan Device"))
for path, name in pairs(fans) do
    fan:value(path, name)
end

-- Temperature to fan speed mapping
mapping = m:section(TypedSection, "map", translate("Temperature to Fan Speed"))
mapping.addremove = true
mapping.anonymous = false
mapping.template = "cbi/tblsection"
mapping.sortable = true

temp = mapping:option(Value, "temperature", translate("Temperature (°C)"))
temp.rmempty = false
temp.datatype = "uinteger"

speed = mapping:option(Value, "speed", translate("Fan Speed (0-255)"))
speed.rmempty = false
speed.datatype = "range(0, 255)"

return m
