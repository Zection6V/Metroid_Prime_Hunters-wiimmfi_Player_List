<#
    MPH Unified Player List  (Wiimmfi + WiiLink WFC)  — PowerShell + WinForms
    ------------------------------------------------------------------------
    1 画面で wiimmfi と WiiLink WFC のオンライン状況を同時に表示する統合ビューワ。

    責務分離（SRP）:
      lib\WiimmfiSource.ps1 / lib\WiiLinkSource.ps1  … 情報取得（データ）
      lib\TreeRender.ps1                             … TreeView 描画（表示）
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

# ---- 色 ----
$bgDark = [System.Drawing.Color]::FromArgb(0x23, 0x23, 0x23)
$panel  = [System.Drawing.Color]::FromArgb(0x2D, 0x2D, 0x2D)
$orange = [System.Drawing.Color]::FromArgb(0xE7, 0x65, 0x0C)
$cream  = [System.Drawing.Color]::FromArgb(0xFF, 0xFF, 0xCA)
$cyan   = [System.Drawing.Color]::FromArgb(0xA4, 0xE1, 0xFF)
$green  = [System.Drawing.Color]::FromArgb(0x6A, 0xD0, 0x8A)
$red    = [System.Drawing.Color]::FromArgb(0xE8, 0x6A, 0x6A)
$dim    = [System.Drawing.Color]::FromArgb(0xB7, 0xB7, 0xB7)
$Colors = @{ cream = $cream; dim = $dim; cyan = $cyan; red = $red; orange = $orange; green = $green }

# ============================================================================
# GUI
# ============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "MPH Player List  -  Wiimmfi + WiiLink"
$form.Size = New-Object System.Drawing.Size(1000, 620)
$form.MinimumSize = New-Object System.Drawing.Size(760, 460)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

# --- 上部バー（タイトル + 間隔セレクタ） ---
$top = New-Object System.Windows.Forms.Panel
$top.Dock = 'Top'; $top.Height = 50; $top.BackColor = $panel

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Metroid Prime Hunters  -  Online Players"
$lblTitle.ForeColor = $orange
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(14, 12)
$lblTitle.AutoSize = $true
$top.Controls.Add($lblTitle)

$flowR = New-Object System.Windows.Forms.FlowLayoutPanel
$flowR.Dock = 'Right'; $flowR.FlowDirection = 'LeftToRight'; $flowR.WrapContents = $false
$flowR.AutoSize = $true; $flowR.BackColor = $panel; $flowR.Padding = New-Object System.Windows.Forms.Padding(0, 12, 12, 0)
$lblInt = New-Object System.Windows.Forms.Label
$lblInt.Text = "Update every:"; $lblInt.ForeColor = $dim; $lblInt.AutoSize = $true
$lblInt.Margin = New-Object System.Windows.Forms.Padding(0, 6, 6, 0)
$cmbInterval = New-Object System.Windows.Forms.ComboBox
$cmbInterval.DropDownStyle = 'DropDownList'; $cmbInterval.Width = 90
$cmbInterval.BackColor = $bgDark; $cmbInterval.ForeColor = $cream; $cmbInterval.FlatStyle = 'Flat'
$intervalMap = [ordered]@{ '15 sec' = 15000; '30 sec' = 30000; '1 min' = 60000; '2 min' = 120000; '5 min' = 300000 }
foreach ($k in $intervalMap.Keys) { [void]$cmbInterval.Items.Add($k) }
$cmbInterval.SelectedItem = '30 sec'
$flowR.Controls.Add($lblInt); $flowR.Controls.Add($cmbInterval)
$top.Controls.Add($flowR)

