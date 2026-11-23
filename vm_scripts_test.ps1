$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies Accessibility @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class N {
  [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
  public static string[] TabNames(IntPtr tab) {
    var r = new List<string>(); Guid g = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71"); object o;
    if (AccessibleObjectFromWindow(tab, 0xFFFFFFFC, ref g, out o) != 0 || o == null) return r.ToArray();
    var a = (Accessibility.IAccessible)o; int n = a.accChildCount;
    for (int i = 1; i <= n; i++) { try { r.Add(a.get_accName(i) ?? ""); } catch { r.Add(""); } }
    return r.ToArray();
  }
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32")] static extern bool EnumWindows(P p, IntPtr l);
  [DllImport("user32")] static extern bool EnumChildWindows(IntPtr h, P p, IntPtr l);
  [DllImport("user32", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32")] public static extern bool SetForegroundWindow(IntPtr h);
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static List<IntPtr> Tops(string prefix) { var r = new List<IntPtr>(); EnumWindows((h,l)=>{ if (IsWindowVisible(h) && Cls(h).StartsWith(prefix)) r.Add(h); return true; }, IntPtr.Zero); return r; }
  public static IntPtr Child(IntPtr p, string c) { IntPtr f = IntPtr.Zero; EnumChildWindows(p, (h,l)=>{ if (Cls(h)==c) { f=h; return false; } return true; }, IntPtr.Zero); return f; }
}
'@

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root 'results'
New-Item -ItemType Directory -Force -Path $results | Out-Null
$tsv = Join-Path $results 'checks.tsv'
Set-Content -LiteralPath $tsv -Value "result`tcheck`tdetail" -Encoding UTF8

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $r = if ($Ok) { 'PASS' } else { 'FAIL' }
    $line = "$r`t$Name`t$($Detail -replace '[\r\n\t]+', ' ')"
    Write-Host $line
    Add-Content -LiteralPath $tsv -Value $line -Encoding UTF8
}
function Save-Screen([string]$Name) {
    try {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $bmp.Save((Join-Path $results "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
    } catch { Write-Host "screenshot failed: $_" }
}

# ---------- Match the live install layout ----------
$installDir = 'C:\Program Files\Everything 1.5a'
$exe = Join-Path $installDir 'Everything64.exe'
$appData = Join-Path $env:APPDATA 'Everything'
$sessionFile = Join-Path $appData 'Session-1.5a.json'
$bookmarks = Join-Path $appData 'Bookmarks-1.5a.csv'
New-Item -ItemType Directory -Force -Path $installDir, $appData | Out-Null
$zip = Join-Path $env:RUNNER_TEMP 'ev1391a.zip'
$unz = Join-Path $env:RUNNER_TEMP 'ev1391a'
Invoke-WebRequest -UseBasicParsing -Uri 'https://www.voidtools.com/Everything-1.5.0.1391a.x64.zip' -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $unz -Force
$src = Get-ChildItem -LiteralPath $unz -Recurse -Filter 'Everything*.exe' | Select-Object -First 1
Copy-Item -LiteralPath $src.FullName -Destination $exe -Force
Add-Check 'exe version is 1391a' ((Get-Item -LiteralPath $exe).VersionInfo.FileVersion -like '1.5.0.1391*') (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
Set-Content -LiteralPath (Join-Path $installDir 'Everything-1.5a.ini') -Encoding ASCII -Value "[Everything]`r`napp_data=1`r`nrun_as_admin=0`r`nindex_as_admin=0`r`nipc=1`r`n"
Set-Content -LiteralPath (Join-Path $appData 'Everything-1.5a.ini') -Encoding ASCII -Value "[Everything]`r`nallow_tabs=1`r`nallow_multiple_windows=0`r`nallow_multiple_instances=0`r`nopen_searches_in_tabs=1`r`nopen_new_windows_in_tabs=0`r`nsession_store=1`r`nsession_store_save_delay=15000`r`ntabs_show=1`r`ntabs_always_show=1`r`ntabs_load_in_background=0`r`n"

New-Item -ItemType Directory -Force -Path 'C:\evtest' | Out-Null
foreach ($n in 'alpha','bravo','charlie','delta','echo') { 1..3 | ForEach-Object { Set-Content -LiteralPath "C:\evtest\evtab_${n}_$_.txt" -Value 'dummy' } }

$wsDir = 'C:\vm test\everything workspaces'
New-Item -ItemType Directory -Force -Path (Join-Path $wsDir 'saved') | Out-Null
Copy-Item -Path (Join-Path $root 'scripts\*') -Destination $wsDir -Force
$saved = Join-Path $wsDir 'saved'

# ---------- Helpers ----------
function Invoke-Everything([string[]]$ArgList, [int]$TimeoutMs = 15000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.UseShellExecute = $false
    $psi.Arguments = ($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($TimeoutMs)) { return $false }
    return $true
}
function Get-EvWindows {
    $out = @()
    foreach ($h in [N]::Tops('EVERYTHING_(')) {
        $tab = [N]::Child($h, 'SysTabControl32')
        $names = @()
        if ($tab -ne [IntPtr]::Zero) { $names = @([N]::TabNames($tab)) }
        $out += [PSCustomObject]@{ Hwnd = $h; Class = [N]::Cls($h); Tabs = $names }
    }
    return ,$out
}
function Wait-Until([scriptblock]$Test, [int]$Seconds = 30) {
    $t = [Diagnostics.Stopwatch]::StartNew()
    while ($t.Elapsed.TotalSeconds -lt $Seconds) { if (& $Test) { return $true }; Start-Sleep -Milliseconds 400 }
    return $false
}
function Read-Session {
    for ($i = 0; $i -lt 8; $i++) {
        try { $d = Get-Content -LiteralPath $sessionFile -Raw -ErrorAction Stop | ConvertFrom-Json; return ,@($d) } catch { Start-Sleep -Milliseconds 500 }
    }
    return ,@()
}
function Get-Root { [System.Windows.Automation.AutomationElement]::RootElement }
function New-IdCond([string]$Id) { New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty), $Id }
function New-NameCond([string]$Name) { New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty), $Name }
function Find-Tops {
    (Get-Root).FindAll([System.Windows.Automation.TreeScope]::Children, (New-NameCond 'Everything Workspaces'))
}
function Get-Gui {
    foreach ($e in (Find-Tops)) { if ($e.Current.ClassName -ne '#32770') { return $e } }
    return $null
}
function Get-Dialog {
    foreach ($e in (Find-Tops)) { if ($e.Current.ClassName -eq '#32770') { return $e } }
    $g = Get-Gui
    if ($g) { foreach ($e in $g.FindAll([System.Windows.Automation.TreeScope]::Children, (New-NameCond 'Everything Workspaces'))) { if ($e.Current.ClassName -eq '#32770') { return $e } } }
    return $null
}
function Wait-Dialog([int]$Seconds = 5) {
    $found = $null
    $t = [Diagnostics.Stopwatch]::StartNew()
    while ($t.Elapsed.TotalSeconds -lt $Seconds) { $found = Get-Dialog; if ($found) { return $found }; Start-Sleep -Milliseconds 150 }
    return $null
}
function Close-Dialog($Dialog, [string]$Button = 'OK') {
    $text = ''
    $tc = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::Text)
    foreach ($x in $Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tc)) { $text += $x.Current.Name + ' ' }
    $b = $Dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-NameCond $Button))
    if ($b) { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
    Start-Sleep -Milliseconds 350
    return $text.Trim()
}
function Click-Id([string]$Id) {
    $g = Get-Gui
    if (-not $g) { throw 'workspace GUI is gone' }
    $b = $g.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-IdCond $Id))
    $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function Set-NameBox([string]$Text) {
    $b = (Get-Gui).FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-IdCond 'SaveNameBox'))
    $b.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
    Start-Sleep -Milliseconds 120
}
function Select-Workspace([string]$Prefix) {
    $list = (Get-Gui).FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-IdCond 'WorkspaceList'))
    $ic = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::ListItem)
    $tc = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::Text)
    foreach ($item in $list.FindAll([System.Windows.Automation.TreeScope]::Descendants, $ic)) {
        $label = $item.Current.Name
        $t = $item.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $tc)
        if ($t) { $label = $t.Current.Name }
        if ($label -like "$Prefix*") { $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 150; return $true }
    }
    return $false
}
function Read-Workspace([string]$Name) {
    $p = Join-Path $saved "$Name.json"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $d = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
    return ,@($d)
}
function Start-Gui {
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$wsDir\Everything Workspaces.bat`"" -WindowStyle Hidden
    return (Wait-Until { [bool](Get-Gui) } 25)
}
function Stop-Gui {
    $g = Get-Gui
    if ($g) { try { $g.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() } catch {} }
    Wait-Until { -not (Get-Gui) } 8 | Out-Null
}

# ---------- Real Everything session ----------
Start-Process -FilePath $exe
Add-Check 'Everything window opens' (Wait-Until { (Get-EvWindows).Count -ge 1 } 30)
$w = Get-EvWindows
Add-Check 'default instance class' ($w.Count -ge 1 -and $w[0].Class -eq 'EVERYTHING_(1.5a)') ($w | ForEach-Object Class | Out-String)
Add-Check 'single-window starts with 1 window' ($w.Count -eq 1) "windows=$($w.Count)"

$omega = 'evtab_omega ' + [char]0x3A9
foreach ($s in 'evtab_alpha','evtab_bravo','evtab_charlie',$omega) {
    Invoke-Everything @('-url', ('es:' + [uri]::EscapeDataString($s) + '?newtab=1')) | Out-Null
    Start-Sleep -Milliseconds 700
}
$w = Get-EvWindows
Add-Check 'seed tabs opened' (($w | ForEach-Object { $_.Tabs.Count } | Measure-Object -Sum).Sum -ge 3) (($w | ForEach-Object { $_.Tabs -join ' | ' }) -join ' || ')
$before = if (Test-Path -LiteralPath $sessionFile) { (Get-Item -LiteralPath $sessionFile).LastWriteTimeUtc } else { [datetime]::MinValue }
$urlOnly = Wait-Until { (Test-Path -LiteralPath $sessionFile) -and (Get-Item -LiteralPath $sessionFile).LastWriteTimeUtc -gt $before } 24
Add-Check 'INFO session saves after URL-opened tabs alone' $urlOnly 'FAIL here means the picker can be stale until the Everything window is used'
function Invoke-SessionTrigger([string]$Text) {
    $target = (Get-EvWindows)[0].Hwnd
    [N]::SetForegroundWindow($target) | Out-Null
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait('^t')
    Start-Sleep -Milliseconds 600
    [System.Windows.Forms.SendKeys]::SendWait($Text)
    Start-Sleep -Milliseconds 500
}
Invoke-SessionTrigger 'evtab_trigger'
$fresh = Wait-Until { (Test-Path -LiteralPath $sessionFile) -and (Get-Item -LiteralPath $sessionFile).LastWriteTimeUtc -gt $before } 30
Add-Check 'session file autosaves after using the window' $fresh "exists=$(Test-Path -LiteralPath $sessionFile)"
Start-Sleep -Seconds 2
$sessionHasSeeds = Wait-Until { (Get-Content -LiteralPath $sessionFile -Raw -ErrorAction SilentlyContinue) -match 'evtab_charlie' } 25
Add-Check 'session contains seeded tabs' $sessionHasSeeds
Copy-Item -LiteralPath $sessionFile -Destination (Join-Path $results 'session_after_seed.json') -ErrorAction SilentlyContinue
Save-Screen '01_seeded'

# Close one tab in Everything so the session holds a closed tab.
$h = (Get-EvWindows)[0].Hwnd
[N]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait('^w')
Start-Sleep -Seconds 19
$sess = Read-Session
$openWin = @($sess | Where-Object { $_.is_closed -ne 1 })
$allTabs = @($openWin | ForEach-Object { @($_.tabs) })
$liveTabs = @($allTabs | Where-Object { $_.is_closed -ne 1 })
Add-Check 'session records a closed tab' ($allTabs.Count -gt $liveTabs.Count) "all=$($allTabs.Count) open=$($liveTabs.Count)"

# ---------- GUI ----------
$five = @(
    @{ search='evtab_alpha'; filter='EVERYTHING'; sort='Date Modified'; sort_ascending=0; match_case=0; match_path=0; match_whole_word=0; match_regex=0 },
    @{ search='evtab_bravo txt'; filter='EVERYTHING'; sort='Name'; sort_ascending=1; match_case=0; match_path=0; match_whole_word=0; match_regex=0 },
    @{ search='path:"C:\evtest" charlie'; filter='EVERYTHING'; sort='Name'; sort_ascending=1; match_case=0; match_path=0; match_whole_word=0; match_regex=0 },
    @{ search='evtab_delta'; filter='EVERYTHING'; sort='Size'; sort_ascending=0; match_case=1; match_path=0; match_whole_word=0; match_regex=0 },
    @{ search=('evtab_echo ' + [char]0x3A9); filter='EVERYTHING'; sort='Name'; sort_ascending=1; match_case=0; match_path=0; match_whole_word=0; match_regex=0 }
)
$five | ForEach-Object { [PSCustomObject]$_ } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $saved 'seed five.json') -Encoding UTF8
[PSCustomObject]$five[0] | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $saved 'seed one.json') -Encoding UTF8

Add-Check 'GUI opens through the bat' (Start-Gui)
Save-Screen '02_gui'
try {
    Set-NameBox 'named save'
    Click-Id 'SaveBtn'
    $dlg = Wait-Dialog
    $msg = if ($dlg) { Close-Dialog $dlg } else { '' }
    $ws = Read-Workspace 'named save'
    Add-Check 'Save writes a workspace' ($null -ne $ws) $msg
    Add-Check 'Save excludes closed tabs' ($null -ne $ws -and $ws.Count -eq $liveTabs.Count) "saved=$(@($ws).Count) open=$($liveTabs.Count)"
    Add-Check 'Save keeps non-ASCII search' (@($ws | Where-Object { $_.search -ceq $omega }).Count -eq 1) (($ws | ForEach-Object search) -join ' | ')

    Set-NameBox 'named save'
    Click-Id 'SaveBtn'
    $dlg = Wait-Dialog
    $msg = if ($dlg) { Close-Dialog $dlg 'No' } else { '' }
    Add-Check 'Overwrite asks first' ($msg -like '*already exists*') $msg

    Set-NameBox ''
    Click-Id 'SaveBtn'
    $dlg = Wait-Dialog
    if ($dlg) { Close-Dialog $dlg | Out-Null }
    Add-Check 'Blank name gets timestamp' (@(Get-ChildItem -LiteralPath $saved -Filter 'Window 1 session *.json').Count -ge 1)

    foreach ($bad in 'bad:name', 'what?', 'a/b') {
        $beforeFiles = @(Get-ChildItem -LiteralPath $saved -File).Count
        Set-NameBox $bad
        Click-Id 'SaveBtn'
        $dlg = Wait-Dialog 3
        $msg = if ($dlg) { Close-Dialog $dlg } else { '(no message shown)' }
        $afterFiles = @(Get-ChildItem -LiteralPath $saved -File).Count
        $honest = ($msg -notlike 'Saved *') -and ($msg -ne '(no message shown)') -and ($afterFiles -eq $beforeFiles)
        Add-Check "Invalid name handled: $bad" $honest "msg=$msg files $beforeFiles -> $afterFiles"
    }
    Set-NameBox 'set [1]'
    Click-Id 'SaveBtn'
    $dlg = Wait-Dialog
    if ($dlg) { Close-Dialog $dlg | Out-Null }
    Add-Check 'Save handles [brackets] in name' (Test-Path -LiteralPath (Join-Path $saved 'set [1].json'))
    foreach ($decoy in 'w1', 'w2', 'w[12]') { '[]' | Set-Content -LiteralPath (Join-Path $saved "$decoy.json") -Encoding UTF8 }
    Set-NameBox ''

    Click-Id 'SnapshotBtn'
    $dlg = Wait-Dialog 8
    $msg = if ($dlg) { Close-Dialog $dlg } else { '' }
    Add-Check 'Snapshot saves each open window' ($msg -like 'Saved 1 window*') $msg

    Stop-Gui
    Start-Gui | Out-Null

    $beforeWins = (Get-EvWindows).Count
    $picked = Select-Workspace 'seed five'
    Add-Check 'List shows 5-tab workspace' $picked
    Click-Id 'LoadBtn'
    Start-Sleep -Seconds 6
    $after = Get-EvWindows
    $newest = $after | Sort-Object { $_.Tabs.Count } -Descending | Select-Object -First 1
    Add-Check 'Load opens a new window' ($after.Count -eq $beforeWins + 1) "windows $beforeWins -> $($after.Count)"
    $tabText = ($after | ForEach-Object { $_.Tabs -join ' | ' }) -join ' || '
    Add-Check 'Load opens all 5 tabs in one window' (@($after | Where-Object { (@($_.Tabs | Where-Object { $_ -match 'evtab_alpha|evtab_bravo txt|charlie|evtab_delta|evtab_echo' }).Count) -ge 5 }).Count -ge 1) $tabText
    Add-Check 'Quoted path stays one tab' ($tabText -match 'path:"C:\\evtest" charlie') $tabText
    Add-Check 'Non-ASCII search survives' ($tabText -match [string][char]0x3A9) $tabText
    Save-Screen '03_loaded_five'

    $picked = Select-Workspace 'seed one'
    Add-Check 'One-tab workspace is listed' $picked
    $beforeWins = (Get-EvWindows).Count
    Click-Id 'LoadBtn'
    Start-Sleep -Seconds 3
    Add-Check 'One-tab workspace loads' ((Get-EvWindows).Count -eq $beforeWins + 1) "windows $beforeWins -> $((Get-EvWindows).Count)"

    Select-Workspace 'named save' | Out-Null
    Set-NameBox 'renamed save'
    Click-Id 'RenameBtn'
    Start-Sleep -Milliseconds 700
    Add-Check 'Rename works' ((Test-Path -LiteralPath (Join-Path $saved 'renamed save.json')) -and -not (Test-Path -LiteralPath (Join-Path $saved 'named save.json')))

    Select-Workspace 'renamed save' | Out-Null
    Set-NameBox 'seed one'
    Click-Id 'RenameBtn'
    $dlg = Wait-Dialog
    $msg = if ($dlg) { Close-Dialog $dlg } else { '' }
    Add-Check 'Rename refuses existing name' ($msg -like '*already exists*') $msg

    Select-Workspace 'renamed save' | Out-Null
    Set-NameBox 'bad:rename'
    Click-Id 'RenameBtn'
    $dlg = Wait-Dialog 3
    $msg = if ($dlg) { Close-Dialog $dlg } else { '(no message shown)' }
    Add-Check 'Rename invalid name tells user' ($msg -ne '(no message shown)') $msg
    Set-NameBox ''

    Select-Workspace 'w[12]' | Out-Null
    Click-Id 'DeleteBtn'
    $dlg = Wait-Dialog
    if ($dlg) { Close-Dialog $dlg 'Yes' | Out-Null }
    Start-Sleep -Milliseconds 500
    Add-Check 'Delete [brackets] removes only that file' ((-not (Test-Path -LiteralPath (Join-Path $saved 'w[12].json'))) -and (Test-Path -LiteralPath (Join-Path $saved 'w1.json')) -and (Test-Path -LiteralPath (Join-Path $saved 'w2.json')))
    Select-Workspace 'renamed save' | Out-Null
    Click-Id 'DeleteBtn'
    $dlg = Wait-Dialog
    if ($dlg) { Close-Dialog $dlg 'No' | Out-Null }
    Add-Check 'Delete No keeps file' (Test-Path -LiteralPath (Join-Path $saved 'renamed save.json'))
    Select-Workspace 'renamed save' | Out-Null
    Click-Id 'DeleteBtn'
    $dlg = Wait-Dialog
    if ($dlg) { Close-Dialog $dlg 'Yes' | Out-Null }
    Start-Sleep -Milliseconds 500
    Add-Check 'Delete Yes removes file' (-not (Test-Path -LiteralPath (Join-Path $saved 'renamed save.json')))
} catch {
    Add-Check 'GUI test finished without an error' $false "$_"
    Save-Screen 'gui_error'
}
$d = Get-Dialog
if ($d) { Close-Dialog $d | Out-Null }
Stop-Gui
Get-ChildItem -LiteralPath $saved -Force | Select-Object Name, Length | Format-Table -AutoSize | Out-File -LiteralPath (Join-Path $results 'saved_listing.txt')

# ---------- Save-SessionBookmarks ----------
function Invoke-Bookmarks {
    $o = Join-Path $results 'bm_out.txt'; $e = Join-Path $results 'bm_err.txt'
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$wsDir\Save-SessionBookmarks.ps1`"" -WindowStyle Hidden -RedirectStandardOutput $o -RedirectStandardError $e -PassThru
    $null = $p.Handle
    $done = $p.WaitForExit(30000)
    [PSCustomObject]@{ Done = $done; Exit = $(if ($done) { $p.ExitCode } else { -1 }); Out = (Get-Content -LiteralPath $o -Raw -ErrorAction SilentlyContinue); Err = (Get-Content -LiteralPath $e -Raw -ErrorAction SilentlyContinue) }
}
$hadFile = Test-Path -LiteralPath $bookmarks
if ($hadFile) { Move-Item -LiteralPath $bookmarks -Destination "$bookmarks.vmhold" -Force }
$r = Invoke-Bookmarks
Add-Check 'Bookmarks: finishes with no bookmark file' ($r.Done -and $r.Out -match '^OK' -and (Test-Path -LiteralPath $bookmarks)) "exit=$($r.Exit) out=$($r.Out) err=$($r.Err)"
if (Test-Path -LiteralPath $bookmarks) {
    $first = Get-Content -LiteralPath $bookmarks -TotalCount 1
    Add-Check 'Bookmarks: new file has header' ($first -like '*Name,Type,Folder*') $first
    Remove-Item -LiteralPath $bookmarks -Force
}
if ($hadFile) { Move-Item -LiteralPath "$bookmarks.vmhold" -Destination $bookmarks -Force }

