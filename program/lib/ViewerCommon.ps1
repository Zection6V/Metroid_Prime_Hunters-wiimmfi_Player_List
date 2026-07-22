<#
    ViewerCommon.ps1 — ビューワ共通の UI 部品とワーカー基盤（単一責務で再利用）

    dot-source して使う:  . "$PSScriptRoot\lib\ViewerCommon.ps1"
    前提: 呼び出し側が事前に Add-Type で System.Windows.Forms / System.Drawing を読み込み済み。
#>

. (Join-Path $PSScriptRoot 'I18n.ps1')

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
    $t.Colors = @{ cream = $t.cream; dim = $t.dim; cyan = $t.cyan; red = $t.red; orange = $t.orange; green = $t.green }
    return $t
}

function New-TopBar {
    param($Theme, [string]$Title, $TitleColor, $I18n, [int]$Height = 48)
    if (-not $I18n) { $I18n = Get-MphI18n }
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
    $cap.Text = $I18n.updateEvery; $cap.ForeColor = $Theme.dim; $cap.AutoSize = $true
    $cap.Margin = New-Object System.Windows.Forms.Padding(0, 6, 6, 0)
    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.DropDownStyle = 'DropDownList'; $cmb.Width = 90
    $cmb.BackColor = $Theme.bgDark; $cmb.ForeColor = $Theme.cream; $cmb.FlatStyle = 'Flat'
    $map = $I18n.intervals
    foreach ($k in $map.Keys) { [void]$cmb.Items.Add($k) }
    $cmb.SelectedItem = ($map.Keys | Where-Object { $map[$_] -eq 30000 } | Select-Object -First 1)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $I18n.refresh; $btn.AutoSize = $true; $btn.FlatStyle = 'Flat'
    $btn.BackColor = $Theme.bgDark; $btn.ForeColor = $Theme.cream
    $btn.FlatAppearance.BorderColor = $Theme.dim
    $btn.Margin = New-Object System.Windows.Forms.Padding(0, 2, 14, 0)
    $btn.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 2)

    $flow.Controls.Add($btn); $flow.Controls.Add($cap); $flow.Controls.Add($cmb)
    $top.Controls.Add($flow)
    return @{ Panel = $top; Combo = $cmb; IntervalMap = $map; Refresh = $btn }
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

