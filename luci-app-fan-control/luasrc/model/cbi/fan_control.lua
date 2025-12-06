local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()

m = Map("fan_control", translate("Fan Control"),
	translate("Automatically control fan speed based on temperature. " ..
	          "The system monitors temperature sensors and adjusts fan PWM values " ..
	          "according to configured thresholds."))

-- ========================================
-- 主配置区域
-- ========================================
s = m:section(TypedSection, "fan_control", translate("Control Settings"))
s.anonymous = true
s.addremove = false

-- 启用开关
e = s:option(Flag, "enabled", translate("Enable Fan Control"))
e.rmempty = false
e.default = "0"
e.description = translate("Enable automatic fan speed control based on temperature readings")

-- 扫描 hwmon 设备
local sensors = {}
local fans = {}

local hwmon_dir = "/sys/class/hwmon"
if fs.access(hwmon_dir) then
	for file in fs.dir(hwmon_dir) do
		if file:match("^hwmon%d+$") then
			local path = hwmon_dir .. "/" .. file
			local name_file = path .. "/name"
			local device_name = "Unknown"

			if fs.access(name_file) then
				local name_content = fs.readfile(name_file)
				if name_content then
					device_name = name_content:gsub("%s+", "")
				end
			end

			-- 检查温度传感器
			local has_temp = false
			if fs.access(path) then
				for subfile in fs.dir(path) do
					if subfile:match("^temp%d+_input$") then
						has_temp = true
						break
					end
				end
			end

			if has_temp then
				sensors[path] = string.format("%s (%s)", device_name, file)
			end

			-- 检查 PWM 风扇
			local has_pwm = false
			if fs.access(path) then
				for subfile in fs.dir(path) do
					if subfile:match("^pwm%d+$") and not subfile:match("_enable$") then
						has_pwm = true
						break
					end
				end
			end

			if has_pwm then
				fans[path] = string.format("%s (%s)", device_name, file)
			end
		end
	end
end

-- 温度传感器选择
sensor = s:option(ListValue, "sensor", translate("Temperature Sensor"))
sensor.rmempty = false
sensor.description = translate("Select the hwmon device to read temperature from")

-- 添加空白占位符或设备列表
if next(sensors) == nil then
	sensor:value("", translate("-- No sensors found --"))
else
	sensor:value("", translate("-- Please select --"))
	for path, name in pairs(sensors) do
		sensor:value(path, name)
	end
end

-- 风扇选择
fan = s:option(ListValue, "fan", translate("PWM Fan Control"))
fan.rmempty = false
fan.description = translate("Select the hwmon device with PWM control for the fan")

if next(fans) == nil then
	fan:value("", translate("-- No PWM fans found --"))
else
	fan:value("", translate("-- Please select --"))
	for path, name in pairs(fans) do
		fan:value(path, name)
	end
end

-- ========================================
-- 温度映射表
-- ========================================
mapping = m:section(TypedSection, "map", translate("Temperature to Fan Speed Mapping"))
mapping.addremove = true
mapping.anonymous = true
mapping.sortable = true
mapping.template = "cbi/tblsection"
mapping.description = translate("Configure temperature thresholds and corresponding fan speeds. " ..
                                 "When the temperature reaches or exceeds a threshold, " ..
                                 "the corresponding PWM value is applied. " ..
                                 "Entries are automatically sorted by temperature.")

-- 温度阈值
temp = mapping:option(Value, "temperature", translate("Temperature (°C)"))
temp.rmempty = false
temp.datatype = "uinteger"
temp.placeholder = "50"
temp.description = translate("Temperature threshold in degrees Celsius (0-150)")

function temp.validate(self, value, section)
	local val = tonumber(value)
	if not val or val < 0 or val > 150 then
		return nil, translate("Temperature must be between 0 and 150")
	end
	return value
end

-- 风扇速度
speed = mapping:option(Value, "speed", translate("Fan Speed (PWM)"))
speed.rmempty = false
speed.datatype = "range(0, 255)"
speed.placeholder = "150"
speed.description = translate("PWM duty cycle value: 0 (off) to 255 (maximum speed)")

function speed.validate(self, value, section)
	local val = tonumber(value)
	if not val or val < 0 or val > 255 then
		return nil, translate("PWM value must be between 0 and 255")
	end
	return value
end

-- ========================================
-- 提交后重启服务
-- ========================================
function m.on_commit(self)
	luci.sys.call("/etc/init.d/fan_control restart >/dev/null 2>&1 &")
end

return m
