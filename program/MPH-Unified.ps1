<#
    MPH Unified Player List  (Wiimmfi + WiiLink WFC)  — PowerShell + WinForms

    ログ責務:
      lib\LogStore.ps1          … ソース別の保存・集約・フィルタ
      lib\DiagnosticLogView.ps1 … ログ表示 UI
      各 Source                  … 自身の診断イベント発行
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$WiimmfiLib = Join-Path $ScriptDir 'lib\WiimmfiSource.ps1'
$WiiLinkLib = Join-Path $ScriptDir 'lib\WiiLinkSource.ps1'
$WiiLinkFallbackLib = Join-Path $ScriptDir 'lib\WiiLinkFallback.ps1'
. $WiimmfiLib
. $WiiLinkLib
. $WiiLinkFallbackLib
. (Join-Path $ScriptDir 'lib\TreeRender.ps1')
. (Join-Path $ScriptDir 'lib\ViewerCommon.ps1')
. (Join-Path $ScriptDir 'lib\LogStore.ps1')
. (Join-Path $ScriptDir 'lib\DiagnosticLogView.ps1')
. (Join-Path $ScriptDir 'lib\I18n.ps1')
$theme = Get-MphTheme
$i18n = Get-MphI18n

$form = New-Object System.Windows.Forms.Form
$form.Text = 'MPH Player List  -  Wiimmfi + WiiLink'
$form.Size = New-Object System.Drawing.Size(1120, 680)
$form.MinimumSize = New-Object System.Drawing.Size(860, 500)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $theme.bgDark
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$bar = New-TopBar -Theme $theme -Title 'Metroid Prime Hunters' -TitleColor $theme.orange -I18n $i18n -Height 50
$wlTransport = New-WiiLinkTransportSelector -Theme $theme -I18n $i18n -Flow $bar.Flow
$wm = New-TreePanel -Theme $theme -HeadColor $theme.cyan
$wl = New-TreePanel -Theme $theme -HeadColor $theme.green

$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.Dock = 'Fill'; $grid.ColumnCount = 2; $grid.RowCount = 1; $grid.BackColor = $theme.bgDark
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$grid.Controls.Add($wm.Panel, 0, 0)
$grid.Controls.Add($wl.Panel, 1, 0)

$status = New-StatusBar -Theme $theme -Text $i18n.connecting
$diagnostic = New-DiagnosticLogPanel -Theme $theme -I18n $i18n -ExpandedHeight 230 -SourceOptions @(
    @{ Key = 'All'; Text = $i18n.logAll },
    @{ Key = 'Wiimmfi'; Text = $i18n.logWiimmfi },
    @{ Key = 'WiiLink'; Text = $i18n.logWiiLink },
    @{ Key = 'App'; Text = $i18n.logApp }
)
$form.Controls.Add($grid)
$form.Controls.Add($bar.Panel)
$form.Controls.Add($status)
$form.Controls.Add($diagnostic.Panel)

$wiimmfiLogStore = New-MphLogStore -Source 'Wiimmfi'
$wiiLinkLogStore = New-MphLogStore -Source 'WiiLink'
$appLogStore = New-MphLogStore -Source 'App'
$logStores = @($wiimmfiLogStore, $wiiLinkLogStore, $appLogStore)

$sync = [hashtable]::Synchronized(@{
        WiimmfiLib = $WiimmfiLib; WiiLinkLib = $WiiLinkLib; WiiLinkFallbackLib = $WiiLinkFallbackLib
        WiimmfiUrl = 'https://wiimmfi.de/stats/game/mprimeds'
        Game = 'mprimeds'; Ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList'; Lang = $i18n.lang
        IntervalMs = 30000; Stop = $false; WiimmfiRefresh = $false; WiiLinkRefresh = $false
        WiimmfiJson = $null; WiimmfiSeq = 0; WiimmfiStatus = 'starting'; WiimmfiPid = 0
        WiiLinkJson = $null; WiiLinkSeq = 0; WiiLinkStatus = 'starting'; WiiLinkTransport = 'browser'; WiiLinkPid = 0
        WiimmfiLogQueue = $wiimmfiLogStore.Queue
        WiiLinkLogQueue = $wiiLinkLogStore.Queue
    })