function New-DiagnosticLogPanel {
    param($Theme, $I18n, [int]$ExpandedHeight = 230)
    if (-not $I18n) { $I18n = Get-MphI18n }

    $outer = New-Object System.Windows.Forms.Panel
    $outer.Dock = 'Bottom'; $outer.Height = 30; $outer.BackColor = $Theme.panel

    $toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
    $toolbar.Dock = 'Top'; $toolbar.Height = 30; $toolbar.FlowDirection = 'LeftToRight'; $toolbar.WrapContents = $false
    $toolbar.BackColor = $Theme.panel; $toolbar.Padding = New-Object System.Windows.Forms.Padding(6, 2, 4, 0)

    $toggle = New-Object System.Windows.Forms.Button
    $toggle.Text = $I18n.logExpand; $toggle.AutoSize = $true; $toggle.FlatStyle = 'Flat'
    $toggle.BackColor = $Theme.bgDark; $toggle.ForeColor = $Theme.cream; $toggle.FlatAppearance.BorderColor = $Theme.dim

    $title = New-Object System.Windows.Forms.Label
    $title.Text = $I18n.diagnosticLog; $title.AutoSize = $true; $title.ForeColor = $Theme.green
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $title.Margin = New-Object System.Windows.Forms.Padding(8, 6, 10, 0)

    $copy = New-Object System.Windows.Forms.Button
    $copy.Text = $I18n.logCopy; $copy.AutoSize = $true; $copy.FlatStyle = 'Flat'; $copy.BackColor = $Theme.bgDark; $copy.ForeColor = $Theme.cream
    $clear = New-Object System.Windows.Forms.Button
    $clear.Text = $I18n.logClear; $clear.AutoSize = $true; $clear.FlatStyle = 'Flat'; $clear.BackColor = $Theme.bgDark; $clear.ForeColor = $Theme.cream

    $auto = New-Object System.Windows.Forms.CheckBox
    $auto.Text = $I18n.logAutoScroll; $auto.Checked = $true; $auto.AutoSize = $true; $auto.ForeColor = $Theme.dim
    $auto.Margin = New-Object System.Windows.Forms.Padding(10, 6, 0, 0)
    $details = New-Object System.Windows.Forms.CheckBox
    $details.Text = $I18n.logDetails; $details.Checked = $false; $details.AutoSize = $true; $details.ForeColor = $Theme.dim
    $details.Margin = New-Object System.Windows.Forms.Padding(10, 6, 0, 0)

    $toolbar.Controls.Add($toggle); $toolbar.Controls.Add($title); $toolbar.Controls.Add($copy); $toolbar.Controls.Add($clear); $toolbar.Controls.Add($auto); $toolbar.Controls.Add($details)

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Dock = 'Fill'; $box.ReadOnly = $true; $box.BackColor = $Theme.bgDark; $box.ForeColor = $Theme.cream
    $box.BorderStyle = 'FixedSingle'; $box.Font = New-Object System.Drawing.Font("Consolas", 9)
    $box.WordWrap = $false; $box.DetectUrls = $false; $box.HideSelection = $false; $box.Visible = $false

    $outer.Controls.Add($box); $outer.Controls.Add($toolbar)
    return @{ Panel = $outer; Toolbar = $toolbar; LogBox = $box; Toggle = $toggle; Copy = $copy; Clear = $clear; AutoScroll = $auto; Details = $details; ExpandedHeight = $ExpandedHeight; Expanded = $false }
}

function Set-DiagnosticLogExpanded {
    param($LogPanel, [bool]$Expanded, $I18n)
    $LogPanel.Expanded = $Expanded
    $LogPanel.LogBox.Visible = $Expanded
    $LogPanel.Panel.Height = if ($Expanded) { [int]$LogPanel.ExpandedHeight } else { 30 }
    $LogPanel.Toggle.Text = if ($Expanded) { $I18n.logCollapse } else { $I18n.logExpand }
}

function Add-DiagnosticLog {
    param($LogPanel, $Entry, $Theme, [int]$MaxLines = 1000)
    if (-not $Entry) { return }
    $level = ([string]$Entry.level).ToUpperInvariant()
    if ($level -eq 'DEBUG' -and -not $LogPanel.Details.Checked) { return }
    $time = try { ([datetime]$Entry.time).ToString('HH:mm:ss.fff') } catch { (Get-Date).ToString('HH:mm:ss.fff') }
    $source = if ($Entry.source) { [string]$Entry.source } else { 'App' }
    $stage = if ($Entry.stage) { " [$([string]$Entry.stage)]" } else { '' }
    $line = "{0} [{1}] [{2}]{3} {4}`r`n" -f $time, $source, $level, $stage, ([string]$Entry.message)
    $color = switch ($level) { 'ERROR' { $Theme.red } 'WARN' { $Theme.orange } 'DEBUG' { $Theme.dim } default { $Theme.cream } }
    $box = $LogPanel.LogBox
    $box.SelectionStart = $box.TextLength; $box.SelectionLength = 0; $box.SelectionColor = $color; $box.AppendText($line); $box.SelectionColor = $box.ForeColor

    $lines = $box.Lines
    if ($lines.Count -gt $MaxLines) {
        $keep = $lines | Select-Object -Last ($MaxLines - 200)
        $box.Text = (($keep -join "`r`n").TrimEnd() + "`r`n")
    }
    if ($LogPanel.AutoScroll.Checked) { $box.SelectionStart = $box.TextLength; $box.ScrollToCaret() }
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