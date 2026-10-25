#!/bin/sh
# Copy the UE4SS mod (+ generated data) into the modding copy. Ctrl+F12 in game hot-reloads it.
set -e
cd "$(dirname "$0")/.."
M=/c/Games/FFR-mod/FFRS/Binaries/Win64/ue4ss/Mods/FFRBestiary
mkdir -p "$M/Scripts"
cp runtime/FFRBestiary/Scripts/*.lua "$M/Scripts/"
cp data/bestiary_data.lua data/worldmap_data.lua "$M/Scripts/"
touch "$M/dev.txt"                 # development keys on (F7 show all, F3 focus log)
ls "$M/Scripts"
