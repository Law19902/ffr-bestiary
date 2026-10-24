-- BestiaryMappings: writes the game's property mappings (ue4ss/Mappings.usmap) once, so the installer can edit the
-- two game tables the Bestiary needs. The installer turns this mod off again once the file exists.
-- the ue4ss folder, from where this script was loaded (Mods/BestiaryMappings/Scripts/main.lua); the process folder is
-- the game root when started from Steam, Binaries\Win64 otherwise
local UE4SS = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):match("^(.*)/Mods/[^/]+/Scripts/[^/]+$")) or "ue4ss"
local TARGET = UE4SS .. "/Mappings.usmap"
local function exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end; return false end

local done = false
local function dump()
    if done then return end
    done = true
    if exists(TARGET) then return end
    local ok, err = pcall(DumpUSMAP)
    print("[BestiaryMappings] DumpUSMAP -> " .. tostring(ok) .. " " .. tostring(err) .. "\n")
    -- UE4SS names the file <Project>-<version>.usmap in the ue4ss folder; give it a fixed name
    local list = io.popen('dir /b /o-d "' .. UE4SS:gsub("/", "\\") .. '\\*.usmap" 2>nul')
    local name = list and list:read("*l"); if list then list:close() end
    if name and name ~= "Mappings.usmap" then os.rename(UE4SS .. "/" .. name, TARGET) end
    print("[BestiaryMappings] " .. (exists(TARGET) and "wrote " .. TARGET or "no mappings file") .. "\n")
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ExecuteWithDelay(8000, function() ExecuteInGameThread(dump) end)
end)
ExecuteWithDelay(45000, function() ExecuteInGameThread(dump) end)
