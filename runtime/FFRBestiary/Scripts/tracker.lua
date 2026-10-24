-- Seen tracking: once a second, note every enemy unit in the battle and the area it is fought in. Polling (instead
-- of a battle-start hook) also catches units that join mid-battle: summons, boss phases, form changes.
local game = require("game")
local store = require("store")
local data = require("bestiary_data")

local M = {}
local lastNamedArea

-- area key for where the player is now (see tools/export_data.py: mapArea / islandArea / stageArea)
function M.currentArea()
    local map, island = game.location()
    if not map then return lastNamedArea end
    local area
    if map == data.worldMapId then area = data.islandArea[tostring(island)]
    else area = data.mapArea[tostring(map)] end
    if not area then                                     -- unnamed cutscene stage: the area the player came from
        local from = data.stageArea[tostring(map)]
        area = (from and #from == 1) and from[1] or lastNamedArea
    end
    if area then lastNamedArea = area end
    return area
end

-- the area is taken from the last poll outside battle (at most a second old), in case the battle stage reports
-- a map of its own
local fieldArea
function M.poll()
    local ids = game.battleEnemies()
    if not ids then fieldArea = M.currentArea(); store.markVisited(fieldArea); return end
    for _, id in ipairs(ids) do store.markSeen(id, fieldArea) end
end

return M
