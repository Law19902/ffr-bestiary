FFR Bestiary - a bestiary for FINAL FANTASY RESONANCE (Steam, PC)
=================================================================

Adds "Bestiary" to the main menu: every enemy you have met, grouped by area, with the game's own scan (Libra)
details once you have scanned it, its animated battle sprite, and where it can be found.

Install
  1. Close the game. Double-click Install.bat.
  2. Start the game from Steam, wait for the title screen, quit.
  3. Double-click Install.bat again.
  After a game update, run Install.bat again (it may ask for step 2 once more).
  Step 3 needs an internet connection the first time (the bundled retoc tool downloads a decompression library).
  If the game isn't found (not a standard Steam library), run from a command prompt:
    powershell -ExecutionPolicy Bypass -File install.ps1 -GamePath "<path to the FINAL FANTASY RESONANCE folder>"
  If you already use UE4SS, it must be 3.0 or newer (the ue4ss\ folder layout); the installer adds the mod to it.

Uninstall
  Double-click Uninstall.bat. Your bestiary progress is kept in %LOCALAPPDATA%\FFRS-backups.

How it works
  - The installer adds UE4SS (unless you already have it) and the Bestiary script mod, and builds a small data pak
    from your own game files (it adds the menu entry). No game files are included in this download.
  - Your game saves are never touched. The installer backs them up to %LOCALAPPDATA%\FFRS-backups first anyway.
  - Bestiary progress is saved next to the mod (ue4ss\Mods\FFRBestiary\saves\slotN.json), one file per save slot,
    written when the game saves and read when you load. Scanned status comes from the game itself.
  - Installing part-way through the game: the enemies your save already records as defeated or scanned, and the
    areas it marks as visited, are picked up when you load. Where you met those enemies isn't recorded by the game,
    so their locations show ??? until you meet them again.
  - Steam Cloud syncs your game saves but not the bestiary files: on another PC the bestiary starts again from what
    your save records (enemies defeated or scanned, areas visited).

Controls in the Bestiary
  Up/Down: move.  Confirm on an area: open/close it.  Confirm on an enemy (or Q/E on a keyboard): next form, for enemies with
  several forms or phases.

Included third-party tools (MIT licence, see licenses\): UE4SS, retoc, UAssetAPI.
