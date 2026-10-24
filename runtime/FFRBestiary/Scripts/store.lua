-- Bestiary progress: which enemies were seen, and where. One JSON file per save slot, never inside the game's saves.
-- Progress follows the game's saves: it is written when the game saves to a slot and read when a slot is loaded, so
-- reloading without saving forgets what was seen since, exactly like the game does.
local json = require("json")
local game = require("game")
local data = require("bestiary_data")

local M = {}
-- this mod's folder, from where this script was loaded (paths relative to the process folder break when the game
-- is started from Steam, whose working folder is the game root, not Binaries\Win64)
local MOD_DIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):match("^(.*)/Scripts/[^/]+$")) or "ue4ss/Mods/FFRBestiary"
local DIR = MOD_DIR .. "/saves/"
os.execute('mkdir "' .. DIR:gsub("/", "\\") .. '" 2>nul')

M.units = {}        -- [unitId] = { seen = true, seenAreas = { [areaKey] = true }, fromSave = true if taken from the save }
M.visited = {}      -- [areaKey] = true: areas the player has been in (their enemies are listed, unseen ones as ???)
M.slot = nil        -- slot the progress belongs to (nil for an unsaved new game)
M.dirty = false

local function log(s) print("[FFRBestiary] " .. s .. "\n") end
local function path(slot) return DIR .. "slot" .. slot .. ".json" end

function M.markSeen(unitId, area)
    local u = M.units[unitId]
    if not u then u = { seen = true, seenAreas = {} }; M.units[unitId] = u; M.dirty = true end
    if area and not u.seenAreas[area] then u.seenAreas[area] = true; M.dirty = true end
end

-- What the game's save already knows, for a Bestiary installed mid-game (and for anything met without the mod):
-- enemies defeated or scanned count as seen, though not where (the list files them under the areas the game data
-- gives them, among the areas visited; their locations stay ??? until met again), and the maps the save marks as
-- visited (Map.perMapSaveDataMap[mapId].bIsVisited) count as visited areas, with the world-map island they are on.
local enemyIds
function M.seedFromSave(sd, records)
    if next(records or {}) == nil then return end         -- title screen / new game: nothing saved yet
    if not enemyIds then
        enemyIds = {}
        for _, e in ipairs(data.entries) do for _, u in ipairs(e.units) do enemyIds[u] = true end end
    end
    local n, v = 0, 0
    for id, r in pairs(records or {}) do
        if enemyIds[id] and not M.units[id] then
            local ok, known = pcall(function() return r.IsAnalyzed or (r.defeatNum or 0) > 0 end)
            if ok and known then M.units[id] = { seen = true, seenAreas = {}, fromSave = true }; n = n + 1 end
        end
    end
    local function visit(a) if a and not M.visited[a] then M.visited[a] = true; v = v + 1 end end
    -- the title screen's placeholder save has empty unit records: leave its map data alone (a crash at start-up
    -- happened around here once)
    local any = n > 0
    for _, r in pairs(records) do if any then break end; pcall(function() any = r.IsAnalyzed or (r.defeatNum or 0) > 0 end) end
    if not any then return end
    local ok, err = pcall(function()
        sd.Map.perMapSaveDataMap:ForEach(function(key, value)
            if value:get().bIsVisited then
                local a = data.mapArea[tostring(key:get())]
                visit(a)
                if a and data.areaRegion[a] then visit(data.islandArea[tostring(data.areaRegion[a])]) end
            end
        end)
    end)
    if not ok then log("visited maps: " .. tostring(err)) end
    if n + v > 0 then M.dirty = true end
    log("from the game save: " .. n .. " enemies, " .. v .. " visited areas")
end

function M.markVisited(area)
    if area and not M.visited[area] then M.visited[area] = true; M.dirty = true end
end

function M.load(slot)
    M.units, M.visited, M.slot, M.dirty = {}, {}, slot, false
    if slot == nil then return end
    local f = io.open(path(slot), "r")
    if not f then log("slot " .. slot .. ": no bestiary file yet"); return end
    local ok, data = pcall(json.decode, f:read("a")); f:close()
    if not ok or type(data) ~= "table" or type(data.units) ~= "table" then
        os.rename(path(slot), path(slot) .. ".bad")       -- kept for a look; the next save writes a fresh one
        log("slot " .. slot .. ": unreadable file (kept as .bad), starting empty"); return
    end
    local n = 0
    for id, u in pairs(data.units) do
        local areas = {}
        for _, a in ipairs(u.seenAreas or {}) do areas[a] = true end
        M.units[tonumber(id)] = { seen = u.seen ~= false, seenAreas = areas, fromSave = u.fromSave == true }
        n = n + 1
    end
    for _, a in ipairs(data.visitedAreas or {}) do M.visited[a] = true end
    log("slot " .. slot .. ": loaded " .. n .. " units")
end

-- write the progress for `slot`; `records` (game unitList by SaveId) supplies the scanned flag for the file
function M.save(slot, records)
    local units = {}
    for id, u in pairs(M.units) do
        local areas = {}
        for a in pairs(u.seenAreas) do areas[#areas + 1] = a end
        table.sort(areas)
        local r = records and records[id]
        units[tostring(id)] = { seen = true, scanned = r and r.IsAnalyzed or false, seenAreas = areas, fromSave = u.fromSave or nil }
    end
    local visited = {}
    for a in pairs(M.visited) do visited[#visited + 1] = a end
    table.sort(visited)
    local tmp = path(slot) .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then log("cannot write " .. tmp); return end
    f:write(json.encode({ version = 1, slot = slot, units = units, visitedAreas = visited }), "\n"); f:close()
    -- Windows can't rename over a file: move the old one aside first, so a failed rename loses nothing
    local file, bak = path(slot), path(slot) .. ".bak"
    os.remove(bak); os.rename(file, bak)
    if not os.rename(tmp, file) then os.rename(bak, file); log("cannot replace " .. file); return end
    os.remove(bak)
    M.slot, M.dirty = slot, false
    log("slot " .. slot .. ": saved")
end

-- Follow the game's saves: a new save object means a load (or a new game); the same object with a new timestamp
-- means the game just saved. Either way the timestamp names the slot.
local lastObj, lastTicks, pendingSave
function M.poll()
    local sd = game.saveData()
    if not sd then return end
    -- the object's full name has a unique number: a new save object allocated where the old one was still differs
    local obj, ticks = sd:GetFullName(), game.savedTicks(sd)
    if obj ~= lastObj then
        lastObj, lastTicks, pendingSave = obj, ticks, nil
        M.load(game.slotForTicks(ticks))
        M.seedFromSave(sd, game.records(sd))
    elseif ticks ~= lastTicks then
        lastTicks, pendingSave = ticks, ticks
    end
    if pendingSave then                                  -- the slot summary may update a moment after the save
        local slot = game.slotForTicks(pendingSave)
        if slot then M.save(slot, game.records(sd)); pendingSave = nil end
    end
end

return M
