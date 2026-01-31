# Roblox Multi-Tool - Technical Reference

## Project Overview
Tool untuk Termux (Android rooted) yang menggabungkan:
1. **Auto-Rejoin** - Launch multiple Roblox instances ke Private Server
2. **Cookie Injector** - Inject .ROBLOSECURITY cookie ke cloned apps

---

## 🔧 Bypass App Chooser Dialog (Deep Link)

### Problem
Saat mengirim deep link `roblox://placeId=xxx&linkCode=xxx` ke package tertentu, Android menampilkan "Open with" dialog karena ada multiple apps yang bisa handle scheme tersebut.

### Root Cause
- Multiple Roblox clones mendaftarkan intent-filter yang sama untuk `roblox://`
- Flag `-p <package>` dalam `am start` tidak cukup jika app belum di-set sebagai default
- Android Intent Resolver melihat multiple kandidat → tampilkan chooser

### Solution: Temporary Disable Strategy ✅

**Metode paling reliable untuk rooted device:**

```lua
-- Disable semua packages KECUALI target
local function disable_other_packages(target_pkg)
    for _, pkg in ipairs(all_roblox_packages) do
        if pkg ~= target_pkg then
            su("pm disable-user --user 0 " .. pkg .. " 2>/dev/null")
        end
    end
end

-- Re-enable semua packages
local function enable_all_packages()
    for _, pkg in ipairs(all_roblox_packages) do
        su("pm enable " .. pkg .. " 2>/dev/null")
    end
end

-- Launch function
local function launch(pkg, deep_link)
    su("am force-stop " .. pkg)
    
    -- Disable others first
    disable_other_packages(pkg)
    os.execute("sleep 1")  -- Tunggu Android register perubahan
    
    -- Launch - hanya 1 package yang bisa handle roblox://
    local cmd = string.format(
        'am start -a android.intent.action.VIEW -d "%s" -p %s --user 0 --activity-clear-top -f 0x10000000',
        deep_link, pkg
    )
    su(cmd)
    
    -- Re-enable setelah app jalan
    os.execute("sleep 3")
    enable_all_packages()
end
```

### Why This Works
- `pm disable-user` membuat package tidak visible ke Intent Resolver
- Saat hanya ada 1 package yang bisa handle `roblox://`, tidak ada chooser
- Re-enable setelah app sudah jalan tidak mengganggu yang sedang running

### Alternative Methods (Tidak Reliable)
| Method | Result |
|--------|--------|
| `-p <package>` flag | ❌ Masih muncul chooser |
| `-n <package>/<activity>` | ❌ Activity name berbeda di cloned apps |
| `monkey -p` lalu `am start` | ❌ Masih muncul chooser |
| Intent URI format | ❌ Tidak konsisten |

---

## 🔧 Running Termux Binaries in Root Shell

### Problem
Saat menjalankan `sqlite3` via `su -c`, error muncul:
```
sh: sqlite3: inaccessible or not found
```

### Root Cause
- `su -c` menjalankan shell minimal (sh) yang tidak punya PATH ke Termux
- Meskipun pakai full path, linker tidak bisa temukan `libsqlite3.so`

### Solution: Export PATH + LD_LIBRARY_PATH ✅

```lua
local function su(cmd)
    local termux_bin = "/data/data/com.termux/files/usr/bin"
    local termux_lib = "/data/data/com.termux/files/usr/lib"
    
    local env = string.format(
        "export PATH=%s:$PATH; export LD_LIBRARY_PATH=%s;", 
        termux_bin, termux_lib
    )
    
    local escaped = cmd:gsub("'", "'\\''")
    return exec(string.format('su -c "%s %s"', env, escaped))
end
```

### Why This Works
- `PATH` memungkinkan shell menemukan binary seperti `sqlite3`
- `LD_LIBRARY_PATH` memungkinkan linker menemukan shared libraries (.so)

---

## 🔧 WebView Cookie Database Paths

### Problem  
Database cookie WebView bisa di lokasi berbeda tergantung versi Android/WebView.

### Solution: Try Multiple Paths

```lua
local function check_db_exists(package_name)
    local paths = {
        -- Old WebView
        string.format("/data/data/%s/app_webview/Default/Cookies", package_name),
        -- New WebView (dengan /Network/)
        string.format("/data/data/%s/app_webview/Default/Network/Cookies", package_name),
        -- Clone apps path
        string.format("/data/user/0/%s/app_webview/Default/Cookies", package_name),
        string.format("/data/user/0/%s/app_webview/Default/Network/Cookies", package_name),
    }
    
    for _, path in ipairs(paths) do
        local result = su("test -f '" .. path .. "' && echo EXISTS")
        if result and result:match("EXISTS") then
            return true, path
        end
    end
    
    return false, nil
end
```

### Additional Tips
- Hapus WAL files (`-wal`, `-shm`) sebelum inject agar perubahan langsung terbaca
- Fix permissions setelah inject: `chown <uid>:<uid>` dan `chmod 660`

---

## 📁 File Structure

```
roblox-auto-rejoin/
├── main.lua          # Unified script (Auto-Rejoin + Cookie Injector)
├── ps.txt            # Saved Private Server URL (auto-generated)
├── cookies.txt       # Cookies for injection (user-created)
└── PROJECT_BRAIN.md  # This reference document
```

---

## 🚀 Quick Start (Termux)

```bash
# Install dependencies
pkg install lua53 sqlite curl -y

# Download script
curl -O https://raw.githubusercontent.com/risxt/rj/main/main.lua

# Create cookies.txt (for cookie injector)
# 1 cookie per line

# Run
lua main.lua
```

---

## 📝 Changelog

- **2026-02-01**: Implemented disable-other-packages strategy for app chooser bypass
- **2026-02-01**: Fixed LD_LIBRARY_PATH for sqlite3 in root shell
- **2026-02-01**: Added PS link auto-save to ps.txt
- **2026-02-01**: Added multiple DB path detection for WebView