$wmWorker = @'
. $sync.WiimmfiLib
$ctx = Start-WiimmfiBrowser -Url $sync.WiimmfiUrl -LogQueue $sync.WiimmfiLogQueue
if (-not $ctx.ok) {
    $sync.WiimmfiJson = (@{ ok = $false; error = $ctx.error; online = 0; players = @() } | ConvertTo-Json -Depth 6 -Compress)
    $sync.WiimmfiSeq = [int]$sync.WiimmfiSeq + 1; $sync.WiimmfiStatus = $ctx.error
    return
}
$sync.WiimmfiPid = $ctx.proc.Id
try {
    while (-not $sync.Stop) {
        $data = Get-WiimmfiData -Port $ctx.port -Lang $sync.Lang -LogQueue $sync.WiimmfiLogQueue
        $sync.WiimmfiJson = ($data | ConvertTo-Json -Depth 8 -Compress)
        $sync.WiimmfiSeq = [int]$sync.WiimmfiSeq + 1
        $sync.WiimmfiStatus = if ($data.ok) { 'ok' } else { 'connecting' }
        $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
        $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop -and -not $sync.WiimmfiRefresh) { Start-Sleep -Milliseconds 200; $slept += 200 }
        $sync.WiimmfiRefresh = $false
    }
} finally {
    Stop-WiimmfiBrowser -Proc $ctx.proc -Profile $ctx.profile -LogQueue $sync.WiimmfiLogQueue
    $sync.WiimmfiPid = 0
}
'@

$wlWorker = @'
. $sync.WiiLinkLib
. $sync.WiiLinkFallbackLib
$browserCtx = $null
try {
    while (-not $sync.Stop) {
        $transport = [string]$sync.WiiLinkTransport
        if ($transport -eq 'browser') {
            if (-not $browserCtx -or -not $browserCtx.ok -or $browserCtx.proc.HasExited) {
                if ($browserCtx) { Stop-WiiLinkBrowser -Context $browserCtx -LogQueue $sync.WiiLinkLogQueue; $browserCtx = $null }
                $browserCtx = Start-WiiLinkBrowser -LogQueue $sync.WiiLinkLogQueue
                if ($browserCtx.ok) { $sync.WiiLinkPid = $browserCtx.proc.Id } else { $sync.WiiLinkPid = 0 }
            }
        } elseif ($browserCtx) {
            Stop-WiiLinkBrowser -Context $browserCtx -LogQueue $sync.WiiLinkLogQueue
            $browserCtx = $null; $sync.WiiLinkPid = 0
        }

        if ($transport -eq 'browser' -and (-not $browserCtx -or -not $browserCtx.ok)) {
            $data = @{ ok = $false; state = 'error'; error = 'no-browser'; transport = 'browser'; stats = @{ online = 0; active = 0; groups = 0 }; rooms = @() }
        } else {
            $port = if ($transport -eq 'browser') { [int]$browserCtx.port } else { 0 }
            $data = Get-WiiLinkData -Game $sync.Game -Ua $sync.Ua -Lang $sync.Lang -Transport $transport -BrowserPort $port -LogQueue $sync.WiiLinkLogQueue
        }

        if (Test-WiiLinkBrowserFallbackRequired -SelectedTransport $transport -Data $data) {
            Write-WiiLinkDiagnostic $sync.WiiLinkLogQueue 'WARN' 'FALLBACK' ("Direct API routes failed; automatically switching to Chrome/Edge; error={0}" -f [string]$data.error)
            $sync.WiiLinkStatus = 'Direct API failed; switching to Chrome/Edge'
            $sync.WiiLinkTransport = 'browser'
            $sync.WiiLinkRefresh = $true
            continue
        }

        $sync.WiiLinkJson = ($data | ConvertTo-Json -Depth 10 -Compress)
        $sync.WiiLinkSeq = [int]$sync.WiiLinkSeq + 1
        $roomCount = @($data.rooms).Count
        $playerCount = 0
        foreach ($room in @($data.rooms)) { $playerCount += @($room.players).Count }
        $prefix = if ($transport -eq 'browser') { 'Chrome/Edge' } else { 'Direct API' }
        switch ([string]$data.state) {
            'ok'      { $sync.WiiLinkStatus = ('{0}: OK rooms={1} players={2}' -f $prefix, $roomCount, $playerCount) }
            'empty'   { $sync.WiiLinkStatus = ('{0}: EMPTY rooms=0 players=0' -f $prefix) }
            'partial' { $sync.WiiLinkStatus = ('{0}: PARTIAL stats-groups={1} parsed-rooms={2}' -f $prefix, [int]$data.stats.groups, $roomCount) }
            default   { $sync.WiiLinkStatus = ('{0}: ERROR {1}' -f $prefix, [string]$data.error) }
        }
        $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
        $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop -and -not $sync.WiiLinkRefresh -and ([string]$sync.WiiLinkTransport -eq $transport)) { Start-Sleep -Milliseconds 200; $slept += 200 }
        $sync.WiiLinkRefresh = $false
    }
} finally {
    if ($browserCtx) { Stop-WiiLinkBrowser -Context $browserCtx -LogQueue $sync.WiiLinkLogQueue }
    $sync.WiiLinkPid = 0
}
'@

