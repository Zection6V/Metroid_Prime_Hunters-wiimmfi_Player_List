<#
    Wiimmfi - MPH Player List  (Wiimmfi 専用ビューワ)  — PowerShell + WinForms
    -------------------------------------------------------------------------
    wiimmfi.de のオンラインプレイヤーと状態を表示する。

    責務分離（SRP）:
      lib\WiimmfiSource.ps1 … 情報取得（Chrome/Edge を CDP 経由で操作し Cloudflare 通過、
                              軽量 /text エンドポイントを取得・解析）
      lib\TreeRender.ps1    … TreeView 描画
      本ファイル            … 画面構成と進行

    依存: Windows + PowerShell 5.1。Chrome もしくは Chromium 版 Edge が必要。
    起動: "Run MPH Player List.bat"。 -SelfTest で診断モード。
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$WiimmfiLib = Join-Path $ScriptDir 'lib\WiimmfiSource.ps1'
. $WiimmfiLib
. (Join-Path $ScriptDir 'lib\TreeRender.ps1')

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
$form.Text = "Wiimmfi - MPH Player List"
$form.Size = New-Object System.Drawing.Size(560, 600)
$form.MinimumSize = New-Object System.Drawing.Size(420, 380)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$top = New-Object System.Windows.Forms.Panel
$top.Dock = 'Top'; $top.Height = 46; $top.BackColor = $panel
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Wiimmfi"; $lblTitle.ForeColor = $orange
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(14, 10); $lblTitle.AutoSize = $true
$top.Controls.Add($lblTitle)
$flowR = New-Object System.Windows.Forms.FlowLayoutPanel
$flowR.Dock = 'Right'; $flowR.FlowDirection = 'LeftToRight'; $flowR.WrapContents = $false
$flowR.AutoSize = $true; $flowR.BackColor = $panel; $flowR.Padding = New-Object System.Windows.Forms.Padding(0, 10, 12, 0)
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

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'; $content.BackColor = $bgDark; $content.Padding = New-Object System.Windows.Forms.Padding(8)
$head = New-Object System.Windows.Forms.Label
$head.Dock = 'Top'; $head.Height = 30; $head.ForeColor = $cyan
$head.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold); $head.TextAlign = 'MiddleLeft'
$tree = New-Object System.Windows.Forms.TreeView
$tree.Dock = 'Fill'; $tree.BackColor = $panel; $tree.ForeColor = $cream; $tree.BorderStyle = 'FixedSingle'
$tree.Font = New-Object System.Drawing.Font("MS Gothic", 10); $tree.HideSelection = $false
$content.Controls.Add($tree); $content.Controls.Add($head)

$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Bottom'; $status.Height = 24; $status.ForeColor = $dim
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9); $status.TextAlign = 'MiddleLeft'
$status.BackColor = $panel; $status.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0); $status.Text = "Connecting..."

$form.Controls.Add($content); $form.Controls.Add($top); $form.Controls.Add($status)
$content.SendToBack(); $top.BringToFront(); $status.BringToFront()

# ============================================================================
# バックグラウンドワーカー（Chrome を起動し /text を取得）
# ============================================================================
$sync = [hashtable]::Synchronized(@{
        WiimmfiLib = $WiimmfiLib; WiimmfiUrl = 'https://wiimmfi.de/stats/game/mprimeds'
        IntervalMs = 30000; Stop = $false; Json = $null; Seq = 0; Status = 'starting'; Pid = 0
    })
$worker = @'
. $sync.WiimmfiLib
$ctx = Start-WiimmfiBrowser -Url $sync.WiimmfiUrl
if (-not $ctx.ok) {
    $sync.Json = (@{ ok = $false; error = $ctx.error; online = 0; players = @() } | ConvertTo-Json -Depth 6 -Compress)
    $sync.Seq = [int]$sync.Seq + 1; $sync.Status = $ctx.error
    return
}
$sync.Pid = $ctx.proc.Id
try {
    while (-not $sync.Stop) {
        $data = Get-WiimmfiData -Port $ctx.port
        $sync.Json = ($data | ConvertTo-Json -Depth 8 -Compress)
        $sync.Seq = [int]$sync.Seq + 1
        $sync.Status = if ($data.ok) { 'ok' } else { 'connecting' }
        $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
        $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop) { Start-Sleep -Milliseconds 200; $slept += 200 }
    }
} finally { Stop-WiimmfiBrowser -Proc $ctx.proc }
'@
$rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'MTA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
$rs.SessionStateProxy.SetVariable('sync', $sync)
$bgPs = [powershell]::Create(); $bgPs.Runspace = $rs; [void]$bgPs.AddScript($worker)
$bgHandle = $bgPs.BeginInvoke()

# ============================================================================
# UI タイマー
# ============================================================================
$cmbInterval.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$intervalMap[[string]$cmbInterval.SelectedItem] })
$script:LastSeq = -1
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 300
$uiTimer.Add_Tick({
        if ($sync.Seq -ne $script:LastSeq) {
            $script:LastSeq = $sync.Seq
            Update-WiimmfiTree -Tree $tree -Head $head -Json $sync.Json -Colors $Colors
        }
        $status.Text = ("Interval: {0}     status: {1}" -f [string]$cmbInterval.SelectedItem, $sync.Status)
    })
$form.Add_Shown({ $uiTimer.Start() })
$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}; try { $sync.Stop = $true } catch {}; try { Start-Sleep -Milliseconds 200 } catch {}
        try { $bgPs.Stop(); $bgPs.Dispose(); $rs.Dispose() } catch {}
        try { if ($sync.Pid -gt 0) { & taskkill /PID $sync.Pid /T /F 2>$null | Out-Null } } catch {}
    })

# ============================================================================
# 診断モード
# ============================================================================
if ($SelfTest) {
    $log = Join-Path $env:TEMP 'mph_selftest.log'; Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        $deadline = (Get-Date).AddSeconds(50)
        while ((Get-Date) -lt $deadline -and $sync.Status -ne 'ok' -and $sync.Status -ne 'no-browser') { Start-Sleep -Milliseconds 300 }
        L ("Seq=$($sync.Seq) Status=$($sync.Status)")
        Update-WiimmfiTree -Tree $tree -Head $head -Json $sync.Json -Colors $Colors
        L ("head: " + $head.Text); L ("player nodes: " + $tree.Nodes.Count)
        foreach ($pn in $tree.Nodes) { L ("   " + $pn.Text); foreach ($cn in $pn.Nodes) { L ("      " + $cn.Text) } }
        L "RESULT: SUCCESS"
    } catch { L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace) }
    finally {
        try { $sync.Stop = $true; Start-Sleep -Milliseconds 200; $bgPs.Stop(); $bgPs.Dispose(); $rs.Dispose() } catch {}
        try { if ($sync.Pid -gt 0) { Stop-Process -Id $sync.Pid -Force -EA SilentlyContinue } } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
