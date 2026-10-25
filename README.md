# FFR Bestiary

A bestiary for **FINAL FANTASY RESONANCE** (Steam, PC). It adds a **Bestiary** page to the main menu: every enemy
you have met, grouped by area, with the game's own scan (Libra) details once you have scanned it, its animated
battle sprite, and where it can be found, with the world map on each area's page.

> First release, made for community feedback - expect rough edges. Bug reports and suggestions are very welcome in
> [Issues](../../issues).

![Area list](docs/screenshots/1_areas.png)
![An enemy page](docs/screenshots/2_goblin.png)
![A boss page](docs/screenshots/3_boss.png)

## Features
- Enemies grouped by area, with encountered / scanned counts for each area and for the whole game
- Unmet enemies of areas you have visited show as `???`, so you can see what is left to find
- Full scan details once scanned: affinities, HP, type, resistances, traits, drops and steals (before a scan, only
  what the battle screen has already shown you)
- Animated battle sprites and the battle timeline's face icons
- Encounter locations: places you have met the enemy are named, the rest show `???`
- Each area's page shows the world map, drawn like the game's own map screen, with the area marked
- Enemies with several forms or phases: confirm on the enemy steps through them
- Installing part-way through the game picks up what your save already records (enemies defeated or scanned, areas
  visited, and so where you met them)
- Enemies only fought before you have Libra (the prologue's, Belmodar) count as scanned once met
- The menu entry is named in the game's language
- Works with controller and keyboard; uses the game's own fonts, panels and icons

## Install
Download `FFRBestiary-0.1.2.zip` from [Nexus Mods](https://www.nexusmods.com/finalfantasyresonance/mods/88) or
[Releases](../../releases). There are no scripts or programs in it: you install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)
once yourself, then extract the zip into your game folder.

**UE4SS (one-time):**
1. Download the `UE4SS_v3...` zip (not `zDEV`) from
   [experimental-latest](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest).
2. In Steam: right-click the game > Manage > Browse local files, then open `FFRS\Binaries\Win64`.
3. Extract the UE4SS zip there (`dwmapi.dll` and the `ue4ss` folder next to `FFRS-Win64-Shipping.exe`).
4. In `ue4ss\UE4SS-settings.ini`, under `[EngineVersionOverride]`, set `MajorVersion = 5` and `MinorVersion = 6`.

**The mod:** extract the zip into the game folder (the one containing `FFRS`). It adds
`FFRS\Binaries\Win64\ue4ss\Mods\FFRBestiary` (enabled by the `enabled.txt` inside it) and
`FFRS\Content\Paks\~mods\zzz_FFRBestiary_P.*` (the menu entry). Bestiary appears in the main menu above System.

**Uninstall:** delete those two. **Your game saves are never written**; Bestiary progress lives in its own files in
the mod folder (`saves\`, one per save slot).

Made for game version 1.0.1.0: after a game update, check for a new version (the menu-entry pak is built from the
game's own menu table).

## How it works
- A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod (`runtime/FFRBestiary`) builds the page inside the game's
  own menu, tracks the enemies you meet in battle, and reads scan status from your save.
- The menu entry needs two rows in the game's data tables: `zzz_FFRBestiary_P` is those two tables with the
  Bestiary rows added (`tools/uasset-json` on [UAssetAPI](https://github.com/atenfyr/UAssetAPI), packed with
  [retoc](https://github.com/trumank/retoc); see `tools/build_pak.sh`).
- `data/bestiary_data.*` holds IDs, numbers and string-table keys only; all names and text come from the game at
  runtime, in your game's language.

## Building from source
Developer notes are in [docs/NOTES.md](docs/NOTES.md) and the original design in [docs/SPEC.md](docs/SPEC.md).
The data tools need the game's files extracted locally (`tools/ffr-dump`, a CUE4Parse dumper; a `.usmap` from
UE4SS) - nothing extracted is committed. `tools/build_pak.sh` builds the pak, `tools/make_release.sh` the zip.

## Credits and licence
- Mod code: MIT licence ([LICENSE](LICENSE)).
- Uses [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT, installed separately); the pak is built with retoc and UAssetAPI (MIT).
- The data tools use [CUE4Parse](https://github.com/FabianFG/CUE4Parse); recon was helped by the open-source
  FFR Vision Studio project.

FINAL FANTASY RESONANCE is © SQUARE ENIX. This is an unofficial fan mod, not affiliated with or endorsed by
Square Enix.