$wmJob = Start-PollWorker -Sync $sync -Body $wmWorker
$wlJob = Start-PollWorker -Sync $sync -Body $wlWorker

function Refresh-DiagnosticLogView {
    $selectedSource = Get-DiagnosticLogSource -LogPanel $diagnostic
    $entries = Get-MphLogEntries -Stores $logStores -Source $selectedSource -IncludeDebug:([bool]$diagnostic.Details.Checked)
    Set-DiagnosticLogEntries -LogPanel $diagnostic -Entries $entries -Theme $theme -MaxLines 2000
}

$bar.Combo.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$bar.IntervalMap[[string]$bar.Combo.SelectedItem] })
$wlTransport.Combo.Add_SelectedIndexChanged({
        $newTransport = if ($wlTransport.Combo.SelectedIndex -eq 1) { 'browser' } else { 'direct' }
        if ([string]$sync.WiiLinkTransport -ne $newTransport) {
            $sync.WiiLinkTransport = $newTransport; $sync.WiiLinkRefresh = $true
            $label = if ($newTransport -eq 'browser') { $i18n.wlBrowser } else { $i18n.wlDirect }
            Write-MphLog -Store $appLogStore -Level INFO -Stage 'TRANSPORT' -Message ($i18n.wlTransportChanged -f $label)
            $status.Text = $i18n.refreshing
        }
    })
$bar.Refresh.Add_Click({
        $sync.WiimmfiRefresh = $true; $sync.WiiLinkRefresh = $true; $status.Text = $i18n.refreshing
        Write-MphLog -Store $appLogStore -Level INFO -Stage 'UI' -Message 'Manual refresh requested'
    })
$diagnostic.Toggle.Add_Click({
        $expanded = -not [bool]$diagnostic.Expanded
        Set-DiagnosticLogExpanded -LogPanel $diagnostic -Expanded $expanded -I18n $i18n
        if ($expanded) { [void](Receive-MphLogStores -Stores $logStores); Refresh-DiagnosticLogView }
    })
$diagnostic.SourceCombo.Add_SelectedIndexChanged({ if ($diagnostic.Expanded) { Refresh-DiagnosticLogView } })
$diagnostic.Details.Add_CheckedChanged({ if ($diagnostic.Expanded) { Refresh-DiagnosticLogView } })
$diagnostic.Clear.Add_Click({
        $selectedSource = Get-DiagnosticLogSource -LogPanel $diagnostic
        Clear-MphLogStores -Stores $logStores -Source $selectedSource
        Refresh-DiagnosticLogView
    })
$diagnostic.Copy.Add_Click({
        try {
            if ($diagnostic.LogBox.TextLength -gt 0) {
                [System.Windows.Forms.Clipboard]::SetText($diagnostic.LogBox.Text)
                $status.Text = $i18n.logCopied
            }
        } catch { $status.Text = $_.Exception.Message }
    })

