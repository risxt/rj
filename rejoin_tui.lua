#!/data/data/com.termux/files/usr/bin/lua
--[[
    ROBLOX TUI DASHBOARD v4.0
    Termux Multi-Instance Auto-Rejoin with Visual Interface
    Usage: lua rejoin_tui.lua <PS_LINK>
]]

-- ============================================================
-- ANSI CODES
-- ============================================================
local A = {
    RESET = "\27[0m",
    CLEAR = "\27[2J",
    HOME = "\27[H",
    HIDE = "\27[?25l",
    SHOW = "\27[?25h",
    BOLD = "\27[1m",
    DIM = "\27[2m",
    RED = "\27[31m",
    GREEN = "\27[32m",
    YELLOW = "\27[33m",
    CYAN = "\27[36m",
    MAGENTA = "\27[35m"
}

-- ============================================================
-- CONFIG
-- ============================================================
local REFRESH = 3
local MAX_LOG = 6

-- ============================================================
-- STATE
-- ============================================================
local State = {
    running = true,
    start = os.time(),
    packages = {},
    data = {},
    logs = {},
    deep_link = "",
    crashes = 0
}

-- ============================================================
-- UTILS
-- ============================================================
local function trim(s)
    return s and s:gsub("^%s*(.-)%s*$", "%1") or ""
end

local function exec(cmd)
    local h = io.popen(cmd .. " 2>/dev/null")
    if not h then return "" end
    local r = h:read("*a") or ""
    h:close()
    return trim(r)
end

local function su(cmd)
    return exec("su -c '" .. cmd:gsub("'", "'\\''") .. "'")
end

local function log(msg)
    table.insert(State.logs, 1, os.date("%H:%M:%S") .. " " .. msg)
    if #State.logs > MAX_LOG then table.remove(State.logs) end
end

-- ============================================================
-- TUI
-- ============================================================
local function clear()
    io.write(A.CLEAR .. A.HOME)
    io.flush()
end

local function draw()
    clear()
    
    -- Header
    local up = os.difftime(os.time(), State.start)
    local uptime = string.format("%02d:%02d:%02d", math.floor(up/3600), math.floor(up%3600/60), up%60)
    
    print(A.BOLD .. A.CYAN .. "  ROBLOX MULTI-INSTANCE CONTROLLER v4.0" .. A.RESET)
    print(A.DIM .. string.rep("-", 50) .. A.RESET)
    print(string.format("  Uptime: %s%s%s  |  Instances: %s%d%s  |  Crashes: %s%d%s",
        A.YELLOW, uptime, A.RESET,
        A.GREEN, #State.packages, A.RESET,
        State.crashes > 0 and A.RED or A.GREEN, State.crashes, A.RESET
    ))
    print(A.DIM .. string.rep("-", 50) .. A.RESET)
    print("")
    
    -- Instance table
    print(A.BOLD .. string.format("  %-25s %-10s %-8s %-6s", "PACKAGE", "STATUS", "PID", "CRASH") .. A.RESET)
    print(A.DIM .. "  " .. string.rep("-", 48) .. A.RESET)
    
    for _, pkg in ipairs(State.packages) do
        local d = State.data[pkg] or {}
        local status = d.status or "waiting"
        local pid = d.pid or "-"
        local cr = d.crashes or 0
        
        local scol = status == "running" and A.GREEN or (status == "crashed" and A.RED or A.YELLOW)
        local icon = status == "running" and "●" or (status == "crashed" and "✗" or "○")
        
        print(string.format("  %s%-25s %s%-10s%s %-8s %s%d%s",
            scol, icon .. " " .. pkg:sub(1,22), scol, status:upper(), A.RESET,
            A.DIM .. pid .. A.RESET,
            cr > 0 and A.RED or A.DIM, cr, A.RESET
        ))
    end
    
    -- Log window
    print("")
    print(A.DIM .. "  " .. string.rep("-", 48) .. A.RESET)
    print(A.BOLD .. "  LOG" .. A.RESET)
    for i = MAX_LOG, 1, -1 do
        print("  " .. A.DIM .. (State.logs[i] or "") .. A.RESET)
    end
    
    -- Footer
    print("")
    print(A.DIM .. "  Ctrl+C to stop" .. A.RESET)
    print(A.DIM .. "  " .. State.deep_link:sub(1, 48) .. A.RESET)
