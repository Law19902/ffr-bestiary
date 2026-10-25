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
-- Everything this mod does runs on the game thread, from one game-thread timer. (0.1.1 used LoopAsync, whose callback
-- runs on UE4SS's own thread, and hooked the game's event dispatcher to see loading screens: Lua running on two
-- threads at once, and inside every game event. Players saw all input die from start-up, mostly with a controller
-- connected, and crashes after an hour or so.)

-- loading screens: objects are being torn down and rebuilt, so the polls stay out of the way. Read from the game's
-- loading-screen manager (found once, then one bool per tick); until it exists the game is still starting up.
local lsm, lsmTries = nil, 0
local function loading()
    if not game.valid(lsm) then
        lsmTries = lsmTries + 1
        if lsmTries % 20 ~= 1 then return true end        -- the object search is slow: once a second
        lsm = FindFirstOf("CPP_LoadingScreenManager")
        if not game.valid(lsm) then return true end
    end
    local ok, showing = pcall(function() return lsm.IsShowLoadingScreen end)
    return not ok or showing == true
end

-- one timer for everything: the screen every 50 ms, the rest every second
local ticks, wasLoading, hooked, hookTries = 0, nil, false, 0
local function tick()
    local l = loading()
    if DEV and l ~= wasLoading then log("loading " .. tostring(l)) end
    wasLoading = l
    if l then return end
    -- The game function hook goes in here, on the game thread once the game is up, not when the mod starts: hooked
    -- from UE4SS's thread during start-up, all input was dead at the title on 4 of 10 launches (a player-style install,
    -- 25 Oct). The game pushes its title and menu screens through that function.
    if not hooked and hookTries < 5 then hookTries = hookTries + 1; hooked = ui.installHooks() end
    ui.pollKeys()
    ticks = ticks + 1
    local t0 = os.clock()                                 -- wall time on Windows (MSVC clock)
    safe("ui", ui.poll)
    local t1 = os.clock()
    if ticks % 20 == 0 then
        safe("menu", game.addMenuEntry)
        safe("menu name", game.localizeMenuEntry)
        safe("store", store.poll)
        safe("tracker", tracker.poll)
    end
    local t2 = os.clock()
    if DEV and (t2 - t0) > 0.003 then
        log(string.format("slow tick: ui %.1f ms (%s), 1 s jobs %.1f ms", (t1 - t0) * 1000, ui.lastTiming or "", (t2 - t1) * 1000))
    end
end
LoopInGameThreadWithDelay(50, function() safe("tick", tick) end)

if DEV then
    RegisterKeyBind(Key.F7, function() ui.toggleShowAll() end)                                                       -- every entry
    RegisterKeyBind(Key.F3, function() ui.debugFocus() end)                                                          -- focus log
    RegisterKeyBind(Key.F8, function() ui.queueDevNext() end)                                                       -- sprite review
    RegisterKeyBind(Key.F9, function() ui.toggleMeasure() end)                                                      -- sprite measure mode
end

-- Q / E (previous / next form) are read by ui.pollKeys on the game thread, not with RegisterKeyBind (its callbacks
-- run on UE4SS's thread)

log("loaded")
