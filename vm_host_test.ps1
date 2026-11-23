$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class T {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32")] static extern bool EnumWindows(P p, IntPtr l);
  [DllImport("user32", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hi, bool r);
  public struct R { public int L, T, Rt, B; }
  public static string Title(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
  public static int Width(IntPtr h) { R r; GetWindowRect(h, out r); return r.Rt - r.L; }
  public static int TopCount() { int n = 0; EnumWindows((h,l)=>{ var s = new StringBuilder(64); GetClassName(h,s,64); if (IsWindowVisible(h) && s.ToString().StartsWith("EVERYTHING_(")) n++; return true; }, IntPtr.Zero); return n; }
  public static IntPtr FirstTop() { IntPtr f = IntPtr.Zero; EnumWindows((h,l)=>{ var s = new StringBuilder(64); GetClassName(h,s,64); if (IsWindowVisible(h) && s.ToString().StartsWith("EVERYTHING_(")) { f = h; return false; } return true; }, IntPtr.Zero); return f; }
}
'@
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root 'results'
New-Item -ItemType Directory -Force -Path $results | Out-Null
$tsv = Join-Path $results 'checks.tsv'
Set-Content -LiteralPath $tsv -Value "result`tcheck`tdetail" -Encoding UTF8
function Add-Check([string]$N, [bool]$Ok, [string]$D = '') { $l = "$(if ($Ok) {'PASS'} else {'FAIL'})`t$N`t$($D -replace '[\r\n\t]+',' ')"; Write-Host $l; Add-Content -LiteralPath $tsv -Value $l -Encoding UTF8 }
function Save-Screen([string]$Name) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save((Join-Path $results "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
}
function Wait-Until([scriptblock]$Test, [int]$Seconds = 10) { $t = [Diagnostics.Stopwatch]::StartNew(); while ($t.Elapsed.TotalSeconds -lt $Seconds) { if (& $Test) { return $true }; Start-Sleep -Milliseconds 120 }; return $false }

$installDir = 'C:\Program Files\Everything 1.5a'; $exe = Join-Path $installDir 'Everything64.exe'; $appData = Join-Path $env:APPDATA 'Everything'
New-Item -ItemType Directory -Force -Path $installDir, $appData, 'C:\evtest' | Out-Null
$zip = Join-Path $env:RUNNER_TEMP 'ev.zip'; $unz = Join-Path $env:RUNNER_TEMP 'ev'
Invoke-WebRequest -UseBasicParsing -Uri 'https://www.voidtools.com/Everything-1.5.0.1391a.x64.zip' -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $unz -Force
Copy-Item -LiteralPath (Join-Path $unz 'Everything64.exe') -Destination $exe -Force
Set-Content -LiteralPath (Join-Path $installDir 'Everything-1.5a.ini') -Encoding ASCII -Value "[Everything]`r`napp_data=1`r`nrun_as_admin=0`r`nindex_as_admin=0`r`nipc=1`r`n"
Set-Content -LiteralPath (Join-Path $appData 'Everything-1.5a.ini') -Encoding ASCII -Value "[Everything]`r`nallow_tabs=1`r`nallow_multiple_windows=0`r`nallow_multiple_instances=0`r`nopen_searches_in_tabs=1`r`nopen_new_windows_in_tabs=0`r`ntabs_show=1`r`ntabs_always_show=1`r`ntabs_load_in_background=0`r`n"
foreach ($n in 'alpha','bravo','charlie','delta') { 1..3 | ForEach-Object { Set-Content -LiteralPath "C:\evtest\evtab_${n}_$_.txt" -Value 'dummy' } }

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$hostExe = Join-Path $results 'EvSplit.exe'
$out = & $csc /nologo /target:winexe /platform:x64 /r:Accessibility.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll "/out:$hostExe" (Join-Path $root 'host\EvSplit.cs') 2>&1
Add-Check 'host compiles' ($LASTEXITCODE -eq 0) ($out | Out-String)
if ($LASTEXITCODE -ne 0) { exit 0 }

Start-Process -FilePath $exe
Wait-Until { [T]::TopCount() -ge 1 } 25 | Out-Null
Start-Sleep -Seconds 3
$outside = [T]::FirstTop()
$state = Join-Path $results 'state.txt'
$hp = Start-Process -FilePath $hostExe -ArgumentList "`"$exe`"", "`"$state`"" -PassThru
function Get-State { $m = @{}; if (Test-Path -LiteralPath $state) { foreach ($l in (Get-Content -LiteralPath $state -ErrorAction SilentlyContinue)) { $i = $l.IndexOf('='); if ($i -gt 0) { $m[$l.Substring(0,$i)] = $l.Substring($i+1) } } }; return $m }
function Send-Keys([string]$K) { [System.Windows.Forms.SendKeys]::SendWait($K); Start-Sleep -Milliseconds 350 }
function Open-Tab([string]$S) { $p = Start-Process -FilePath $exe -ArgumentList '-url', "es:$S`?newtab=1" -PassThru; $p.WaitForExit(8000) | Out-Null; Start-Sleep -Milliseconds 600 }

Add-Check 'host adopts two panes' (Wait-Until { $s = Get-State; $s['L_hwnd'] -and $s['R_hwnd'] } 25)
$s = Get-State; $L = [IntPtr][long]$s['L_hwnd']; $R = [IntPtr][long]$s['R_hwnd']; $H = $hp.MainWindowHandle
$hp.Refresh(); $H = $hp.MainWindowHandle
$desktop = [T]::GetDesktopWindow()
Add-Check 'both panes embedded' (([T]::GetAncestor($L, 1) -ne $desktop) -and ([T]::GetAncestor($R, 1) -ne $desktop))
Add-Check 'outside window not adopted' ([T]::IsWindow($outside) -and [T]::GetParent($outside) -eq [IntPtr]::Zero -and $outside -ne $L -and $outside -ne $R)

[T]::SetForegroundWindow($L) | Out-Null; Start-Sleep -Milliseconds 400
foreach ($q in 'evtab_alpha','evtab_bravo') { Open-Tab $q; [T]::SetForegroundWindow($L) | Out-Null; Start-Sleep -Milliseconds 200 }
Send-Keys '^%o'
Add-Check 'Ctrl+Alt+O moves to right pane' (Wait-Until { (Get-State)['active'] -eq 'R' } 4) (Get-State)['active']
foreach ($q in 'evtab_charlie','evtab_delta') { [T]::SetForegroundWindow($R) | Out-Null; Start-Sleep -Milliseconds 300; Send-Keys '^t'; Send-Keys $q; Start-Sleep -Milliseconds 300 }
Start-Sleep -Milliseconds 500
$s = Get-State
Add-Check 'each pane has its own tabs' ($s['L_tabs'] -match 'evtab_bravo' -and $s['R_tabs'] -match 'evtab_delta' -and $s['L_tabs'] -notmatch 'evtab_delta') "L=$($s['L_tabs']) R=$($s['R_tabs'])"
Save-Screen '01_split'

Send-Keys '^%k'
Add-Check 'Ctrl+Alt+K opens tab search' (Wait-Until { (Get-Process -Id $hp.Id).MainWindowTitle -ne $null } 2)
Start-Sleep -Milliseconds 400
Send-Keys 'alpha'
Save-Screen '02_palette'
Send-Keys '{ENTER}'
Add-Check 'tab search switches pane and tab' (Wait-Until { $x = Get-State; $x['active'] -eq 'L' -and $x['L_cur'] -match 'evtab_alpha' } 4) (Get-State)['L_cur']
Add-Check 'results really changed' (Wait-Until { [T]::Title($L) -match 'evtab_alpha' } 4) ([T]::Title($L))

Send-Keys '^%e'
Add-Check 'recent key returns to last tab' (Wait-Until { $x = Get-State; $x['active'] -eq 'R' -and $x['R_cur'] -match 'evtab_delta' } 4) "active=$((Get-State)['active']) R=$((Get-State)['R_cur'])"
Send-Keys '^%e'
Add-Check 'recent key flips back' (Wait-Until { $x = Get-State; $x['active'] -eq 'L' -and $x['L_cur'] -match 'evtab_alpha' } 4) "active=$((Get-State)['active']) L=$((Get-State)['L_cur'])"

[T]::SetForegroundWindow($L) | Out-Null; Start-Sleep -Milliseconds 300
Send-Keys '^a'; Send-Keys 'evtab_charlie'
Add-Check 'typing reaches focused pane' (Wait-Until { [T]::Title($L) -match 'evtab_charlie' } 4) ([T]::Title($L))
Add-Check 'other pane unaffected' ([T]::Title($R) -match 'evtab_delta') ([T]::Title($R))

$w1 = [T]::Width($L); [T]::MoveWindow($H, 10, 10, 800, 600, $true) | Out-Null; Start-Sleep -Milliseconds 500
Add-Check 'panes follow host resize' ([T]::Width($L) -ne $w1 -and [T]::Width($L) -gt 100) "$w1 -> $([T]::Width($L))"
[T]::SetForegroundWindow($L) | Out-Null; Start-Sleep -Milliseconds 250
Send-Keys '^%s'
Add-Check 'Ctrl+Alt+S collapses split' (Wait-Until { (Get-State)['collapsed'] -eq 'True' } 3)
Send-Keys '^%s'
Add-Check 'Ctrl+Alt+S restores split' (Wait-Until { (Get-State)['collapsed'] -eq 'False' } 3)

[T]::SetForegroundWindow($L) | Out-Null; Start-Sleep -Milliseconds 250
$hp.Refresh(); [GC]::Collect(); $h0 = $hp.HandleCount; $ws0 = $hp.WorkingSet64
for ($i = 0; $i -lt 150; $i++) { [System.Windows.Forms.SendKeys]::SendWait('^%e'); Start-Sleep -Milliseconds 70 }
Start-Sleep -Seconds 2; $hp.Refresh()
Add-Check 'no handle leak over 150 switches' (($hp.HandleCount - $h0) -le 20) "handles $h0 -> $($hp.HandleCount)"
Add-Check 'working set stable over 150 switches' (($hp.WorkingSet64 - $ws0) -le 15MB) "MB $([math]::Round($ws0/1MB,1)) -> $([math]::Round($hp.WorkingSet64/1MB,1))"
Save-Screen '03_after_soak'

$hp.CloseMainWindow() | Out-Null
Add-Check 'host exits cleanly' ($hp.WaitForExit(6000))
Start-Sleep -Seconds 1
Add-Check 'embedded windows closed' (-not ([T]::IsWindowVisible($L)) -and -not ([T]::IsWindowVisible($R)))
Add-Check 'outside window survives' ([T]::IsWindow($outside) -and [T]::IsWindowVisible($outside))
Add-Check 'Everything still running' (@(Get-Process -Name 'Everything64' -ErrorAction SilentlyContinue).Count -ge 1)
Save-Screen '04_after_close'
Remove-Item -LiteralPath $hostExe -ErrorAction SilentlyContinue
exit 0