$script:WmLastSeq = -1; $script:WlLastSeq = -1
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 300
$uiTimer.Add_Tick({
        $transportIndex = Get-WiiLinkTransportComboIndex -Transport ([string]$sync.WiiLinkTransport)
        if ($wlTransport.Combo.SelectedIndex -ne $transportIndex) { $wlTransport.Combo.SelectedIndex = $transportIndex }
        if ($sync.WiimmfiSeq -ne $script:WmLastSeq) {
            $script:WmLastSeq = $sync.WiimmfiSeq
            Update-WiimmfiTree -Tree $wm.Tree -Head $wm.Head -Json $sync.WiimmfiJson -Colors $theme.Colors -I18n $i18n
        }
        if ($sync.WiiLinkSeq -ne $script:WlLastSeq) {
            $script:WlLastSeq = $sync.WiiLinkSeq
            Update-WiiLinkTree -Tree $wl.Tree -Head $wl.Head -Json $sync.WiiLinkJson -Colors $theme.Colors -I18n $i18n
        }
        $received = Receive-MphLogStores -Stores $logStores -MaxDrainPerStore 200
        if ($received -gt 0 -and $diagnostic.Expanded) { Refresh-DiagnosticLogView }
        $status.Text = ('{0}: {1}     Wiimmfi: {2}     WiiLink: {3}' -f $i18n.intervalLabel, $bar.Combo.SelectedItem, $sync.WiimmfiStatus, $sync.WiiLinkStatus)
    })
$form.Add_Shown({ $uiTimer.Start() })

$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}
        try { $sync.Stop = $true } catch {}
        try { Start-Sleep -Milliseconds 250 } catch {}
        Stop-PollWorker $wmJob; Stop-PollWorker $wlJob
        try { if ($sync.WiimmfiPid -gt 0) { & taskkill /PID $sync.WiimmfiPid /T /F 2>$null | Out-Null } } catch {}
        try { if ($sync.WiiLinkPid -gt 0) { & taskkill /PID $sync.WiiLinkPid /T /F 2>$null | Out-Null } } catch {}
    })

if ($SelfTest) {
    $log = Join-Path $env:TEMP 'unified_selftest.log'
    Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        L "FORM BUILT OK; controls=$($form.Controls.Count)"
        L "WIILINK TRANSPORT SELECTOR BUILT; items=$($wlTransport.Combo.Items.Count); selected=$($wlTransport.Combo.SelectedItem)"
        L "DIAGNOSTIC SOURCE SELECTOR BUILT; items=$($diagnostic.SourceCombo.Items.Count); selected=$($diagnostic.SourceCombo.SelectedItem)"
        $deadline = (Get-Date).AddSeconds(55)
        while ((Get-Date) -lt $deadline -and ([int]$sync.WiiLinkSeq -lt 1 -or ($sync.WiimmfiStatus -ne 'ok' -and $sync.WiimmfiStatus -ne 'no-browser'))) { Start-Sleep -Milliseconds 300 }
        [void](Receive-MphLogStores -Stores $logStores -MaxDrainPerStore 1000)
        L ("WiiLink Seq=$($sync.WiiLinkSeq) Status=$($sync.WiiLinkStatus) Transport=$($sync.WiiLinkTransport)")
        L ("Wiimmfi Seq=$($sync.WiimmfiSeq) Status=$($sync.WiimmfiStatus)")
        L ("Log counts: Wiimmfi=$($wiimmfiLogStore.Entries.Count) WiiLink=$($wiiLinkLogStore.Entries.Count) App=$($appLogStore.Entries.Count)")
        Update-WiiLinkTree -Tree $wl.Tree -Head $wl.Head -Json $sync.WiiLinkJson -Colors $theme.Colors -I18n $i18n
        Update-WiimmfiTree -Tree $wm.Tree -Head $wm.Head -Json $sync.WiimmfiJson -Colors $theme.Colors -I18n $i18n
        L ("WiiLink head: " + $wl.Head.Text)
        L ("WiiLink room nodes: " + $wl.Tree.Nodes.Count)
        L ("Wiimmfi head: " + $wm.Head.Text)
        L ("Wiimmfi player nodes: " + $wm.Tree.Nodes.Count)
        L 'RESULT: SUCCESS'
    } catch { L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace) }
    finally {
        try { $sync.Stop = $true; Start-Sleep -Milliseconds 250 } catch {}
        Stop-PollWorker $wmJob; Stop-PollWorker $wlJob
        try { if ($sync.WiimmfiPid -gt 0) { Stop-Process -Id $sync.WiimmfiPid -Force -EA SilentlyContinue } } catch {}
        try { if ($sync.WiiLinkPid -gt 0) { Stop-Process -Id $sync.WiiLinkPid -Force -EA SilentlyContinue } } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
