<#
    WiiLink WFC - MPH Player List  (WiiLink 専用ビューワ)  — PowerShell + WinForms

    直接API / Chrome・Edge の取得方式を実行中に切替可能。
    情報取得、ログ保存、ログ表示、一般 UI を独立したモジュールへ分離する。
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WiiLinkLib = Join-Path $ScriptDir 'lib\WiiLinkSource.ps1'
$WiiLinkFallbackLib = Join-Path $ScriptDir 'lib\WiiLinkFallback.ps1'
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
$form.Text = 'WiiLink WFC - MPH Player List'
$form.Size = New-Object System.Drawing.Size(760, 600)
$form.MinimumSize = New-Object System.Drawing.Size(620, 380)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $theme.bgDark
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$bar = New-TopBar -Theme $theme -Title 'WiiLink WFC' -TitleColor $theme.green -I18n $i18n
$wlTransport = New-WiiLinkTransportSelector -Theme $theme -I18n $i18n -Flow $bar.Flow
$pane = New-TreePanel -Theme $theme -HeadColor $theme.green
$status = New-StatusBar -Theme $theme -Text $i18n.connecting
$diagnostic = New-DiagnosticLogPanel -Theme $theme -I18n $i18n -ExpandedHeight 230 -SourceOptions @(
    @{ Key = 'WiiLink'; Text = $i18n.logWiiLink }
)
$form.Controls.Add($pane.Panel); $form.Controls.Add($bar.Panel); $form.Controls.Add($status); $form.Controls.Add($diagnostic.Panel)

$logStore = New-MphLogStore -Source 'WiiLink'
$logStores = @($logStore)
$sync = [hashtable]::Synchronized(@{
        WiiLinkLib = $WiiLinkLib; WiiLinkFallbackLib = $WiiLinkFallbackLib
        Game = 'mprimeds'; Ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList'; Lang = $i18n.lang
        IntervalMs = 30000; Stop = $false; Refresh = $false; Json = $null; Seq = 0; Status = 'starting'
        Transport = 'direct'; BrowserPid = 0; LogQueue = $logStore.Queue
    })

$worker = @'
. $sync.WiiLinkLib
. $sync.WiiLinkFallbackLib
$browserCtx = $null
try {
    while (-not $sync.Stop) {
        $transport = [string]$sync.Transport
        if ($transport -eq 'browser') {
            if (-not $browserCtx -or -not $browserCtx.ok -or $browserCtx.proc.HasExited) {
                if ($browserCtx) { Stop-WiiLinkBrowser -Context $browserCtx -LogQueue $sync.LogQueue; $browserCtx = $null }
                $browserCtx = Start-WiiLinkBrowser -LogQueue $sync.LogQueue
                if ($browserCtx.ok) { $sync.BrowserPid = $browserCtx.proc.Id } else { $sync.BrowserPid = 0 }
            }
        } elseif ($browserCtx) {
            Stop-WiiLinkBrowser -Context $browserCtx -LogQueue $sync.LogQueue
            $browserCtx = $null; $sync.BrowserPid = 0
        }

        if ($transport -eq 'browser' -and (-not $browserCtx -or -not $browserCtx.ok)) {
            $data = @{ ok = $false; state = 'error'; error = 'no-browser'; transport = 'browser'; stats = @{ online = 0; active = 0; groups = 0 }; rooms = @() }
        } else {
            $port = if ($transport -eq 'browser') { [int]$browserCtx.port } else { 0 }
            $data = Get-WiiLinkData -Game $sync.Game -Ua $sync.Ua -Lang $sync.Lang -Transport $transport -BrowserPort $port -LogQueue $sync.LogQueue
        }

        if (Test-WiiLinkBrowserFallbackRequired -SelectedTransport $transport -Data $data) {
            Write-WiiLinkDiagnostic $sync.LogQueue 'WARN' 'FALLBACK' ("Direct API routes failed; automatically switching to Chrome/Edge; error={0}" -f [string]$data.error)
            $sync.Status = 'Direct API failed; switching to Chrome/Edge'
            $sync.Transport = 'browser'
            $sync.Refresh = $true
            continue
        }

        $sync.Json = ($data | ConvertTo-Json -Depth 10 -Compress)
        $sync.Seq = [int]$sync.Seq + 1
        $roomCount = @($data.rooms).Count
        $playerCount = 0
        foreach ($room in @($data.rooms)) { $playerCount += @($room.players).Count }
        $prefix = if ($transport -eq 'browser') { 'Chrome/Edge' } else { 'Direct API' }
        switch ([string]$data.state) {
            'ok'      { $sync.Status = ('{0}: OK rooms={1} players={2}' -f $prefix, $roomCount, $playerCount) }
            'empty'   { $sync.Status = ('{0}: EMPTY rooms=0 players=0' -f $prefix) }
            'partial' { $sync.Status = ('{0}: PARTIAL stats-groups={1} parsed-rooms={2}' -f $prefix, [int]$data.stats.groups, $roomCount) }
            default   { $sync.Status = ('{0}: ERROR {1}' -f $prefix, [string]$data.error) }
        }
        $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
        $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop -and -not $sync.Refresh -and ([string]$sync.Transport -eq $transport)) { Start-Sleep -Milliseconds 200; $slept += 200 }
        $sync.Refresh = $false
    }
} finally {
    if ($browserCtx) { Stop-WiiLinkBrowser -Context $browserCtx -LogQueue $sync.LogQueue }
    $sync.BrowserPid = 0
}
'@
$job = Start-PollWorker -Sync $sync -Body $worker

