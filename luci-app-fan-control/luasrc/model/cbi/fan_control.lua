local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"

m = Map("fan_control", translate("Fan Control"),
	translate("Automatically control fan speed based on temperature. " ..
	          "The system monitors temperature sensors and adjusts fan PWM values or GPIO " ..
	          "according to configured thresholds. Supports multiple fan groups."))

-- ========================================
-- 风扇控制组配置
-- ========================================
s = m:section(TypedSection, "fan_group", translate("Fan Control Groups"))
s.anonymous = true
s.addremove = true
s.sortable = true
s.template = "cbi/tblsection"
s.description = translate("Configure multiple fan control groups. Each group can control one fan based on one temperature sensor.")

-- 启用开关
e = s:option(Flag, "enabled", translate("Enable"))
e.rmempty = false
e.default = "0"
e.width = "5%"

-- 组名称
name = s:option(Value, "name", translate("Name"))
name.rmempty = false
name.placeholder = "Fan 1"
name.description = translate("Descriptive name for this fan control group")
name.width = "15%"

-- 风扇类型选择
fan_type = s:option(ListValue, "fan_type", translate("Fan Type"))
fan_type.rmempty = false
fan_type.default = "pwm"
fan_type:value("pwm", translate("PWM Fan (Multiple speeds)"))
fan_type:value("dc", translate("DC Fan (On/Off via GPIO)"))
fan_type.description = translate("PWM fans support multiple speed levels. DC fans are controlled via GPIO (on/off only).")
fan_type.width = "20%"

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

-- 扫描可用的 GPIO
local gpios = {}
local gpio_dir = "/sys/class/gpio"
if fs.access(gpio_dir) then
	-- 扫描已导出的 GPIO
	for file in fs.dir(gpio_dir) do
		if file:match("^gpio%d+$") then
			local gpio_num = file:match("^gpio(%d+)$")
			if gpio_num then
				gpios[gpio_num] = string.format("GPIO %s", gpio_num)
			end
		end
	end

	-- 添加 gpiochip 信息供参考
	local gpiochip_base = {}
	for file in fs.dir(gpio_dir) do
		if file:match("^gpiochip%d+$") then
			local base_file = gpio_dir .. "/" .. file .. "/base"
			local ngpio_file = gpio_dir .. "/" .. file .. "/ngpio"
			if fs.access(base_file) and fs.access(ngpio_file) then
				local base = tonumber(fs.readfile(base_file))
				local ngpio = tonumber(fs.readfile(ngpio_file))
				if base and ngpio then
					table.insert(gpiochip_base, string.format("%s: GPIO %d-%d", file, base, base + ngpio - 1))
				end
			end
		end
	end
end

-- 温度传感器选择
sensor = s:option(ListValue, "sensor", translate("Sensor"))
sensor.rmempty = false
sensor.description = translate("Select the hwmon device to read temperature from")
sensor.width = "20%"

if next(sensors) == nil then
	sensor:value("", translate("-- No sensors found --"))
else
	sensor:value("", translate("-- Please select --"))
	for path, name in pairs(sensors) do
		sensor:value(path, name)
	end
end

-- PWM 风扇选择（仅在 fan_type=pwm 时显示）
fan = s:option(ListValue, "fan", translate("PWM Fan"))
fan.rmempty = false
fan.description = translate("Select the hwmon device with PWM control for the fan")
fan.width = "20%"
fan:depends("fan_type", "pwm")

if next(fans) == nil then
	fan:value("", translate("-- No PWM fans found --"))
else
	fan:value("", translate("-- Please select --"))
	for path, name in pairs(fans) do
		fan:value(path, name)
	end
end

-- GPIO 选择（仅在 fan_type=dc 时显示）
gpio = s:option(Value, "gpio", translate("GPIO Number"))
gpio.rmempty = false
gpio.datatype = "uinteger"
gpio.placeholder = "例如: 17"
gpio.description = translate("GPIO pin number to control the DC fan (e.g., 17 for GPIO17)")
gpio.width = "10%"
gpio:depends("fan_type", "dc")

-- GPIO 有效电平
gpio_active_high = s:option(ListValue, "gpio_active_high", translate("Active"))
gpio_active_high.rmempty = false
gpio_active_high.default = "1"
gpio_active_high:value("1", translate("High (1=On)"))
gpio_active_high:value("0", translate("Low (0=On)"))
gpio_active_high.description = translate("GPIO active level: High means GPIO=1 turns fan on")
gpio_active_high.width = "10%"
gpio_active_high:depends("fan_type", "dc")

-- 直流风扇触发温度（仅在 fan_type=dc 时显示）
trigger_temp = s:option(Value, "trigger_temp", translate("Trigger Temp"))
trigger_temp.rmempty = false
trigger_temp.datatype = "uinteger"
trigger_temp.placeholder = "50"
trigger_temp.description = translate("Temperature (°C) at which the DC fan turns on")
trigger_temp.width = "10%"
trigger_temp:depends("fan_type", "dc")

function trigger_temp.validate(self, value, section)
	local val = tonumber(value)
	if not val or val < 0 or val > 150 then
		return nil, translate("Temperature must be between 0 and 150")
	end
	return value
end

-- ========================================
-- 温度映射表（仅用于 PWM 风扇）
-- ========================================
mapping = m:section(TypedSection, "map", translate("Temperature to PWM Speed Mapping (PWM Fans Only)"))
mapping.addremove = true
mapping.anonymous = true
mapping.sortable = true
mapping.template = "cbi/tblsection"
mapping.description = translate("Configure temperature thresholds and corresponding fan speeds for PWM fans. " ..
                                 "When the temperature reaches or exceeds a threshold, " ..
                                 "the corresponding PWM value is applied. " ..
                                 "Each mapping belongs to a specific fan group.")

-- 所属组选择
group_ref = mapping:option(ListValue, "group", translate("Fan Group"))
group_ref.rmempty = false
group_ref.description = translate("Select which fan group this mapping applies to")

-- 动态添加所有 PWM 类型的风扇组
uci:foreach("fan_control", "fan_group", function(section)
	local section_name = section[".name"]
	local display_name = section.name or section_name
	local fan_type_val = section.fan_type or "pwm"

	-- 只显示 PWM 类型的组
	if fan_type_val == "pwm" then
		group_ref:value(section_name, display_name .. " (" .. section_name .. ")")
	end
end)

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
