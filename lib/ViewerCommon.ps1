<#
    ViewerCommon.ps1 — ビューワ共通の UI 部品とワーカー基盤（単一責務で再利用）

    dot-source して使う:  . "$PSScriptRoot\lib\ViewerCommon.ps1"
    前提: 呼び出し側が事前に Add-Type で System.Windows.Forms / System.Drawing を読み込み済み。

    公開関数:
      Get-MphTheme                                   … 配色テーマ（色 + TreeRender 用 Colors）
      New-TopBar    -Theme -Title -TitleColor        … タイトル + 間隔セレクタの上部バー
                                                       戻り値 @{ Panel; Combo; IntervalMap }
      New-TreePanel -Theme -HeadColor                … 見出しラベル + TreeView のパネル
                                                       戻り値 @{ Panel; Head; Tree }
      New-StatusBar -Theme [-Text]                   … 下部ステータスバー（Label）
      Start-PollWorker -Sync -Body                   … 別 runspace でワーカー起動 @{ ps; rs; handle }
      Stop-PollWorker  -Job                          … ワーカーの停止・破棄
#>

function Get-MphTheme {
    $t = @{}
    $t.bgDark = [System.Drawing.Color]::FromArgb(0x23, 0x23, 0x23)
    $t.panel  = [System.Drawing.Color]::FromArgb(0x2D, 0x2D, 0x2D)
    $t.orange = [System.Drawing.Color]::FromArgb(0xE7, 0x65, 0x0C)
    $t.cream  = [System.Drawing.Color]::FromArgb(0xFF, 0xFF, 0xCA)
    $t.cyan   = [System.Drawing.Color]::FromArgb(0xA4, 0xE1, 0xFF)
    $t.green  = [System.Drawing.Color]::FromArgb(0x6A, 0xD0, 0x8A)
    $t.red    = [System.Drawing.Color]::FromArgb(0xE8, 0x6A, 0x6A)
    $t.dim    = [System.Drawing.Color]::FromArgb(0xB7, 0xB7, 0xB7)
    # lib\TreeRender.ps1 の Update-*Tree に渡す Colors
    $t.Colors = @{ cream = $t.cream; dim = $t.dim; cyan = $t.cyan; red = $t.red; orange = $t.orange; green = $t.green }
    return $t
}

function New-TopBar {
    param($Theme, [string]$Title, $TitleColor, [int]$Height = 48)
    $pad = [int](($Height - 26) / 2)
    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = 'Top'; $top.Height = $Height; $top.BackColor = $Theme.panel

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Title; $lbl.ForeColor = $TitleColor
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(14, $pad); $lbl.AutoSize = $true
    $top.Controls.Add($lbl)

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Right'; $flow.FlowDirection = 'LeftToRight'; $flow.WrapContents = $false
    $flow.AutoSize = $true; $flow.BackColor = $Theme.panel; $flow.Padding = New-Object System.Windows.Forms.Padding(0, $pad, 12, 0)
    $cap = New-Object System.Windows.Forms.Label
    $cap.Text = "Update every:"; $cap.ForeColor = $Theme.dim; $cap.AutoSize = $true
    $cap.Margin = New-Object System.Windows.Forms.Padding(0, 6, 6, 0)
    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.DropDownStyle = 'DropDownList'; $cmb.Width = 90
    $cmb.BackColor = $Theme.bgDark; $cmb.ForeColor = $Theme.cream; $cmb.FlatStyle = 'Flat'
    $map = [ordered]@{ '15 sec' = 15000; '30 sec' = 30000; '1 min' = 60000; '2 min' = 120000; '5 min' = 300000 }
    foreach ($k in $map.Keys) { [void]$cmb.Items.Add($k) }
    $cmb.SelectedItem = '30 sec'
    $flow.Controls.Add($cap); $flow.Controls.Add($cmb)
    $top.Controls.Add($flow)

    return @{ Panel = $top; Combo = $cmb; IntervalMap = $map }
}

function New-TreePanel {
    param($Theme, $HeadColor)
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Dock = 'Fill'; $pnl.BackColor = $Theme.bgDark; $pnl.Padding = New-Object System.Windows.Forms.Padding(8)
    $head = New-Object System.Windows.Forms.Label
    $head.Dock = 'Top'; $head.Height = 30; $head.ForeColor = $HeadColor
    $head.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold); $head.TextAlign = 'MiddleLeft'
    $tree = New-Object System.Windows.Forms.TreeView
    $tree.Dock = 'Fill'; $tree.BackColor = $Theme.panel; $tree.ForeColor = $Theme.cream; $tree.BorderStyle = 'FixedSingle'
    $tree.Font = New-Object System.Drawing.Font("MS Gothic", 10); $tree.HideSelection = $false
    $tree.ShowLines = $true; $tree.ShowRootLines = $true; $tree.ShowPlusMinus = $true
    $pnl.Controls.Add($tree); $pnl.Controls.Add($head)
    return @{ Panel = $pnl; Head = $head; Tree = $tree }
}

function New-StatusBar {
    param($Theme, [string]$Text = 'Connecting...')
    $s = New-Object System.Windows.Forms.Label
    $s.Dock = 'Bottom'; $s.Height = 24; $s.ForeColor = $Theme.dim
    $s.Font = New-Object System.Drawing.Font("Segoe UI", 9); $s.TextAlign = 'MiddleLeft'
    $s.BackColor = $Theme.panel; $s.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0); $s.Text = $Text
    return $s
}

function Start-PollWorker {
    param($Sync, [string]$Body)
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'MTA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $Sync)
    $ps = [powershell]::Create(); $ps.Runspace = $rs; [void]$ps.AddScript($Body)
    $h = $ps.BeginInvoke()
    return @{ ps = $ps; rs = $rs; handle = $h }
}

function Stop-PollWorker {
    param($Job)
    if (-not $Job) { return }
    try { $Job.ps.Stop() } catch {}
    try { $Job.ps.Dispose() } catch {}
    try { $Job.rs.Dispose() } catch {}
}