end

-- ============================================================
-- CORE
-- ============================================================
local function parse_link(url)
    local pid = url:match("/games/(%d+)")
    local code = url:match("privateServerLinkCode=(%d+)") or url:match("code=(%d+)")
    return pid, code
end

local function scan_packages()
    local out = su("pm list packages")
    local pkgs = {}
    for line in out:gmatch("[^\r\n]+") do
        local p = line:match("package:(.+)")
        if p and p:lower():find("roblox") then
            table.insert(pkgs, trim(p))
            State.data[trim(p)] = State.data[trim(p)] or {status="waiting", crashes=0, pid=nil}
        end
    end
    return pkgs
end

local function is_running(pkg)
    local pid = su("pidof " .. pkg)
    return pid ~= "", pid
end

local function launch(pkg)
    su("am force-stop " .. pkg)
    os.execute("sleep 1")
    su('am start -a android.intent.action.VIEW -d "' .. State.deep_link .. '" -p ' .. pkg)
    State.data[pkg].status = "relaunch"
    log(A.YELLOW .. "Launched " .. pkg .. A.RESET)
end

-- ============================================================
-- MAIN
-- ============================================================
local function main()
    io.write(A.HIDE)
    
    -- Parse link
    local url = arg[1]
    if not url or url == "" then
        clear()
        print(A.BOLD .. "ROBLOX TUI CONTROLLER" .. A.RESET)
        print("")
        io.write("Paste PS URL: ")
        io.flush()
        url = io.read()
    end
    
    local pid, code = parse_link(url)
    if not pid or not code then
        log("Invalid URL!")
        draw()
        io.write(A.SHOW)
        return
    end
    
    State.deep_link = "roblox://placeId=" .. pid .. "&linkCode=" .. code
    log("Deep link: " .. State.deep_link:sub(1, 40) .. "...")
    
    -- Scan
    State.packages = scan_packages()
    if #State.packages == 0 then
        log("No Roblox packages found!")
        draw()
        io.write(A.SHOW)
        return
    end
    log("Found " .. #State.packages .. " package(s)")
    
    -- Initial launch
    for _, pkg in ipairs(State.packages) do
        launch(pkg)
        os.execute("sleep 10")
    end
    os.execute("sleep 3")
    
    -- Monitor loop
    while State.running do
        for _, pkg in ipairs(State.packages) do
            local d = State.data[pkg]
            local alive, p = is_running(pkg)
            
            if alive then
                if d.status ~= "running" then
                    log(A.GREEN .. pkg .. " running" .. A.RESET)
                end
                d.status = "running"
                d.pid = p
            else
                if d.status == "running" then
                    d.status = "crashed"
                    d.crashes = d.crashes + 1
                    State.crashes = State.crashes + 1
                    log(A.RED .. pkg .. " crashed!" .. A.RESET)
                end
                
                -- Backoff: wait if crashed too much
                if d.crashes < 5 then
                    launch(pkg)
                else
                    d.status = "waiting"
                    log(A.YELLOW .. pkg .. " too many crashes, skipping" .. A.RESET)
                end
            end
        end
        
        draw()
        os.execute("sleep " .. REFRESH)
    end
end

-- ============================================================
-- ENTRY
-- ============================================================
local ok, err = xpcall(main, function(e)
    io.write(A.SHOW)
    clear()
    print(A.RED .. "ERROR: " .. tostring(e) .. A.RESET)
    for _, pkg in pairs(State.packages) do
        su("am force-stop " .. pkg)
    end
    return e
end)

if not ok then
    io.write(A.SHOW)
    os.exit(1)
end

io.write(A.SHOW)
