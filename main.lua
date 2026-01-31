#!/data/data/com.termux/files/usr/bin/lua
--[[
    ROBLOX MULTI-TOOL v5.0
    Unified: Auto-Rejoin TUI + Cookie Injector
    For Termux (Rooted Android)
    
    Usage: lua main.lua
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
    BLUE = "\27[34m",
    MAGENTA = "\27[35m",
    CYAN = "\27[36m"
}

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    -- Rejoin settings
    REFRESH = 3,
    MAX_LOG = 6,
    LAUNCH_DELAY = 20,  -- 20 detik per instance
    
    -- Cookie settings
    HOST_KEY = ".roblox.com",
    COOKIE_NAME = ".ROBLOSECURITY",
    COOKIE_PATH = "/",
    EXPIRY_DAYS = 365,
    IS_SECURE = 1,
    IS_HTTPONLY = 1,
    DB_PATH_TEMPLATE = "/data/data/%s/app_webview/Default/Cookies",
    WEBVIEW_DIR_TEMPLATE = "/data/data/%s/app_webview/Default",
}

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
    local h = io.popen(cmd .. " 2>&1")
    if not h then return "", false end
    local r = h:read("*a") or ""
    local ok = h:close()
    return trim(r), ok
end

local function su(cmd)
    local termux_bin = "/data/data/com.termux/files/usr/bin"
    local termux_lib = "/data/data/com.termux/files/usr/lib"
    
    -- Export PATH and LD_LIBRARY_PATH so Termux binaries can run and find their libraries
    local env = string.format("export PATH=%s:$PATH; export LD_LIBRARY_PATH=%s;", termux_bin, termux_lib)
    
    local escaped = cmd:gsub("'", "'\\''")
    -- Run through su with proper environment
    return exec(string.format('su -c "%s %s"', env, escaped))
end

local function log(msg)
    table.insert(State.logs, 1, os.date("%H:%M:%S") .. " " .. msg)
    if #State.logs > CONFIG.MAX_LOG then table.remove(State.logs) end
end

local function print_log(level, msg)
    local colors = {INFO = A.CYAN, OK = A.GREEN, WARN = A.YELLOW, ERR = A.RED}
    print(string.format("%s[%s]%s %s", colors[level] or A.RESET, level, A.RESET, msg))
end

local function clear()
    io.write(A.CLEAR .. A.HOME)
    io.flush()
end

local function pause()
    io.write("\n" .. A.DIM .. "Tekan Enter untuk lanjut..." .. A.RESET)
    io.flush()
    io.read()
end

-- ============================================================
-- PACKAGE SCANNER
-- ============================================================
local function scan_packages()
    local out = su("pm list packages")
    local pkgs = {}
    for line in out:gmatch("[^\r\n]+") do
        local p = line:match("package:(.+)")
        if p and p:lower():find("roblox") then
            table.insert(pkgs, trim(p))
        end
    end
    return pkgs
end

local function check_db_exists(package_name)
    -- Try multiple possible paths (old and new WebView locations)
    local paths = {
        string.format("/data/data/%s/app_webview/Default/Cookies", package_name),
        string.format("/data/data/%s/app_webview/Default/Network/Cookies", package_name),
        string.format("/data/user/0/%s/app_webview/Default/Cookies", package_name),
        string.format("/data/user/0/%s/app_webview/Default/Network/Cookies", package_name),
    }
    
    for _, path in ipairs(paths) do
        local result = su("test -f '" .. path .. "' && echo EXISTS || echo NOT_FOUND")
        if result and result:match("EXISTS") then
            return true, path
        end
    end
    
    return false, nil
end

local function get_package_uid(package_name)
    local result = su("stat -c '%u' /data/data/" .. package_name .. " 2>/dev/null")
    if result and result:match("^%d+$") then return result end
    -- Try /data/user/0 path
    result = su("stat -c '%u' /data/user/0/" .. package_name .. " 2>/dev/null")
    if result and result:match("^%d+$") then return result end
    return "10000"
