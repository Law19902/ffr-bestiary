-- The Bestiary screen. The menu row opens the game's Help layout; this turns it into the bestiary: the window covers
-- the whole page, its native list shows areas (with counts) and their enemies, and a detail panel sits beside it.
-- Text uses the game's own style and heading widget (as on the Quests page); scanned enemies get the Quests check.
local game = require("game")
local store = require("store")
local data = require("bestiary_data")
local worldmap = require("worldmap_data")

local M = {}
M.showAll = false                  -- DEVELOPMENT: treat every enemy as seen everywhere (F7 toggles)

local valid = game.valid
local function log(s) print("[FFRBestiary] " .. s .. "\n") end

-- layout, in the UI's 1920x1080 design units
local WINDOW_W, WINDOW_H = 1760, 830
local LIST_W, LIST_H = 640, 670     -- wide enough for "Dirnado, the Continent of Wind" plus its counts
local DETAIL_W = 918                -- inside the info frame (its padding takes 2 x PANEL_PAD of the window's room)
local DETAIL_H = LIST_H + 76       -- the detail panel's room (down to just above the window's bottom edge)
local COLUMN_GAP = 30
local SPRITE = 320
local SPRITE_FILL = 0.9            -- the enemy fills this much of the sprite box (its larger side)...
local SPRITE_FILL_MEASURED = 0.97  -- ...nearly all of it when its outline was measured (exact)
local MEASURE_SCALE = 0.5          -- dev measure mode: canvas drawn at half its fitted size, so nothing is clipped
local SPRITE_MAX_PX = 3.0          -- ...but small ones are drawn no bigger than 3 screen pixels per sprite pixel
local LABEL_W = 180
local DROP_LABEL_W = 190           -- "Items Dropped" / "Stealable Items" (left room for "Lightning Scroll I" etc.)
local PANEL_PAD = 16               -- inside a framed panel (the game's WBP_Cmn_Window), each side
local VALUE_W = DETAIL_W - SPRITE - 24 - LABEL_W - 10 - 2 * PANEL_PAD - 2 * 12 - 8   -- detail - sprite - gap - label - panel - row frame
local TOP_H = 521                  -- sprite + locations | stats: a fixed height, so the panel never changes size
local AREA_SCALE = 0.78           -- locations text, relative to the panel's
local AREAS_H = TOP_H - SPRITE - 76 -- locations list under the sprite (heading and frame take the rest); scrolls
local MAP_H = 536                  -- world map under an area's counts, the panel's full width
local MAP_INSET = 12               -- clear of the info frame's border, each side
local MAP_WORLD_FILL = 0.8         -- the world's height in it (the game's map screen leaves sea all round)
local MAP_MARKER = 36              -- the selected area's marker on it (at 64 it reached the next island: Siren's
                                   -- Tower's looked like it was on Dirnado, 25 Oct)
local MAP_MARKER_TEX = "/Game/UI/Textures/menu/T_WldMapCursor_Focus.T_WldMapCursor_Focus"   -- the world map's cursor
-- the game's map screen (WBP_WldMapBG / WBP_WldMapLayout): its sea, vignette and frame
local MAP_LAYERS = { { tex = "/Game/UI/Textures/MapCapture/Wld/T_Wld_ocean.T_Wld_ocean", z = -20 },
                     { tex = "/Game/UI/Textures/Menu/T_Menu_Map_Vignette.T_Menu_Map_Vignette", z = 50 },
                     { tex = "/Game/UI/Textures/MapCapture/Wld/T_Wld_frame.T_Wld_frame", z = 60 } }
-- affinity groups shown in the scan panel (DA_BtlLibra styles Weak/Halved/Invalid/Absorb), eResistance values
-- (labels: the scan panel's own keys have no text, so the battle's damage words: Weak / Resisted / Immune / Absorbed)
local RESIST_ROWS = { { key = "UIBtlProp_Weakness", value = 1 }, { key = "UIBtlProp_Halved", value = 2 },
                      { key = "UIBtlProp_Invalid", value = 3 }, { key = "UIBtlProp_Absorb", value = 4 } }
local ELEMENT_ICONS_MAX = 8        -- eElement 1..8
local MAX_CONDITIONS = 21           -- eUnitStatusCondition values a unit can resist (1..21)
local NEST = 34                    -- enemy rows sit this far in from their area header
local FACE = 40                    -- face icon before an enemy's name in the list
local TOP_PAD = 26                 -- the window's title was collapsed; keep content clear of the frame
local GREY = { R = 0.55, G = 0.58, B = 0.63, A = 1.0 }
local DIM = { R = 0.42, G = 0.44, B = 0.48, A = 1.0 }
local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local UNKNOWN = "???"
local OTHER_PLACES = "Other"          -- list group for enemies met where no place name could be found
local ENCOUNTERED, SCANNED = "Encountered", "Scanned"   -- the game has no strings for these

-- widget helpers --------------------------------------------------------------------------------------------------
local function walk(w, test, depth)
    depth = depth or 0
    if not valid(w) or depth > 16 then return nil end
    if test(w) then return w end
    local okTree, tree = pcall(function() return w.WidgetTree end)
    if okTree and valid(tree) and depth > 0 then return walk(tree.RootWidget, test, depth + 1) end
    local okN, n = pcall(function() return w:GetChildrenCount() end)
    if okN and n then
        for i = 0, n - 1 do
            local hit = walk(w:GetChildAt(i), test, depth + 1)
            if hit then return hit end
        end
    end
end
local function find(w, name) return walk(w, function(x) return x:GetFName():ToString() == name end) end

local host, ui                     -- open host widget, and the widgets built into it
local create, widgetRow, panel, viewportScale, faceTexture, placeOnMap, loadQueuedTile
local styleClass, subheadClass, checkTex

local function new(kind, outer)
    local module = kind:find("^Common") and "/Script/CommonUI." or (kind:find("^CPP_") and "/Script/mucha." or "/Script/UMG.")
    local o = StaticConstructObject(StaticFindObject(module .. kind), outer or host.WidgetTree)
    assert(valid(o), "cannot create " .. kind)
    return o
end

local function paint(t, color) t:SetColorAndOpacity({ SpecifiedColor = color or WHITE, ColorUseRule = 0 }) end

-- body text in the game's SystemText style
local function text(value, color)
    local t = new("CommonTextBlock")
    if valid(styleClass) then pcall(function() t:SetStyle(styleClass) end) end
    t:SetText(FText(value or ""))
    paint(t, color)
    return t
end

local function set(t, value, color) t:SetText(FText(value or "")); paint(t, color) end

-- a heading with the game's underline (WBP_SystemSubhead)
local function heading(value)
    local pc = FindFirstOf("PlayerController")
    local h = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, subheadClass, pc)
    h:SetTitle(FText(value or ""))
    return h
end

local function sized(content, w, h)
    local b = new("SizeBox")
    if w then b:SetWidthOverride(w) end
    if h then b:SetHeightOverride(h) end
    if content then b:SetContent(content) end
    return b
end

local function spacer(h) local s = new("Spacer"); s:SetSize({ X = 1, Y = h }); return s end

local function icon(size, outer)
    local img = new("Image", outer)
    if valid(checkTex) then img:SetBrushFromTexture(checkTex, false) end
    img:SetDesiredSizeOverride({ X = size, Y = size })
    return img
end

-- a framed panel like the Equipment page's sections (WBP_Cmn_Window) around `content`; falls back to the bare
-- content if the game's widget is missing
panel = function(content)
    local pad = new("VerticalBox")
    pad:AddChildToVerticalBox(content):SetPadding({ Left = PANEL_PAD, Top = 8, Right = PANEL_PAD, Bottom = 8 })
    local w = create(game.WINDOW)
    if not w then return pad end
    local ok, err = pcall(function() find(w.WidgetTree.RootWidget, "Window_Content"):SetContent(pad) end)
    if not ok then log("panel: " .. tostring(err)); return pad end
    return w
end

-- "Label    value" row; returns the value text
-- `content` in the game's framed row (WBP_LeftLineButton, the bar behind each item / ability on the Equipment page),
-- for display only: not focusable or clickable. Grows past its usual 40 px for two-line text.
local FRAME_PAD = 12               -- content inset inside the bar, each side
local function framed(content)
    local b = create(game.LEFT_LINE)
    if not b then return content end
    local ok = pcall(function()
        local root = b.WidgetTree.RootWidget
        local slot = find(root, "Overlay_Content") or find(root, "Overlay_0")
        local s = slot:AddChildToOverlay(content)
        s:SetVerticalAlignment(2); s:SetHorizontalAlignment(0)
        s:SetPadding({ Left = FRAME_PAD, Top = 4, Right = FRAME_PAD, Bottom = 4 })
        local box = find(root, "SizeBox_0")
        if box then box:ClearHeightOverride(); box:SetMinDesiredHeight(40) end
    end)
    if not ok then return content end
    pcall(function() b:SetIsFocusable(false) end)
    b:SetVisibility(3)                                    -- HitTestInvisible: the controller and mouse pass it by
    return b
