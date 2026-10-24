# FFR Bestiary Mod — Spec

## Goal
A mod for FINAL FANTASY RESONANCE (PC, Steam) that adds a **Bestiary** entry to the pause menu. It is a database of every enemy in the game, filled in as the player encounters and scans them.

## Behaviour

**Enemy list**
- One entry per enemy that can actually be encountered in the released game. Entries that exist in the data but have no encounter location anywhere are cut content and are excluded.
- An enemy appears in the list once the player has **seen** it (it has appeared in a battle).
- Enemies not yet seen are not listed at all (no placeholders).

**Entry detail — Seen**
- Shows the same basic information the battle screen shows for an enemy you have not scanned: name, level, type, HP, and whatever else is visible in battle without a scan.
- Shows the enemy's **animated idle sprite**, playing in the panel.
- Everything a scan would reveal (weaknesses, resistances, drops, steals, stats, move list etc.) is shown as `???`.

**Entry detail — Scanned**
- Once the player has scanned the enemy, every `???` field is replaced with the full information the in-game scan shows.

**Encounter locations**
- Each entry has a list of areas where the enemy can be encountered.
- Areas where the player has actually seen the enemy show the area name.
- Areas where the enemy can be encountered but the player has not seen it there yet are shown greyed out as `???`.
- So the number of `???` rows tells the player how many locations are left to find.

**Scope — keep it tight**
- Seen / scanned / locations only. No kill counts, no drop tracking, no sprite viewer, no retroactive filling for existing saves. These can come later.
- Missable enemies are not the mod's problem; no special handling.

## Data storage
- Bestiary progress is stored in the mod's **own JSON file, one per save slot**, not inside the game's save. Must never risk corrupting the game's saves.
- Game saves live at `%LOCALAPPDATA%\FFRS\Steam\<SteamID>\GameSaveData*.sav` — use the slot number to key the bestiary file.
- Fields per enemy: `seen` (bool), `scanned` (bool), `seenAreas` (list of area IDs).

## Technical facts (confirmed from the demo / community)
- Engine: **Unreal Engine 5**. Process is `FFRS-Win64-Shipping.exe`; project name is `FFRS`.
- Paks are in `FFRS/Content/Paks`. Mods load from `FFRS/Content/Paks/~mods`. The demo's paks were **not encrypted**; verify the same is true for the full game before assuming an AES key is needed.
- PC version uses **Denuvo**. It protects the exe, not the paks. UE4SS is confirmed working (there is a UE4SS mod menu for the demo on Nexus); UE4SS goes in `FFRS/Binaries/Win64`.
- Enemies, abilities and visions are all in **DataTables**. The open-source **FFR Vision Studio** (github.com/FFBE-JP-Translation/FFR-Vison-Studio, site ffbe.luminest.io) reads and writes these tables and ships as three pak files in `~mods`. **Read its source first** to learn the table names, row structure and localisation setup before doing any recon of your own.
- Fan databases list ~264 boss records plus regular enemies with level, type, EXP, gil, HP, drops, rare drops, steal chances and move lists — so all of that is in the tables.
- Tools: FModel for browsing paks and exporting DataTables/localisation as JSON; UE4SS for runtime hooks and dumping classes; UAssetGUI if assets need editing.

## Implementation outline
1. **Recon.** Read the Vision Studio repo. Open the full game in FModel. Identify: the enemy DataTable, the encounter/spawn tables (likely per-map), how scripted boss fights are placed (may be event scripts or level Blueprints rather than tables), the localisation string tables for area and enemy names, the enemy sprite/flipbook assets (Paper2D or custom), and the pause-menu widget.
2. **Hooks** (UE4SS). On battle start: record each enemy ID and the current area ID as seen. On a scan resolving: mark that enemy scanned. Write to the JSON file.
3. **Location map.** Build enemy → list of area IDs from the spawn/encounter data plus scripted fights. Enemies with no locations are excluded from the bestiary.
4. **UI.** A bespoke bestiary screen (do not reuse the battle info or scan widgets): list on one side, detail panel on the other, animated sprite, `???` for unknown fields and locations. Must work with controller navigation and match the game's menu style. Add a Bestiary entry to the pause menu.
5. **Verify** everything in-game before calling a step done. Everything in this spec that depends on how the game is built must be confirmed from the actual files; where the game does something differently, say so and adapt rather than guessing.

## Constraints
- Never bundle extracted game assets in the released mod.
- Expect game patches to break hooks; keep hook code isolated and easy to update.
- Back up saves before any testing.
