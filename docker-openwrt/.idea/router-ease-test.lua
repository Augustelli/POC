module("luci.controller.router-ease", package.seeall)

function index()
    -- Create a top-level menu entry
    entry({"admin", "router-ease"}, firstchild(), "Router Ease GUI", 60).dependent=false

    -- Add submenu entries
    entry({"admin", "router-ease", "network"}, template("router-ease/network"), "Network Settings", 1)
    entry({"admin", "router-ease", "system"}, template("router-ease/system"), "System Settings", 2)
    entry({"admin", "router-ease", "device-information"}, template("router-ease/system"), "Devices Information", 3)
    entry({"admin", "router-ease", "speed-test"}, template("router-ease/speed-test"), "Speed Test", 4)
    entry({"admin", "router-ease", "qr"}, template("router-ease/qr"), "QR", 5)
    entry({"admin", "router-ease", "configurations"}, template("router-ease/configurations"), "Configurations", 6)

    -- API endpoints for AJAX calls
    entry({"admin", "router-ease", "get_network"}, call("get_network_info"))
    entry({"admin", "router-ease", "update_network"}, call("update_network"))
    entry({"admin", "router-ease", "run_speed_test"}, call("run_speed_test"))
    entry({"admin", "router-ease", "get_wifi_info"}, call("get_wifi_info"))
    entry({"admin", "router-ease", "get_uci_config"}, call("get_uci_config"))

end

function get_uci_config()
    local http = require("luci.http")
    local util = require("luci.util")
    local result = {}

    -- Run uci show command to get all configurations
    local cmd = io.popen("uci show")
    if not cmd then
        http.status(500, "Failed to execute command")
        return
    end

    -- Parse the output into a structured format
    for line in cmd:lines() do
        local config, path, value = line:match("([^.]+)%.([^=]+)=(.+)")
        if config and path and value then
            -- Initialize config section if it doesn't exist
            result[config] = result[config] or {}

            -- Remove quotes from values
            value = value:gsub('^"(.-)"$', '%1')

            -- Store in the result
            result[config][path] = value
        end
    end
    cmd:close()

    http.prepare_content("application/json")
    http.write_json(result)
end

function get_network_info()
    local uci = require("luci.model.uci").cursor()
    local network_info = {}

    -- Get all network configurations
    uci:foreach("network", nil, function(section)
        network_info[section[".name"]] = section
    end)

    -- Include additional network info
    network_info["interfaces"] = {}
    local interfaces = io.popen("ip -j addr show")
    if interfaces then
        local output = interfaces:read("*a")
        interfaces:close()
        if output and output ~= "" then
            local json = require("luci.jsonc")
            network_info["interfaces"] = json.parse(output) or {}
        end
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json(network_info)
end

function update_network()
    local uci = require("luci.model.uci").cursor()
    local json = require("luci.jsonc")
    local http = require("luci.http")

    local data = http.content()
    local settings = json.parse(data)

    if not settings or not settings.section or not settings.options then
        http.status(400, "Invalid input")
        return
    end

    -- Update network settings
    for option, value in pairs(settings.options) do
        uci:set("network", settings.section, option, value)
    end

    uci:commit("network")
    os.execute("/etc/init.d/network restart")

    http.prepare_content("application/json")
    http.write_json({success = true})
end

function run_speed_test()
    local http = require("luci.http")
    local result = {}

    -- Using speedtest-netperf with proper error handling
    local cmd = io.popen("speedtest 2>&1")
    if not cmd then
        result = {
            download = "Failed to execute speedtest",
            upload = "Failed to execute speedtest",
            latency = "N/A",
            timestamp = os.date("%Y-%m-%d %H:%M:%S")
        }
    else
        local output = cmd:read("*a")
        cmd:close()

        -- Parse output with flexible pattern matching
        local download = output:match("[Dd]ownload:%s+([%d%.]+)%s+[Mm]bit/s") or
                         output:match("[Dd]ownload:%s+([%d%.]+)%s+[Mm][Bb]ps")
        local upload = output:match("[Uu]pload:%s+([%d%.]+)%s+[Mm]bit/s") or
                       output:match("[Uu]pload:%s+([%d%.]+)%s+[Mm][Bb]ps")
        local latency = output:match("[Ll]atency:%s+([%d%.]+)%s+ms") or
                        output:match("[Pp]ing:%s+([%d%.]+)%s+ms")

        -- Also try to extract server info if available
        local server = output:match("[Ss]erver:%s+(.-)[\r\n]")

        if download and upload then
            result = {
                download = download .. " Mbps",
                upload = upload .. " Mbps",
                latency = latency and (latency .. " ms") or "N/A",
                server = server or "Unknown",
                timestamp = os.date("%Y-%m-%d %H:%M:%S")
            }
        else
            -- If parsing failed, include partial output for debugging
            local error_msg = output:match("Error:[^\n]+") or "Unknown error"
            result = {
                download = "Test failed",
                upload = "Test failed",
                latency = "N/A",
                error = error_msg:sub(1, 100),
                timestamp = os.date("%Y-%m-%d %H:%M:%S")
            }
        end
    end

    http.prepare_content("application/json")
    http.write_json(result)
end

function get_wifi_info()
    local uci = require("luci.model.uci").cursor()
    local http = require("luci.http")
    local wifi_info = {}

    -- Get wireless configurations
    local wireless = uci:get_all("wireless")

    -- Find the first wireless interface that's not disabled
    for k, v in pairs(wireless) do
        if v[".type"] == "wifi-iface" and v.disabled ~= "1" then
            wifi_info = {
                ssid = v.ssid or "",
                encryption = v.encryption or "",
                key = v.key or ""
            }
            break
        end
    end

    http.prepare_content("application/json")
    http.write_json(wifi_info)
end