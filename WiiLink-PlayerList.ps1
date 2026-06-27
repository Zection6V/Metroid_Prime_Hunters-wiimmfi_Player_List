<#
    WiiLink WFC - MPH Player List  (WiiLink 専用ビューワ)  — PowerShell + WinForms
    ----------------------------------------------------------------------------
    WiiLink WFC (wfc.wiilink24.com) のオンライン・ルーム/プレイヤーを表示する。

    責務分離（SRP）:
      lib\WiiLinkSource.ps1 … 情報取得（公式 JSON API、ブラウザ不要）
      lib\TreeRender.ps1    … TreeView 描画
      本ファイル            … 画面構成と進行

    依存: Windows + PowerShell 5.1 のみ。
    起動: "Run WiiLink Player List.bat"。 -SelfTest で診断モード。
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$WiiLinkLib = Join-Path $ScriptDir 'lib\WiiLinkSource.ps1'
. $WiiLinkLib
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
$form.Text = "WiiLink WFC - MPH Player List"
$form.Size = New-Object System.Drawing.Size(560, 600)
$form.MinimumSize = New-Object System.Drawing.Size(420, 380)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$top = New-Object System.Windows.Forms.Panel
$top.Dock = 'Top'; $top.Height = 46; $top.BackColor = $panel
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "WiiLink WFC"; $lblTitle.ForeColor = $green
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
$head.Dock = 'Top'; $head.Height = 30; $head.ForeColor = $green
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
# バックグラウンドワーカー
# ============================================================================
$sync = [hashtable]::Synchronized(@{
        WiiLinkLib = $WiiLinkLib; Game = 'mprimeds'; Ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList'
        IntervalMs = 30000; Stop = $false; Json = $null; Seq = 0; Status = 'starting'
    })
$worker = @'
. $sync.WiiLinkLib
while (-not $sync.Stop) {
    $data = Get-WiiLinkData -Game $sync.Game -Ua $sync.Ua
    $sync.Json = ($data | ConvertTo-Json -Depth 10 -Compress)
    $sync.Seq = [int]$sync.Seq + 1
    $sync.Status = if ($data.ok) { 'ok' } else { 'error' }
    $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
    $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop) { Start-Sleep -Milliseconds 200; $slept += 200 }
}
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
            Update-WiiLinkTree -Tree $tree -Head $head -Json $sync.Json -Colors $Colors
        }
        $status.Text = ("Interval: {0}     status: {1}" -f [string]$cmbInterval.SelectedItem, $sync.Status)
    })
$form.Add_Shown({ $uiTimer.Start() })
$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}; try { $sync.Stop = $true } catch {}; try { Start-Sleep -Milliseconds 150 } catch {}
        try { $bgPs.Stop(); $bgPs.Dispose(); $rs.Dispose() } catch {}
    })

# ============================================================================
# 診断モード
# ============================================================================
if ($SelfTest) {
    $log = Join-Path $env:TEMP 'wiilink_selftest.log'; Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline -and [int]$sync.Seq -lt 1) { Start-Sleep -Milliseconds 250 }
        L ("Seq=$($sync.Seq) Status=$($sync.Status)")
        Update-WiiLinkTree -Tree $tree -Head $head -Json $sync.Json -Colors $Colors
        L ("head: " + $head.Text); L ("room nodes: " + $tree.Nodes.Count)
        foreach ($rn in $tree.Nodes) { L ("   " + $rn.Text); foreach ($pn in $rn.Nodes) { if ($pn.Tag.Key -like 'wl:*') { L ("      " + $pn.Text) } } }
        L "RESULT: SUCCESS"
    } catch { L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace) }
    finally { try { $sync.Stop = $true; Start-Sleep -Milliseconds 150; $bgPs.Stop(); $bgPs.Dispose(); $rs.Dispose() } catch {} }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
