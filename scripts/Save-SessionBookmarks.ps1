$everythingExe  = 'C:\Program Files\Everything 1.5a\Everything64.exe'
$sessionFile    = Join-Path $env:APPDATA 'Everything\Session-1.5a.json'
$bookmarksFile  = Join-Path $env:APPDATA 'Everything\Bookmarks-1.5a.csv'
$parentFolder   = 'Sessions'

function Csv-Quoted {
    param([string]$s)
    if ($null -eq $s) { $s = '' }
    return '"' + ($s -replace '"', '""') + '"'
}

function Csv-Bool {
    param($v)
    if ($v -eq 1 -or $v -eq $true) { return '1' }
    return '0'
}

function Build-Row {
    param(
        [string]$Name, [int]$Type, [string]$Folder,
        [int]$Case = 0, [int]$WholeWord = 0, [int]$Path = 0,
        [int]$Regex = 0, [string]$Search = '', [string]$Filter = '',
        [string]$Sort = '', [int]$Descending = 0
    )
    $fields = @(
        (Csv-Quoted $Name),
        $Type,
        (Csv-Quoted $Folder),
        (Csv-Bool $Case),
        (Csv-Bool $WholeWord),
        (Csv-Bool $Path),
        '0',
        '0',
        '0',
        '0',
        '0',
        (Csv-Bool $Regex),
        (Csv-Quoted $Search),
        (Csv-Quoted $Filter),
        (Csv-Quoted ''),
        (Csv-Quoted $Sort),
        $Descending,
        '0',
        '',
        '',
        '',
        '0',
        '',
        '',
        (Csv-Quoted '')
    )
    return ($fields -join ',')
}

if (-not (Test-Path $everythingExe)) { throw "Everything 1.5a not found at $everythingExe" }

Start-Process -FilePath $everythingExe -ArgumentList '-save-db-now' -WindowStyle Hidden | Out-Null
Start-Sleep -Milliseconds 800

if (-not (Test-Path $sessionFile)) { throw "Session file not found: $sessionFile" }
$data = Get-Content $sessionFile -Raw | ConvertFrom-Json

$openWindows = @()
for ($i = 0; $i -lt $data.Count; $i++) {
    $w = $data[$i]
    if ($w.is_closed -eq 1) { continue }
    $openTabs = @($w.tabs | Where-Object { $_.is_closed -ne 1 })
    if ($openTabs.Count -eq 0) { continue }
    $openWindows += [PSCustomObject]@{ Tabs = $openTabs }
}

if ($openWindows.Count -eq 0) {
    Write-Output "NO_OPEN_WINDOWS"
    exit 0
}

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$backupPath = Join-Path (Split-Path $bookmarksFile) ("Bookmarks-1.5a.backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".csv")
Copy-Item -Path $bookmarksFile -Destination $backupPath -Force

$newLines = @()
$windowNum = 0
foreach ($w in $openWindows) {
    $windowNum++
    $folderName = "Window $windowNum - $stamp"
    $newLines += Build-Row -Name $folderName -Type 1 -Folder $parentFolder
    foreach ($t in $w.Tabs) {
        $searchText = if ($t.search) { $t.search } else { '' }
        $name = if ($searchText) { $searchText } else { '(empty search)' }
        $descending = if ($t.sort_ascending -eq 1) { 0 } else { 1 }
        $newLines += Build-Row -Name $name -Type 0 -Folder $folderName `
            -Case $t.match_case -WholeWord $t.match_whole_word -Path $t.match_path -Regex $t.match_regex `
            -Search $searchText -Filter $t.filter -Sort $t.sort -Descending $descending
    }
}

Add-Content -Path $bookmarksFile -Value $newLines -Encoding utf8

Write-Output "OK windows=$($openWindows.Count) tabs=$(($openWindows.Tabs | Measure-Object).Count) backup=$backupPath"
