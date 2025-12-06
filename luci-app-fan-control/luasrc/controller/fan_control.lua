module("luci.controller.fan_control", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/fan_control") then
        return
    end

    entry({"admin", "services", "fan_control"}, cbi("fan_control"), _("Fan Control"), 90).dependent = true
    entry({"admin", "services", "fan_control", "status"}, call("get_status")).leaf = true
    entry({"admin", "services", "fan_control", "add_map"}, call("add_map")).leaf = true
    entry({"admin", "services", "fan_control", "delete_map"}, call("delete_map")).leaf = true
    entry({"admin", "services", "fan_control", "list_map"}, call("list_map")).leaf = true
end

function get_status()
    local uci = require "luci.model.uci".cursor()
    local fs = require "nixio.fs"
    local json = require "luci.jsonc"
    
    local response = {}
    
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
    
    local fan = uci:get("fan_control", "fan_control", "fan")
    if fan and fs.access(fan) then
        for file in fs.dir(fan) do
            if file:match("pwm%d+$") then
                local pwm_file = fan .. "/" .. file
                if fs.access(pwm_file) then
                    local raw_pwm = fs.readfile(pwm_file)
                    if raw_pwm then
                        local pwm_val = tonumber(raw_pwm)
                        local speed_pct = math.floor((pwm_val / 255) * 100)
                        response.current_fan_speed = speed_pct
                    end
                end
                break
            end
        end
    end
    
    response.enabled = uci:get("fan_control", "fan_control", "enabled") == "1"
    
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(response))
end

function list_map()
    local uci = require "luci.model.uci".cursor()
    local json = require "luci.jsonc"
    
    local maps = {}
    uci:foreach("fan_control", "map", function(section)
        table.insert(maps, {
            idx = section['.name'],
            temperature = section.temperature,
            speed = section.speed
        })
    end)
    
    -- Sort by temperature
    table.sort(maps, function(a, b)
        return tonumber(a.temperature or 0) < tonumber(b.temperature or 0)
    end)
    
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify({maps = maps}))
end

function add_map()
    local uci = require "luci.model.uci".cursor()
    local json = require "luci.jsonc"
    local temp = luci.http.formvalue("temperature")
    local speed = luci.http.formvalue("speed")
    
    if not temp or not speed then
        luci.http.prepare_content("application/json")
        luci.http.write(json.stringify({success = false, error = "Missing temperature or speed"}))
        return
    end
    
    temp = tonumber(temp)
    speed = tonumber(speed)
    
    if not temp or not speed or temp < 0 or speed < 0 or speed > 255 then
        luci.http.prepare_content("application/json")
        luci.http.write(json.stringify({success = false, error = "Invalid values"}))
        return
    end
    
    -- Generate unique ID
    local id = "map_" .. temp .. "_" .. math.floor(os.time() % 10000)
    
    uci:set("fan_control", id, "map")
    uci:set("fan_control", id, "temperature", tostring(temp))
    uci:set("fan_control", id, "speed", tostring(speed))
    uci:commit("fan_control")
    
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify({success = true, id = id}))
end

function delete_map()
    local uci = require "luci.model.uci".cursor()
    local json = require "luci.jsonc"
    local idx = luci.http.formvalue("idx")
    
    if not idx then
        luci.http.prepare_content("application/json")
        luci.http.write(json.stringify({success = false, error = "Missing index"}))
        return
    end
    
    uci:delete("fan_control", idx)
    uci:commit("fan_control")
    
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify({success = true}))
end


