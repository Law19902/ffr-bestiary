FFR Bestiary 0.1.6 - a bestiary for FINAL FANTASY RESONANCE (Steam, PC)
=====================================================================

Adds "Bestiary" to the main menu (above System): every enemy you have met, grouped by area, with the game's own
scan (Libra) details once you have scanned it, its animated battle sprite, and where it can be found - with the
world map on each area's page.

Made for game version 1.0.1.0.


REQUIREMENT: UE4SS (one-time setup)
  1. Download UE4SS from https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest
     (the "UE4SS_v3..." zip, not the "zDEV" one).
  2. Open your game folder: in Steam, right-click FINAL FANTASY RESONANCE > Manage > Browse local files.
  3. Go into FFRS\Binaries\Win64 (the folder with FFRS-Win64-Shipping.exe) and extract the UE4SS zip there,
     so that dwmapi.dll and the ue4ss folder sit next to FFRS-Win64-Shipping.exe.
  4. Open ue4ss\UE4SS-settings.ini in Notepad, find [EngineVersionOverride] and set:
         MajorVersion = 5
         MinorVersion = 6
     Save the file.

INSTALL
  Extract this zip into your game folder (the FINAL FANTASY RESONANCE folder that contains FFRS). Its FFRS folder
  merges with the game's and adds:
    FFRS\Binaries\Win64\ue4ss\Mods\FFRBestiary\     the mod (switched on by the enabled.txt inside it)
    FFRS\Content\Paks\~mods\zzz_FFRBestiary_P.*      the menu entry
  Start the game and open the main menu: Bestiary is above System.

UNINSTALL
  Delete FFRS\Binaries\Win64\ue4ss\Mods\FFRBestiary and the three FFRS\Content\Paks\~mods\zzz_FFRBestiary_P files.
  (To remove UE4SS too, delete dwmapi.dll and the ue4ss folder in FFRS\Binaries\Win64 - if no other mod uses it.)
  Your bestiary progress is in ...\Mods\FFRBestiary\saves: copy it somewhere first if you want to keep it.

UPDATING
  Extract the new version over the old one. Progress (the saves folder) is kept.
  After a game update, check for a new version of this mod: the menu-entry pak is made for one game version.

GOOD TO KNOW
  - Your game saves are never written. Bestiary progress is kept in its own files next to the mod, one per save
    slot, written when the game saves and read when you load. Steam Cloud doesn't sync those files.
  - Installing part-way through the game: the enemies your save already records as defeated or scanned, and the
    areas it marks as visited, are picked up when you load (with their locations in the areas you have visited).
  - Enemies you can only fight before you have Libra (the prologue's, Belmodar) count as scanned once met.
  - The menu entry is named in the game's language (Japanese, German, French, Spanish, Korean, Chinese).
  - Already using UE4SS for other mods? Nothing to set up: just extract this zip.

CONTROLS IN THE BESTIARY
  Up/Down: move.  Confirm on an area: open/close it.  Confirm on an enemy (or Q/E on a keyboard): next form, for
  enemies with several forms or phases.

Source code and bug reports: https://github.com/Law19902/ffr-bestiary (MIT licence)
Support the mod and future ones: https://www.patreon.com/c/MerkyLAW
FINAL FANTASY RESONANCE is (c) SQUARE ENIX. Unofficial fan mod, not affiliated with or endorsed by Square Enix.