# --- 中央 2 ペイン ---
function New-ServerPanel($headColor) {
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Dock = 'Fill'; $pnl.BackColor = $bgDark; $pnl.Padding = New-Object System.Windows.Forms.Padding(8)
    $head = New-Object System.Windows.Forms.Label
    $head.Dock = 'Top'; $head.Height = 30; $head.ForeColor = $headColor
    $head.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $head.TextAlign = 'MiddleLeft'
    $tree = New-Object System.Windows.Forms.TreeView
    $tree.Dock = 'Fill'; $tree.BackColor = $panel; $tree.ForeColor = $cream
    $tree.BorderStyle = 'FixedSingle'; $tree.Font = New-Object System.Drawing.Font("MS Gothic", 10)
    $tree.HideSelection = $false; $tree.ShowLines = $true; $tree.ShowRootLines = $true; $tree.ShowPlusMinus = $true
    $pnl.Controls.Add($tree); $pnl.Controls.Add($head)
    return @{ Panel = $pnl; Head = $head; Tree = $tree }
}
$wm = New-ServerPanel $cyan
$wl = New-ServerPanel $green

$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.Dock = 'Fill'; $grid.ColumnCount = 2; $grid.RowCount = 1; $grid.BackColor = $bgDark
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$grid.Controls.Add($wm.Panel, 0, 0)
$grid.Controls.Add($wl.Panel, 1, 0)

# --- 下部ステータスバー ---
$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Bottom'; $status.Height = 24; $status.ForeColor = $dim
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9); $status.TextAlign = 'MiddleLeft'
$status.Text = "Starting..."
$status.BackColor = $panel; $status.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

$form.Controls.Add($grid)
$form.Controls.Add($top)
$form.Controls.Add($status)
$grid.SendToBack(); $top.BringToFront(); $status.BringToFront()

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

function Start-Worker([string]$body) {
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'MTA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $ps = [powershell]::Create(); $ps.Runspace = $rs; [void]$ps.AddScript($body)
    $h = $ps.BeginInvoke()
    return @{ ps = $ps; rs = $rs; handle = $h }
}
$wmJob = Start-Worker $wmWorker
$wlJob = Start-Worker $wlWorker

# ============================================================================
# UI タイマー（描画は lib\TreeRender.ps1 の共有関数に委譲）
# ============================================================================
$cmbInterval.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$intervalMap[[string]$cmbInterval.SelectedItem] })

$script:WmLastSeq = -1; $script:WlLastSeq = -1; $script:WmUpdated = '-'; $script:WlUpdated = '-'
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 300
$uiTimer.Add_Tick({
        if ($sync.WiimmfiSeq -ne $script:WmLastSeq) {
            $script:WmLastSeq = $sync.WiimmfiSeq; $script:WmUpdated = (Get-Date -Format 'HH:mm:ss')
            Update-WiimmfiTree -Tree $wm.Tree -Head $wm.Head -Json $sync.WiimmfiJson -Colors $Colors
        }
        if ($sync.WiiLinkSeq -ne $script:WlLastSeq) {
            $script:WlLastSeq = $sync.WiiLinkSeq; $script:WlUpdated = (Get-Date -Format 'HH:mm:ss')
            Update-WiiLinkTree -Tree $wl.Tree -Head $wl.Head -Json $sync.WiiLinkJson -Colors $Colors
        }
        $status.Text = ("Interval: {0}     Wiimmfi: {1}     WiiLink: {2}" -f [string]$cmbInterval.SelectedItem, $sync.WiimmfiStatus, $sync.WiiLinkStatus)
    })
$form.Add_Shown({ $uiTimer.Start() })

$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}
        try { $sync.Stop = $true } catch {}
        try { Start-Sleep -Milliseconds 200 } catch {}
        foreach ($j in @($wmJob, $wlJob)) { try { $j.ps.Stop(); $j.ps.Dispose(); $j.rs.Dispose() } catch {} }
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
        Update-WiiLinkTree -Tree $wl.Tree -Head $wl.Head -Json $sync.WiiLinkJson -Colors $Colors
        Update-WiimmfiTree -Tree $wm.Tree -Head $wm.Head -Json $sync.WiimmfiJson -Colors $Colors
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
        foreach ($j in @($wmJob, $wlJob)) { try { $j.ps.Stop(); $j.ps.Dispose(); $j.rs.Dispose() } catch {} }
        try { if ($sync.WiimmfiPid -gt 0) { Stop-Process -Id $sync.WiimmfiPid -Force -EA SilentlyContinue } } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