end

-- ============================================================
-- COOKIE INJECTOR
-- ============================================================
local function inject_cookie(package_name, cookie_value)
    print_log("INFO", "Injecting cookie to: " .. A.BOLD .. package_name .. A.RESET)
    
    -- Clean cookie
    cookie_value = cookie_value:gsub("^_|", "")
    if not cookie_value:match("^WARNING:") then
        cookie_value = "_|WARNING:-DO-NOT-SHARE-THIS.--Sharing-this-will-allow-someone-to-log-in-as-you-and-to-steal-your-ROBUX-and-items.|" .. cookie_value
    end
    
    local db_exists, db_path = check_db_exists(package_name)
    if not db_exists then
        print_log("ERR", "Database not found! Buka Roblox sekali dulu.")
        return false
    end
    
    print_log("INFO", "DB: " .. db_path:match("[^/]+/Cookies$"))
    
    -- Force stop
    su("am force-stop " .. package_name)
    os.execute("sleep 1")
    
    -- Delete WAL files to ensure changes are read
    su("rm -f '" .. db_path .. "-wal' '" .. db_path .. "-shm' 2>/dev/null")
    
    local now = os.time() * 1000000
    local expiry = (os.time() + (CONFIG.EXPIRY_DAYS * 86400)) * 1000000
    
    local sql = string.format([[
        INSERT OR REPLACE INTO cookies (
            creation_utc, host_key, top_frame_site_key, name, value,
            encrypted_value, path, expires_utc, is_secure, is_httponly,
            last_access_utc, has_expires, is_persistent, priority, samesite,
            source_scheme, source_port, last_update_utc, source_type, has_cross_site_ancestor
        ) VALUES (%d, '%s', '', '%s', '%s', '', '%s', %d, %d, %d, %d, 1, 1, 1, 0, 2, 443, %d, 0, 0);
    ]], now, CONFIG.HOST_KEY, CONFIG.COOKIE_NAME, cookie_value:gsub("'", "''"), 
        CONFIG.COOKIE_PATH, expiry, CONFIG.IS_SECURE, CONFIG.IS_HTTPONLY, now, now)
    
    local result, ok = su(string.format('sqlite3 "%s" "%s"', db_path, sql:gsub("\n", " ")))
    
    if result and result ~= "" and not ok then
        print_log("ERR", "SQL Error: " .. result:sub(1, 50))
        return false
    end
    
    -- Fix permissions - restore ownership to app's UID
    local uid = get_package_uid(package_name)
    su(string.format("chown %s:%s '%s'", uid, uid, db_path))
    su(string.format("chmod 660 '%s'", db_path))
    -- Also fix parent directory if needed
    local db_dir = db_path:match("(.+)/[^/]+$")
    su(string.format("chown %s:%s '%s'", uid, uid, db_dir))
    
    print_log("OK", "Cookie injected!")
    return true
end

-- Read cookies from file
local function read_cookies_file()
    local cookies = {}
    local file = io.open("cookies.txt", "r")
    if not file then
        return nil
    end
    for line in file:lines() do
        local cookie = trim(line)
        if cookie ~= "" and not cookie:match("^#") then  -- Skip empty & comments
            table.insert(cookies, cookie)
        end
    end
    file:close()
    return cookies
end

