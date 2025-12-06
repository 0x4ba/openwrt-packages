local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()

m = Map("fan_control", translate("Fan Control"),
    translate("Control fan speed based on CPU temperature. When temperature reaches or exceeds a threshold, the corresponding fan speed will be applied."))

-- Main control section
s = m:section(TypedSection, "fan_control", translate("Control Settings"))
s.anonymous = true
s.addremove = false

-- Enable switch
e = s:option(Flag, "enabled", translate("Enable Fan Control"))
e.rmempty = false
e.default = "0"
e.description = translate("Enable or disable automatic fan speed control based on temperature")

-- Scan /sys/class/hwmon for sensors and fans
local sensors = {}
local fans = {}

local hwmon_dir = "/sys/class/hwmon"
if fs.access(hwmon_dir) then
    for file in fs.dir(hwmon_dir) do
        if file:match("^hwmon%d+$") then
            local path = hwmon_dir .. "/" .. file
            local name_file = path .. "/name"
            local device_name = "Unknown"

            -- Read device name from 'name' file
            if fs.access(name_file) then
                local name_content = fs.readfile(name_file)
                if name_content then
                    device_name = name_content:gsub("%s+", "")
                end
            end

            -- Check if device has temperature input
            local has_temp = false
            for subfile in fs.dir(path) do
                if subfile:match("^temp%d+_input$") then
                    has_temp = true
                    break
                end
            end

            if has_temp then
                sensors[path] = device_name .. " (" .. file .. ")"
            end

            -- Check if device has PWM control
            local has_pwm = false
            for subfile in fs.dir(path) do
                if subfile:match("^pwm%d+$") and not subfile:match("_enable$") then
                    has_pwm = true
                    break
                end
            end

            if has_pwm then
                fans[path] = device_name .. " (" .. file .. ")"
            end
        end
    end
end

-- Temperature sensor selection
sensor = s:option(ListValue, "sensor", translate("Temperature Sensor"))
sensor.rmempty = false
sensor.description = translate("Select the temperature sensor to monitor")
for path, name in pairs(sensors) do
    sensor:value(path, name)
end

-- Fan device selection
fan = s:option(ListValue, "fan", translate("PWM Fan Control"))
fan.rmempty = false
fan.description = translate("Select the PWM fan device to control")
for path, name in pairs(fans) do
    fan:value(path, name)
end

-- Temperature to fan speed mapping table
mapping = m:section(TypedSection, "map", translate("Temperature to Fan Speed Mapping"))
mapping.addremove = true
mapping.anonymous = false
mapping.template = "cbi/tblsection"
mapping.sortable = true
mapping.description = translate("Define temperature thresholds and corresponding fan speeds. When temperature >= threshold, the fan speed will be set accordingly. Mappings are automatically sorted by temperature.")

-- Custom function to sort by temperature
function mapping.sortedby(self)
    local sections = {}
    uci:foreach("fan_control", "map", function(s)
        table.insert(sections, s[".name"])
    end)

    -- Sort sections by temperature value
    table.sort(sections, function(a, b)
        local temp_a = tonumber(uci:get("fan_control", a, "temperature") or 0)
        local temp_b = tonumber(uci:get("fan_control", b, "temperature") or 0)
        return temp_a < temp_b
    end)

    return sections
end

-- Temperature threshold
temp = mapping:option(Value, "temperature", translate("Temperature (°C)"))
temp.rmempty = false
temp.datatype = "uinteger"
temp.placeholder = "50"
temp.description = translate("Temperature threshold in degrees Celsius")

-- Fan speed (PWM value)
speed = mapping:option(Value, "speed", translate("Fan Speed (PWM)"))
speed.rmempty = false
speed.datatype = "range(0, 255)"
speed.placeholder = "150"
speed.description = translate("PWM value: 0 (off) to 255 (full speed)")

return m
