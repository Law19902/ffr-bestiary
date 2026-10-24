#!/bin/sh
# Assemble the release folder dist/FFRBestiary from the repo + third-party tools. Nothing from the game goes in.
set -e
cd "$(dirname "$0")/.."
D=dist/FFRBestiary
rm -rf dist && mkdir -p $D/mod/FFRBestiary/Scripts $D/mod/BestiaryMappings/Scripts $D/tools $D/ue4ss $D/licenses
cp release/install.ps1 release/uninstall.ps1 release/find-game.ps1 release/Install.bat release/Uninstall.bat release/README.txt $D/
cp runtime/FFRBestiary/Scripts/*.lua data/bestiary_data.lua $D/mod/FFRBestiary/Scripts/
cp runtime/BestiaryMappings/Scripts/main.lua $D/mod/BestiaryMappings/Scripts/
# UE4SS: the build tested with this mod (experimental 3.0.1-1181), loader + core only, no sample mods
U=tools/downloads/ue4ss-zip
cp $U/dwmapi.dll $D/ue4ss/
mkdir -p $D/ue4ss/ue4ss/Mods
cp $U/ue4ss/UE4SS.dll $U/ue4ss/UE4SS-settings.ini $D/ue4ss/ue4ss/
cp -r $U/ue4ss/UE4SS_SDK_Backends $D/ue4ss/ue4ss/ 2>/dev/null || true
printf 'Keybinds : 0\n' > $D/ue4ss/ue4ss/Mods/mods.txt
cp $U/ue4ss/LICENSE $D/licenses/UE4SS-LICENSE.txt
cp tools/downloads/pipeline/retoc/retoc.exe $D/tools/
cp tools/downloads/pipeline/retoc/LICENSE $D/licenses/retoc-LICENSE.txt
cp build/publish/uasset-json/uasset-json.exe $D/tools/
printf 'UAssetAPI (https://github.com/atenfyr/UAssetAPI), MIT License, is compiled into tools\uasset-json.exe.\n' > $D/licenses/UAssetAPI.txt
echo "release assembled in $D"; du -sh $D
# the zip to publish, from the fresh folder (running the installer from dist/ lets retoc download its Oodle DLL into
# tools/; that is not ours to ship)
if ls $D/tools | grep -qi oo2core; then echo "ERROR: Oodle DLL in $D/tools" >&2; exit 1; fi
rm -f dist/FFRBestiary.zip
powershell -NoProfile -Command "Compress-Archive -Path 'dist/FFRBestiary' -DestinationPath 'dist/FFRBestiary.zip'"
ls -la dist/FFRBestiary.zip
