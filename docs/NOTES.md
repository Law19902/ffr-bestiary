# Gap analysis: Bestiary detail vs the game's scan (Libra) panel

Reference: the in-battle scan panel (Anet, Lv.19) and its data asset `/Game/UI/Battle/Libra/Data/DA_BtlLibra`, which
lists every field's style and whether it needs a scan (`bIsDisplayRequiresAnalysis`).

## Fields (updated 24 Oct 2026, afternoon)
| Scan panel field | Needs scan (DA_BtlLibra) | Bestiary | Status |
|---|---|---|---|
| Name | no | heading (`WBP_SystemSubhead`), game name | done |
| Lv. | no | right side of the name bar | done |
| Affinities | elements: yes (but reactions already seen in battle show: save `analyzedElments`) | the game's `WBP_ElementIconList` per group, labelled with the battle's words Weak / Resisted / Immune / Absorbed (the scan panel's own label keys have no text) | done; Reflect has no group in the scan panel either |
| HP | yes | table HP x difficulty rate (Expert x1.6, matches battle) | done (max only, by design) |
| Type | yes | game race string | done |
| Resistances | yes | the game's `WBP_BtlLibra_ConditionIconList`, one widget per status in a wrapping row; "-" when none | done; **assumption**: statuses with resistance 100 (immune). The panel's own rule is in C++; check on an enemy with immunities |
| Trait 1 | **no** | always shown | done |
| Trait 2-4 | yes | wrapped text | done |
| Items Dropped / Rare Drop / Stealable / Rare Stealable | yes | the game's `WBP_BtlLibraEntry_Item` (item icon + name, "-") | done |
| Kill Count | (style exists) | not shown: the scan panel never lists it in `DisplayEntryTagList`, and the spec leaves kill counts out | n/a |
| Face icon in reticle | - | animated idle battle sprite (game's `CPP_MuchaSsPlayerWidget`, `DT_BtlUnitAsset` project, "idle"), fitted from its measured outline; the battle-timeline face (`DA_UnitIcon_Timeline` by `FaceIconId`) beside each name in the list | done |

## Behaviour
- Forms: **confirm on the enemy row** steps to the next form on any device; the line under the name shows the game's
  `WBP_KeyIcon` for `IA_UI_Common_Decide` (keyboard F / pad button) and "1 / 2". Q / E also work on a keyboard.
  The pad bumpers can't be read: the game's menu input actions aren't bound in a way Enhanced Input reports.
- Seen tracking and per-slot files: **tested end to end** 24 Oct (fight Anet -> list shows it -> save to slot 01 ->
  `saves/slot1.json` written -> load autosave/slot 02: empty -> load slot 01: Anet back). Test save restored after.
- Tutorial pop-up: never opens. A pre-hook on `CPP_BFL_GameWidgetManager:PushLayoutWidget` turns the
  `UI.Layout.Tutorial` push into the already-open `UI.Layout.MainMenu` while the Bestiary is open; the push is also
  the confirm signal. The game's own Help tutorials still open afterwards (checked 24 Oct evening).
- Crashes (all fixed, 24 Oct): rows copied a freed Help item's `TutorialData`, then copied whole `TutorialData`
  structs through Lua tables (shared page arrays); `GetUnitParameterById` out-params pointed into freed memory
  (scan data now comes from the mod's data file); two timers running into each other in UE4SS's Lua state (one
  timer now). Stress test (all 408 entries, every area opened) passes.
- Installing mid-game: enemies the save records as defeated / scanned and maps it marks visited
  (`Map.perMapSaveDataMap.bIsVisited`) are picked up on load; they're listed under their data areas the player
  has visited. The save has no `perMapSaveDataMap` entry at all for some maps (Grandshelt Castle 2012/2014/3020,
  Old Town Olderion), so since 0.1.3 a save-known enemy whose data gives one place only marks that place visited,
  unless a story stage (5000-5999, stageArea) can stand for it (25 Oct; checked in game on slot 0).
- Sprites: `tools/sprite_measure.py` measures every sprite as the game draws it (dev measure mode: F9 magenta box,
  F8 steps entries; captures by a walk script); whole screen pixels per sprite pixel from 2x up.
- Dev copy only: the `BestiaryProbe` dev mod also binds F8 (it adds test menu entries; 124 presses crashed the
  game). It is off in `C:\Games\FFR-mod`; never ship it.
- Menu tag: now the mod's own `UI.MainMenu.Scene.Bestiary`, registered by a row added to the debug menu's tag table
  (`DM_DT_GameplayTag_Option`, loaded via `GameplayTagTableList`) in the same pak. Tested 24 Oct.
- **Release** (`tools/make_release.sh` -> `dist/FFRBestiary`, no game files in it): `Install.bat` runs twice around one
  game launch. Run 1: UE4SS (bundled, MIT) + the mod + the `BestiaryMappings` helper. Game launch: writes
  `ue4ss/Mappings.usmap`. Run 2: bundled retoc extracts `DT_MainMenuScene` and `DM_DT_GameplayTag_Option` from the
  player's paks, `uasset-json bestiary` adds the rows, retoc builds `~mods/zzz_FFRBestiary_P`. Rerun after patches.
  Tested 24 Oct on a fresh copy (`C:\Games\FFR-installtest`): uninstall, both install phases, Steam-style launch
  from the game root, then in game (save picked up, faces, sprites, forms) - all working (24 Oct evening).
- Unnamed cutscene stages (`map:5200` etc.) are left out of location lists and headers. Still to confirm in play:
  `map:3170` (07Mys_40) and `QuestMapWorld` (world-map events with no island), and the element-mode variants.
- Text that is the mod's own English (no game string exists): "Encountered", "Scanned", "Locations".

## Pre-release review (Fable, 24 Oct evening) - fixed
- dist/ rebuilt fresh; make_release.sh now also zips it (dist/FFRBestiary.zip) and refuses if retoc's Oodle DLL
  (downloaded at install time; proprietary, never shipped) is in it. README says step 3 needs internet once.
- Installer: removes an earlier Bestiary pak before extracting (reinstall / after a game patch; tested: reinstall
  over an existing install), shows retoc / uasset-json output on failure (run with stderr-safe Invoke-Tool),
  refuses UE4SS 2.x layouts; uninstall keeps UE4SS when other mods use it.
- Runtime: the save slot comes from the save manager's GameSaveDataSummaryMap (no out-param struct), the current
  save from its m_pGameSaveData (no object search); a load is a new save object by full name (not address).
  Tested: load finds slot 1; a save to slot 10 wrote slot10.json a second later (slot 10 restored after).
- The menu entry is added only when the data pak exists (so installer step 1 is safe); the 20 s start-up fallback
  applies only if no loading screen was seen; one tick closure on the game thread.
- Screen rebuilt (e.g. after Return to Title): classes / textures / face cache looked up again; a new host is told by
  full name. Q/E or confirm pressed while closed is dropped on open. Entries met only in unnamed places are listed under "Other".
- Progress files: unreadable ones kept as .bad; writes go through .tmp and .bak so a failed rename loses nothing.
- Not changed: the DisplaySceneList append from Lua (works; isolated in game.addMenuEntry); backups accumulate in
  %LOCALAPPDATA%\FFRS-backups (one zip per install run).
