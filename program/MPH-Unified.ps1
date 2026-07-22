<#
    MPH Unified Player List  (Wiimmfi + WiiLink WFC)  — PowerShell + WinForms
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$WiimmfiLib = Join-Path $ScriptDir 'lib\WiimmfiSource.ps1'
$WiiLinkLib = Join-Path $ScriptDir 'lib\WiiLinkSource.ps1'
. $WiimmfiLib
. $WiiLinkLib
. (Join-Path $ScriptDir 'lib\TreeRender.ps1')
. (Join-Path $ScriptDir 'lib\ViewerCommon.ps1')
. (Join-Path $ScriptDir 'lib\I18n.ps1')
$theme = Get-MphTheme
$i18n = Get-MphI18n

$form = New-Object System.Windows.Forms.Form
$form.Text = "MPH Player List  -  Wiimmfi + WiiLink"
$form.Size = New-Object System.Drawing.Size(1120, 680)
$form.MinimumSize = New-Object System.Drawing.Size(860, 500)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $theme.bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$bar = New-TopBar -Theme $theme -Title "Metroid Prime Hunters" -TitleColor $theme.orange -I18n $i18n -Height 50
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
$diagnostic = New-DiagnosticLogPanel -Theme $theme -I18n $i18n -ExpandedHeight 230
$form.Controls.Add($grid)
$form.Controls.Add($bar.Panel)
$form.Controls.Add($status)
$form.Controls.Add($diagnostic.Panel)

$logQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$sync = [hashtable]::Synchronized(@{
        WiimmfiLib = $WiimmfiLib; WiiLinkLib = $WiiLinkLib
        WiimmfiUrl = 'https://wiimmfi.de/stats/game/mprimeds'
        Game = 'mprimeds'; Ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList'; Lang = $i18n.lang
        IntervalMs = 30000; Stop = $false; WiimmfiRefresh = $false; WiiLinkRefresh = $false
        WiimmfiJson = $null; WiimmfiSeq = 0; WiimmfiStatus = 'starting'; WiimmfiPid = 0
        WiiLinkJson = $null; WiiLinkSeq = 0; WiiLinkStatus = 'starting'; WiiLinkTransport = 'direct'; WiiLinkPid = 0
        LogQueue = $logQueue
    })

$wmWorker = @'
. $sync.WiimmfiLib
$ctx = Start-WiimmfiBrowser -Url $sync.WiimmfiUrl
if (-not $ctx.ok) {
    $sync.WiimmfiJson = (@{ ok = $false; error = $ctx.error; online = 0; players = @() } | ConvertTo-Json -Depth 6 -Compress)
    $sync.WiimmfiSeq = [int]$sync.WiimmfiSeq + 1; $sync.WiimmfiStatus = $ctx.error
    return
}
$sync.WiimmfiPid = $ctx.proc.Id
try {
    while (-not $sync.Stop) {
        $data = Get-WiimmfiData -Port $ctx.port -Lang $sync.Lang
        $sync.WiimmfiJson = ($data | ConvertTo-Json -Depth 8 -Compress)
        $sync.WiimmfiSeq = [int]$sync.WiimmfiSeq + 1
        $sync.WiimmfiStatus = if ($data.ok) { 'ok' } else { 'connecting' }
        $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
        $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop -and -not $sync.WiimmfiRefresh) { Start-Sleep -Milliseconds 200; $slept += 200 }
        $sync.WiimmfiRefresh = $false
    }
} finally { Stop-WiimmfiBrowser -Proc $ctx.proc }
'@

