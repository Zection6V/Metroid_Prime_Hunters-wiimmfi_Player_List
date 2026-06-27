<#
    MPH Unified Player List  (Wiimmfi + WiiLink WFC)  — PowerShell + WinForms
    ------------------------------------------------------------------------
    1 画面で wiimmfi と WiiLink WFC のオンライン状況を同時に表示する統合ビューワ。

    責務分離（SRP）:
      lib\WiimmfiSource.ps1 / lib\WiiLinkSource.ps1  … 情報取得（データ）
      lib\TreeRender.ps1                             … TreeView 描画（表示）
      lib\ViewerCommon.ps1                           … UI 部品・ワーカー基盤（共通）
      本ファイル                                     … 画面構成と進行（ビューワ）

    - 左右 2 ペイン（TableLayoutPanel 50/50 + Dock）でレスポンシブ。横スクロール無し。
    - ネットワーク取得は各サーバごとの別 runspace で実行し、UI を固めない。
    - ポーリング間隔を選択可能（サーバ負荷に配慮し既定 30 秒）。

    依存: Windows + PowerShell 5.1。Wiimmfi 側のみ Chrome/Edge が必要（無ければ
          その旨を表示し、WiiLink 側は通常どおり動作する）。
    起動: "Run MPH Unified.bat" をダブルクリック。 -SelfTest で診断モード。
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
$theme = Get-MphTheme

# ============================================================================
# GUI
# ============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "MPH Player List  -  Wiimmfi + WiiLink"
$form.Size = New-Object System.Drawing.Size(1000, 620)
$form.MinimumSize = New-Object System.Drawing.Size(760, 460)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $theme.bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$bar = New-TopBar -Theme $theme -Title "Metroid Prime Hunters  -  Online Players" -TitleColor $theme.orange -Height 50
$wm = New-TreePanel -Theme $theme -HeadColor $theme.cyan
$wl = New-TreePanel -Theme $theme -HeadColor $theme.green

$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.Dock = 'Fill'; $grid.ColumnCount = 2; $grid.RowCount = 1; $grid.BackColor = $theme.bgDark
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$grid.Controls.Add($wm.Panel, 0, 0)
$grid.Controls.Add($wl.Panel, 1, 0)

$status = New-StatusBar -Theme $theme -Text "Starting..."

$form.Controls.Add($grid); $form.Controls.Add($bar.Panel); $form.Controls.Add($status)
$grid.SendToBack(); $bar.Panel.BringToFront(); $status.BringToFront()

# ============================================================================
# バックグラウンドワーカー（サーバごとに別 runspace）
# ============================================================================
$sync = [hashtable]::Synchronized(@{
        WiimmfiLib = $WiimmfiLib; WiiLinkLib = $WiiLinkLib
        WiimmfiUrl = 'https://wiimmfi.de/stats/game/mprimeds'
        Game = 'mprimeds'; Ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList'
        IntervalMs = 30000; Stop = $false
        WiimmfiJson = $null; WiimmfiSeq = 0; WiimmfiStatus = 'starting'; WiimmfiPid = 0
        WiiLinkJson = $null; WiiLinkSeq = 0; WiiLinkStatus = 'starting'
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
        $data = Get-WiimmfiData -Port $ctx.port
        $sync.WiimmfiJson = ($data | ConvertTo-Json -Depth 8 -Compress)
        $sync.WiimmfiSeq = [int]$sync.WiimmfiSeq + 1
        $sync.WiimmfiStatus = if ($data.ok) { 'ok' } else { 'connecting' }
        $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
        $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop) { Start-Sleep -Milliseconds 200; $slept += 200 }
    }
} finally { Stop-WiimmfiBrowser -Proc $ctx.proc }
'@

$wlWorker = @'
. $sync.WiiLinkLib
while (-not $sync.Stop) {
    $data = Get-WiiLinkData -Game $sync.Game -Ua $sync.Ua
    $sync.WiiLinkJson = ($data | ConvertTo-Json -Depth 10 -Compress)
    $sync.WiiLinkSeq = [int]$sync.WiiLinkSeq + 1
    $sync.WiiLinkStatus = if ($data.ok) { 'ok' } else { 'error' }
    $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
    $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop) { Start-Sleep -Milliseconds 200; $slept += 200 }
}
'@