function Refresh-DiagnosticLogView {
    $entries = Get-MphLogEntries -Stores $logStores -Source 'WiiLink' -IncludeDebug:([bool]$diagnostic.Details.Checked)
    Set-DiagnosticLogEntries -LogPanel $diagnostic -Entries $entries -Theme $theme -MaxLines 2000
}

$bar.Combo.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$bar.IntervalMap[[string]$bar.Combo.SelectedItem] })
$wlTransport.Combo.Add_SelectedIndexChanged({
        $newTransport = if ($wlTransport.Combo.SelectedIndex -eq 1) { 'browser' } else { 'direct' }
        if ([string]$sync.Transport -ne $newTransport) {
            $sync.Transport = $newTransport; $sync.Refresh = $true; $status.Text = $i18n.refreshing
            $label = if ($newTransport -eq 'browser') { $i18n.wlBrowser } else { $i18n.wlDirect }
            Write-MphLog -Store $logStore -Level INFO -Stage 'TRANSPORT' -Message ($i18n.wlTransportChanged -f $label)
        }
    })
$bar.Refresh.Add_Click({
        $sync.Refresh = $true; $status.Text = $i18n.refreshing
        Write-MphLog -Store $logStore -Level INFO -Stage 'UI' -Message 'Manual refresh requested'
    })
$diagnostic.Toggle.Add_Click({
        $expanded = -not [bool]$diagnostic.Expanded
        Set-DiagnosticLogExpanded -LogPanel $diagnostic -Expanded $expanded -I18n $i18n
        if ($expanded) { [void](Receive-MphLogStores -Stores $logStores); Refresh-DiagnosticLogView }
    })
$diagnostic.Details.Add_CheckedChanged({ if ($diagnostic.Expanded) { Refresh-DiagnosticLogView } })
$diagnostic.Clear.Add_Click({ Clear-MphLogStores -Stores $logStores -Source 'WiiLink'; Refresh-DiagnosticLogView })
$diagnostic.Copy.Add_Click({
        try {
            if ($diagnostic.LogBox.TextLength -gt 0) {
                [System.Windows.Forms.Clipboard]::SetText($diagnostic.LogBox.Text)
                $status.Text = $i18n.logCopied
            }
        } catch { $status.Text = $_.Exception.Message }
    })

$script:LastSeq = -1
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 300
$uiTimer.Add_Tick({
        $transportIndex = Get-WiiLinkTransportComboIndex -Transport ([string]$sync.Transport)
        if ($wlTransport.Combo.SelectedIndex -ne $transportIndex) { $wlTransport.Combo.SelectedIndex = $transportIndex }
        if ($sync.Seq -ne $script:LastSeq) {
            $script:LastSeq = $sync.Seq
            Update-WiiLinkTree -Tree $pane.Tree -Head $pane.Head -Json $sync.Json -Colors $theme.Colors -I18n $i18n
        }
        $received = Receive-MphLogStores -Stores $logStores -MaxDrainPerStore 200
        if ($received -gt 0 -and $diagnostic.Expanded) { Refresh-DiagnosticLogView }
        $status.Text = ('{0}: {1}     {2}: {3}' -f $i18n.intervalLabel, $bar.Combo.SelectedItem, $i18n.statusLabel, $sync.Status)
    })
$form.Add_Shown({ $uiTimer.Start() })
$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}; try { $sync.Stop = $true } catch {}; try { Start-Sleep -Milliseconds 250 } catch {}
        Stop-PollWorker $job
        try { if ($sync.BrowserPid -gt 0) { & taskkill /PID $sync.BrowserPid /T /F 2>$null | Out-Null } } catch {}
    })

if ($SelfTest) {
    $log = Join-Path $env:TEMP 'wiilink_selftest.log'; Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        L ("TRANSPORT SELECTOR items=$($wlTransport.Combo.Items.Count) selected=$($wlTransport.Combo.SelectedItem)")
        L ("DIAGNOSTIC PANEL sourceItems=$($diagnostic.SourceCombo.Items.Count) sourceVisible=$($diagnostic.SourceCombo.Visible)")
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline -and [int]$sync.Seq -lt 1) { Start-Sleep -Milliseconds 250 }
        [void](Receive-MphLogStores -Stores $logStores -MaxDrainPerStore 1000)
        L ("Seq=$($sync.Seq) Status=$($sync.Status) Transport=$($sync.Transport) LogEntries=$($logStore.Entries.Count)")
        Update-WiiLinkTree -Tree $pane.Tree -Head $pane.Head -Json $sync.Json -Colors $theme.Colors -I18n $i18n
        L ("head: " + $pane.Head.Text); L ("room nodes: " + $pane.Tree.Nodes.Count)
        L 'RESULT: SUCCESS'
    } catch { L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace) }
    finally {
        try { $sync.Stop = $true; Start-Sleep -Milliseconds 250 } catch {}; Stop-PollWorker $job
        try { if ($sync.BrowserPid -gt 0) { Stop-Process -Id $sync.BrowserPid -Force -EA SilentlyContinue } } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
