module("luci.controller.fan_control", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/fan_control") then
        return
    end

    local page = entry({"admin", "services", "fan_control"}, call("index_page"), _("Fan Control"), 90)
    page.dependent = true

    local get_dev = entry({"admin", "services", "fan_control", "get_devices"}, call("get_devices"))
    get_dev.leaf = true

    local get_cfg = entry({"admin", "services", "fan_control", "get_config"}, call("get_config"))
    get_cfg.leaf = true

    local save_cfg = entry({"admin", "services", "fan_control", "save_config"}, call("save_config"))
    save_cfg.leaf = true

    local list = entry({"admin", "services", "fan_control", "list_map"}, call("list_map"))
    list.leaf = true

    local add = entry({"admin", "services", "fan_control", "add_map"}, call("add_map"))
    add.leaf = true

    local del = entry({"admin", "services", "fan_control", "delete_map"}, call("delete_map"))
    del.leaf = true
end

function index_page()
    luci.template.render("fan_control/index")
end

function get_devices()
    local fs = require "nixio.fs"
    local json = require "luci.jsonc"

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

                -- Check for temperature sensors
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
                    sensors[path] = device_name .. " (" .. file .. ")"
                end

                -- Check for PWM fans
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
                    fans[path] = device_name .. " (" .. file .. ")"
                end
            end
        end
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({sensors = sensors, fans = fans})
end

function get_config()
    local uci = require "luci.model.uci".cursor()
    local json = require "luci.jsonc"

    local config = {
        enabled = uci:get("fan_control", "fan_control", "enabled") or "0",
        sensor = uci:get("fan_control", "fan_control", "sensor") or "",
        fan = uci:get("fan_control", "fan_control", "fan") or ""
    }

    luci.http.prepare_content("application/json")
    luci.http.write_json(config)
end

function save_config()
    local uci = require "luci.model.uci".cursor()
    local json = require "luci.jsonc"

    local enabled = luci.http.formvalue("enabled")
    local sensor = luci.http.formvalue("sensor")
    local fan = luci.http.formvalue("fan")

    uci:set("fan_control", "fan_control", "enabled", enabled or "0")
    uci:set("fan_control", "fan_control", "sensor", sensor or "")
    uci:set("fan_control", "fan_control", "fan", fan or "")
    uci:commit("fan_control")

    -- Reload the service
    os.execute("/etc/init.d/fan_control restart >/dev/null 2>&1 &")

    luci.http.prepare_content("application/json")
    luci.http.write_json({success = true})
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
    luci.http.write_json({maps = maps})
end

function add_map()
    local uci = require "luci.model.uci".cursor()
    local json = require "luci.jsonc"
    local temp = luci.http.formvalue("temperature")
    local speed = luci.http.formvalue("speed")

    if not temp or not speed then
        luci.http.prepare_content("application/json")
        luci.http.write_json({success = false, error = "Missing temperature or speed"})
        return
    end

    temp = tonumber(temp)
    speed = tonumber(speed)

    if not temp or not speed or temp < 0 or speed < 0 or speed > 255 then
        luci.http.prepare_content("application/json")
        luci.http.write_json({success = false, error = "Invalid values"})
        return
    end

    -- Generate unique ID
    local id = "map_" .. temp .. "_" .. math.floor(os.time() % 10000)

    uci:set("fan_control", id, "map")
    uci:set("fan_control", id, "temperature", tostring(temp))
    uci:set("fan_control", id, "speed", tostring(speed))
    uci:commit("fan_control")

    -- Reload the service
    os.execute("/etc/init.d/fan_control reload >/dev/null 2>&1 &")

    luci.http.prepare_content("application/json")
    luci.http.write_json({success = true, id = id})
end

function delete_map()
    local uci = require "luci.model.uci".cursor()
    local json = require "luci.jsonc"
    local idx = luci.http.formvalue("idx")

    if not idx then
        luci.http.prepare_content("application/json")
        luci.http.write_json({success = false, error = "Missing index"})
        return
    end

    uci:delete("fan_control", idx)
    uci:commit("fan_control")

    -- Reload the service
    os.execute("/etc/init.d/fan_control reload >/dev/null 2>&1 &")

    luci.http.prepare_content("application/json")
    luci.http.write_json({success = true})
end