Invoke-Everything @('-exit') 20000 | Out-Null
Wait-Until { (Get-EvWindows).Count -eq 0 } 15 | Out-Null
$header = 'Name,Type,Folder,Case,Whole Word,Path,Diacritic,Prefix,Suffix,Ignore Punctuation,Ignore Whitespace,Regex,Search,Filter,Columns,Sort,Descending,View,Index,File List,Host,Link Type,Macro,Key,Icon'
$keep = '"keep me",0,"",0,0,0,0,0,0,0,0,0,"evtab_alpha","","","",0,0,,,,0,,,""'
[IO.File]::WriteAllText($bookmarks, "$header`r`n$keep`r`n", (New-Object System.Text.UTF8Encoding $false))
Start-Process -FilePath $exe
Wait-Until { (Get-EvWindows).Count -ge 1 } 25 | Out-Null
foreach ($s in 'evtab_bookmark_one','evtab "quoted" two',('evtab_bm_omega ' + [char]0x3A9)) {
    Invoke-Everything @('-url', ('es:' + [uri]::EscapeDataString($s) + '?newtab=1')) | Out-Null
    Start-Sleep -Milliseconds 700
}
Invoke-SessionTrigger 'evtab_bm_trigger'
Wait-Until { (Get-Content -LiteralPath $sessionFile -Raw -ErrorAction SilentlyContinue) -match 'evtab_bookmark_one' } 30 | Out-Null
Start-Sleep -Seconds 2
$r = Invoke-Bookmarks
Add-Check 'Bookmarks: runs without hanging' ($r.Done -and $r.Exit -eq 0 -and $r.Out -match '^OK') "exit=$($r.Exit) out=$($r.Out) err=$($r.Err)"
Copy-Item -LiteralPath $bookmarks -Destination (Join-Path $results 'bookmarks_after_run.csv') -ErrorAction SilentlyContinue
$raw = [IO.File]::ReadAllBytes($bookmarks)
$bomCount = 0
for ($i = 3; $i -lt $raw.Length - 2; $i++) { if ($raw[$i] -eq 0xEF -and $raw[$i+1] -eq 0xBB -and $raw[$i+2] -eq 0xBF) { $bomCount++ } }
Add-Check 'Bookmarks: no BOM mid-file' ($bomCount -eq 0) "mid-file BOMs=$bomCount"
$rows = @(Import-Csv -LiteralPath $bookmarks)
Add-Check 'Bookmarks: CSV parses with 25 fields' ($rows.Count -gt 1 -and @($rows[0].PSObject.Properties).Count -eq 25) "rows=$($rows.Count)"
Add-Check 'Bookmarks: keeps existing row' (@($rows | Where-Object Name -eq 'keep me').Count -eq 1)
Add-Check 'Bookmarks: quoted search intact' (@($rows | Where-Object Search -eq 'evtab "quoted" two').Count -ge 1)
$sessionFolderRows = @($rows | Where-Object { $_.Name -eq 'Sessions' -and $_.Type -eq '1' })
Add-Check 'Bookmarks: Sessions parent folder exists' ($sessionFolderRows.Count -ge 1) "rows=$($sessionFolderRows.Count)"
$sessionRows = @($rows | Where-Object Search -eq 'evtab_bookmark_one').Count
$child = @($rows | Where-Object Search -eq 'evtab_bookmark_one')[0]
Add-Check 'Bookmarks: tab nests under Sessions/Window' ($child.Folder -like 'Sessions/Window%201%20-%20*') $child.Folder
$winName = [uri]::UnescapeDataString(($child.Folder -split '/')[1])
Add-Check 'Bookmarks: window folder row is under Sessions' (@($rows | Where-Object { $_.Type -eq '1' -and $_.Name -eq $winName -and $_.Folder -eq 'Sessions' }).Count -eq 1) $winName
$utfRows = @(Import-Csv -LiteralPath $bookmarks -Encoding UTF8)
Add-Check 'Bookmarks: non-ASCII search intact' (@($utfRows | Where-Object { $_.Search -ceq ('evtab_bm_omega ' + [char]0x3A9) }).Count -ge 1)
Add-Check 'Bookmarks: file stays without BOM' (-not ($raw[0] -eq 0xEF -and $raw[1] -eq 0xBB))
Start-Sleep -Seconds 1
$r2 = Invoke-Bookmarks
$rows2 = @(Import-Csv -LiteralPath $bookmarks -Encoding UTF8)
Add-Check 'Bookmarks: second run keeps one Sessions folder' ($r2.Exit -eq 0 -and @($rows2 | Where-Object { $_.Name -eq 'Sessions' -and $_.Type -eq '1' }).Count -eq 1) "exit=$($r2.Exit)"
$rows = $rows2
$sessionRows = @($rows | Where-Object Search -eq 'evtab_bookmark_one').Count

