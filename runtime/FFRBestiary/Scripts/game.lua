-- Everything that depends on how FINAL FANTASY RESONANCE is built lives here, so a game patch only touches this file.
-- Verified on the full game v1.0.1.0 (Steam build 24250053), 24 Oct 2026. See RECON.md.
local data = require("bestiary_data")
local M = {}

M.SCENE_TAG = "UI.MainMenu.Scene.Bestiary" -- the mod's own tag (tag-table row in the pak); must match make_menu_row.py
M.HOST_CLASS = "WBP_HelpLayout_C"          -- screen the Bestiary row opens (LayoutWidget in DT_MainMenuScene)
M.HOST_PARENT = "WBP_MainMenuLayout"       -- the real Help screen is not under the main menu
M.SPRITE_WIDGET = "/Game/UI/Common/SsProject/Widget/WBP_UnitSsPlayerWidget"
M.REL_ENEMY = 2                            -- UCPP_UnitParameter:GetRelation(): 1 party, 2 enemy

local function valid(o)
    if not o then return false end
    local ok, v = pcall(function() return o:IsValid() end)   -- a dead object's wrapper can throw instead
    return ok and v
end
M.valid = valid

local libs = {}
local function lib(path)
    local o = libs[path]
    if not valid(o) then o = StaticFindObject(path); libs[path] = o end
    return o
end

-- the game's save manager (a game-instance subsystem: one for the whole session)
local manager
local function saveManager()
    if not valid(manager) then manager = FindFirstOf("CPP_MuchaSaveDataManager") end
    return valid(manager) and manager or nil
end

-- the loaded game's save object (one record per unit: SaveId, IsAnalyzed, defeatNum, analyzedElments): the manager's
-- current one (an object search could also find an old one that is not collected yet)
function M.saveData()
    local mgr = saveManager()
    local sd = mgr and mgr.m_pGameSaveData
    if valid(sd) and #sd.unitList > 0 then return sd end
end

-- ticks of the loaded save's timestamp; slot summaries carry the same value
function M.savedTicks(sd)
    local ok, t = pcall(function() return sd.Player.SavedDateTime.Ticks end)
    return ok and t or nil
end

-- slot whose summary timestamp equals `ticks` (0 = autosave), or nil. Read from the manager's own summary map (a
-- property of a live object), not FindGameSaveDataSummary's out-param struct, which UE4SS hands back as wrappers
-- into memory freed after the call.
function M.slotForTicks(ticks)
    local mgr = saveManager()
    if not mgr or not ticks then return nil end
    local found
    pcall(function()
        mgr.GameSaveDataSummaryMap:ForEach(function(key, value)
            local sum = value:get()
            if not found and sum.bExists and sum.DateTime.Ticks == ticks then found = key:get() end
        end)
    end)
    return found
end

-- per-unit records from the save, keyed by SaveId (= unit id for enemies)
function M.records(sd)
    local out = {}
    local list = sd.unitList
    for i = 1, #list do
        local r = list[i]
        out[r.SaveId] = r
    end
    return out
end

-- current map id and island number (eMapIslandType)
function M.location()
    local mm = FindFirstOf("CPP_MapManager")
    if not valid(mm) then return nil end
    local ok1, map = pcall(function() return mm:GetMapId() end)
    local ok2, isl = pcall(function() return mm:GetCurrentIslandType() end)
    if ok1 then return map, ok2 and isl or 0 end
end

