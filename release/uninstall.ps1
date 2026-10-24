# FFR Bestiary uninstaller. Removes the data pak and the mod; removes UE4SS only if this mod's installer put it there.
# Your bestiary progress (ue4ss\Mods\FFRBestiary\saves) is moved to %LOCALAPPDATA%\FFRS-backups first.
# usage: powershell -ExecutionPolicy Bypass -File uninstall.ps1 [-GamePath "<...>\FINAL FANTASY RESONANCE"]
param([string]$GamePath)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'find-game.ps1')
if (-not $GamePath) { $GamePath = Find-Game }
if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'FFRS\Binaries\Win64'))) { Write-Host 'Game not found; pass -GamePath.'; exit 1 }
if (Get-Process FFRS-Win64-Shipping -ErrorAction SilentlyContinue) { Write-Host 'Please close the game first.'; exit 1 }
$win64 = Join-Path $GamePath 'FFRS\Binaries\Win64'
$mods = Join-Path $win64 'ue4ss\Mods'
$mod = Join-Path $mods 'FFRBestiary'

Remove-Item (Join-Path $GamePath 'FFRS\Content\Paks\~mods\zzz_FFRBestiary_P.*') -Force -ErrorAction SilentlyContinue
$installedUE4SS = $false
if (Test-Path (Join-Path $mod 'install.json')) { $installedUE4SS = (Get-Content (Join-Path $mod 'install.json') -Raw | ConvertFrom-Json).installedUE4SS }
if (Test-Path (Join-Path $mod 'saves')) {
    $bk = Join-Path $env:LOCALAPPDATA ('FFRS-backups\bestiary-progress-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force $bk | Out-Null
    Copy-Item (Join-Path $mod 'saves\*') $bk -Recurse -Force
    Write-Host "Bestiary progress kept in $bk"
}
foreach ($m in 'FFRBestiary', 'BestiaryMappings') { Remove-Item (Join-Path $mods $m) -Recurse -Force -ErrorAction SilentlyContinue }
$txt = Join-Path $mods 'mods.txt'
if (Test-Path $txt) {
    $lines = @(Get-Content $txt | Where-Object { $_ -notmatch '^\s*(FFRBestiary|BestiaryMappings)\s*:' })
    [IO.File]::WriteAllLines($txt, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
}
if ($installedUE4SS) {
    # other mods added since: UE4SS stays for them
    $others = @(Get-ChildItem $mods -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'FFRBestiary', 'BestiaryMappings', 'shared' })
    if ($others.Count -gt 0) {
        Write-Host ('UE4SS kept: other mods use it (' + (($others | ForEach-Object Name) -join ', ') + ').')
    } else {
        Remove-Item (Join-Path $win64 'dwmapi.dll') -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $win64 'ue4ss') -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host 'UE4SS removed (it was installed by the Bestiary installer).'
    }
}
Write-Host 'FFR Bestiary uninstalled.'
