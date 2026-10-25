#!/bin/sh
# Assemble the release zip: a folder tree to extract into the game folder. Only the mod's own files and the small
# menu-entry pak built by tools/build_pak.sh - no scripts, no programs, no UE4SS (players install it themselves;
# Nexus quarantines .bat/.ps1/.exe).
set -e
cd "$(dirname "$0")/.."
VERSION=0.1.2
D=dist/FFRBestiary
M=$D/FFRS/Binaries/Win64/ue4ss/Mods/FFRBestiary
P=$D/FFRS/Content/Paks/~mods
rm -rf dist && mkdir -p $M/Scripts "$P"
cp runtime/FFRBestiary/Scripts/*.lua data/bestiary_data.lua data/worldmap_data.lua $M/Scripts/
printf 'UE4SS loads this mod because this file exists.
' > $M/enabled.txt   # no mods.txt edit needed
cp release/README.txt $M/README.txt
cp build/out/zzz_FFRBestiary_P.pak build/out/zzz_FFRBestiary_P.utoc build/out/zzz_FFRBestiary_P.ucas "$P/"
# nothing executable may slip in
if find $D -type f | grep -iqE '\.(bat|cmd|ps1|exe|dll|vbs|js)$'; then echo "ERROR: executable file in $D" >&2; exit 1; fi
rm -f dist/FFRBestiary-$VERSION.zip
# zip with forward slashes (Windows PowerShell's Compress-Archive writes backslashes, which some tools mishandle)
python -c "
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for d, _, files in os.walk(os.path.join(root, 'FFRS')):
        for f in sorted(files):
            full = os.path.join(d, f)
            z.write(full, os.path.relpath(full, root).replace(os.sep, '/'))
" $D dist/FFRBestiary-$VERSION.zip
find $D -type f | sed "s|^$D/||"
ls -la dist/FFRBestiary-$VERSION.zip