-- enemy unit ids currently in battle (nil when no battle)
function M.battleEnemies()
    local bm = FindFirstOf("CPP_BtlManager")
    local um = valid(bm) and bm.m_pUnitManager or nil
    local list = valid(um) and um.m_UnitList or nil
    if not list or #list == 0 then return nil end
    local ids = {}
    for i = 1, #list do
        local u = list[i]
        if valid(u) then
            pcall(function()
                local p = u:GetUnitParameter()
                if valid(p) and p:GetRelation() == M.REL_ENEMY then ids[#ids + 1] = p:GetUnitId() end
            end)
        end
    end
    return ids
end

-- FUNIT_PARAMETER of a unit (Level, Race, MaxHitPoint, Drop*, Steal*, Traits, Name, ElementResistanceList, ...)
local paramCache = {}
-- a unit's scan data from the mod's data file (tools/export_data.py "stats"), shaped like the game's FUnitParameter
-- fields the screen reads. Plain Lua values only: the game's own GetUnitParameterById comes back from UE4SS as
-- wrappers into memory that is freed after the call, and reading them later crashed the game.
function M.unitParam(id)
    if paramCache[id] then return paramCache[id] end
    local d = data.stats[tostring(id)]
    if not d then return nil end
    local function str(ref) return ref and M.text(ref[1], ref[2]) end
    local p = { Name = str(d.name), Level = d.lv, MaxHitPoint = d.hp, Race = d.race, Traits = {},
                ElementResistanceList = {}, StatusConditionResistanceList = {},
                DropNormalItem = d.drop[1], DropRareItem = d.drop[2], StealNormalItem = d.drop[3], StealRareItem = d.drop[4] }
    for _, ref in ipairs(d.traits) do p.Traits[#p.Traits + 1] = str(ref) end
    for k, v in pairs(d.el) do p.ElementResistanceList[tonumber(k)] = v end
    for k, v in pairs(d.st) do p.StatusConditionResistanceList[tonumber(k)] = v end
    paramCache[id] = p
    return p
end

function M.text(tableId, key)
    local ok, t = pcall(function() return lib("/Script/Engine.Default__KismetTextLibrary"):TextFromStringTable(FName(tableId), key) end)
    if ok and t then
        local str = t:ToString()
        if str ~= "" and not str:find("MISSING STRING TABLE ENTRY", 1, true) then return str end
    end
end

function M.libra(key) return M.text("/Game/Datatable/Strings/UI/UI_Common/ST_UI_Libra.ST_UI_Libra", key) end

-- battle damage words (Weak / Resisted / Immune / Absorbed)
function M.battleWord(key) return M.text("/Game/Datatable/Strings/UI/UI_Common/ST_UI_BattleDamageProp.ST_UI_BattleDamageProp", key) end

function M.itemName(id)
    if not id or id < 0 then return nil end
    local ok, t = pcall(function() return lib("/Script/mucha.Default__CPP_BFL_Item"):GetItemName(id) end)
    if ok and t then return t:ToString() end
end

-- an asset ('/Game/Path/Asset.Asset'), loading it if it isn't in memory yet
-- an asset by path, loading it if needed. LoadAsset_Blocking returns at once for a loaded asset; StaticFindObject
-- is avoided because for an object that is not loaded it takes milliseconds (UE4SS falls back to a search).
function M.load(path)
    local sys = lib("/Script/Engine.Default__KismetSystemLibrary")
    local ok, r = pcall(function() return sys:LoadAsset_Blocking(sys:Conv_SoftObjPathToSoftObjRef(sys:MakeSoftObjectPath(path))) end)
    if ok and valid(r) then return r end
    local o = StaticFindObject(path)
    if valid(o) then return o end
end

-- a Blueprint class ('/Game/Path/WBP_X'), loading it if needed
function M.class(path)
    local name = path:match("([^/]+)$")
    local c = StaticFindObject(path .. "." .. name .. "_C")
    if valid(c) then return c end
    local sys = lib("/Script/Engine.Default__KismetSystemLibrary")
    local ok, r = pcall(function() return sys:LoadClassAsset_Blocking(sys:Conv_SoftClassPathToSoftClassRef(sys:MakeSoftClassPath(path .. "." .. name .. "_C"))) end)
    if ok and valid(r) then return r end
end

-- UI pieces reused from the game, so the screen looks like the other menu pages
M.TEXT_STYLE = "/Game/UI/Common/Text/TextStyle/SystemText/BP_SystemTextStyle"   -- body text on the Quests page
M.SUBHEAD = "/Game/UI/Common/Layout/Subhead/WBP_SystemSubhead"                  -- "Goal" / "Summary" headings
M.WINDOW = "/Game/UI/Common/Window/WBP_Cmn_Window"                               -- framed section (Equipment page)
M.LEFT_LINE = "/Game/UI/Common/Button/LeftLine/Widget/WBP_LeftLineButton"          -- framed row (Equipment page items)
M.KEY_ICON = "/Game/UI/Common/KeyIcon/WBP_KeyIcon"                                   -- SetInputAction: device's glyph
M.DECIDE_ACTION = "/Game/Input/UI/Common/InputAction/IA_UI_Common_Decide.IA_UI_Common_Decide"
M.CHECK_ICON = "/Game/UI/Textures/Icon/menu/ICON_Quest_Check.ICON_Quest_Check"   -- completed-quest check
M.ELEMENT_ICONS = "/Game/UI/Common/Icon/Element/WBP_ElementIconList"                 -- SetElementList(eElement[])
M.CONDITION_ICONS = "/Game/UI/Battle/Libra/Widget/Entry/WBP_BtlLibra_ConditionIconList" -- SetConditionList(...)
M.ITEM_ENTRY = "/Game/UI/Battle/Libra/Widget/Entry/WBP_BtlLibraEntry_Item"            -- SetContentId(item): icon + name
M.TUTORIAL_LAYOUT = "/Game/UI/Tutorial/WBP_TutorialLayout.WBP_TutorialLayout_C" -- what Help opens on confirm

-- eRace values (mucha_enums.hpp) -> ST_UI_Libra keys
M.RACE_KEY = { [0] = "None", "Animal", "Avian", "Aquatic", "Demon", "Human", "Machina", "Dragon", "Fairy", "Insect",
               "Stone", "Plantoid", "Reaper", "Chocobo", "Vision", "Beast" }

-- the data pak with the menu row (shipped in ~mods; tools/build_pak.sh). Without it the mod stays out
-- of the menu: the scene list would name a row the menu table doesn't have.
local MOD_DIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):match("^(.*)/Scripts/[^/]+$")) or "."
local pakChecked
function M.pakInstalled()
    if pakChecked == nil then
        -- Mods/FFRBestiary -> FFRS/Content/Paks/~mods (Mods, ue4ss, Win64, Binaries, FFRS)
        local f = io.open(MOD_DIR .. "/../../../../../Content/Paks/~mods/zzz_FFRBestiary_P.utoc", "rb")
        pakChecked = f ~= nil
        if f then f:close() else print("[FFRBestiary] menu-entry pak not found in FFRS/Content/Paks/~mods: extract the whole mod zip into the game folder\n") end
    end
    return pakChecked