Invoke-Everything @('-exit') 20000 | Out-Null
Wait-Until { (Get-EvWindows).Count -eq 0 } 15 | Out-Null
Start-Sleep -Seconds 2
$after = @(Import-Csv -LiteralPath $bookmarks)
Add-Check 'Bookmarks: survive Everything exit' (@($after | Where-Object Search -eq 'evtab_bookmark_one').Count -eq $sessionRows -and $sessionRows -ge 1) "before=$sessionRows after=$(@($after | Where-Object Search -eq 'evtab_bookmark_one').Count)"
Copy-Item -LiteralPath $bookmarks -Destination (Join-Path $results 'bookmarks_after_exit.csv') -ErrorAction SilentlyContinue
Start-Process -FilePath $exe
Wait-Until { (Get-EvWindows).Count -ge 1 } 25 | Out-Null
Start-Sleep -Seconds 3
Invoke-Everything @('-exit') 20000 | Out-Null
Wait-Until { (Get-EvWindows).Count -eq 0 } 15 | Out-Null
Start-Sleep -Seconds 2
$after2 = @(Import-Csv -LiteralPath $bookmarks)
Add-Check 'Bookmarks: survive a restart' (@($after2 | Where-Object Search -eq 'evtab_bookmark_one').Count -ge 1) "rows=$($after2.Count)"
Start-Process -FilePath $exe
Wait-Until { (Get-EvWindows).Count -ge 1 } 25 | Out-Null
Start-Sleep -Seconds 2
Invoke-Everything @('-bookmark', 'evtab_bookmark_one') | Out-Null
$opened = Wait-Until { @((Get-EvWindows) | Where-Object { ($_.Tabs -join ' ') -match 'evtab_bookmark_one' }).Count -ge 1 } 8
Add-Check 'Bookmarks: Everything can open a saved bookmark' $opened (((Get-EvWindows) | ForEach-Object { $_.Tabs -join ' | ' }) -join ' || ')
[N]::SetForegroundWindow((Get-EvWindows)[0].Hwnd) | Out-Null
Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait('%b')
Start-Sleep -Milliseconds 700
Save-Screen '04_bookmarks_menu'
[System.Windows.Forms.SendKeys]::SendWait('{ESC}{ESC}')
$big = Join-Path $env:RUNNER_TEMP 'big_session.json'
$oneTab = '{"is_closed":0,"search":"evtab_big_search_text_for_size","filter":"EVERYTHING","sort":"Name","sort_ascending":1,"match_case":0,"match_path":0,"match_whole_word":0,"match_regex":0,"padding":"' + ('x' * 300) + '"}'
$oneWin = '{"is_closed":0,"tabs":[' + ((1..60 | ForEach-Object { $oneTab }) -join ',') + ']}'
[IO.File]::WriteAllText($big, '[' + ((1..($([int](20MB / $oneWin.Length))) | ForEach-Object { $oneWin }) -join ',') + ']')
$sw = [Diagnostics.Stopwatch]::StartNew()
$bigOk = $false
try { $bigData = Get-Content -LiteralPath $big -Raw -Encoding UTF8 | ConvertFrom-Json; $bigOk = @($bigData).Count -gt 1 } catch { $bigErr = "$_" }
$sw.Stop()
Add-Check 'Large 20 MB session parses' $bigOk ("seconds=$([math]::Round($sw.Elapsed.TotalSeconds,1)) bytes=$((Get-Item -LiteralPath $big).Length) $bigErr")

$fails = @(Import-Csv -LiteralPath $tsv -Delimiter "`t" | Where-Object result -eq 'FAIL').Count
Write-Host "FAILS: $fails"
exit 0
