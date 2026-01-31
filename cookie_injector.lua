#!/data/data/com.termux/files/usr/bin/lua
--[[
    ROBLOX COOKIE INJECTOR MODULE v1.0
    Bulk .ROBLOSECURITY Cookie Injector for Rooted Android
    
    Usage:
        local injector = require("cookie_injector")
        injector.inject("com.roblox.client", "YOUR_ROBLOSECURITY_COOKIE")
        injector.bulk_inject({"com.roblox.client", "com.roblox.clone1"}, "COOKIE")
]]

local Injector = {}

-- ============================================================
-- CONFIG
-- ============================================================
Injector.CONFIG = {
    -- Cookie settings
    HOST_KEY = ".roblox.com",
    COOKIE_NAME = ".ROBLOSECURITY",
    COOKIE_PATH = "/",
    
    -- Expiry: 1 year from now (microseconds since epoch)
    EXPIRY_DAYS = 365,
    
    -- Security flags
    IS_SECURE = 1,
    IS_HTTPONLY = 1,
    SAMESITE = 0,
    PRIORITY = 1,
    
    -- Database path template
    DB_PATH_TEMPLATE = "/data/data/%s/app_webview/Default/Cookies",
    WEBVIEW_DIR_TEMPLATE = "/data/data/%s/app_webview/Default",
}