end

-- Whether the menu table the game loaded has the pak's Bestiary row (nil: the menu subsystem isn't up yet). Another
-- mod's pak that replaces DT_MainMenuScene and loads after ours drops the row; the entry then showed as a dead "???"
-- (reproduced 25 Oct with the game's own table in a second pak).
local rowMissingLogged, rowSub
local function sceneRowLoaded()
    if not valid(rowSub) then rowSub = FindFirstOf("CPP_MainMenuSubsystem") end   -- one per world
    if not valid(rowSub) then return nil end
    local found, rows = false, 0
    local ok = pcall(function()
        rowSub.SceneDataMap:ForEach(function(k)
            rows = rows + 1
            if k:get().TagName:ToString() == M.SCENE_TAG then found = true end
        end)
    end)
    if not ok or rows == 0 then return nil end           -- the table isn't filled in yet
    if not found and not rowMissingLogged then
        rowMissingLogged = true
        print("[FFRBestiary] the main menu table has no Bestiary row: another mod's pak replaces DT_MainMenuScene; no menu entry\n")
    end
    return found
end

-- Put the Bestiary entry into the main menu, before System. The menu reads DA_MainMenuRoot.DisplaySceneList each time
-- it opens, so this only needs doing once per load of that asset.
function M.addMenuEntry()
    if not M.pakInstalled() then return false end
    local da = FindFirstOf("CPP_DA_MainMenuRoot")
    if not valid(da) then return false end
    local list = da.DisplaySceneList
    local n = #list
    if n == 0 then return false end
    for i = 1, n do
        if list[i].TagName:ToString() == M.SCENE_TAG then return true end
    end
    if not sceneRowLoaded() then return false end
    local last = list[n].TagName:ToString()
    if last == "UI.MainMenu.Scene.System" then
        list[n + 1] = { TagName = FName(last) }
        list[n].TagName = FName(M.SCENE_TAG)
    else
        list[n + 1] = { TagName = FName(M.SCENE_TAG) }
    end
    return true
end

-- The menu entry's name and page title in the game's language. The pak's row can only hold one fixed text (the game
-- has no "Bestiary" string of its own), so the main menu's copy of the row (CPP_MainMenuSubsystem.SceneDataMap) gets
-- the usual name for a bestiary in the language the game is set to (souha0624 asked for Japanese, 25 Oct).
-- ELanguage: Ja 0, En 1, De 2, Fr 3, Es 4, Ko 5, Zh_hant 6, Zh_hans 7.
local MENU_NAMES = { [0] = "モンスター図鑑", [2] = "Bestiarium", [3] = "Bestiaire", [4] = "Bestiario",
                     [5] = "몬스터 도감", [6] = "魔物圖鑑", [7] = "魔物图鉴" }
local menuSub, namedFor
function M.localizeMenuEntry()
    if not valid(menuSub) then menuSub = FindFirstOf("CPP_MainMenuSubsystem") end   -- one per world
    if not valid(menuSub) then return end
    local ok, lang = pcall(function() return StaticFindObject("/Script/mucha.Default__CPP_BFL_Localize"):GetLanguage() end)
    if not ok or lang == nil then return end
    local key = menuSub:GetFullName() .. "#" .. tostring(lang)
    if namedFor == key then return end                    -- once per subsystem and language
    namedFor = key
    local name = MENU_NAMES[tonumber(lang)]
    if not name then return end                           -- English (and anything else): the pak's "Bestiary"
    menuSub.SceneDataMap:ForEach(function(k, v)
        if k:get().TagName:ToString() == M.SCENE_TAG then
            local d = v:get()
            d.EntryName = FText(name)
            d.SceneTitle = FText(name)
        end
    end)
    print("[FFRBestiary] menu name for language " .. tostring(lang) .. "\n")
end

-- the open Bestiary screen (the host layout under the main menu, activated), or nil. The menu pools the widget, so
-- the one found last is checked first; the object search (slow) runs every third call (0.3 s) otherwise.
local lastHost, calls = nil, 0
function M.openHost()
    if valid(lastHost) then
        local ok, active = pcall(function() return lastHost:IsActivated() end)
        if ok and active then return lastHost end
    end
    calls = calls + 1
    if calls % 3 ~= 0 then return nil end
    for _, w in ipairs(FindAllOf(M.HOST_CLASS) or {}) do
        if valid(w) and w:GetFullName():find(M.HOST_PARENT, 1, true) then
            local ok, active = pcall(function() return w:IsActivated() end)
            if ok and active then lastHost = w; return w end
        end
    end
end

return M
