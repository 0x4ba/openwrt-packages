local sys = require "luci.sys"
local fs = require "nixio.fs"

m = Map("fan_control", translate("Fan Control"), translate("Configure system fan speed based on temperature sensors"))

-- Status section
status = m:section(NamedSection, "status", "status", translate("Status"))
status.addremove = false

current_temp = status:option(DummyValue, "current_temp", translate("Current Temperature"))
current_temp.rawhtml = true
function current_temp.cfgvalue()
    local temp_file = "/tmp/fan_control_temp"
    if fs.access(temp_file) then
        return fs.readfile(temp_file):gsub("\n", "") .. " °C"
    end
    return "N/A"
end

current_fan_speed = status:option(DummyValue, "current_fan_speed", translate("Current Fan Speed"))
current_fan_speed.rawhtml = true
function current_fan_speed.cfgvalue()
    local speed_file = "/tmp/fan_control_speed"
    if fs.access(speed_file) then
        return fs.readfile(speed_file):gsub("\n", "") .. " %"
    end
    return "N/A"
end

-- Settings section
s = m:section(TypedSection, "fan_control", translate("Basic Settings"))
s.anonymous = true
s.addremove = false

e = s:option(Flag, "enabled", translate("Enable Fan Control"))
e.rmempty = false
e.description = translate("Enable or disable automatic fan control")

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
sensor.description = translate("Select the temperature sensor to monitor")
for path, name in pairs(sensors) do
    sensor:value(path, name)
end

fan = s:option(ListValue, "fan", translate("Fan Device"))
fan.description = translate("Select the fan device to control")
for path, name in pairs(fans) do
    fan:value(path, name)
end

-- Temperature thresholds section
therm = m:section(TypedSection, "thermal", translate("Temperature Thresholds"))
therm.addremove = true
therm.anonymous = false
therm.template = "cbi/tblsection"

therm_name = therm:option(Value, "name", translate("Profile Name"))
therm_name.rmempty = false

therm_target = therm:option(Value, "target_temp", translate("Target Temperature (°C)"))
therm_target.rmempty = false
therm_target.datatype = "uinteger"
therm_target.description = translate("Temperature at which to adjust fan speed")

therm_min_speed = therm:option(Value, "min_speed", translate("Minimum Speed (%)"))
therm_min_speed.rmempty = false
therm_min_speed.datatype = "range(0, 100)"
therm_min_speed.description = translate("Minimum fan speed percentage")

therm_max_speed = therm:option(Value, "max_speed", translate("Maximum Speed (%)"))
therm_max_speed.rmempty = false
therm_max_speed.datatype = "range(0, 100)"
therm_max_speed.description = translate("Maximum fan speed percentage")

-- Fan speed levels section
levels = m:section(TypedSection, "speed_level", translate("Fan Speed Levels"))
levels.addremove = true
levels.anonymous = false
levels.template = "cbi/tblsection"

level_name = levels:option(Value, "name", translate("Level Name"))
level_name.rmempty = false

level_speed = levels:option(Value, "speed", translate("Speed (%)"))
level_speed.rmempty = false
level_speed.datatype = "range(0, 100)"

level_temp_min = levels:option(Value, "temp_min", translate("Min Temp (°C)"))
level_temp_min.rmempty = false
level_temp_min.datatype = "uinteger"

level_temp_max = levels:option(Value, "temp_max", translate("Max Temp (°C)"))
level_temp_max.rmempty = false
level_temp_max.datatype = "uinteger"

-- Advanced settings section
adv = m:section(TypedSection, "advanced", translate("Advanced Settings"))
adv.anonymous = true
adv.addremove = false

poll_interval = adv:option(Value, "poll_interval", translate("Poll Interval (seconds)"))
poll_interval.rmempty = false
poll_interval.datatype = "uinteger"
poll_interval.default = 10
poll_interval.description = translate("How often to check temperature")

hysteresis = adv:option(Value, "hysteresis", translate("Temperature Hysteresis (°C)"))
hysteresis.rmempty = false
hysteresis.datatype = "uinteger"
hysteresis.default = 2
hysteresis.description = translate("Prevent rapid fan speed changes")

return m