$wmJob = Start-PollWorker -Sync $sync -Body $wmWorker
$wlJob = Start-PollWorker -Sync $sync -Body $wlWorker

# ============================================================================
# UI タイマー（描画は lib\TreeRender.ps1 の共有関数に委譲）
# ============================================================================
$bar.Combo.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$bar.IntervalMap[[string]$bar.Combo.SelectedItem] })

$script:WmLastSeq = -1; $script:WlLastSeq = -1
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 300
$uiTimer.Add_Tick({
        if ($sync.WiimmfiSeq -ne $script:WmLastSeq) {
            $script:WmLastSeq = $sync.WiimmfiSeq
            Update-WiimmfiTree -Tree $wm.Tree -Head $wm.Head -Json $sync.WiimmfiJson -Colors $theme.Colors
        }
        if ($sync.WiiLinkSeq -ne $script:WlLastSeq) {
            $script:WlLastSeq = $sync.WiiLinkSeq
            Update-WiiLinkTree -Tree $wl.Tree -Head $wl.Head -Json $sync.WiiLinkJson -Colors $theme.Colors
        }
        $status.Text = ("Interval: {0}     Wiimmfi: {1}     WiiLink: {2}" -f [string]$bar.Combo.SelectedItem, $sync.WiimmfiStatus, $sync.WiiLinkStatus)
    })
$form.Add_Shown({ $uiTimer.Start() })

$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}
        try { $sync.Stop = $true } catch {}
        try { Start-Sleep -Milliseconds 200 } catch {}
        Stop-PollWorker $wmJob; Stop-PollWorker $wlJob
        try { if ($sync.WiimmfiPid -gt 0) { & taskkill /PID $sync.WiimmfiPid /T /F 2>$null | Out-Null } } catch {}
    })

# ============================================================================
# 診断モード
# ============================================================================
if ($SelfTest) {
    $log = Join-Path $env:TEMP 'unified_selftest.log'
    Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        L "FORM BUILT OK; controls=$($form.Controls.Count)"
        $deadline = (Get-Date).AddSeconds(55)
        while ((Get-Date) -lt $deadline -and ([int]$sync.WiiLinkSeq -lt 1 -or ($sync.WiimmfiStatus -ne 'ok' -and $sync.WiimmfiStatus -ne 'no-browser'))) { Start-Sleep -Milliseconds 300 }
        L ("WiiLink Seq=$($sync.WiiLinkSeq) Status=$($sync.WiiLinkStatus)")
        L ("Wiimmfi Seq=$($sync.WiimmfiSeq) Status=$($sync.WiimmfiStatus)")
        Update-WiiLinkTree -Tree $wl.Tree -Head $wl.Head -Json $sync.WiiLinkJson -Colors $theme.Colors
        Update-WiimmfiTree -Tree $wm.Tree -Head $wm.Head -Json $sync.WiimmfiJson -Colors $theme.Colors
        L ("WiiLink head: " + $wl.Head.Text)
        L ("WiiLink room nodes: " + $wl.Tree.Nodes.Count)
        foreach ($rn in $wl.Tree.Nodes) { L ("   " + $rn.Text); foreach ($pn in $rn.Nodes) { if ($pn.Tag.Key -like 'wl:*') { L ("      " + $pn.Text) } } }
        L ("Wiimmfi head: " + $wm.Head.Text)
        L ("Wiimmfi player nodes: " + $wm.Tree.Nodes.Count)
        foreach ($pn in $wm.Tree.Nodes) { L ("   " + $pn.Text) }
        L "RESULT: SUCCESS"
    } catch { L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace) }
    finally {
        try { $sync.Stop = $true; Start-Sleep -Milliseconds 200 } catch {}
        Stop-PollWorker $wmJob; Stop-PollWorker $wlJob
        try { if ($sync.WiimmfiPid -gt 0) { Stop-Process -Id $sync.WiimmfiPid -Force -EA SilentlyContinue } } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