$wlWorker = @'
. $sync.WiiLinkLib
$browserCtx = $null
try {
    while (-not $sync.Stop) {
        $transport = [string]$sync.WiiLinkTransport
        if ($transport -eq 'browser') {
            if (-not $browserCtx -or -not $browserCtx.ok -or $browserCtx.proc.HasExited) {
                if ($browserCtx) { Stop-WiiLinkBrowser -Context $browserCtx; $browserCtx = $null }
                try { $sync.LogQueue.Enqueue(@{ time = [datetime]::Now; source = 'WiiLink'; level = 'INFO'; stage = 'BROWSER'; message = 'Starting Chrome/Edge transport' }) } catch {}
                $browserCtx = Start-WiiLinkBrowser
                if ($browserCtx.ok) {
                    $sync.WiiLinkPid = $browserCtx.proc.Id
                    try { $sync.LogQueue.Enqueue(@{ time = [datetime]::Now; source = 'WiiLink'; level = 'INFO'; stage = 'BROWSER'; message = ('Browser started; pid={0}; port={1}; executable={2}' -f $browserCtx.proc.Id, $browserCtx.port, $browserCtx.browser) }) } catch {}
                } else {
                    $sync.WiiLinkPid = 0
                    try { $sync.LogQueue.Enqueue(@{ time = [datetime]::Now; source = 'WiiLink'; level = 'ERROR'; stage = 'BROWSER'; message = ('Browser start failed: {0}' -f $browserCtx.error) }) } catch {}
                }
            }
        } elseif ($browserCtx) {
            try { $sync.LogQueue.Enqueue(@{ time = [datetime]::Now; source = 'WiiLink'; level = 'INFO'; stage = 'BROWSER'; message = 'Stopping browser transport; switched to direct API' }) } catch {}
            Stop-WiiLinkBrowser -Context $browserCtx
            $browserCtx = $null; $sync.WiiLinkPid = 0
        }

        if ($transport -eq 'browser' -and (-not $browserCtx -or -not $browserCtx.ok)) {
            $data = @{ ok = $false; state = 'error'; error = 'no-browser'; transport = 'browser'; stats = @{ online = 0; active = 0; groups = 0 }; rooms = @() }
        } else {
            $port = if ($transport -eq 'browser') { [int]$browserCtx.port } else { 0 }
            $data = Get-WiiLinkData -Game $sync.Game -Ua $sync.Ua -Lang $sync.Lang -Transport $transport -BrowserPort $port -LogQueue $sync.LogQueue
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
    if ($browserCtx) { Stop-WiiLinkBrowser -Context $browserCtx }
    $sync.WiiLinkPid = 0
}
'@

$wmJob = Start-PollWorker -Sync $sync -Body $wmWorker
$wlJob = Start-PollWorker -Sync $sync -Body $wlWorker

$bar.Combo.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$bar.IntervalMap[[string]$bar.Combo.SelectedItem] })
$wlTransport.Combo.Add_SelectedIndexChanged({
        $newTransport = if ($wlTransport.Combo.SelectedIndex -eq 1) { 'browser' } else { 'direct' }
        if ([string]$sync.WiiLinkTransport -ne $newTransport) {
            $sync.WiiLinkTransport = $newTransport; $sync.WiiLinkRefresh = $true
            $label = if ($newTransport -eq 'browser') { $i18n.wlBrowser } else { $i18n.wlDirect }
            try { $sync.LogQueue.Enqueue(@{ time = [datetime]::Now; source = 'App'; level = 'INFO'; stage = 'TRANSPORT'; message = ($i18n.wlTransportChanged -f $label) }) } catch {}
            $status.Text = $i18n.refreshing
        }
    })
$bar.Refresh.Add_Click({
        $sync.WiimmfiRefresh = $true; $sync.WiiLinkRefresh = $true; $status.Text = $i18n.refreshing
        try { $sync.LogQueue.Enqueue(@{ time = [datetime]::Now; source = 'App'; level = 'INFO'; stage = 'UI'; message = 'Manual refresh requested' }) } catch {}
    })
$diagnostic.Toggle.Add_Click({ Set-DiagnosticLogExpanded -LogPanel $diagnostic -Expanded (-not [bool]$diagnostic.Expanded) -I18n $i18n })
$diagnostic.Clear.Add_Click({ $diagnostic.LogBox.Clear() })
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
        if ($sync.WiimmfiSeq -ne $script:WmLastSeq) {
            $script:WmLastSeq = $sync.WiimmfiSeq
            Update-WiimmfiTree -Tree $wm.Tree -Head $wm.Head -Json $sync.WiimmfiJson -Colors $theme.Colors -I18n $i18n
        }
        if ($sync.WiiLinkSeq -ne $script:WlLastSeq) {
            $script:WlLastSeq = $sync.WiiLinkSeq
            Update-WiiLinkTree -Tree $wl.Tree -Head $wl.Head -Json $sync.WiiLinkJson -Colors $theme.Colors -I18n $i18n
        }
        $drained = 0
        while ($sync.LogQueue.Count -gt 0 -and $drained -lt 200) {
            Add-DiagnosticLog -LogPanel $diagnostic -Entry $sync.LogQueue.Dequeue() -Theme $theme -MaxLines 1000
            $drained++
        }
        $status.Text = ("{0}: {1}     Wiimmfi: {2}     WiiLink: {3}" -f $i18n.intervalLabel, $bar.Combo.SelectedItem, $sync.WiimmfiStatus, $sync.WiiLinkStatus)
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
        L "DIAGNOSTIC PANEL BUILT; controls=$($diagnostic.Panel.Controls.Count)"
        $deadline = (Get-Date).AddSeconds(55)
        while ((Get-Date) -lt $deadline -and ([int]$sync.WiiLinkSeq -lt 1 -or ($sync.WiimmfiStatus -ne 'ok' -and $sync.WiimmfiStatus -ne 'no-browser'))) { Start-Sleep -Milliseconds 300 }
        L ("WiiLink Seq=$($sync.WiiLinkSeq) Status=$($sync.WiiLinkStatus) Transport=$($sync.WiiLinkTransport)")
        L ("Wiimmfi Seq=$($sync.WiimmfiSeq) Status=$($sync.WiimmfiStatus)")
        L ("Queued diagnostic entries=$($sync.LogQueue.Count)")
        Update-WiiLinkTree -Tree $wl.Tree -Head $wl.Head -Json $sync.WiiLinkJson -Colors $theme.Colors -I18n $i18n
        Update-WiimmfiTree -Tree $wm.Tree -Head $wm.Head -Json $sync.WiimmfiJson -Colors $theme.Colors -I18n $i18n
        L ("WiiLink head: " + $wl.Head.Text)
        L ("WiiLink room nodes: " + $wl.Tree.Nodes.Count)
        L ("Wiimmfi head: " + $wm.Head.Text)
        L ("Wiimmfi player nodes: " + $wm.Tree.Nodes.Count)
        L "RESULT: SUCCESS"
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