local function menu_cookie_injector()
    clear()
    print(A.BOLD .. A.CYAN .. "╔══════════════════════════════════════╗" .. A.RESET)
    print(A.BOLD .. A.CYAN .. "║     COOKIE INJECTOR (Auto Mode)      ║" .. A.RESET)
    print(A.BOLD .. A.CYAN .. "╚══════════════════════════════════════╝" .. A.RESET)
    print("")
    
    -- Scan packages
    print_log("INFO", "Scanning Roblox packages...")
    local packages = scan_packages()
    
    if #packages == 0 then
        print_log("ERR", "Tidak ada Roblox terinstall!")
        pause()
        return
    end
    
    print("")
    print(A.BOLD .. "Roblox Packages Found:" .. A.RESET)
    for i, pkg in ipairs(packages) do
        local db_exists = check_db_exists(pkg)
        local status = db_exists and (A.GREEN .. "Ready" .. A.RESET) or (A.YELLOW .. "Need Open" .. A.RESET)
        print(string.format("  %d. %s [%s]", i, pkg, status))
    end
    
    -- Read cookies from file
    print("")
    print(A.DIM .. string.rep("-", 40) .. A.RESET)
    print_log("INFO", "Reading cookies.txt...")
    
    local cookies = read_cookies_file()
    
    if not cookies then
        print("")
        print_log("ERR", "File cookies.txt tidak ditemukan!")
        print("")
        print(A.YELLOW .. "Cara pakai:" .. A.RESET)
        print("  1. Buat file " .. A.BOLD .. "cookies.txt" .. A.RESET .. " di folder yang sama")
        print("  2. Isi dengan cookie (1 cookie per baris)")
        print("  3. Jalankan lagi menu ini")
        print("")
        print(A.DIM .. "Contoh isi cookies.txt:" .. A.RESET)
        print(A.DIM .. "  _|WARNING:...|cookie_untuk_roblox_1" .. A.RESET)
        print(A.DIM .. "  _|WARNING:...|cookie_untuk_roblox_2" .. A.RESET)
        print(A.DIM .. "  # Baris dengan # adalah komentar" .. A.RESET)
        pause()
        return
    end
    
    if #cookies == 0 then
        print_log("ERR", "cookies.txt kosong!")
        pause()
        return
    end
    
    print_log("OK", "Found " .. #cookies .. " cookie(s) in file")
    print("")
    
    -- Show mapping
    print(A.BOLD .. "Cookie -> Package Mapping:" .. A.RESET)
    local count = math.min(#packages, #cookies)
    for i = 1, count do
        print(string.format("  %s✓%s Cookie %d -> %s", A.GREEN, A.RESET, i, packages[i]))
    end
    
    if #cookies < #packages then
        print("")
        print_log("WARN", string.format("Cookie kurang! %d package, hanya %d cookie", #packages, #cookies))
    elseif #cookies > #packages then
        print("")
        print_log("WARN", string.format("Cookie lebih! %d cookie, hanya %d package", #cookies, #packages))
    end
    
    -- Auto inject immediately
    print("")
    print(A.DIM .. string.rep("-", 40) .. A.RESET)
    print_log("INFO", "Auto-injecting " .. count .. " cookie(s)...")
    print("")
    
    local success, failed = 0, 0
    
    for i = 1, count do
        print(string.format("[%d/%d] %s", i, count, packages[i]))
        if inject_cookie(packages[i], cookies[i]) then
            success = success + 1
        else
            failed = failed + 1
        end
        print("")
    end
    
    print(A.DIM .. string.rep("=", 40) .. A.RESET)
    print(A.BOLD .. "HASIL:" .. A.RESET)
    print(A.GREEN .. "  ✓ Success: " .. success .. A.RESET)
    if failed > 0 then
        print(A.RED .. "  ✗ Failed: " .. failed .. A.RESET)
    end
    
    pause()
end

-- ============================================================
-- AUTO-REJOIN TUI
-- ============================================================
local function parse_link(url)
    local pid = url:match("/games/(%d+)")
    local code = url:match("privateServerLinkCode=(%d+)") or url:match("code=(%d+)")
    return pid, code
end

local function is_running(pkg)
    local pid = su("pidof " .. pkg)
    return pid ~= "", pid
end

local function launch(pkg)
    su("am force-stop " .. pkg)
    os.execute("sleep 1")
    -- Use component name to force open in specific package without app chooser
    -- Also add --activity-single-top to prevent multiple activities
    local cmd = string.format(
        'am start -a android.intent.action.VIEW -d "%s" -n %s/com.roblox.client.ActivitySplash --activity-single-top',
        State.deep_link, pkg
    )
    su(cmd)
    State.data[pkg].status = "launching"
    log(A.YELLOW .. "Launched " .. pkg .. A.RESET)
end

local function draw()
    clear()
    
    local up = os.difftime(os.time(), State.start)
    local uptime = string.format("%02d:%02d:%02d", math.floor(up/3600), math.floor(up%3600/60), up%60)
    
    print(A.BOLD .. A.CYAN .. "╔══════════════════════════════════════════════════╗" .. A.RESET)
    print(A.BOLD .. A.CYAN .. "║     ROBLOX MULTI-INSTANCE CONTROLLER v5.0       ║" .. A.RESET)
    print(A.BOLD .. A.CYAN .. "╚══════════════════════════════════════════════════╝" .. A.RESET)
    print(string.format("  Uptime: %s%s%s  |  Instances: %s%d%s  |  Crashes: %s%d%s",
        A.YELLOW, uptime, A.RESET,
        A.GREEN, #State.packages, A.RESET,
        State.crashes > 0 and A.RED or A.GREEN, State.crashes, A.RESET
    ))
    print(A.DIM .. string.rep("-", 52) .. A.RESET)
    print("")
    
    print(A.BOLD .. string.format("  %-28s %-10s %-8s", "PACKAGE", "STATUS", "CRASH") .. A.RESET)
    print(A.DIM .. "  " .. string.rep("-", 48) .. A.RESET)
    
    for _, pkg in ipairs(State.packages) do
        local d = State.data[pkg] or {}
        local status = d.status or "waiting"
        local cr = d.crashes or 0
        
        local scol = status == "running" and A.GREEN or (status == "crashed" and A.RED or A.YELLOW)
        local icon = status == "running" and "●" or (status == "crashed" and "✗" or "○")
        
        print(string.format("  %s%-28s %s%-10s%s %s%d%s",
            scol, icon .. " " .. pkg:sub(1,25), scol, status:upper(), A.RESET,
            cr > 0 and A.RED or A.DIM, cr, A.RESET
        ))
    end
    
    print("")
    print(A.DIM .. "  " .. string.rep("-", 48) .. A.RESET)
    print(A.BOLD .. "  LOG" .. A.RESET)
    for i = CONFIG.MAX_LOG, 1, -1 do
        print("  " .. A.DIM .. (State.logs[i] or "") .. A.RESET)
    end
    
    print("")
    print(A.DIM .. "  Ctrl+C to stop | Delay: " .. CONFIG.LAUNCH_DELAY .. "s per instance" .. A.RESET)
end

local function menu_auto_rejoin()
    clear()
    print(A.BOLD .. A.CYAN .. "╔══════════════════════════════════════╗" .. A.RESET)
    print(A.BOLD .. A.CYAN .. "║     AUTO-REJOIN                      ║" .. A.RESET)
    print(A.BOLD .. A.CYAN .. "╚══════════════════════════════════════╝" .. A.RESET)
    print("")
    
    io.write("Paste Private Server URL: ")
    io.flush()
    local url = io.read()
    
    local pid, code = parse_link(url)
    if not pid or not code then
        print_log("ERR", "URL tidak valid!")
        pause()
        return
    end
    
    State.deep_link = "roblox://placeId=" .. pid .. "&linkCode=" .. code
    log("Deep link: " .. State.deep_link:sub(1, 40) .. "...")
    
    -- Scan
    State.packages = scan_packages()
    if #State.packages == 0 then
        print_log("ERR", "Tidak ada Roblox terinstall!")
        pause()
        return
    end
    
    for _, pkg in ipairs(State.packages) do
        State.data[pkg] = State.data[pkg] or {status = "waiting", crashes = 0, pid = nil}
    end
    
    log("Found " .. #State.packages .. " package(s)")
    
    io.write(A.HIDE)
    
    -- Initial launch with 20s delay per instance
    for i, pkg in ipairs(State.packages) do
        log(string.format("Launching %d/%d: %s", i, #State.packages, pkg))
        draw()
        launch(pkg)
        
        if i < #State.packages then
            -- Countdown display
            for countdown = CONFIG.LAUNCH_DELAY, 1, -1 do
                State.data[pkg].status = "wait " .. countdown .. "s"
                draw()
                os.execute("sleep 1")
            end
        end
    end
    
    os.execute("sleep 3")
    
    -- Monitor loop
    State.running = true
    State.start = os.time()
    
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
                
                if d.crashes < 5 then
                    launch(pkg)
                    -- Wait before next check
                    for countdown = CONFIG.LAUNCH_DELAY, 1, -1 do
                        d.status = "relaunch " .. countdown .. "s"
                        draw()
                        os.execute("sleep 1")
                    end
                else
                    d.status = "disabled"
                    log(A.YELLOW .. pkg .. " too many crashes" .. A.RESET)
                end
            end
        end
        
        draw()
        os.execute("sleep " .. CONFIG.REFRESH)
    end
    
    io.write(A.SHOW)
end

-- ============================================================
-- MAIN MENU
-- ============================================================
local function main_menu()
    while true do
        clear()
        print(A.BOLD .. A.CYAN .. "╔══════════════════════════════════════╗" .. A.RESET)
        print(A.BOLD .. A.CYAN .. "║     ROBLOX MULTI-TOOL v5.0           ║" .. A.RESET)
        print(A.BOLD .. A.CYAN .. "║     by risxt                         ║" .. A.RESET)
        print(A.BOLD .. A.CYAN .. "╚══════════════════════════════════════╝" .. A.RESET)
        print("")
        print(A.BOLD .. "  Pilih menu:" .. A.RESET)
        print("")
        print("  [1] " .. A.GREEN .. "Auto-Rejoin" .. A.RESET .. " - Launch & monitor multiple Roblox")
        print("  [2] " .. A.YELLOW .. "Cookie Injector" .. A.RESET .. " - Inject .ROBLOSECURITY cookie")
        print("  [3] " .. A.CYAN .. "Scan Packages" .. A.RESET .. " - Lihat semua Roblox terinstall")
        print("  [0] " .. A.RED .. "Exit" .. A.RESET)
        print("")
        io.write("  Pilihan: ")
        io.flush()
        
        local choice = io.read()
        
        if choice == "1" then
            menu_auto_rejoin()
        elseif choice == "2" then
            menu_cookie_injector()
        elseif choice == "3" then
            clear()
            print(A.BOLD .. "INSTALLED ROBLOX PACKAGES:" .. A.RESET)
            print("")
            local packages = scan_packages()
            for i, pkg in ipairs(packages) do
                local db_exists = check_db_exists(pkg)
                local status = db_exists and (A.GREEN .. "Cookie DB Ready" .. A.RESET) or (A.YELLOW .. "Need Open Once" .. A.RESET)
                print(string.format("  %d. %s\n     [%s]", i, pkg, status))
            end
            if #packages == 0 then
                print(A.RED .. "  Tidak ada Roblox terinstall!" .. A.RESET)
            end
            pause()
        elseif choice == "0" or choice == "q" then
            clear()
            print(A.GREEN .. "Bye!" .. A.RESET)
            os.exit(0)
        end
    end
end

-- ============================================================
-- ENTRY POINT
-- ============================================================
local ok, err = xpcall(main_menu, function(e)
    io.write(A.SHOW)
    clear()
    print(A.RED .. "ERROR: " .. tostring(e) .. A.RESET)
    return e
end)

if not ok then
    io.write(A.SHOW)
    os.exit(1)
end
