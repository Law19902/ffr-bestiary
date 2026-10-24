# FFR Bestiary installer (FINAL FANTASY RESONANCE, Steam, PC).
#
# Run it twice:
#   1st run: installs UE4SS and the Bestiary mod, plus a one-time helper that writes the game's property mappings.
#            Then start the game once and wait for the title screen; quit.
#   2nd run: builds the Bestiary's small data pak from YOUR game's files (nothing from the game ships with this mod)
#            and switches the helper off. Done.
# Run it again after a game patch: it rebuilds the pak (and asks for the one game launch again if needed).
#
# usage: powershell -ExecutionPolicy Bypass -File install.ps1 [-GamePath "<...>\FINAL FANTASY RESONANCE"]
param([string]$GamePath)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say($m) { Write-Host $m }
function Fail($m) { Write-Host "`nERROR: $m" -ForegroundColor Red; exit 1 }
# run a bundled tool and return its output (stdout + stderr). Windows PowerShell turns stderr lines into errors,
# which 'Stop' would make fatal even when the tool succeeds, so that is relaxed for the call only.
function Invoke-Tool($exe, [string[]]$toolArgs) {
    $ErrorActionPreference = 'Continue'
    $out = & $exe @toolArgs 2>&1 | ForEach-Object { "$_" } | Out-String
    return $out
}

# --- find the game ---------------------------------------------------------------------------------------------
. (Join-Path $here 'find-game.ps1')
if (-not $GamePath) { $GamePath = Find-Game }
if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'FFRS\Binaries\Win64\FFRS-Win64-Shipping.exe'))) {
    Fail "Couldn't find FINAL FANTASY RESONANCE. Run again with -GamePath ""<path to the FINAL FANTASY RESONANCE folder>""."
}
if (Get-Process FFRS-Win64-Shipping -ErrorAction SilentlyContinue) { Fail 'Please close the game first.' }
$win64 = Join-Path $GamePath 'FFRS\Binaries\Win64'
$ue4ss = Join-Path $win64 'ue4ss'
$mods = Join-Path $ue4ss 'Mods'
$paks = Join-Path $GamePath 'FFRS\Content\Paks'
Say "Game: $GamePath"

