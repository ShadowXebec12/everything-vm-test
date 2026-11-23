$ErrorActionPreference = 'Stop'

$results = Join-Path $PWD 'results'
New-Item -ItemType Directory -Force -Path $results | Out-Null
$log = Join-Path $results 'info.txt'
function Write-Info([string]$Text) { Write-Host $Text; Add-Content -LiteralPath $log -Value $Text }

$dummy = 'C:\evtest'
New-Item -ItemType Directory -Force -Path $dummy | Out-Null
1..20 | ForEach-Object { Set-Content -LiteralPath (Join-Path $dummy ("evtest_dummy_{0:d2}.txt" -f $_)) -Value 'dummy' }

$zipName = 'Everything-1.5.0.1424b.x64.en-US.zip'
$zip = Join-Path $env:RUNNER_TEMP $zipName
$dir = Join-Path $env:RUNNER_TEMP 'everything'
Invoke-WebRequest -Uri "https://www.voidtools.com/$zipName" -OutFile $zip
Write-Info "zip sha256: $((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash)"
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
$exe = Get-ChildItem -LiteralPath $dir -Recurse -Filter 'Everything*.exe' | Select-Object -First 1
if (-not $exe) { throw 'Everything exe not found in zip' }
Write-Info "exe: $($exe.Name) version $($exe.VersionInfo.FileVersion)"

$proc = Start-Process -FilePath $exe.FullName -ArgumentList '-instance', 'vmtest', '-search', 'evtest_dummy' -PassThru

$title = ''
for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 1
    $proc.Refresh()
    if ($proc.HasExited) { throw "Everything exited with code $($proc.ExitCode)" }
    if ($proc.MainWindowHandle -ne 0) { $title = $proc.MainWindowTitle; break }
}
Start-Sleep -Seconds 15
$proc.Refresh()
$title = $proc.MainWindowTitle
Write-Info "pid: $($proc.Id)"
Write-Info "window handle: $($proc.MainWindowHandle)"
Write-Info "window title: $title"
Write-Info "session: $($proc.SessionId)"

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Info "screen: $($bounds.Width)x$($bounds.Height)"
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save((Join-Path $results 'screen.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

if ($proc.MainWindowHandle -eq 0) { throw 'Everything has no visible main window' }
Write-Info 'RESULT: window opened'