end

local function row(parent, key, valueW)
    local line = new("HorizontalBox")
    line:AddChildToHorizontalBox(sized(text(game.libra(key) or key, GREY), LABEL_W, nil))
    local v = text("")
    pcall(function() v:SetAutoWrapText(true) end)
    line:AddChildToHorizontalBox(sized(v, valueW or VALUE_W, nil))
    local f = framed(line)
    parent:AddChildToVerticalBox(f):SetPadding({ Left = 0, Top = 2, Right = 0, Bottom = 2 })
    return v, f
end

-- a game widget (WBP class path) for this screen
create = function(path)
    local cls = game.class(path)
    if not valid(cls) then log("missing widget " .. path); return nil end
    local pc = FindFirstOf("PlayerController")
    return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, cls, pc)
end

-- "Label    [text][widgets]" row; returns the value text and the box that holds the widgets
widgetRow = function(parent, key, labelW)
    local line = new("HorizontalBox")
    line:AddChildToHorizontalBox(sized(text(game.libra(key) or key, GREY), labelW or LABEL_W, nil))
    local v = text("")
    line:AddChildToHorizontalBox(v):SetVerticalAlignment(2)
    local box = new("HorizontalBox")
    line:AddChildToHorizontalBox(box):SetVerticalAlignment(2)
    parent:AddChildToVerticalBox(framed(line)):SetPadding({ Left = 0, Top = 2, Right = 0, Bottom = 2 })
    return v, box
end

