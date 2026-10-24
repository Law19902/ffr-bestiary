#!/bin/sh
# Development: build the data pak from extracted/legacy (DT_MainMenuScene + tag table, Bestiary rows added) and
# install it in the modding copy. The release does the same on the player's machine (release/install.ps1).
# usage: tools/build_pak.sh
set -e
export MSYS_NO_PATHCONV=1          # keep /Game and /Script paths as they are
cd "$(dirname "$0")/.."
UJ=tools/uasset-json/bin/Release/net10.0/uasset-json.exe
RETOC=tools/downloads/pipeline/retoc/retoc.exe
rm -rf build/pak build/out && mkdir -p build/out
$UJ bestiary extracted/legacy build/pak
$RETOC to-zen --version UE5_6 build/pak build/out/zzz_FFRBestiary_P.utoc > build/retoc.log 2>&1
cp build/out/zzz_FFRBestiary_P.* "/c/Games/FFR-mod/FFRS/Content/Paks/~mods/"
echo installed
