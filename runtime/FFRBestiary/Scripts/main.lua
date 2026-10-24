-- FFR Bestiary (UE4SS). The menu row itself comes from the data pak zzz_FFRBestiary_P (DT_MainMenuScene).
local game = require("game")
local store = require("store")
local tracker = require("tracker")
local ui = require("ui")

local function log(s) print("[FFRBestiary] " .. s .. "\n") end

local function safe(name, fn)
    local ok, err = pcall(fn)
    if not ok then log(name .. ": " .. tostring(err)) end
end

-- development keys, only with a dev.txt next to this mod's Scripts folder (tools/deploy.sh writes one)
-- this mod's folder, from where this script was loaded (paths relative to the process folder break when the game
-- is started from Steam, whose working folder is the game root, not Binaries\Win64)
local MOD_DIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):match("^(.*)/Scripts/[^/]+$")) or "ue4ss/Mods/FFRBestiary"
local devFile = io.open(MOD_DIR .. "/dev.txt", "r")
local DEV = devFile ~= nil
if devFile then devFile:close() end
-- loading screens: objects are being torn down and rebuilt, so the polls stay out of the way. The game starts
-- behind one that began before this mod loaded, so the polls wait for its end (or 20 s, if that is missed).
local loading, sawLoading = true, false
ExecuteWithDelay(20000, function() if not sawLoading then loading = false end end)
pcall(function()
    RegisterHook("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent", function(self, tag)
        local ok, name = pcall(function() return tag:get().TagName:ToString() end)
        if ok and name == "Delegate.Common.LoadingScreen.Begin" then loading = true; sawLoading = true
        elseif ok and name == "Delegate.Common.LoadingScreen.End" then loading = false end
    end)
end)

ui.installHooks()

-- one timer for everything, one game-thread call per tick: the screen every 50 ms, the rest every second
-- (the timer thread only queues the tick; everything, including the loading check, runs on the game thread)
local ticks = 0
local function tick()
    if loading then return end
    ticks = ticks + 1
    local t0 = os.clock()                                 -- wall time on Windows (MSVC clock)
    safe("ui", ui.poll)
    local t1 = os.clock()
    if ticks % 20 == 0 then
        safe("menu", game.addMenuEntry)
        safe("store", store.poll)
        safe("tracker", tracker.poll)
    end
    local t2 = os.clock()
    if DEV and (t2 - t0) > 0.003 then
        log(string.format("slow tick: ui %.1f ms (%s), 1 s jobs %.1f ms", (t1 - t0) * 1000, ui.lastTiming or "", (t2 - t1) * 1000))
    end
end
LoopAsync(50, function() ExecuteInGameThread(tick); return false end)

if DEV then
    RegisterKeyBind(Key.F7, function() ui.showAll = not ui.showAll; log("showAll " .. tostring(ui.showAll)) end)   -- every entry
    RegisterKeyBind(Key.F3, function() ui.debugFocus() end)                                                          -- focus log
    RegisterKeyBind(Key.F8, function() ui.queueDevNext() end)                                                       -- sprite review
    RegisterKeyBind(Key.F9, function() ui.toggleMeasure() end)                                                      -- sprite measure mode
end

RegisterKeyBind(Key.Q, function() ui.queueForm(-1) end)
RegisterKeyBind(Key.E, function() ui.queueForm(1) end)

log("loaded")