-- build (once per host widget; the game pools it) ---------------------------------------------------------------
local function build()
    -- looked up again on every build: after a return to the title the old screen (and with it the only references to
    -- these) can be gone, and a cached wrapper would point at freed memory
    styleClass = game.class(game.TEXT_STYLE)
    subheadClass = game.class(game.SUBHEAD)
    checkTex = game.load(game.CHECK_ICON)

    local root = host.WidgetTree.RootWidget
    local box, title, gap = find(root, "CPP_CommonSizeBox_0"), find(root, "Text_Title"), find(root, "Spacer_101")
    local slot, listBox, lv = find(root, "NamedSlot_93"), find(root, "SizeBox_0"), find(root, "CmnListView")
    assert(box and title and slot and listBox and lv, "host layout changed")
    ui = { list = lv, entryIcons = {} }

    box:SetWidthOverride(WINDOW_W); box:SetHeightOverride(WINDOW_H)
    listBox:SetWidthOverride(LIST_W); listBox:SetHeightOverride(LIST_H)
    title:SetVisibility(1)                                -- Collapsed: the page header already says BESTIARY
    if gap then gap:SetVisibility(1) end

    local body = new("HorizontalBox")
    slot:SetContent(body)                                 -- detaches the list box from the slot
    local column = new("VerticalBox")
    body:AddChildToHorizontalBox(column)
    local summary = new("HorizontalBox")
    ui.summary = text("", GREY)
    ui.summaryScanned = text("", GREY)
    summary:AddChildToHorizontalBox(text(ENCOUNTERED .. "  ", GREY))
    summary:AddChildToHorizontalBox(ui.summary)
    summary:AddChildToHorizontalBox(sized(nil, 30, nil))
    summary:AddChildToHorizontalBox(icon(26)):SetVerticalAlignment(2)
    summary:AddChildToHorizontalBox(text(" " .. SCANNED .. "  ", GREY))
    summary:AddChildToHorizontalBox(ui.summaryScanned)
    column:AddChildToVerticalBox(sized(summary, LIST_W, nil)):SetPadding({ Left = 14, Top = TOP_PAD, Right = 0, Bottom = 8 })
    column:AddChildToVerticalBox(listBox)
    body:AddChildToHorizontalBox(sized(nil, COLUMN_GAP, nil))

    ui.faceHold = new("VerticalBox")                      -- keeps loaded face textures alive (never shown)
    ui.faceHold:SetVisibility(1)
    column:AddChildToVerticalBox(ui.faceHold)
    local detail = new("VerticalBox")
    ui.detail = detail
    -- an enemy with many affinities / locations / long traits can need more room: the panel then shrinks to fit
    local fit = new("ScaleBox")
    ui.fit = fit
    pcall(function() fit:SetStretch(2); fit:SetStretchDirection(1) end)   -- ScaleToFit, DownOnly
    local fitSlot = fit:SetContent(detail)
    pcall(function() fitSlot:SetHorizontalAlignment(1); fitSlot:SetVerticalAlignment(1) end)   -- top left
    -- the whole info side in the game's window frame, like the fast-travel list on the map screen
    body:AddChildToHorizontalBox(panel(sized(fit, DETAIL_W, DETAIL_H)))

    detail:AddChildToVerticalBox(spacer(TOP_PAD))          -- clear of the window frame
    -- name bar like the scan panel's: name, then Lv. and the scanned check on the right
    local nameLine = new("HorizontalBox")
    ui.name = heading("")
    nameLine:AddChildToHorizontalBox(sized(ui.name, DETAIL_W - 254, nil))
    nameLine:AddChildToHorizontalBox(sized(nil, 24, nil))  -- keep the heading's underline clear of "Lv."
    ui.level = text("")
    nameLine:AddChildToHorizontalBox(sized(ui.level, 160, nil)):SetVerticalAlignment(2)
    ui.check = icon(40)
    nameLine:AddChildToHorizontalBox(ui.check):SetVerticalAlignment(2)
    detail:AddChildToVerticalBox(nameLine)
    ui.forms = new("HorizontalBox")
    ui.formsKey = create(game.KEY_ICON)
    if ui.formsKey then
        pcall(function() ui.formsKey:SetInputAction(game.load(game.DECIDE_ACTION)) end)
        ui.forms:AddChildToHorizontalBox(ui.formsKey):SetVerticalAlignment(2)
    end
    ui.formsText = text("", GREY)
    ui.forms:AddChildToHorizontalBox(ui.formsText):SetPadding({ Left = 8, Top = 0, Right = 0, Bottom = 0 })
    detail:AddChildToVerticalBox(ui.forms):SetPadding({ Left = 4, Top = 2, Right = 0, Bottom = 0 })
    detail:AddChildToVerticalBox(spacer(6))
    local areaInfo = new("VerticalBox")                   -- shown for area headers
    ui.areaEnc = row(areaInfo, ENCOUNTERED)
    ui.areaScan = row(areaInfo, SCANNED)
    ui.areaInfo = panel(areaInfo)
    detail:AddChildToVerticalBox(sized(ui.areaInfo, DETAIL_W / 2, nil))
    -- the world map under them, drawn like the game's map screen: its sea filling the space, the world's island tiles
    -- centred in it, its vignette and frame on top, and a marker. Textures load one a tick (loadQueuedTile).
    ui.mapW, ui.mapH = DETAIL_W - 2 * MAP_INSET, MAP_H     -- inset: its frame art clipped into the window's border
    local wh = math.floor(MAP_H * MAP_WORLD_FILL)
    local ww = math.floor(wh * worldmap.aspect)
    ui.world = { x = (ui.mapW - ww) / 2, y = (ui.mapH - wh) / 2, w = ww, h = wh }
    ui.map = sized(nil, ui.mapW, ui.mapH)
    pcall(function() ui.map:SetClipping(1) end)          -- tiles reaching past the map's edge are cut off
    ui.mapCanvas = new("CanvasPanel")
    ui.map:SetContent(ui.mapCanvas)
    ui.mapTiles, ui.mapShow, ui.mapQueue, ui.mapQueued = {}, {}, {}, {}   -- queue: jobs in order; queued: tiles in it
    for _, l in ipairs(MAP_LAYERS) do
        local img = new("Image")
        img:SetVisibility(1)                              -- until its texture is in
        local slot = ui.mapCanvas:AddChildToCanvas(img)
        slot:SetPosition({ X = 0, Y = 0 }); slot:SetSize({ X = ui.mapW, Y = ui.mapH }); slot:SetZOrder(l.z)
        ui.mapQueue[#ui.mapQueue + 1] = { img = img, tex = l.tex }
    end
    ui.mapMarker = new("Image")
    local markerTex = game.load(MAP_MARKER_TEX)
    if markerTex then ui.mapMarker:SetBrushFromTexture(markerTex, false)
    else ui.mapMarker:SetColorAndOpacity({ R = 1, G = 0.3, B = 0.2, A = 1 }) end
    ui.mapMarkerSlot = ui.mapCanvas:AddChildToCanvas(ui.mapMarker)
    ui.mapMarkerSlot:SetSize({ X = MAP_MARKER, Y = MAP_MARKER })
    ui.mapMarkerSlot:SetZOrder(100)
    detail:AddChildToVerticalBox(ui.map):SetPadding({ Left = MAP_INSET, Top = 12, Right = 0, Bottom = 0 })

    -- Fixed layout (players saw the panel change size from enemy to enemy: it shrank to fit whatever an entry
    -- needed): left the sprite with the locations under it, right the stats in a box of fixed height whose text alone
    -- shrinks for the few entries that need more room (many affinities, statuses and long traits).
    local top = new("HorizontalBox")
    ui.top = top
    detail:AddChildToVerticalBox(sized(top, nil, TOP_H))
    local leftCol = new("VerticalBox")
    top:AddChildToHorizontalBox(sized(leftCol, SPRITE, TOP_H))
    ui.spriteBox = sized(nil, SPRITE, SPRITE)
    pcall(function() ui.spriteBox:SetClipping(1) end)    -- ClipToBounds: nothing spills over the text
    leftCol:AddChildToVerticalBox(ui.spriteBox)
    top:AddChildToHorizontalBox(sized(nil, 24, nil))
    local info = new("VerticalBox")
    ui.infoPanel = info
    local infoFit = new("ScaleBox")
    pcall(function() infoFit:SetStretch(2); infoFit:SetStretchDirection(1) end)   -- ScaleToFit, DownOnly
    local infoSlot = infoFit:SetContent(info)
    pcall(function() infoSlot:SetHorizontalAlignment(1); infoSlot:SetVerticalAlignment(1) end)   -- top left
    top:AddChildToHorizontalBox(sized(panel(sized(infoFit, nil, TOP_H - 24)), DETAIL_W - SPRITE - 24, TOP_H))

    -- fields in the scan panel's order (DA_BtlLibra); each row has a text value and/or the game's own icon widgets
    ui.affinity, ui.affinityBox = widgetRow(info, "UI_Libra_Resistance")
    ui.affinityRows = new("VerticalBox")                  -- one line per group (Weak / Resisted / ...)
    ui.affinityBox:AddChildToHorizontalBox(sized(ui.affinityRows, VALUE_W, nil))
    -- each group on its own line: its word, then one icon widget per element in a wrapping row, so a long list
    -- carries on onto the next line at full size (one widget holding eight icons can't wrap)
    ui.elementGroups = {}
    for _, kind in ipairs(RESIST_ROWS) do
        local g = { row = new("WrapBox"), label = text(game.battleWord(kind.key) or kind.key, GREY), icons = {} }
        g.row:AddChildToWrapBox(g.label):SetPadding({ Left = 0, Top = 0, Right = 8, Bottom = 0 })
        for i = 1, ELEMENT_ICONS_MAX do
            local w = create(game.ELEMENT_ICONS)
            if w then g.row:AddChildToWrapBox(w); g.icons[i] = w end
        end
        ui.affinityRows:AddChildToVerticalBox(g.row)
        ui.elementGroups[kind.value] = g
    end
    ui.hp = row(info, "UI_Libra_HP")
    ui.race = row(info, "UI_Libra_Race")
    ui.resist, ui.resistBox = widgetRow(info, "UI_Libra_Condition_Invalid")
    -- one icon widget per status in a wrapping row (like the affinities)
    ui.conditionWrap = new("WrapBox")
    ui.resistBox:AddChildToHorizontalBox(sized(ui.conditionWrap, VALUE_W, nil))
    ui.conditions = {}
    for i = 1, MAX_CONDITIONS do
        local w = create(game.CONDITION_ICONS)
        if not w then break end
        ui.conditionWrap:AddChildToWrapBox(w); ui.conditions[i] = w
    end
    info:AddChildToVerticalBox(spacer(6))
    ui.traits, ui.traitRows = {}, {}
    for k, key in ipairs({ "UI_Libra_1", "UI_Libra_2", "UI_Libra_3", "UI_Libra_4" }) do
        ui.traits[k], ui.traitRows[k] = row(info, key)
    end

    detail:AddChildToVerticalBox(spacer(6))
    local scan = new("HorizontalBox")
    local left, right = new("VerticalBox"), new("VerticalBox")
    scan:AddChildToHorizontalBox(sized(left, DETAIL_W / 2 - PANEL_PAD, nil))
    scan:AddChildToHorizontalBox(sized(right, DETAIL_W / 2 - PANEL_PAD, nil))
    ui.items = {}
    for _, f in ipairs({ { left, "UI_Libra_NormalDrop", "DropNormalItem" }, { left, "UI_Libra_RareDrop", "DropRareItem" },
                         { right, "UI_Libra_NormalSteal", "StealNormalItem" }, { right, "UI_Libra_RareSteal", "StealRareItem" } }) do
        local t, box = widgetRow(f[1], f[2], DROP_LABEL_W)   -- narrower label: long item names fit their column
        local w = create(game.ITEM_ENTRY)
        if w then box:AddChildToHorizontalBox(w) end
        ui.items[#ui.items + 1] = { text = t, box = box, widget = w, field = f[3] }
    end
    ui.scan = panel(scan)
    detail:AddChildToVerticalBox(ui.scan)

    local where = new("VerticalBox")
    where:AddChildToVerticalBox(heading("Locations"))     -- the game has no string for this
    ui.areasScroll = new("ScrollBox")
    where:AddChildToVerticalBox(sized(ui.areasScroll, nil, AREAS_H))
    ui.areas = new("VerticalBox")
    -- smaller text, so enemies found in many places fit (players couldn't see them all, 25 Oct)
    local areasScale = new("ScaleBox")
    pcall(function() areasScale:SetStretch(7); areasScale:SetUserSpecifiedScale(AREA_SCALE) end)   -- UserSpecified
    local areasSlot = areasScale:SetContent(ui.areas)
    pcall(function() areasSlot:SetHorizontalAlignment(1); areasSlot:SetVerticalAlignment(1) end)   -- top left
    ui.areasScroll:AddChild(areasScale)
    ui.areasHead = panel(where)                           -- shown / hidden as a whole
    leftCol:AddChildToVerticalBox(ui.areasHead):SetPadding({ Left = 0, Top = 6, Right = 0, Bottom = 0 })
end

-- data --------------------------------------------------------------------------------------------------------------
local ELEMENT = { "Fire", "Ice", "Wind", "Earth", "Thunder", "Water", "Light", "Dark" }   -- APPROXIMATION: text until the icons are wired
local RESIST = { [1] = "Weak", [2] = "Halved", [3] = "Null", [4] = "Absorb", [5] = "Reflect" }

local rows = {}                   -- list rows: { header = area, seen = n, total = m } or { entry = e, known = bool }
local expanded = {}               -- [area] = true when its enemies are shown
local shown

local function areaName(key)
    if key == "?" then return OTHER_PLACES end           -- enemies met somewhere without a place name
    local a = data.areas[key]
    return a and a.table and game.text(a.table, a.key) or key
end

-- areas where some unit of entry `e` was seen
local function seenAreasOf(e)
    local out = {}
    if M.showAll then for _, a in ipairs(e.areas) do out[a] = true end; return out end
    for _, u in ipairs(e.units) do
        local s = store.units[u]
        if s then
            for a in pairs(s.seenAreas) do out[a] = true end
            -- seen where no area could be named (enemies taken from the save are filed by groupAreasOf instead)
            if next(s.seenAreas) == nil and not s.fromSave then out["?"] = true end
        end
    end
    return out
end

-- areas where entry `e` counts as met: where it was seen, plus, if the save already knew it (the mod was installed
-- mid-game, so it never saw where), its data areas the player has visited. Areas not reached yet never count.
local function knownAreasOf(e)
    local out = seenAreasOf(e)
    for _, u in ipairs(e.units) do
        local s = store.units[u]
        if s and s.fromSave then
            for _, a in ipairs(e.areas) do if store.visited[a] then out[a] = true end end
        end
    end
    return out
end

-- areas the list files entry `e` under: the known ones. A save-known entry with none of its areas visited (fought in
-- a story event the save doesn't mark as a visit) goes under "Other": listing it under its data areas named places
-- the player had never been (Arcane Library, 25 Oct).
local function groupAreasOf(e)
    local out = knownAreasOf(e)
    if next(out) == nil then
        for _, u in ipairs(e.units) do
            local s = store.units[u]
            if s and s.fromSave then out["?"] = true end
        end
    end
    return out
end

-- Units only ever fought before the party has Libra, so they can never be scanned: they count as scanned once met
-- (players asked for these to be completable, 25 Oct). The prologue's event fights on the Battlefield (their later
-- versions, the Battlefield's random encounters, Shock Trooper and Iron Giant are "(5章)" chapter-5 units that can
-- be scanned) and the Earth Shrine boss. From extracted/locations.json: event-only on the Battlefield, plus Belmodar.
local NO_LIBRA = { [1] = true, [90] = true, [412] = true, [416] = true, [401] = true }

local function isScanned(e)
    if M.showAll then return true end                     -- dev (F7): everything seen and scanned
    for _, u in ipairs(e.units) do
        local r = ui.records[u]; if r and r.IsAnalyzed then return true end
        if NO_LIBRA[u] and (store.units[u] or (r and (r.defeatNum or 0) > 0)) then return true end
    end
    return false
end

local function entryName(e)
    local p = game.unitParam(e.units[1]) or {}
    return p.Name or ("#" .. e.units[1])
end

-- UE4SS hands TMap / TArray out-params back as Lua tables; values may be numbers, enum names or wrapped params
local function plain(v)
    if type(v) == "userdata" then
        local ok, x = pcall(function() return v:get() end)
        if ok and x ~= nil then v = x end
        if type(v) == "userdata" and v.ToString then return v:ToString() end
    end
    return v
end
local function enumIndex(v, names)
    v = plain(v)
    if type(v) == "number" then return v end
    local name = tostring(v):match("::(%w+)$") or tostring(v)
    for i, n in pairs(names) do if n == name then return i end end
end

local ELEMENT_NAMES = { [1] = "Fire", "Ice", "Wind", "Earth", "Thunder", "Water", "Light", "Dark" }
local RESIST_NAMES = { [1] = "Weakness", "Halved", "Invalid", "Absorb", "Reflect" }

local function affinities(p)
    local out = {}
    pcall(function()
        for k, v in pairs(p.ElementResistanceList or {}) do
            local key, val = k, v
            if type(v) == "table" then key, val = v.Key, v.Value end   -- array of pairs, if that's the shape
            local r = RESIST[enumIndex(val, RESIST_NAMES) or 0]
            if r then out[#out + 1] = r .. " " .. (ELEMENT[enumIndex(key, ELEMENT_NAMES) or 0] or "?") end
        end
    end)
    table.sort(out)
    return #out > 0 and table.concat(out, ", ") or (game.libra("UI_Libra_Nodata") or "-")
end

local function traits(p)
    local out = {}
    pcall(function()
        for i = 1, 4 do
            local t = p.Traits and p.Traits[i]
            if t == nil then break end
            local s = plain(t)
            if type(s) == "string" and s ~= "" then out[#out + 1] = s end
        end
    end)
    return out
end

local hpRate
local logged = false
local function logShapes(p)
    if logged then return end
    logged = true
    local parts = {}
    for k, v in pairs(p.ElementResistanceList or {}) do parts[#parts + 1] = type(k) .. ":" .. tostring(k) .. "=" .. type(v) .. ":" .. tostring(plain(v)) end
    log("shapes: elements {" .. table.concat(parts, ", ") .. "} traits " .. type(p.Traits) .. " n=" .. tostring(p.Traits and #p.Traits))
end

-- enemy HP as the battle shows it: the table value times the save's difficulty rate (Expert: x1.6)
hpRate = function()
    local d = 1
    pcall(function() d = plain(game.saveData().Player.GameDifficulty) end)
    return data.enemyHpRate[tostring(enumIndex(d, { [0] = "Easy", "Normal", "Expert" }) or 1)] or 1
end

-- detail panel ------------------------------------------------------------------------------------------------------
-- the enemy's battle sprite, playing its idle animation, in the game's own SpriteStudio player. (The game's
-- WBP_UnitSsPlayerWidget looks projects up by unit in a table that only has party members and Visions.)
local function setSprite(id)
    pcall(function()
        if not valid(ui.sprite) then
            ui.sprite = new("CPP_MuchaSsPlayerWidget")
            ui.spriteBack = new("Border")                 -- clear; magenta in the dev measure mode
            ui.spriteBack:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
            ui.spriteBack:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
            ui.spriteBack:SetContent(ui.sprite)
            ui.spriteBox:SetContent(ui.spriteBack)
            ui.sprite:SetRenderTransformPivot({ X = 0.5, Y = 0.5 })
        end
        local path = id and data.sprites[tostring(id)]
        local tex = id and data.spriteTex and data.spriteTex[tostring(id)]   -- a recolour's own colours (see below)
        local project = path and game.load(path)
        ui.sprite:SetVisibility(project and 4 or 1)          -- SelfHitTestInvisible / Collapsed
        local key = path and (path .. "|" .. (tex or ""))
        if not project or (ui.spriteFor == key and not M.measure) then return end
        ui.spriteFor = key
        -- The widget draws the animation's canvas fitted into the box (k box pixels per sprite pixel), centred.
        -- Scale it so the enemy fills the box (whole screen pixels per sprite pixel, so it stays sharp), and move the
        -- enemy's centre to the box centre. The enemy's outline comes from measuring it as the game draws it
        -- (spriteBox: x0, x1, y0, y1 in sprite pixels from the canvas centre, y down; tools/sprite_measure.py);
        -- without one, from the estimate in spriteSize (tools/sprite_bounds.py).
        -- The widget stretches the canvas to fill the (square) box: kx, ky box pixels per sprite pixel across and down,
        -- unequal unless the canvas is square, so the scale below is per axis to undo it. (spriteBox was measured
        -- assuming one k for both axes, min(kx, ky); fx, fy convert it to true sprite pixels.)
        local b = data.spriteSize[path] or { cw = 256, ch = 256, py = 0, w = 128, h = 128, cy = 64 }
        local kx, ky = SPRITE / b.cw, SPRITE / b.ch
        local k = math.min(kx, ky)
        local m = data.spriteBox and data.spriteBox[path]
        local bw, bh, cx, cy
        if m then
            local fx, fy = k / kx, k / ky
            bw, bh, cx, cy = (m[2] - m[1]) * fx, (m[4] - m[3]) * fy, (m[1] + m[2]) / 2 * fx, (m[3] + m[4]) / 2 * fy
        else bw, bh, cx, cy = b.w, b.h, 0, -(b.py * b.ch + b.cy) end
        local px = math.min(SPRITE_MAX_PX, (m and SPRITE_FILL_MEASURED or SPRITE_FILL) * SPRITE / math.max(bw, bh, 1))
        local vs = viewportScale()                       -- screen px per design px
        -- whole screen pixels per sprite pixel when there is room for 2 or more (sharp); below that the exact fit, as
        -- rounding 1.9 down to 1 would halve the enemy
        if px * vs >= 2 then px = math.floor(px * vs) / vs end
        local sx, sy, tx, ty = px / kx, px / ky, -px * cx, -px * cy
        if M.measure then sx, sy, tx, ty = MEASURE_SCALE, MEASURE_SCALE, 0, 0 end
        M.lastSprite = { path = path, k = k, vs = vs }
        ui.spriteBack:SetBrushColor(M.measure and { R = 1, G = 0, B = 1, A = 1 } or { R = 0, G = 0, B = 0, A = 0 })
        ui.sprite:SetRenderScale({ X = sx, Y = sy })
        ui.sprite:SetRenderTranslation({ X = tx, Y = ty })
        ui.sprite:SetSsProject(project)
        -- A recoloured enemy (Metal Cactuar, Goblin Guard, ...) plays another enemy's animation; battle draws it with
        -- its own colour texture (DT_BtlUnitAsset textureBaseColor), so swap that in for the animation's sheet.
        pcall(function() ui.sprite:RemoveCellmapTextureReplacementAll() end)
        if tex then
            local t = game.load(tex)
            -- keyed by the cell map's CellMapName ("monster005"); the project's CellmapNames ("monster005.ssce")
            -- are accepted but change nothing (tested 25 Oct)
            local ok, err = t and pcall(function()
                local list = project.CellmapList
                for i = 1, #list do ui.sprite:AddCellmapTextureReplacement(list[i].CellMapName, t) end
            end)
            if t and not ok then log("recolour " .. tostring(id) .. ": " .. tostring(err)) end
        end
        ui.sprite:SetAutoUpdate(true)
        local names, idle = {}, nil
        pcall(function() ui.sprite:GetAnimationNameList(names) end)
        for _, n in ipairs(names) do
            local name = n:get():ToString()
            if name:lower():find("idle") then idle = name; break end
        end
        ui.sprite:PlayAnimation(FName(idle or "idle"), 0, 1.0, 0)
    end)
end

-- screen pixels per UI design pixel (1080p design), for drawing sprites at whole pixels
local vpScale
viewportScale = function()
    if not vpScale then
        pcall(function()
            vpScale = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportScale(FindFirstOf("PlayerController"))
        end)
        if not vpScale or vpScale <= 0 then vpScale = 1 end
    end
    return vpScale
end

-- every value field: texts set, the game's icon widgets hidden (text-only state: ??? or blank)
local function fields(value, color)
    ui.forms:SetVisibility(2)                             -- Hidden: the line keeps its room, so nothing below moves
    for k = 2, 4 do ui.traitRows[k]:SetVisibility(3) end   -- unscanned: all four rows (???), hidden again once known
    for _, t in ipairs({ ui.affinity, ui.hp, ui.race, ui.resist, ui.traits[1], ui.traits[2], ui.traits[3], ui.traits[4] }) do
        set(t, value, color); t:SetVisibility(4)
    end
    ui.affinityBox:SetVisibility(1); ui.resistBox:SetVisibility(1)
    for _, it in ipairs(ui.items) do set(it.text, value, color); it.text:SetVisibility(4); it.box:SetVisibility(1) end
    set(ui.level, "")
end

local function blocks(visible)
    ui.top:SetVisibility(visible and 4 or 1); ui.scan:SetVisibility(visible and 4 or 1)
    ui.areaInfo:SetVisibility(visible and 1 or 4)
    ui.map:SetVisibility(visible and 1 or 4)
end

-- world map ---------------------------------------------------------------------------------------------------------
-- put `w` on the map over u0..u1, v0..v1 (map coordinates, 0..1 over the whole world)
local function mapX(u) return ui.world.x + u * ui.world.w end
local function mapY(v) return ui.world.y + v * ui.world.h end
placeOnMap = function(w, u0, v0, u1, v1, z)
    local slot = ui.mapCanvas:AddChildToCanvas(w)
    slot:SetPosition({ X = mapX(u0), Y = mapY(v0) })
    slot:SetSize({ X = mapX(u1) - mapX(u0), Y = mapY(v1) - mapY(v0) })
    slot:SetZOrder(z or 0)
    return slot
end

-- the save's main story progress: some islands' tiles change with it (Olderion before / after the flood, ...)
local function storyProgress()
    local ok, p = pcall(function() return game.saveData().Progress.Progress[1] end)
    return ok and tonumber(p) or 0
end

-- the islands the game's own map shows at this point of the story (it shows every island, some in a form that
-- changes with the story: Olderion before / after the flood, Mysidia and the Crystal Tower only later)
local function tileWanted(t, progress)
    local c = t.cond
    return not c or (c.op == "<" and progress < c.progress) or (c.op == ">=" and progress >= c.progress)
        or (c.op == "==" and progress == c.progress)
end

local function showMap(area)
    local progress = storyProgress()
    for i, t in ipairs(worldmap.tiles) do
        local want = tileWanted(t, progress)
        ui.mapShow[i] = want
        if ui.mapTiles[i] then ui.mapTiles[i]:SetVisibility(want and 4 or 1)
        elseif want and not ui.mapQueued[i] then ui.mapQueued[i] = true; ui.mapQueue[#ui.mapQueue + 1] = i end
    end
    local p = worldmap.areas[area]
    ui.mapMarker:SetVisibility(p and 4 or 1)
    if p then ui.mapMarkerSlot:SetPosition({ X = mapX(p.u) - MAP_MARKER / 2, Y = mapY(p.v) - MAP_MARKER / 2 }) end
end

-- one map tile a tick (1024 x 1024 each), as the faces are loaded
loadQueuedTile = function()
    if not ui or not ui.mapQueue then return end
    local i = table.remove(ui.mapQueue, 1)
    if not i then return end
    if type(i) == "table" then                            -- a full-size layer (sea, vignette, frame)
        local tex = game.load(i.tex)
        if tex then i.img:SetBrushFromTexture(tex, false); i.img:SetVisibility(4) end
        return
    end
    local t = worldmap.tiles[i]
    local tex = game.load(t.tex)
    if not tex then return end
    local img = new("Image")
    img:SetBrushFromTexture(tex, false)
    placeOnMap(img, t.rect[1], t.rect[2], t.rect[3], t.rect[4], t.z)
    img:SetVisibility(ui.mapShow[i] and 4 or 1)
    ui.mapTiles[i] = img
end

local function showHeader(r)
    setSprite(nil)
    blocks(false)
    ui.forms:SetVisibility(1)                             -- an enemy's forms line must not stay on a header
    ui.check:SetVisibility(1)
    set(ui.level, "")
    ui.name:SetTitle(FText(areaName(r.header)))
    set(ui.areaEnc, r.seen .. " / " .. r.total)
    set(ui.areaScan, r.scanned .. " / " .. r.total)
    ui.areasHead:SetVisibility(1)
    ui.areas:ClearChildren()
    local ok, err = pcall(showMap, r.header)
    if not ok then log("map: " .. tostring(err)) end
end

local function showUnknown()
    setSprite(nil)
    blocks(true)
    fields(UNKNOWN, DIM)
    ui.check:SetVisibility(1)
    ui.name:SetTitle(FText(UNKNOWN))
    ui.areasHead:SetVisibility(1)
    ui.areas:ClearChildren()
end

-- one place name in the locations list (under the sprite, so long names wrap)
local function areaLine(name, color)
    local t = text(name, color)
    pcall(function() t:SetAutoWrapText(true) end)
    return framed(sized(t, (SPRITE - 2 * PANEL_PAD - 8) / AREA_SCALE - 2 * FRAME_PAD - 8, nil))   -- wraps at the column's width once scaled
end
local AREA_PAD = { Left = 4, Top = 2, Right = 0, Bottom = 2 }

local function showLocations(e, id)
    ui.areasHead:SetVisibility(4)
    ui.areas:ClearChildren()
    local seen, shownAny = knownAreasOf(e), false
    for _, a in ipairs(e.areas) do
        local named = data.areas[a] and data.areas[a].table
        if named then
            local k = seen[a]
            ui.areas:AddChildToVerticalBox(areaLine(k and areaName(a) or UNKNOWN, k and WHITE or DIM)):SetPadding(AREA_PAD)
            shownAny = true
        end
    end
    if not shownAny then                                  -- only met in unnamed places (world-map events)
        ui.areas:AddChildToVerticalBox(areaLine(game.libra("UI_Libra_Nodata") or "-", DIM)):SetPadding(AREA_PAD)
    end
    setSprite(id)
end

-- element -> resistance for a unit (eElement / eResistance numbers)
local function resistances(p)
    local out = {}
    pcall(function()
        for k, v in pairs(p.ElementResistanceList or {}) do
            local key, val = k, v
            if type(v) == "table" then key, val = v.Key, v.Value end
            local e, r = enumIndex(key, ELEMENT_NAMES), enumIndex(val, RESIST_NAMES)
            if e and r and r > 0 then out[e] = r end
        end
    end)
    return out
end

-- elements whose reaction the player has already seen in battle (the save's analyzedElments), for unscanned entries
local function discovered(e)
    local out = {}
    for _, u in ipairs(e.units) do
        local r = ui.records[u]
        if r then
            pcall(function()
                r.analyzedElments:ForEach(function(k, v)
                    if plain(v) then out[enumIndex(k, ELEMENT_NAMES) or -1] = true end
                end)
            end)
        end
    end
    return out
end

-- statuses the unit is immune to (StatusConditionResistanceList value 100). APPROXIMATION: the scan panel's own
-- rule lives in C++; "Resistances" is keyed UI_Libra_Condition_Invalid, so immune-only is assumed. Check in battle.
local function immunities(p)
    local out = {}
    pcall(function()
        for k, v in pairs(p.StatusConditionResistanceList or {}) do
            local key, val = k, v
            if type(v) == "table" then key, val = v.Key, v.Value end
            if (tonumber(plain(val)) or 0) >= 100 then out[#out + 1] = tonumber(plain(key)) or plain(key) end
        end
    end)
    table.sort(out, function(x, y) return tostring(x) < tostring(y) end)
    return out
end

local form = 1                     -- which unit (form / phase / mode) of the shown entry
local function showEntry(e)
    if form > #e.units then form = 1 end
    local id = e.units[form]
    local p = game.unitParam(id) or {}
    local scanned = isScanned(e)
    local none = game.libra("UI_Libra_Nodata") or "-"
    blocks(true)
    fields(UNKNOWN, DIM)                                  -- start from "nothing known", then reveal

    ui.name:SetTitle(FText(entryName(e)))
    ui.check:SetVisibility(scanned and 4 or 1)
    set(ui.level, (game.libra("UI_Libra_Level") or "Lv.") .. " " .. tostring(p.Level or "?"))
    if #e.units > 1 then
        ui.forms:SetVisibility(4)
        -- forms / phases: confirm shows the next (worded as a prompt: the button glyph and a bare "1 / 2" read as noise)
        set(ui.formsText, string.format("Next form  (%d / %d)", form, #e.units), GREY)
    else
        ui.forms:SetVisibility(2)                         -- Hidden, not Collapsed: the layout stays the same
    end

    -- Affinities: the game's icons per Weak/Halved/Null/Absorb; before a scan only reactions already seen in battle
    local res, seen = resistances(p), (not scanned) and discovered(e) or nil
    local any = false
    for value, g in pairs(ui.elementGroups) do
        local list = {}
        for el, r in pairs(res) do if r == value and (scanned or seen[el]) then list[#list + 1] = el end end
        table.sort(list)
        local on = #list > 0
        g.row:SetVisibility(on and 4 or 1)
        for i, w in pairs(g.icons) do
            w:SetVisibility(list[i] and 4 or 1)
            if list[i] then pcall(function() w:SetElementList({ list[i] }) end) end
        end
        any = any or on
    end
    if any then ui.affinity:SetVisibility(1); ui.affinityBox:SetVisibility(4)
    elseif scanned then set(ui.affinity, none) end

    -- Trait 1 shows without a scan (DA_BtlLibra); everything else needs one
    local tr = traits(p)
    set(ui.traits[1], tr[1] or none)
    if not scanned then return showLocations(e, id) end

    set(ui.hp, p.MaxHitPoint and tostring(math.floor(p.MaxHitPoint * hpRate() + 0.5)) or "?")
    set(ui.race, game.libra("UI_Libra_Race_" .. (game.RACE_KEY[tonumber(plain(p.Race)) or 0] or "None")) or "?")
    local imm = immunities(p)
    if #ui.conditions > 0 and #imm > 0 then
        ui.resist:SetVisibility(1); ui.resistBox:SetVisibility(4)
        for i, w in ipairs(ui.conditions) do
            w:SetVisibility(imm[i] and 4 or 1)
            if imm[i] then pcall(function() w:SetConditionList({ imm[i] }) end) end
        end
    else
        set(ui.resist, none)                              -- an empty icon list draws only its underline
    end
    -- traits 2-4 only where the enemy has them (scanned: the count is known; empty "-" rows were clutter)
    for k = 2, 4 do
        set(ui.traits[k], tr[k] or none)
        ui.traitRows[k]:SetVisibility(tr[k] and 3 or 1)
    end
    for _, it in ipairs(ui.items) do
        if it.widget then
            it.text:SetVisibility(1); it.box:SetVisibility(4)
            pcall(function() it.widget:SetContentId(tonumber(plain(p[it.field])) or -1) end)
        else
            set(it.text, game.itemName(p[it.field]) or none)
        end
    end
    showLocations(e, id)
end

local function show(i, force)
    local r = rows[i]
    if not r or (shown == i and not force) then return end
    if shown ~= i then form = 1 end
    shown = i
    if r.header then showHeader(r) elseif r.known then showEntry(r.entry) else showUnknown() end
end

-- list --------------------------------------------------------------------------------------------------------------
local function buildRows()
    local total, members, seenIn, seenCount, scannedCount = {}, {}, {}, 0, 0
    for _, e in ipairs(data.entries) do
        for _, a in ipairs(e.areas) do
            total[a] = (total[a] or 0) + 1
            members[a] = members[a] or {}
            table.insert(members[a], e)
        end
        local seen = groupAreasOf(e)
        if next(seen) then
            seenCount = seenCount + 1
            if isScanned(e) then scannedCount = scannedCount + 1 end
        end
        for a in pairs(seen) do
            seenIn[a] = seenIn[a] or {}
            seenIn[a][e] = true
            if not total[a] or a == "?" then                 -- seen somewhere the data doesn't list it
                members[a] = members[a] or {}
                local listed = false
                for _, x in ipairs(members[a]) do if x == e then listed = true end end
                if not listed then table.insert(members[a], e) end
            end
        end
    end
    local order, inOrder = {}, {}
    for _, a in ipairs(data.areaOrder) do order[#order + 1] = a; inOrder[a] = true end
    for a in pairs(seenIn) do if not inOrder[a] then order[#order + 1] = a end end

    rows = {}
    for _, a in ipairs(order) do
        local named = a == "?" or (data.areas[a] and data.areas[a].table)
        if named and (M.showAll or store.visited[a] or seenIn[a]) then
            local list, seenHere = members[a] or {}, seenIn[a] or {}
            local n, sc = 0, 0
            for e in pairs(seenHere) do
                n = n + 1
                if isScanned(e) then sc = sc + 1 end
            end
            rows[#rows + 1] = { header = a, seen = n, scanned = sc, total = math.max(total[a] or 0, #list) }
            if expanded[a] then
                for _, e in ipairs(list) do rows[#rows + 1] = { entry = e, area = a, known = seenHere[e] == true } end
            end
        end
    end
    set(ui.summary, string.format("%d / %d", seenCount, #data.entries), GREY)
    set(ui.summaryScanned, string.format("%d / %d", scannedCount, #data.entries), GREY)
end

-- the text a row shows
local function rowLabel(r) return r.header and areaName(r.header) or (r.known and entryName(r.entry) or UNKNOWN) end

local function fillList(focus)
    -- The Help list's navigator (WBP_ListViewMenu) owns the list items: SetChildrenCount makes one per row (keeping
    -- the ones it has) and hands them to the list, so the count it moves the cursor through always matches ours (left
    -- at Help's own 38, up on the first row wrapped to the wrong row). Being the game's, the items are never
    -- garbage-collected under us. An item belongs to a position, not a row, so rows also set their entry's text
    -- themselves (decorate); TutorialData.Name is kept in step for the entry's own first draw. (Earlier versions
    -- made their own items: copying TutorialData through Lua, and writing the navigator's array from Lua, crashed.)
    ui.pathMenu = valid(ui.pathMenu) and ui.pathMenu or find(host.WidgetTree.RootWidget, "WBP_HelpList"):GetPathMenu()
    ui.pathMenu:SetChildrenCount(#rows, true)
    local items = {}
    local arr = ui.pathMenu.ListItems
    for i = 1, #arr do
        local it = arr[i]
        if type(it) == "userdata" and not it.IsValid then it = it:get() end
        items[i] = it
    end
    if #items ~= #rows then log("navigator made " .. #items .. " items for " .. #rows .. " rows") end
    for i, r in ipairs(rows) do
        local item = items[i]
        if valid(item) then
            item.ItemIndex = i - 1
            item.TutorialData.Name = FText(rowLabel(r))
        end
    end
    if ui.list:GetNumItems() ~= #items then pcall(function() ui.list:SetListItems(items) end) end
    pcall(function() ui.list:RequestRefresh() end)       -- else rows added below the cursor show only after a scroll
    shown = nil
    if #rows == 0 then
        ui.name:SetTitle(FText("")); fields(""); setSprite(nil); ui.check:SetVisibility(1); ui.areasHead:SetVisibility(1)
        return
    end
    focus = math.min(focus or 1, #rows)
    show(focus)
end

local function refresh(focus)
    local sd = game.saveData()
    ui.records = sd and game.records(sd) or {}
    buildRows()
    fillList(focus)
end

-- the row under the cursor: the entry widget holding focus, mapped back to its list item
local entryLib
-- each element of a TArray handed back by UE4SS (a Lua table or an array object; elements may be wrapped)
local function each(arr, fn)
    if type(arr) == "table" then
        for _, v in ipairs(arr) do local ok, x = pcall(function() return v:get() end); fn(ok and x or v) end
    elseif arr then
        pcall(function() arr:ForEach(function(_, v) fn(v:get()) end) end)
    end
end
-- the list's entry widgets on screen (the list recycles them while scrolling)
local function ourEntries()
    local out = {}
    local ok, arr = pcall(function() return ui.list:GetDisplayedEntryWidgets() end)
    if ok then each(arr, function(w) if valid(w) then out[#out + 1] = w end end) end
    if #out == 0 then                                     -- fallback: search all entry widgets (slow)
        for _, w in ipairs(FindAllOf("WBP_HelpEntry_C") or {}) do
            if valid(w) and w:GetFullName():find(game.HOST_PARENT, 1, true) then out[#out + 1] = w end
        end
    end
    return out
end
local function rowOf(w)
    entryLib = valid(entryLib) and entryLib or StaticFindObject("/Script/UMG.Default__UserObjectListEntryLibrary")
    local item = entryLib:GetListItemObject(w)
    if valid(item) then return item.ItemIndex + 1 end
end

-- face icon textures: from this table, otherwise queued for the poll to load (two per tick) and kept
-- alive by an image in a hidden box (nothing else references them while their row is off screen)
local faceTex, faceQueued, faceQueue = {}, {}, {}
local function forgetCaches()                             -- a new screen: textures the old one held may be gone
    faceTex, faceQueued, faceQueue = {}, {}, {}
    vpScale = nil
end
faceTexture = function(path)
    local t = faceTex[path]
    if t and valid(t) then return t end
    if not faceQueued[path] then faceQueued[path] = true; faceQueue[#faceQueue + 1] = path end
end
local function loadQueuedFaces()
    local loaded = false
    for _ = 1, 2 do
        local path = table.remove(faceQueue, 1)
        if not path then break end
        faceQueued[path] = nil
        local tex = game.load(path)
        if tex then
            faceTex[path] = tex
            pcall(function()
                local keep = new("Image"); keep:SetBrushFromTexture(tex, false)
                ui.faceHold:AddChildToVerticalBox(keep)
            end)
            loaded = true
        end
    end
    if loaded then for _, x in pairs(ui.entryIcons) do x.row = nil end end   -- rows pick their faces up next tick
end

-- extras on list rows, added once to each (recycled) entry widget: the scanned check on enemy rows and the
-- right-aligned count on area headers
local function decorate(w, i)
    local key = w:GetAddress()
    local extra = ui.entryIcons[key]
    if not extra or not valid(extra.box) then
        local button = w.WidgetTree.RootWidget                           -- WBP_LeftLineButton_C
        local overlay = valid(button) and find(button.WidgetTree.RootWidget, "Overlay_0")
        if not overlay then return end
        local indentSlot = overlay.Slot                   -- SizeBox_0's slot: everything the button draws
        local tree = button.WidgetTree
        extra = { box = new("HorizontalBox", tree), count = text(""), icon = icon(26, tree), scanned = text("") }
        pcall(function() extra.count:SetJustification(2); extra.scanned:SetJustification(2) end)   -- right
        extra.countBox = new("SizeBox", tree); extra.countBox:SetWidthOverride(110); extra.countBox:SetContent(extra.count)
        extra.scanBox = new("SizeBox", tree); extra.scanBox:SetWidthOverride(52); extra.scanBox:SetContent(extra.scanned)
        extra.gap = new("SizeBox", tree); extra.gap:SetWidthOverride(18)
        extra.box:AddChildToHorizontalBox(extra.countBox)
        extra.box:AddChildToHorizontalBox(extra.gap)
        extra.box:AddChildToHorizontalBox(extra.icon):SetVerticalAlignment(2)
        extra.box:AddChildToHorizontalBox(extra.scanBox)
        local s = overlay:AddChildToOverlay(extra.box)
        s:SetHorizontalAlignment(3); s:SetVerticalAlignment(2)            -- right, centre
        s:SetPadding({ Left = 0, Top = 0, Right = 18, Bottom = 0 })
        -- the enemy's face (the battle timeline's icon) before its name: the entry's ScaleBox gets [face][name]
        local inner = button.WidgetTree.RootWidget                       -- the name sits in the button's named slot
        local scale, title = find(inner, "ScaleBox_0"), find(inner, "Text_Title")
        if not (scale and title) then log("row layout: no ScaleBox_0 / Text_Title") end
        if scale and title then
            local line = new("HorizontalBox", w.WidgetTree)
            local slot = scale:SetContent(line)
            pcall(function() slot:SetHorizontalAlignment(1) end)   -- Left (the name used to fill the row)
            -- every row is FACE tall (the list assumes one row height; taller enemy rows left a gap at its end);
            -- on headers the face box is 0 wide so their text stays put
            extra.face = new("Image", w.WidgetTree)
            extra.face:SetDesiredSizeOverride({ X = FACE, Y = FACE })
            extra.faceBox = new("SizeBox", w.WidgetTree)
            extra.faceBox:SetHeightOverride(FACE); extra.faceBox:SetWidthOverride(FACE)
            extra.faceBox:SetContent(extra.face)
            extra.faceSlot = line:AddChildToHorizontalBox(extra.faceBox)
            extra.faceSlot:SetVerticalAlignment(2)
            extra.faceSlot:SetPadding({ Left = 0, Top = 0, Right = 10, Bottom = 0 })
            line:AddChildToHorizontalBox(title):SetVerticalAlignment(2)
            extra.title = title
        end
        extra.indentSlot = indentSlot
        ui.entryIcons[key] = extra
    end
    local r = rows[i]
    local header = r and r.header
    -- Nesting: the button's own content (bar, background, text) is padded inside the button. The list resets the
    -- entry's outer padding whenever it reuses a row while scrolling, so indenting that made rows jump left until
    -- the next tick; this inner slot is the mod's alone.
    local want = header and 0 or NEST
    if extra.indent ~= want and extra.indentSlot then
        extra.indent = want
        pcall(function() extra.indentSlot:SetPadding({ Left = want, Top = 0, Right = 0, Bottom = 0 }) end)
    end
    -- face: headers none; ??? rows keep the space (Hidden) so names line up. Visibility is set every tick (cheap)
    -- so a row can't keep another row's state; the texture only when it changes
    if extra.face then
        local path = r and r.entry and r.known and data.faces[tostring(r.entry.units[1])]
        local tex = path and faceTexture(path)
        if tex and extra.faceTex ~= tex then
            extra.face:SetBrushFromTexture(tex, false)
            extra.face:SetDesiredSizeOverride({ X = FACE, Y = FACE })
            extra.faceTex = tex
        end
        extra.face:SetVisibility(tex and 4 or 2)
        local wide = r and r.entry and true or false
        if extra.faceWide ~= wide then
            extra.faceWide = wide
            extra.faceBox:SetWidthOverride(wide and FACE or 0)
            extra.faceSlot:SetPadding({ Left = 0, Top = 0, Right = wide and 10 or 0, Bottom = 0 })
        end
    end
    if extra.row == r then return end                    -- already showing this row
    extra.row = r
    if extra.title and r then pcall(function() extra.title:SetText(FText(rowLabel(r))) end) end
    local scannedEnemy = r and r.entry and r.known and isScanned(r.entry)
    extra.countBox:SetVisibility(header and 4 or 1)
    extra.gap:SetVisibility(header and 4 or 1)
    extra.scanBox:SetVisibility(header and 4 or 1)
    extra.icon:SetVisibility((header or scannedEnemy) and 4 or 1)
    if header then
        extra.count:SetText(FText(r.seen .. " / " .. r.total))
        extra.scanned:SetText(FText(tostring(r.scanned)))
    end
end

-- Confirm on a row. Help's handler (WBP_HelpLayout:HandleClickedHelpList) pushes the tutorial pop-up with
-- CPP_BFL_GameWidgetManager:PushLayoutWidget(UI.Layout.Tutorial, PrioritizeExisting) and stops if it gets no tutorial
-- widget back. While the Bestiary is open the push is turned into one of the main menu's own layout, which is
-- already open, so nothing opens; the push also tells us a row was confirmed. On an area header that expands or
-- collapses the area; on an enemy with several forms it shows the next form.
local TUTORIAL_LAYOUT, OPEN_LAYOUT = "UI.Layout.Tutorial", "UI.Layout.MainMenu"
local focusRow                     -- row of the entry widget holding focus (the detail panel may lag behind it)
-- work left for the next poll by the push hook, the Q / E keys and confirm (nothing else schedules its own call:
-- UE4SS callbacks running into each other broke its Lua state)
local pendingConfirm, pendingRefresh, pendingForm
function M.queueForm(step) pendingForm = step end
function M.toggleShowAll() M.showAll = not M.showAll; pendingRefresh = true; log("showAll " .. tostring(M.showAll)) end
-- Q / E while the Bestiary is open: previous / next form, read from the player controller's key state each tick
-- (a key press, not a hold, pages once)
local formKeys, keyDown, pc = { { "Q", -1 }, { "E", 1 } }, {}, nil
function M.pollKeys()
    if not host then keyDown = {}; return end
    if not valid(pc) then pc = FindFirstOf("PlayerController") end
    if not valid(pc) then return end
    for _, k in ipairs(formKeys) do
        local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k[1]) }) end)
        down = ok and down == true
        if down and not keyDown[k[1]] then pendingForm = k[2] end
        keyDown[k[1]] = down
    end
end
-- development: show entry after entry in the detail panel (sprite review)
local devIndex, pendingDev, devTargets = 0, false, nil
function M.queueDevNext() pendingDev = true end
function M.toggleMeasure()
    M.measure = not M.measure
    pcall(function() ui.fit:SetStretch(M.measure and 0 or 2) end)   -- measure: no shrinking, the box stays put
    log("measure " .. tostring(M.measure))
end
local function confirmed(row)
    row = row or focusRow or shown
    local r = rows[row or 0]
    if r and r.header then
        expanded[r.header] = not expanded[r.header] or nil
        pendingRefresh = row or true                      -- next tick, after the click has been handled
    elseif r and r.entry and r.known and #r.entry.units > 1 then
        if row ~= shown then show(row) end
        M.switchForm(1)                                   -- controller: confirm pages through forms
    end
end

local lastClick, clickTick, ticks = 0, nil, 0
function M.installHooks()
    local ok, err = pcall(function()
        RegisterHook("/Script/mucha.CPP_BFL_GameWidgetManager:PushLayoutWidget", function(_, tag)
            if not host or not ui then return end
            local t = tag:get()
            if t.TagName:ToString() ~= TUTORIAL_LAYOUT then return end
            t.TagName = FName(OPEN_LAYOUT)
            lastClick = os.clock()
            clickTick = ticks
            local row = focusRow
            pendingConfirm = row or true                  -- handled by the next poll, on the game thread
        end)
    end)
    if not ok then log("hook PushLayoutWidget: " .. tostring(err)) end
    return ok
end

-- safety net: if the pop-up still opens, hide it and take it off the input stack at once
local closing = {}
local function closeStrayPopup()
    for _, w in ipairs(FindAllOf("WBP_TutorialLayout_C") or {}) do
        local ok, active = pcall(function() return w:IsActivated() end)
        local key = w:GetAddress()
        if ok and active and not closing[key] then
            local vis = 4
            pcall(function() vis = w:GetVisibility() end)
            closing[key] = vis                               -- the game reuses it for the real Help: restore later
            pcall(function() w:SetVisibility(1) end)        -- never shown
            pcall(function() w:DeactivateWidget() end)      -- off the input stack (OnRequestClose only animates)
            log("tutorial pop-up opened anyway; closed it")
            if os.clock() - lastClick > 0.3 then confirmed() end
        elseif ok and not active and closing[key] then
            pcall(function() w:SetVisibility(closing[key]) end)
            closing[key] = nil
        end
    end
end

-- Decorate a list row the moment the list hands it a row. Expanding or collapsing an area makes the list build new
-- entry widgets; decorated only by the next poll (up to 50 ms later) they showed for a frame without their indent,
-- face and counts (players saw the list "freak out" on expand). Runs on the game thread, inside the list's update.
local entryHooked = false
local function hookEntries()
    if entryHooked then return end
    entryHooked = true
    local ok, err = pcall(function()
        RegisterHook("/Game/UI/MainMenu/Help/Widget/WBP_HelpEntry.WBP_HelpEntry_C:OnListItemObjectSet", function(self, item)
            if not host or not ui or not ui.entryIcons then return end
            pcall(function()
                local w, it = self:get(), item:get()
                if valid(w) and valid(it) and w:GetFullName():find(game.HOST_PARENT, 1, true) then
                    decorate(w, it.ItemIndex + 1)
                end
            end)
        end)
    end)
    if not ok then log("hook entries: " .. tostring(err)) end
end

-- called every 100 ms ------------------------------------------------------------------------------------------------
local builtFor, openAddr, pending, refreshedFor = nil, nil, nil, nil
function M.poll()
    local h = game.openHost()
    if not h then host, openAddr = nil, nil; return end
    local addr = h:GetFullName()                          -- unique per object, unlike its address
    if addr ~= openAddr then                              -- just opened (the widget is pooled: same object each time)
        host, openAddr = h, addr
        local ok, err = pcall(function()
            if builtFor ~= addr then forgetCaches(); build(); builtFor = addr end
            hookEntries()                                 -- the entry class is loaded now
            pendingForm, pendingConfirm, pendingRefresh = nil, nil, nil   -- input from before it was open
            -- every area starts closed: opening the player's current area each time undid closing it, and areas
            -- stayed open from the last visit (RaifRedacted, 25 Oct)
            for a in pairs(expanded) do expanded[a] = nil end
            refresh(1)
        end)
        if not ok then log("screen: " .. tostring(err)) end
        return
    end
    ticks = ticks + 1
    local c0 = os.clock()
    if pendingRefresh then local r = pendingRefresh; pendingRefresh = nil; pcall(refresh, r ~= true and r or shown) end
    if pendingConfirm then local r = pendingConfirm; pendingConfirm = nil; pcall(confirmed, r ~= true and r or nil) end
    if pendingForm then local f = pendingForm; pendingForm = nil; pcall(M.switchForm, f) end
    if pendingDev then
        pendingDev = false
        -- normal: every entry; measure mode: one unit for each sprite not measured yet
        if not devTargets or devTargets.measure ~= M.measure then
            devTargets, devIndex = { measure = M.measure }, 0
            local seen = {}
            for _, en in ipairs(data.entries) do
                for f, u in ipairs(en.units) do
                    local sp = data.sprites[tostring(u)]
                    if not M.measure then devTargets[#devTargets + 1] = { en, f }   -- every form
                    elseif M.measure and sp and not data.spriteBox[sp] and not seen[sp] then
                        seen[sp] = true; devTargets[#devTargets + 1] = { en, f }
                    end
                end
            end
            log("dev targets: " .. #devTargets)
        end
        -- the entry shown by the last step has been laid out since: log its height (to size the panel's parts)
        if devIndex > 0 then
            pcall(function()
                local d, i = ui.detail:GetDesiredSize(), ui.infoPanel:GetDesiredSize()
                log(string.format("dev layout %d detail %.0f info %.0f forms %s", devIndex, d.Y, i.Y,
                    tostring(ui.forms:GetVisibility())))
            end)
        end
        devIndex = devIndex % math.max(#devTargets, 1) + 1
        local t = devTargets[devIndex]
        if not t then return end
        local e = t[1]
        local id = e.units[t[2]]
        local path = data.sprites[tostring(id)]
        form = t[2]
        pcall(showEntry, e)
        local ls = M.lastSprite or {}
        log(string.format("dev sprite %d unit %d %s k=%.5f vs=%.4f measure=%s", devIndex, id, tostring(path),
            ls.k or 0, ls.vs or 0, tostring(M.measure)))
        shown = focusRow                                  -- so the cursor's row does not replace it next tick
        return
    end
    if clickTick and ticks - clickTick <= 10 then pcall(closeStrayPopup) end   -- just after a confirm only
    pcall(loadQueuedFaces)
    pcall(loadQueuedTile)
    local c1 = os.clock()
    focusRow = nil
    local entries = ourEntries()
    local c2 = os.clock()
    for _, w in ipairs(entries) do
        pcall(function()
            local i = rowOf(w)
            if i then
                decorate(w, i)
                if w:HasFocusedDescendants() then focusRow = i end
            end
        end)
    end
    -- the detail panel follows the cursor; an enemy (its sprite loads) waits until the cursor rests for one tick, so
    -- scrolling past rows stays smooth
    local c3 = os.clock()
    -- after the list scrolls to the cursor it can leave its last row empty until the next input; a refresh once the
    -- cursor has rested on a new row fills it
    if focusRow and focusRow ~= refreshedFor and pending == nil then
        refreshedFor = focusRow
        pcall(function() ui.list:RequestRefresh() end)
    end
    if focusRow and focusRow ~= shown then
        local r = rows[focusRow]
        if not (r and r.entry and r.known) or pending == focusRow then show(focusRow); pending = nil
        else pending = focusRow end
    end
    local c4 = os.clock()
    M.lastTiming = string.format("pending/popup %.1f, entries %.1f, rows %.1f, detail %.1f", (c1 - c0) * 1000,
        (c2 - c1) * 1000, (c3 - c2) * 1000, (c4 - c3) * 1000)
end

-- Q / E: previous / next form of the shown entry (only while the Bestiary is open)
function M.switchForm(step)
    if not host or not ui then return end
    local r = rows[shown or 0]
    if not (r and r.entry and r.known and #r.entry.units > 1) then return end
    form = (form - 1 + step) % #r.entry.units + 1
    show(shown, true)
end

-- development: where is keyboard focus?
function M.debugFocus()
    local out = {}
    pcall(function() out[#out + 1] = "host=" .. tostring(host and host:HasFocusedDescendants()) end)
    pcall(function() out[#out + 1] = "list=" .. tostring(ui.list:HasFocusedDescendants()) end)
    pcall(function() out[#out + 1] = "listKb=" .. tostring(ui.list:HasKeyboardFocus()) end)
    for _, w in ipairs(ourEntries()) do
        pcall(function() if w:HasFocusedDescendants() then out[#out + 1] = "entry row " .. tostring(rowOf(w)) end end)
    end
    pcall(function() out[#out + 1] = "rows=" .. #rows .. " items=" .. tostring(ui.list:GetNumItems()) .. " focusRow=" .. tostring(focusRow) end)
    pcall(function()
        local hl = find(host.WidgetTree.RootWidget, "WBP_HelpList")
        local pm = hl:GetPathMenu()
        out[#out + 1] = "pathMenu=" .. pm:GetFullName()
        pcall(function() out[#out + 1] = "children=" .. tostring(pm:GetChildrenCount()) end)
        pcall(function() out[#out + 1] = "focusedIdx=" .. tostring(pm:GetFocusedItemIndex(0)) end)
        pcall(function() out[#out + 1] = "numItem=" .. tostring(pm:GetNumItem()) end)
    end)
    log("focus: " .. table.concat(out, " "))
end

return M
