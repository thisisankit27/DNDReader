# Synthetic-input + screenshot helpers used for the Windows verification run (manual-style input only).
# Dot-source it:  . .\input-helpers.ps1     Gotchas learned the hard way:
#  * Flutter's Windows embedder maps keys from SCAN codes - keybd_event with scan code 0 is ignored (KD/Key below add them).
#  * Do NOT name a function `Move` (alias of Move-Item). Use MouseTo.
#  * SetProcessDPIAware is called below; without it coordinates are DPI-virtualised (1920x1080@150% reads as 1280x720).
#  * Another window (e.g. an IDE) can take the foreground between tool calls: call Activate and check its result at
#    the start of every script, and keep one test inside one call.
#  * Never aim input at a CAPTCHA or an interstitial verification widget.
# Verification helpers: screenshot + synthetic mouse/keyboard (ordinary manual-style input)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c,uint t);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,int dx,int dy,int d,int e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte sc,uint f,int e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h,int i);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
[void][W]::SetProcessDPIAware()
function Shot($name, $dir=(Get-Location).Path) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width,$b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size)
  $p = Join-Path $dir "$name.png"; $bmp.Save($p,[System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose(); $p
}
function MouseTo($x,$y){ [void][W]::SetCursorPos($x,$y) }
function Click($x,$y,$n=1){ MouseTo $x $y; Start-Sleep -Milliseconds 80; 1..$n | % { [W]::mouse_event(2,0,0,0,0); [W]::mouse_event(4,0,0,0,0); Start-Sleep -Milliseconds 60 } }
function RClick($x,$y){ MouseTo $x $y; Start-Sleep -Milliseconds 80; [W]::mouse_event(8,0,0,0,0); [W]::mouse_event(16,0,0,0,0) }
function Drag($x1,$y1,$x2,$y2){ MouseTo $x1 $y1; Start-Sleep -Milliseconds 80; [W]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 80; MouseTo $x2 $y2; Start-Sleep -Milliseconds 120; [W]::mouse_event(4,0,0,0,0) }
function Wheel($x,$y,$notches){ MouseTo $x $y; Start-Sleep -Milliseconds 60; [W]::mouse_event(0x800,0,0,[int](-120*$notches),0) }
function KD($vk,$up){ $sc=[byte][W]::MapVirtualKey([uint32]$vk,0); $ext=0; if(@(0x25,0x26,0x27,0x28,0x2E,0x24,0x23,0x21,0x22) -contains $vk){$ext=1}; $fl=$ext; if($up){$fl=$fl -bor 2}; [W]::keybd_event([byte]$vk,$sc,[uint32]$fl,0) }
function Key($vk,$mods=@()){ foreach($m in $mods){KD $m $false}; KD $vk $false; Start-Sleep -Milliseconds 40; KD $vk $true; foreach($m in ($mods|Sort-Object -Descending)){KD $m $true}; Start-Sleep -Milliseconds 200 }
$VK = @{ CTRL=0x11; SHIFT=0x10; ALT=0x12; ESC=0x1B; ENTER=0x0D; F11=0x7A; DOWN=0x28; UP=0x26; LEFT=0x25; RIGHT=0x27; O=0x4F; E=0x45; T=0x54; R=0x52; TAB=0x09; A=0x41; BACK=0x08 }
function Typ($s){ [System.Windows.Forms.SendKeys]::SendWait($s) }
function Title(){ $sb = New-Object System.Text.StringBuilder 256; [void][W]::GetWindowText([W]::GetForegroundWindow(),$sb,256); $sb.ToString() }
function Rect($h){ $r = New-Object W+RECT; [void][W]::GetWindowRect($h,[ref]$r); "$($r.L),$($r.T) $($r.R-$r.L)x$($r.B-$r.T)" }
function Activate(){
  $p = Get-Process dndreader -EA SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } | Select -First 1
  if(-not $p){ return $false }
  $h = $p.MainWindowHandle
  [W]::ShowWindow($h,9) | Out-Null
  KD 0x12 $false; [W]::SetForegroundWindow($h) | Out-Null; KD 0x12 $true   # ALT trick to defeat foreground lock
  Start-Sleep -Milliseconds 400
  return ([W]::GetForegroundWindow() -eq $h)
}
function AppRect(){ $p = Get-Process dndreader -EA SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } | Select -First 1; if($p){ Rect $p.MainWindowHandle } }
