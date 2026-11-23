$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root 'results'
New-Item -ItemType Directory -Force -Path $results | Out-Null
$log = Join-Path $results 'diag.txt'
function Write-Diag([string]$T) { Write-Host $T; Add-Content -LiteralPath $log -Value $T -Encoding UTF8 }

$installDir = 'C:\Program Files\Everything 1.5a'
$exe = Join-Path $installDir 'Everything64.exe'
$appData = Join-Path $env:APPDATA 'Everything'
New-Item -ItemType Directory -Force -Path $installDir, $appData | Out-Null
$zip = Join-Path $env:RUNNER_TEMP 'ev.zip'
$unz = Join-Path $env:RUNNER_TEMP 'ev'
Invoke-WebRequest -UseBasicParsing -Uri 'https://www.voidtools.com/Everything-1.5.0.1391a.x64.zip' -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $unz -Force
Write-Diag ('zip contents: ' + ((Get-ChildItem -LiteralPath $unz -Recurse -File | ForEach-Object Name) -join ', '))
$src = Get-ChildItem -LiteralPath $unz -Recurse -Filter 'Everything*.exe' | Select-Object -First 1
Copy-Item -LiteralPath $src.FullName -Destination $exe -Force
Set-Content -LiteralPath (Join-Path $installDir 'Everything-1.5a.ini') -Encoding ASCII -Value "[Everything]`r`napp_data=1`r`nrun_as_admin=0`r`nindex_as_admin=0`r`nipc=1`r`n"
Set-Content -LiteralPath (Join-Path $appData 'Everything-1.5a.ini') -Encoding ASCII -Value "[Everything]`r`nallow_tabs=1`r`nallow_multiple_windows=0`r`nallow_multiple_instances=0`r`nopen_searches_in_tabs=1`r`nsession_store=1`r`nsession_store_save_delay=15000`r`ntabs_show=1`r`ntabs_always_show=1`r`n"

function Write-Listing([string]$Label) {
    Write-Diag "--- $Label"
    foreach ($d in $appData, $installDir, (Join-Path $env:LOCALAPPDATA 'Everything')) {
        if (Test-Path -LiteralPath $d) {
            Get-ChildItem -LiteralPath $d -File -Force | ForEach-Object { Write-Diag ("{0} | {1} | {2:HH:mm:ss}" -f $_.FullName, $_.Length, $_.LastWriteTime) }
        }
    }
}

$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 5
foreach ($s in 'evdiag_a', 'evdiag_b') {
    Start-Process -FilePath $exe -ArgumentList '-url', "es:$s`?newtab=1" -Wait
    Start-Sleep -Milliseconds 700
}
Write-Listing 'after seeding'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace V -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);'
$p.Refresh()
[V.W]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait('^t')
Start-Sleep -Milliseconds 600
[System.Windows.Forms.SendKeys]::SendWait('evdiag_typed')
Start-Sleep -Seconds 22
Write-Listing 'after typing in a new tab, 22s'
$p.Refresh()
[V.W]::PostMessage($p.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
Start-Sleep -Seconds 4
$p.Refresh()
Write-Diag "after WM_CLOSE, process exited: $($p.HasExited)"
Write-Listing 'after closing window'
if ($p.HasExited) { $p = Start-Process -FilePath $exe -PassThru } else { Start-Process -FilePath $exe }
Start-Sleep -Seconds 5
Write-Listing 'after reopening'
Start-Sleep -Seconds 18
Write-Listing 'after 18s more'
$s = Start-Process -FilePath $exe -ArgumentList '-save-db-now' -PassThru
Write-Diag "save-db-now exited in 15s: $($s.WaitForExit(15000))"
Start-Sleep -Seconds 3
Write-Listing 'after save-db-now'
$x = Start-Process -FilePath $exe -ArgumentList '-exit' -PassThru
$x.WaitForExit(20000) | Out-Null
$p.WaitForExit(20000) | Out-Null
Start-Sleep -Seconds 2
Write-Listing 'after exit'
$ini = Join-Path $appData 'Everything-1.5a.ini'
if (Test-Path -LiteralPath $ini) {
    Write-Diag '--- ini session keys after exit'
    Get-Content -LiteralPath $ini | Where-Object { $_ -match '^[a-z_]*session[a-z_]*=' } | ForEach-Object { Write-Diag $_ }
    Copy-Item -LiteralPath $ini -Destination (Join-Path $results 'vm_ini.txt')
}
$f = Join-Path $appData 'Session-1.5a.json'
if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination (Join-Path $results 'session.json') }
exit 0
