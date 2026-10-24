# Drive the modding copy for tests: focus the game window, send keys (hardware scan codes), take screenshots.
# usage: powershell -File tools\drive.ps1 <command> [args]
#   keys "<k>[:ms] <k>[:ms] ..."   press keys in order; :ms holds the key (default 80 ms). k = name from $codes
#   shot <out.png>                  screenshot of the primary screen, scaled to 1280 wide
param([string]$cmd, [string]$arg)

Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class Drv {
  [StructLayout(LayoutKind.Sequential)] public struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size=40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static void Key(ushort scan, bool up, bool ext) {
    var i = new INPUT[1]; i[0].type = 1; i[0].ki.scan = scan;
    i[0].ki.flags = 0x0008u | (up ? 0x0002u : 0u) | (ext ? 0x0001u : 0u);
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@

$codes = @{ esc=0x01; enter=0x1C; space=0x39; w=0x11; a=0x1E; s=0x1F; d=0x20; q=0x10; e=0x12; tab=0x0F; f=0x21;
            up=0x48; down=0x50; left=0x4B; right=0x4D; f7=0x41; backspace=0x0E; shift=0x2A; z=0x2C; x=0x2D; c=0x2E; r=0x13; t=0x14; b=0x30; v=0x2F; m=0x32; j=0x24; g=0x22; h=0x23; k=0x25; l=0x26;
            n=0x31; y=0x15; u=0x16; i=0x17; o=0x18; p=0x19; ctrl=0x1D; alt=0x38; f1=0x3B; f2=0x3C; f3=0x3D; f4=0x3E; f8=0x42; f9=0x43; f10=0x44; f11=0x57; f12=0x58; f6=0x40; f5=0x3F }
$ext = @('up','down','left','right')

function Focus {
  $p = Get-Process FFRS-Win64-Shipping -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $p) { throw 'game not running' }
  for ($try = 0; $try -lt 5 -and [Drv]::GetForegroundWindow() -ne $p.MainWindowHandle; $try++) {
    # Windows only lets the process that got the last input change the foreground: tap Alt first
    [Drv]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Drv]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [Drv]::ShowWindow($p.MainWindowHandle, 9) | Out-Null
    [Drv]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 200
  }
  if ([Drv]::GetForegroundWindow() -ne $p.MainWindowHandle) { throw 'could not focus the game window' }
}

if ($cmd -eq 'keys') {
  Focus
  $game = (Get-Process FFRS-Win64-Shipping | Select-Object -First 1).MainWindowHandle
  foreach ($tok in $arg.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)) {
    if ($tok -match '^wait:(\d+)$') { Start-Sleep -Milliseconds ([int]$Matches[1]); continue }
    # never type into another window: stop if the game closed or lost the foreground since the last key
    if ([Drv]::GetForegroundWindow() -ne $game -or -not (Get-Process FFRS-Win64-Shipping -ErrorAction SilentlyContinue)) {
      throw "game window no longer in front; stopped before '$tok'"
    }
    $name, $ms = $tok.Split(':'); if (-not $ms) { $ms = 80 }
    $mods = @(); if ($name.Contains('+')) { $parts = $name.Split('+'); $mods = $parts[0..($parts.Count - 2)]; $name = $parts[-1] }
    foreach ($m in $mods) { [Drv]::Key([uint16]$codes[$m], $false, $false); Start-Sleep -Milliseconds 40 }
    $sc = [uint16]$codes[$name]; $isExt = $ext -contains $name
    [Drv]::Key($sc, $false, $isExt); Start-Sleep -Milliseconds ([int]$ms); [Drv]::Key($sc, $true, $isExt)
    foreach ($m in $mods) { [Drv]::Key([uint16]$codes[$m], $true, $false) }
    Start-Sleep -Milliseconds 120
  }
} elseif ($cmd -eq 'shot') {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
  $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
  $w = 1280; $h = [int]($b.Height * $w / $b.Width)
  $small = New-Object Drawing.Bitmap $bmp, $w, $h
  $small.Save($arg)
}
