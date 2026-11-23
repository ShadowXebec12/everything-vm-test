Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$everythingExe = 'C:\Program Files\Everything 1.5a\Everything64.exe'
$sessionFile   = Join-Path $env:APPDATA 'Everything\Session-1.5a.json'
$scriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$savedDir      = Join-Path $scriptDir 'saved'
if (-not (Test-Path $savedDir)) { New-Item -ItemType Directory -Path $savedDir | Out-Null }

function ConvertTo-WindowsArgument {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
        } elseif ($character -eq '"') {
            if ($backslashes -gt 0) { [void]$builder.Append((('\' * ($backslashes * 2)) -join '')) }
            [void]$builder.Append('\"')
            $backslashes = 0
        } else {
            if ($backslashes -gt 0) { [void]$builder.Append((('\' * $backslashes) -join '')) }
            [void]$builder.Append($character)
            $backslashes = 0
        }
    }
    if ($backslashes -gt 0) { [void]$builder.Append((('\' * ($backslashes * 2)) -join '')) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Start-EverythingArguments {
    param([string[]]$Arguments)

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $everythingExe
    $processInfo.UseShellExecute = $false
    $processInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' ')
    [System.Diagnostics.Process]::Start($processInfo) | Out-Null
}

function ConvertTo-EverythingUrl {
    param(
        $Tab,
        [switch]$NewWindow
    )

    $settings = @()
    if ($Tab.filter) { $settings += 'filter=' + [uri]::EscapeDataString([string]$Tab.filter) }
    if ($Tab.sort) {
        $sortName = ([string]$Tab.sort -replace '\s+', '-')
        $settings += 'sort=' + [uri]::EscapeDataString($sortName)
    }
    if ($null -ne $Tab.sort_ascending)   { $settings += 'ascending=' + [string]$Tab.sort_ascending }
    if ($null -ne $Tab.match_case)       { $settings += 'case=' + [string]$Tab.match_case }
    if ($null -ne $Tab.match_path)       { $settings += 'path=' + [string]$Tab.match_path }
    if ($null -ne $Tab.match_whole_word) { $settings += 'wholeword=' + [string]$Tab.match_whole_word }
    if ($null -ne $Tab.match_regex)      { $settings += 'regex=' + [string]$Tab.match_regex }
    if ($NewWindow) { $settings += 'newwindow=1' }
    $settings += 'newtab=1'

    return 'es:' + [uri]::EscapeDataString([string]$Tab.search) + '?' + ($settings -join '&')
}

function Get-OpenWindows {
    if (-not (Test-Path $sessionFile)) { return @() }
    try {
        $data = Get-Content $sessionFile -Raw | ConvertFrom-Json
    } catch {
        return @()
    }
    $windows = @()
    for ($i = 0; $i -lt $data.Count; $i++) {
        $w = $data[$i]
        if ($w.is_closed -eq 1) { continue }
        $sessionTabs = @($w.tabs)
        if ($sessionTabs.Count -eq 0) { continue }
        $preview = ($sessionTabs | Select-Object -First 3 | ForEach-Object { if ($_.search) { $_.search } else { '(empty)' } }) -join ' | '
        $windows += [PSCustomObject]@{
            Index   = $i
            Tabs    = $sessionTabs
            Label   = "Window $($windows.Count + 1) [open window] - $($sessionTabs.Count) tabs - $preview"
        }
    }
    return $windows
}

function Get-TabsOut {
    param($winTabs)
    $tabsOut = @()
    foreach ($t in $winTabs) {
        $tabsOut += [PSCustomObject]@{
            search           = $t.search
            filter           = $t.filter
            sort             = $t.sort
            sort_ascending   = $t.sort_ascending
            match_case       = $t.match_case
            match_path       = $t.match_path
            match_whole_word = $t.match_whole_word
            match_regex      = $t.match_regex
        }
    }
    return $tabsOut
}

function Get-DefaultWorkspaceName {
    param(
        [int]$WindowNumber,
        [datetime]$Timestamp = (Get-Date)
    )
    return "Window $WindowNumber session $($Timestamp.ToString('yyyy-MM-dd_HHmmss'))"
}

function Get-SavedWorkspaces {
    Get-ChildItem -Path $savedDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | ForEach-Object {
            $tabs = @()
            try {
                # Windows PowerShell returns a JSON array as one Object[] item
                # when the pipeline is wrapped directly in @(...).
                $tabs = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $tabs = @($tabs)
            } catch {}
            $preview = ($tabs | Select-Object -First 3 | ForEach-Object { if ($_.search) { $_.search } else { '(empty)' } }) -join ' | '
            [PSCustomObject]@{
                Name  = $_.BaseName
                Label = "$($_.BaseName) - $($tabs.Count) tabs - $preview"
            }
        }
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Everything Workspaces" Height="520" Width="560" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="Save current Everything window as a workspace:" FontWeight="Bold" Margin="0,0,0,4"/>

        <Grid Grid.Row="1" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <ComboBox Name="WindowCombo" Grid.Column="0" Margin="0,0,6,0"/>
            <Button Name="RefreshWindowsBtn" Grid.Column="1" Content="Refresh open windows" Padding="6,2"/>
        </Grid>

        <Grid Grid.Row="2" Margin="0,0,0,6">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox Name="SaveNameBox" Grid.Column="0" Margin="0,0,6,0"/>
            <Button Name="SaveBtn" Grid.Column="1" Content="Save as workspace" Padding="6,2"/>
        </Grid>

        <Button Grid.Row="3" Name="SnapshotBtn" Content="Save current session (timestamped file per window)"
                Margin="0,0,0,10" Padding="6,4"/>

        <GroupBox Grid.Row="4" Header="Saved workspaces / snapshots">
            <ListBox Name="WorkspaceList"/>
        </GroupBox>

        <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="LoadBtn" Content="Load (open in new window)" Padding="8,3" Margin="0,0,6,0"/>
            <Button Name="RenameBtn" Content="Rename" Padding="8,3" Margin="0,0,6,0"/>
            <Button Name="DeleteBtn" Content="Delete" Padding="8,3"/>
        </StackPanel>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$windowCombo     = $window.FindName('WindowCombo')
$refreshBtn      = $window.FindName('RefreshWindowsBtn')
$saveNameBox     = $window.FindName('SaveNameBox')
$saveBtn         = $window.FindName('SaveBtn')
$snapshotBtn     = $window.FindName('SnapshotBtn')
$workspaceList   = $window.FindName('WorkspaceList')
$loadBtn         = $window.FindName('LoadBtn')
$renameBtn       = $window.FindName('RenameBtn')
$deleteBtn       = $window.FindName('DeleteBtn')
$workspaceList.DisplayMemberPath = 'Label'

$script:openWindows = @()

function Refresh-WindowCombo {
    # Everything autosaves Session-1.5a.json on its own periodically -- no need to
    # force it with -save-db-now (that CLI call has hung the live process before).
    $script:openWindows = Get-OpenWindows
    $windowCombo.Items.Clear()
    foreach ($w in $script:openWindows) { $windowCombo.Items.Add($w.Label) | Out-Null }
    if ($windowCombo.Items.Count -gt 0) { $windowCombo.SelectedIndex = 0 }
}

function Refresh-WorkspaceList {
    $workspaceList.Items.Clear()
    foreach ($w in (Get-SavedWorkspaces)) { $workspaceList.Items.Add($w) | Out-Null }
}

$refreshBtn.Add_Click({ Refresh-WindowCombo })

$saveBtn.Add_Click({
    if ($windowCombo.SelectedIndex -lt 0 -or $script:openWindows.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No open Everything window found. Click "Refresh open windows" first.', 'Everything Workspaces') | Out-Null
        return
    }
    $selectedWindow = $script:openWindows[$windowCombo.SelectedIndex]
    $name = $saveNameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = Get-DefaultWorkspaceName -WindowNumber ($windowCombo.SelectedIndex + 1)
    }
    $tabsOut = Get-TabsOut $selectedWindow.Tabs
    $destPath = Join-Path $savedDir ($name + '.json')
    if (Test-Path $destPath) {
        $confirm = [System.Windows.MessageBox]::Show("Workspace '$name' already exists. Overwrite?", 'Everything Workspaces', 'YesNo')
        if ($confirm -ne 'Yes') { return }
    }
    $tabsOut | ConvertTo-Json -Depth 5 | Set-Content -Path $destPath -Encoding utf8
    $saveNameBox.Text = ''
    Refresh-WorkspaceList
    [System.Windows.MessageBox]::Show("Saved $($tabsOut.Count) tabs to workspace '$name'.", 'Everything Workspaces') | Out-Null
})

$loadBtn.Add_Click({
    $selected = $workspaceList.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Select a saved workspace first.', 'Everything Workspaces') | Out-Null
        return
    }
    $name = $selected.Name
    $path = Join-Path $savedDir ($name + '.json')
    # Unwrap top-level JSON arrays correctly under Windows PowerShell 5.1.
    $tabs = Get-Content $path -Raw | ConvertFrom-Json
    $tabs = @($tabs)
    if ($tabs.Count -eq 0) {
        [System.Windows.MessageBox]::Show('That workspace has no saved tabs.', 'Everything Workspaces') | Out-Null
        return
    }
    # URL-encode the complete search. This preserves embedded quotes and paths
    # as one argument, so words from a path can never become separate tabs.
    for ($i = 0; $i -lt $tabs.Count; $i++) {
        $t = $tabs[$i]
        $everythingUrl = ConvertTo-EverythingUrl -Tab $t -NewWindow:($i -eq 0)
        Start-EverythingArguments -Arguments @('-url', $everythingUrl)
        Start-Sleep -Milliseconds 350
    }
})

$snapshotBtn.Add_Click({
    Refresh-WindowCombo
    if ($script:openWindows.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No open Everything windows found.', 'Everything Workspaces') | Out-Null
        return
    }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $saved = 0
    for ($i = 0; $i -lt $script:openWindows.Count; $i++) {
        $w = $script:openWindows[$i]
        $tabsOut = Get-TabsOut $w.Tabs
        $destPath = Join-Path $savedDir "Window $($i + 1) session $stamp.json"
        $tabsOut | ConvertTo-Json -Depth 5 | Set-Content -Path $destPath -Encoding utf8
        $saved++
    }
    Refresh-WorkspaceList
    [System.Windows.MessageBox]::Show("Saved $saved window(s) as timestamped session files ($stamp).", 'Everything Workspaces') | Out-Null
})

$renameBtn.Add_Click({
    $selected = $workspaceList.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Select a saved workspace first.', 'Everything Workspaces') | Out-Null
        return
    }
    $name = $selected.Name
    $newName = $saveNameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($newName)) {
        [System.Windows.MessageBox]::Show('Type the new name in the box above, then click Rename.', 'Everything Workspaces') | Out-Null
        return
    }
    $oldPath = Join-Path $savedDir ($name + '.json')
    $newPath = Join-Path $savedDir ($newName + '.json')
    if (Test-Path $newPath) {
        [System.Windows.MessageBox]::Show("A workspace named '$newName' already exists.", 'Everything Workspaces') | Out-Null
        return
    }
    Rename-Item -Path $oldPath -NewName (Split-Path -Leaf $newPath)
    $saveNameBox.Text = ''
    Refresh-WorkspaceList
})

$deleteBtn.Add_Click({
    $selected = $workspaceList.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Select a saved workspace first.', 'Everything Workspaces') | Out-Null
        return
    }
    $name = $selected.Name
    $confirm = [System.Windows.MessageBox]::Show("Delete workspace '$name'?", 'Everything Workspaces', 'YesNo')
    if ($confirm -ne 'Yes') { return }
    Remove-Item -Path (Join-Path $savedDir ($name + '.json')) -Force
    Refresh-WorkspaceList
})

Refresh-WindowCombo
Refresh-WorkspaceList

$window.ShowDialog() | Out-Null
