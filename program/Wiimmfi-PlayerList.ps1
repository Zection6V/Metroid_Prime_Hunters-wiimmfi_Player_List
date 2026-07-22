<#
    Wiimmfi - MPH Player List  (Wiimmfi 専用ビューワ)  — PowerShell + WinForms

    情報取得、ログ保存、ログ表示、一般 UI を独立したモジュールへ分離する。
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WiimmfiLib = Join-Path $ScriptDir 'lib\WiimmfiSource.ps1'
. $WiimmfiLib
. (Join-Path $ScriptDir 'lib\TreeRender.ps1')
. (Join-Path $ScriptDir 'lib\ViewerCommon.ps1')
. (Join-Path $ScriptDir 'lib\LogStore.ps1')
. (Join-Path $ScriptDir 'lib\DiagnosticLogView.ps1')
. (Join-Path $ScriptDir 'lib\I18n.ps1')
$theme = Get-MphTheme
$i18n = Get-MphI18n

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Wiimmfi - MPH Player List'
$form.Size = New-Object System.Drawing.Size(760, 600)
$form.MinimumSize = New-Object System.Drawing.Size(620, 380)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $theme.bgDark
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$bar = New-TopBar -Theme $theme -Title 'Wiimmfi' -TitleColor $theme.orange -I18n $i18n
$pane = New-TreePanel -Theme $theme -HeadColor $theme.cyan
$status = New-StatusBar -Theme $theme -Text $i18n.connecting
$diagnostic = New-DiagnosticLogPanel -Theme $theme -I18n $i18n -ExpandedHeight 230 -SourceOptions @(
    @{ Key = 'Wiimmfi'; Text = $i18n.logWiimmfi }
)
$form.Controls.Add($pane.Panel); $form.Controls.Add($bar.Panel); $form.Controls.Add($status); $form.Controls.Add($diagnostic.Panel)

$logStore = New-MphLogStore -Source 'Wiimmfi'
$logStores = @($logStore)
$sync = [hashtable]::Synchronized(@{
        WiimmfiLib = $WiimmfiLib; WiimmfiUrl = 'https://wiimmfi.de/stats/game/mprimeds'; Lang = $i18n.lang
        IntervalMs = 30000; Stop = $false; Refresh = $false; Json = $null; Seq = 0; Status = 'starting'; Pid = 0
        LogQueue = $logStore.Queue
    })

$worker = @'
. $sync.WiimmfiLib
$ctx = Start-WiimmfiBrowser -Url $sync.WiimmfiUrl -LogQueue $sync.LogQueue
if (-not $ctx.ok) {
    $sync.Json = (@{ ok = $false; error = $ctx.error; online = 0; players = @() } | ConvertTo-Json -Depth 6 -Compress)
    $sync.Seq = [int]$sync.Seq + 1; $sync.Status = $ctx.error
    return
}
$sync.Pid = $ctx.proc.Id
try {
    while (-not $sync.Stop) {
        $data = Get-WiimmfiData -Port $ctx.port -Lang $sync.Lang -LogQueue $sync.LogQueue
        $sync.Json = ($data | ConvertTo-Json -Depth 8 -Compress)
        $sync.Seq = [int]$sync.Seq + 1
        $sync.Status = if ($data.ok) { 'ok' } else { 'connecting' }
        $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
        $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop -and -not $sync.Refresh) { Start-Sleep -Milliseconds 200; $slept += 200 }
        $sync.Refresh = $false
    }
} finally {
    Stop-WiimmfiBrowser -Proc $ctx.proc -Profile $ctx.profile -LogQueue $sync.LogQueue
    $sync.Pid = 0
}
'@
$job = Start-PollWorker -Sync $sync -Body $worker

function Refresh-DiagnosticLogView {
    $entries = Get-MphLogEntries -Stores $logStores -Source 'Wiimmfi' -IncludeDebug:([bool]$diagnostic.Details.Checked)
    Set-DiagnosticLogEntries -LogPanel $diagnostic -Entries $entries -Theme $theme -MaxLines 2000
}

$bar.Combo.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$bar.IntervalMap[[string]$bar.Combo.SelectedItem] })
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
$diagnostic.Clear.Add_Click({ Clear-MphLogStores -Stores $logStores -Source 'Wiimmfi'; Refresh-DiagnosticLogView })
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
        if ($sync.Seq -ne $script:LastSeq) {
            $script:LastSeq = $sync.Seq
            Update-WiimmfiTree -Tree $pane.Tree -Head $pane.Head -Json $sync.Json -Colors $theme.Colors -I18n $i18n
        }
        $received = Receive-MphLogStores -Stores $logStores -MaxDrainPerStore 200
        if ($received -gt 0 -and $diagnostic.Expanded) { Refresh-DiagnosticLogView }
        $status.Text = ('{0}: {1}     {2}: {3}' -f $i18n.intervalLabel, $bar.Combo.SelectedItem, $i18n.statusLabel, $sync.Status)
    })
$form.Add_Shown({ $uiTimer.Start() })
$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}; try { $sync.Stop = $true } catch {}; try { Start-Sleep -Milliseconds 200 } catch {}
        Stop-PollWorker $job
        try { if ($sync.Pid -gt 0) { & taskkill /PID $sync.Pid /T /F 2>$null | Out-Null } } catch {}
    })

if ($SelfTest) {
    $log = Join-Path $env:TEMP 'mph_selftest.log'; Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        L ("DIAGNOSTIC PANEL sourceItems=$($diagnostic.SourceCombo.Items.Count) sourceVisible=$($diagnostic.SourceCombo.Visible)")
        $deadline = (Get-Date).AddSeconds(50)
        while ((Get-Date) -lt $deadline -and $sync.Status -ne 'ok' -and $sync.Status -ne 'no-browser') { Start-Sleep -Milliseconds 300 }
        [void](Receive-MphLogStores -Stores $logStores -MaxDrainPerStore 1000)
        L ("Seq=$($sync.Seq) Status=$($sync.Status) LogEntries=$($logStore.Entries.Count)")
        Update-WiimmfiTree -Tree $pane.Tree -Head $pane.Head -Json $sync.Json -Colors $theme.Colors -I18n $i18n
        L ("head: " + $pane.Head.Text); L ("player nodes: " + $pane.Tree.Nodes.Count)
        L 'RESULT: SUCCESS'
    } catch { L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace) }
    finally {
        try { $sync.Stop = $true; Start-Sleep -Milliseconds 200 } catch {}; Stop-PollWorker $job
        try { if ($sync.Pid -gt 0) { Stop-Process -Id $sync.Pid -Force -EA SilentlyContinue } } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
