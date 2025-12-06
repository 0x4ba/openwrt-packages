module("luci.controller.fan_control", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/fan_control") then
        return
    end

    entry({"admin", "services", "fan_control"}, cbi("fan_control"), _("Fan Control"), 90).dependent = true
    entry({"admin", "services", "fan_control", "status"}, call("get_status")).leaf = true
end

function get_status()
    local uci = require "luci.model.uci".cursor()
    local fs = require "nixio.fs"
    local json = require "luci.jsonc"
    
    local response = {}
    
    -- Get current temperature
    local sensor = uci:get("fan_control", "fan_control", "sensor")
    if sensor and fs.access(sensor) then
        for file in fs.dir(sensor) do
            if file:match("temp%d+_input") then
                local temp_file = sensor .. "/" .. file
                if fs.access(temp_file) then
                    local raw_temp = fs.readfile(temp_file)
                    if raw_temp then
                        local temp_c = tonumber(raw_temp) / 1000
                        response.current_temp = string.format("%.1f", temp_c)
                    end
                end
                break
            end
        end
    end
    
    -- Get current fan speed
    local fan = uci:get("fan_control", "fan_control", "fan")
    if fan and fs.access(fan) then
        for file in fs.dir(fan) do
            if file:match("pwm%d+$") then
                local pwm_file = fan .. "/" .. file
                if fs.access(pwm_file) then
                    local raw_pwm = fs.readfile(pwm_file)
                    if raw_pwm then
                        local pwm_val = tonumber(raw_pwm)
                        -- Assuming PWM is 0-255, convert to percentage
                        local speed_pct = math.floor((pwm_val / 255) * 100)
                        response.current_fan_speed = speed_pct
                    end
                end
                break
            end
        end
    end
    
    response.enabled = uci:get("fan_control", "fan_control", "enabled") == "1"
    response.poll_interval = uci:get("fan_control", "advanced", "poll_interval") or "10"
    
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(response))
end