-- ============================================================
-- ANSI COLORS
-- ============================================================
local C = {
    RESET = "\27[0m",
    RED = "\27[31m",
    GREEN = "\27[32m",
    YELLOW = "\27[33m",
    CYAN = "\27[36m",
    BOLD = "\27[1m",
    DIM = "\27[2m"
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
    local escaped = cmd:gsub("'", "'\\''")
    return exec("su -c '" .. escaped .. "'")
end

local function log(level, msg)
    local colors = {
        INFO = C.CYAN,
        OK = C.GREEN,
        WARN = C.YELLOW,
        ERR = C.RED
    }
    local color = colors[level] or C.RESET
    print(string.format("%s[%s]%s %s", color, level, C.RESET, msg))
end

-- ============================================================
-- CORE FUNCTIONS
-- ============================================================

local function get_timestamp_utc()
    return os.time() * 1000000
end

local function get_expiry_utc(days)
    days = days or Injector.CONFIG.EXPIRY_DAYS
    return (os.time() + (days * 24 * 60 * 60)) * 1000000
end

function Injector.check_db_exists(package_name)
    local db_path = string.format(Injector.CONFIG.DB_PATH_TEMPLATE, package_name)
    local result, _ = su("test -f '" .. db_path .. "' && echo 'EXISTS' || echo 'NOT_FOUND'")
    return result == "EXISTS", db_path
end

function Injector.check_webview_dir(package_name)
    local dir_path = string.format(Injector.CONFIG.WEBVIEW_DIR_TEMPLATE, package_name)
    local result, _ = su("test -d '" .. dir_path .. "' && echo 'EXISTS' || echo 'NOT_FOUND'")
    return result == "EXISTS", dir_path
end

local function get_package_uid(package_name)
    local result, _ = su("stat -c '%u' /data/data/" .. package_name .. " 2>/dev/null")
    if result and result:match("^%d+$") then
        return result
    end
    result, _ = su("dumpsys package " .. package_name .. " | grep userId= | head -1")
    local uid = result and result:match("userId=(%d+)")
    return uid or "10000"
end

function Injector.create_db(package_name)
    local exists, db_path = Injector.check_db_exists(package_name)
    if exists then
        log("INFO", "Database already exists: " .. db_path)
        return true
    end
    
    local dir_exists, dir_path = Injector.check_webview_dir(package_name)
    if not dir_exists then
        log("WARN", "WebView directory not found. App must be opened once first!")
        log("WARN", "Path: " .. dir_path)
        return false, "WEBVIEW_NOT_INITIALIZED"
    end
    
    local create_sql = [[
        CREATE TABLE IF NOT EXISTS cookies (
            creation_utc INTEGER NOT NULL,
            host_key TEXT NOT NULL,
            top_frame_site_key TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL,
            value TEXT NOT NULL,
            encrypted_value BLOB NOT NULL DEFAULT '',
            path TEXT NOT NULL,
            expires_utc INTEGER NOT NULL,
            is_secure INTEGER NOT NULL,
            is_httponly INTEGER NOT NULL,
            last_access_utc INTEGER NOT NULL,
            has_expires INTEGER NOT NULL DEFAULT 1,
            is_persistent INTEGER NOT NULL DEFAULT 1,
            priority INTEGER NOT NULL DEFAULT 1,
            samesite INTEGER NOT NULL DEFAULT 0,
            source_scheme INTEGER NOT NULL DEFAULT 2,
            source_port INTEGER NOT NULL DEFAULT 443,
            last_update_utc INTEGER NOT NULL,
            source_type INTEGER NOT NULL DEFAULT 0,
            has_cross_site_ancestor INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (host_key, top_frame_site_key, name, path)
        );
        CREATE INDEX IF NOT EXISTS cookies_index ON cookies(host_key);
    ]]
    
    local cmd = string.format("sqlite3 '%s' \"%s\"", db_path, create_sql:gsub("\n", " "))
    local result, ok = su(cmd)
    
    if ok then
        log("OK", "Created database: " .. db_path)
        return true
    else
        log("ERR", "Failed to create database: " .. result)
        return false, result
    end
end

function Injector.inject(package_name, cookie_value, options)
    options = options or {}
    
    log("INFO", "Injecting cookie to: " .. C.BOLD .. package_name .. C.RESET)
    
    if not package_name or package_name == "" then
        log("ERR", "Package name is required!")
        return false, "INVALID_PACKAGE"
    end
    
    if not cookie_value or cookie_value == "" then
        log("ERR", "Cookie value is required!")
        return false, "INVALID_COOKIE"
    end
    
    -- Clean cookie value
    cookie_value = cookie_value:gsub("^_|", "")
    if not cookie_value:match("^WARNING:") then
        cookie_value = "_|WARNING:-DO-NOT-SHARE-THIS.--Sharing-this-will-allow-someone-to-log-in-as-you-and-to-steal-your-ROBUX-and-items.|" .. cookie_value
    end
    
    local db_exists, db_path = Injector.check_db_exists(package_name)
    
    if not db_exists then
        log("WARN", "Database not found, attempting to create...")
        local created, err = Injector.create_db(package_name)
        if not created then
            return false, err
        end
        db_path = string.format(Injector.CONFIG.DB_PATH_TEMPLATE, package_name)
    end
    
    -- Force stop the app
    log("INFO", "Stopping " .. package_name .. "...")
    su("am force-stop " .. package_name)
    os.execute("sleep 1")
    
    local now = get_timestamp_utc()
    local expiry = get_expiry_utc(options.expiry_days or Injector.CONFIG.EXPIRY_DAYS)
    
    local sql = string.format([[
        INSERT OR REPLACE INTO cookies (
            creation_utc, host_key, top_frame_site_key, name, value,
            encrypted_value, path, expires_utc, is_secure, is_httponly,
            last_access_utc, has_expires, is_persistent, priority, samesite,
            source_scheme, source_port, last_update_utc, source_type, has_cross_site_ancestor
        ) VALUES (
            %d, '%s', '', '%s', '%s', '', '%s', %d, %d, %d, %d, 1, 1, %d, %d, 2, 443, %d, 0, 0
        );
    ]],
        now, Injector.CONFIG.HOST_KEY, Injector.CONFIG.COOKIE_NAME,
        cookie_value:gsub("'", "''"), Injector.CONFIG.COOKIE_PATH,
        expiry, Injector.CONFIG.IS_SECURE, Injector.CONFIG.IS_HTTPONLY,
        now, Injector.CONFIG.PRIORITY, Injector.CONFIG.SAMESITE, now
    )
    
    local cmd = string.format('sqlite3 "%s" "%s"', db_path, sql:gsub("\n", " "):gsub("%s+", " "))
    local result, ok = su(cmd)
    
    if result and result ~= "" and not ok then
        log("ERR", "SQL Error: " .. result)
        return false, result
    end
    
    log("OK", "Cookie injected successfully!")
    
    -- Fix permissions
    local uid = get_package_uid(package_name)
    log("INFO", "Fixing permissions (UID: " .. uid .. ")...")
    
    su(string.format("chown %s:%s '%s'", uid, uid, db_path))
    su(string.format("chmod 660 '%s'", db_path))
    su(string.format("chown %s:%s '%s-journal' 2>/dev/null", uid, uid, db_path))
    su(string.format("chmod 660 '%s-journal' 2>/dev/null", db_path))
    su(string.format("chown %s:%s '%s-wal' 2>/dev/null", uid, uid, db_path))
    su(string.format("chmod 660 '%s-wal' 2>/dev/null", db_path))
    su(string.format("chown %s:%s '%s-shm' 2>/dev/null", uid, uid, db_path))
    su(string.format("chmod 660 '%s-shm' 2>/dev/null", db_path))
    
    log("OK", "Permissions fixed!")
    
    return true
end

function Injector.bulk_inject(packages, cookie_value, options)
    log("INFO", C.BOLD .. "Starting bulk injection to " .. #packages .. " packages..." .. C.RESET)
    print(string.rep("-", 50))
    
    local results = { success = {}, failed = {} }
    
    for i, pkg in ipairs(packages) do
        print(string.format("\n[%d/%d] Processing: %s", i, #packages, pkg))
        local ok, err = Injector.inject(pkg, cookie_value, options)
        if ok then
            table.insert(results.success, pkg)
        else
            table.insert(results.failed, {package = pkg, error = err})
        end
    end
    
    print("\n" .. string.rep("=", 50))
    log("INFO", C.BOLD .. "INJECTION SUMMARY" .. C.RESET)
    print(string.rep("-", 50))
    print(string.format("%s✓ Success:%s %d packages", C.GREEN, C.RESET, #results.success))
    print(string.format("%s✗ Failed:%s  %d packages", C.RED, C.RESET, #results.failed))
    
    if #results.failed > 0 then
        print("\n" .. C.YELLOW .. "Failed packages:" .. C.RESET)
        for _, f in ipairs(results.failed) do
            print(string.format("  - %s: %s", f.package, f.error or "Unknown error"))
        end
    end
    
    return results
end

function Injector.scan_packages()
    log("INFO", "Scanning for Roblox packages...")
    
    local result, _ = su("pm list packages | grep -i roblox")
    local packages = {}
    
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then
            table.insert(packages, trim(pkg))
        end
    end
    
    log("OK", "Found " .. #packages .. " Roblox package(s)")
    for i, pkg in ipairs(packages) do
        local db_exists = Injector.check_db_exists(pkg)
        local status = db_exists and (C.GREEN .. "DB Ready" .. C.RESET) or (C.YELLOW .. "DB Missing" .. C.RESET)
        print(string.format("  %d. %s [%s]", i, pkg, status))
    end
    
    return packages
end

function Injector.verify(package_name)
    local db_exists, db_path = Injector.check_db_exists(package_name)
    
    if not db_exists then
        log("ERR", "Database not found!")
        return false
    end
    
    local sql = string.format(
        "SELECT value FROM cookies WHERE host_key='%s' AND name='%s' LIMIT 1;",
        Injector.CONFIG.HOST_KEY, Injector.CONFIG.COOKIE_NAME
    )
    
    local result, _ = su(string.format('sqlite3 "%s" "%s"', db_path, sql))
    
    if result and result ~= "" then
        log("OK", "Cookie found! (Length: " .. #result .. " chars)")
        if #result > 50 then
            print(C.DIM .. "  Value: " .. result:sub(1, 30) .. "..." .. result:sub(-20) .. C.RESET)
        end
        return true, result
    else
        log("WARN", "Cookie not found in database")
        return false
    end
end

function Injector.delete(package_name)
    local db_exists, db_path = Injector.check_db_exists(package_name)
    
    if not db_exists then
        log("WARN", "Database not found, nothing to delete")
        return true
    end
    
    su("am force-stop " .. package_name)
    os.execute("sleep 1")
    
    local sql = string.format(
        "DELETE FROM cookies WHERE host_key='%s' AND name='%s';",
        Injector.CONFIG.HOST_KEY, Injector.CONFIG.COOKIE_NAME
    )
    
    local result, ok = su(string.format('sqlite3 "%s" "%s"', db_path, sql))
    
    if ok or result == "" then
        log("OK", "Cookie deleted from " .. package_name)
        return true
    else
        log("ERR", "Failed to delete: " .. result)
        return false, result
    end
end

-- ============================================================
-- CLI INTERFACE
-- ============================================================
local function print_usage()
    print(C.BOLD .. C.CYAN .. "\nROBLOX COOKIE INJECTOR v1.0" .. C.RESET)
    print(C.DIM .. string.rep("-", 40) .. C.RESET)
    print("\nUsage:")
    print("  lua cookie_injector.lua <command> [args]\n")
    print("Commands:")
    print("  scan              - Scan all Roblox packages")
    print("  inject <pkg> <cookie>  - Inject cookie to package")
    print("  bulk <cookie>     - Inject to ALL Roblox packages")
    print("  verify <pkg>      - Verify cookie in package")
    print("  delete <pkg>      - Delete cookie from package")
    print("\nExamples:")
    print("  lua cookie_injector.lua scan")
    print("  lua cookie_injector.lua inject com.roblox.client YOUR_COOKIE")
    print("  lua cookie_injector.lua bulk YOUR_COOKIE")
    print("")
end

if arg and arg[0] and arg[0]:match("cookie_injector") then
    local cmd = arg[1]
    
    if not cmd or cmd == "help" or cmd == "-h" or cmd == "--help" then
        print_usage()
        os.exit(0)
    end
    
    if cmd == "scan" then
        Injector.scan_packages()
    elseif cmd == "inject" then
        local pkg = arg[2]
        local cookie = arg[3]
        if not pkg or not cookie then
            log("ERR", "Usage: inject <package> <cookie>")
            os.exit(1)
        end
        Injector.inject(pkg, cookie)
    elseif cmd == "bulk" then
        local cookie = arg[2]
        if not cookie then
            log("ERR", "Usage: bulk <cookie>")
            os.exit(1)
        end
        local packages = Injector.scan_packages()
        if #packages > 0 then
            print("\n")
            Injector.bulk_inject(packages, cookie)
        end
    elseif cmd == "verify" then
        local pkg = arg[2]
        if not pkg then
            log("ERR", "Usage: verify <package>")
            os.exit(1)
        end
        Injector.verify(pkg)
    elseif cmd == "delete" then
        local pkg = arg[2]
        if not pkg then
            log("ERR", "Usage: delete <package>")
            os.exit(1)
        end
        Injector.delete(pkg)
    else
        log("ERR", "Unknown command: " .. cmd)
        print_usage()
        os.exit(1)
    end
end

return Injector