# --- back up saves (the mod never writes them, but better safe) -------------------------------------------------
$saves = Join-Path $env:LOCALAPPDATA 'FFRS'
if (Test-Path $saves) {
    $bk = Join-Path $env:LOCALAPPDATA 'FFRS-backups'
    New-Item -ItemType Directory -Force $bk | Out-Null
    $zip = Join-Path $bk ("before-bestiary-install-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
    Compress-Archive -Path $saves -DestinationPath $zip
    Say "Saves backed up to $zip"
}

# --- UE4SS -----------------------------------------------------------------------------------------------------
# an older UE4SS (2.x: UE4SS.dll and Mods\ straight in Win64, loaded by xinput1_3.dll) can't run this mod, and adding
# ours beside it would load two
if ((Test-Path (Join-Path $win64 'UE4SS.dll')) -or (Test-Path (Join-Path $win64 'Mods\mods.txt'))) {
    Fail "An older UE4SS (2.x) is installed in $win64. This mod needs UE4SS 3.0 or newer (ue4ss\ folder layout): update or remove the old one, then run this again."
}
$record = Join-Path $mods 'FFRBestiary\install.json'
$weInstalledUE4SS = $false
if (Test-Path $record) { $weInstalledUE4SS = (Get-Content $record -Raw | ConvertFrom-Json).installedUE4SS }
if (-not (Test-Path (Join-Path $ue4ss 'UE4SS.dll'))) {
    Say 'Installing UE4SS...'
    Copy-Item (Join-Path $here 'ue4ss\dwmapi.dll') $win64 -Force
    Copy-Item (Join-Path $here 'ue4ss\ue4ss') $win64 -Recurse -Force
    $weInstalledUE4SS = $true
} else {
    Say 'UE4SS already installed; adding the mod to it.'
}
$ini = Join-Path $ue4ss 'UE4SS-settings.ini'
if ($weInstalledUE4SS -and (Test-Path $ini)) {
    $t = Get-Content $ini -Raw
    $t = $t -replace '(?m)^MajorVersion\s*=.*$', 'MajorVersion = 5' -replace '(?m)^MinorVersion\s*=.*$', 'MinorVersion = 6'
    [IO.File]::WriteAllText($ini, $t, (New-Object Text.UTF8Encoding($false)))
}

function Set-ModEnabled($name, $on) {
    $txt = Join-Path $mods 'mods.txt'
    $lines = @(); if (Test-Path $txt) { $lines = @(Get-Content $txt) }
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) { if ($l -notmatch "^\s*$([regex]::Escape($name))\s*:") { $list.Add($l) } }
    if ($on) {
        # UE4SS wants the Keybinds line last
        $i = $list.FindIndex([Predicate[string]]{ param($l) $l -match '^\s*Keybinds\s*:' })
        if ($i -ge 0) { $list.Insert($i, "$name : 1") } else { $list.Add("$name : 1") }
    }
    $lines = $list.ToArray()
    [IO.File]::WriteAllLines($txt, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
}

# --- the Bestiary mod (keeps its saves/ folder: your bestiary progress) -----------------------------------------
Say 'Installing the Bestiary mod...'
$dst = Join-Path $mods 'FFRBestiary'
New-Item -ItemType Directory -Force (Join-Path $dst 'Scripts') | Out-Null
Copy-Item (Join-Path $here 'mod\FFRBestiary\Scripts\*') (Join-Path $dst 'Scripts') -Force
Set-ModEnabled 'FFRBestiary' $true

# --- phase 2 needs the game's property mappings -----------------------------------------------------------------
$usmap = Join-Path $ue4ss 'Mappings.usmap'
$buildOf = { (Get-Item (Join-Path $win64 'FFRS-Win64-Shipping.exe')).LastWriteTimeUtc.ToString('o') }
$recordData = @{ installedUE4SS = $weInstalledUE4SS; gameExe = (& $buildOf); pak = $false }
if ((Test-Path $usmap) -and (Test-Path $record)) {
    $old = Get-Content $record -Raw | ConvertFrom-Json
    if ($old.gameExe -ne (& $buildOf)) {
        Say 'The game was updated since the last install: refreshing the mappings.'
        Remove-Item $usmap -Force
        Remove-Item (Join-Path $paks '~mods\zzz_FFRBestiary_P.*') -Force -ErrorAction SilentlyContinue   # built from the old tables
    }
}
if (-not (Test-Path $usmap)) {
    $helper = Join-Path $mods 'BestiaryMappings'
    New-Item -ItemType Directory -Force (Join-Path $helper 'Scripts') | Out-Null
    Copy-Item (Join-Path $here 'mod\BestiaryMappings\Scripts\*') (Join-Path $helper 'Scripts') -Force
    Set-ModEnabled 'BestiaryMappings' $true
    $recordData | ConvertTo-Json | Set-Content $record -Encoding UTF8
    Say "`nStep 1 of 2 done."
    Say 'Now start the game from Steam, wait for the title screen (about a minute), then quit the game'
    Say 'and run this installer once more.'
    exit 0
}

# --- build the data pak from this game's own files ------------------------------------------------------------
Say 'Building the Bestiary data pak from your game files (retoc may download a decompression library the first time)...'
# a pak from an earlier install would be read instead of the game's own table ("Bestiary row already there")
Remove-Item (Join-Path $paks '~mods\zzz_FFRBestiary_P.*') -Force -ErrorAction SilentlyContinue
$work = Join-Path $env:TEMP ('ffr-bestiary-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
try {
    $retoc = Join-Path $here 'tools\retoc.exe'
    $uj = Join-Path $here 'tools\uasset-json.exe'
    foreach ($f in 'DT_MainMenuScene', 'DM_DT_GameplayTag_Option') {
        $log = Invoke-Tool $retoc @('to-legacy', '--version', 'UE5_6', '--no-shaders', '-f', $f, $paks, (Join-Path $work 'legacy'))
        if ($LASTEXITCODE -ne 0) { Fail ("retoc could not extract $f (it needs internet the first time):`n" + $log) }
    }
    $log = Invoke-Tool $uj @('bestiary', (Join-Path $work 'legacy'), (Join-Path $work 'pak'), '--usmap', $usmap)
    if ($LASTEXITCODE -ne 0) { Fail ("could not add the Bestiary rows (game updated in an incompatible way?):`n" + $log) }
    $out = Join-Path $work 'out'; New-Item -ItemType Directory -Force $out | Out-Null
    $log = Invoke-Tool $retoc @('to-zen', '--version', 'UE5_6', (Join-Path $work 'pak'), (Join-Path $out 'zzz_FFRBestiary_P.utoc'))
    if ($LASTEXITCODE -ne 0) { Fail ("retoc could not build the pak:`n" + $log) }
    $modsDir = Join-Path $paks '~mods'
    New-Item -ItemType Directory -Force $modsDir | Out-Null
    Copy-Item (Join-Path $out 'zzz_FFRBestiary_P.*') $modsDir -Force
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Set-ModEnabled 'BestiaryMappings' $false
Remove-Item (Join-Path $mods 'BestiaryMappings') -Recurse -Force -ErrorAction SilentlyContinue
$recordData.pak = $true
$recordData | ConvertTo-Json | Set-Content $record -Encoding UTF8
Say "`nInstalled. Open the main menu in game (Tab / Menu button): Bestiary is above System."
