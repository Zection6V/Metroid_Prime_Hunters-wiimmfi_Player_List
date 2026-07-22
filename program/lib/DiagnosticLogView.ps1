<#
    DiagnosticLogView.ps1 — 診断ログの WinForms 表示コンポーネント

    LogStore の保存方式やデータ取得処理には依存しない。
    渡された LogEntry の描画、表示元の選択、コピー等の UI のみを担当する。
#>

. (Join-Path $PSScriptRoot 'I18n.ps1')

function New-DiagnosticLogPanel {
    param(
        $Theme,
        $I18n,
        [array]$SourceOptions = @(),
        [int]$ExpandedHeight = 230
    )
    if (-not $I18n) { $I18n = Get-MphI18n }

    $options = @($SourceOptions | Where-Object { $_ -and $_.Key })
    if ($options.Count -eq 0) { $options = @(@{ Key = 'All'; Text = $I18n.logAll }) }

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
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $title.Margin = New-Object System.Windows.Forms.Padding(8, 6, 10, 0)

    $sourceLabel = New-Object System.Windows.Forms.Label
    $sourceLabel.Text = $I18n.logSource; $sourceLabel.AutoSize = $true; $sourceLabel.ForeColor = $Theme.dim
    $sourceLabel.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 0)

    $sourceCombo = New-Object System.Windows.Forms.ComboBox
    $sourceCombo.DropDownStyle = 'DropDownList'; $sourceCombo.Width = 120
    $sourceCombo.BackColor = $Theme.bgDark; $sourceCombo.ForeColor = $Theme.cream; $sourceCombo.FlatStyle = 'Flat'
    $sourceKeys = New-Object System.Collections.ArrayList
    foreach ($option in $options) {
        [void]$sourceCombo.Items.Add([string]$option.Text)
        [void]$sourceKeys.Add([string]$option.Key)
    }
    $sourceCombo.SelectedIndex = 0
    $hasMultipleSources = ($options.Count -gt 1)
    $sourceLabel.Visible = $hasMultipleSources
    $sourceCombo.Visible = $hasMultipleSources

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

    $toolbar.Controls.Add($toggle); $toolbar.Controls.Add($title)
    $toolbar.Controls.Add($sourceLabel); $toolbar.Controls.Add($sourceCombo)
    $toolbar.Controls.Add($copy); $toolbar.Controls.Add($clear); $toolbar.Controls.Add($auto); $toolbar.Controls.Add($details)

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Dock = 'Fill'; $box.ReadOnly = $true; $box.BackColor = $Theme.bgDark; $box.ForeColor = $Theme.cream
    $box.BorderStyle = 'FixedSingle'; $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.WordWrap = $false; $box.DetectUrls = $false; $box.HideSelection = $false; $box.Visible = $false

    $outer.Controls.Add($box); $outer.Controls.Add($toolbar)
    return @{
        Panel = $outer; Toolbar = $toolbar; LogBox = $box; Toggle = $toggle; Copy = $copy; Clear = $clear
        AutoScroll = $auto; Details = $details; SourceLabel = $sourceLabel; SourceCombo = $sourceCombo
        SourceKeys = @($sourceKeys); ExpandedHeight = $ExpandedHeight; Expanded = $false
    }
}

function Get-DiagnosticLogSource {
    param($LogPanel)
    if (-not $LogPanel -or -not $LogPanel.SourceCombo) { return 'All' }
    $index = [int]$LogPanel.SourceCombo.SelectedIndex
    if ($index -lt 0 -or $index -ge @($LogPanel.SourceKeys).Count) { return 'All' }
    return [string]$LogPanel.SourceKeys[$index]
}

function Set-DiagnosticLogExpanded {
    param($LogPanel, [bool]$Expanded, $I18n)
    $LogPanel.Expanded = $Expanded
    $LogPanel.LogBox.Visible = $Expanded
    $LogPanel.Panel.Height = if ($Expanded) { [int]$LogPanel.ExpandedHeight } else { 30 }
    $LogPanel.Toggle.Text = if ($Expanded) { $I18n.logCollapse } else { $I18n.logExpand }
}

function Add-DiagnosticLog {
    param($LogPanel, $Entry, $Theme, [int]$MaxLines = 2000)
    if (-not $Entry) { return }
    $level = ([string]$Entry.level).ToUpperInvariant()
    $time = try { ([datetime]$Entry.time).ToString('HH:mm:ss.fff') } catch { (Get-Date).ToString('HH:mm:ss.fff') }
    $source = if ($Entry.source) { [string]$Entry.source } else { 'App' }
    $stage = if ($Entry.stage) { " [$([string]$Entry.stage)]" } else { '' }
    $line = "{0} [{1}] [{2}]{3} {4}`r`n" -f $time, $source, $level, $stage, ([string]$Entry.message)
    $color = switch ($level) { 'ERROR' { $Theme.red } 'WARN' { $Theme.orange } 'DEBUG' { $Theme.dim } default { $Theme.cream } }

    $box = $LogPanel.LogBox
    $box.SelectionStart = $box.TextLength; $box.SelectionLength = 0; $box.SelectionColor = $color
    $box.AppendText($line); $box.SelectionColor = $box.ForeColor

    if ($box.Lines.Count -gt $MaxLines) {
        $keep = $box.Lines | Select-Object -Last ($MaxLines - 200)
        $box.Text = (($keep -join "`r`n").TrimEnd() + "`r`n")
    }
}

function Set-DiagnosticLogEntries {
    param($LogPanel, [array]$Entries, $Theme, [int]$MaxLines = 2000)
    $box = $LogPanel.LogBox
    $box.SuspendLayout()
    try {
        $box.Clear()
        foreach ($entry in @($Entries)) { Add-DiagnosticLog -LogPanel $LogPanel -Entry $entry -Theme $Theme -MaxLines $MaxLines }
        if ($LogPanel.AutoScroll.Checked) { $box.SelectionStart = $box.TextLength; $box.ScrollToCaret() }
    } finally {
        $box.ResumeLayout()
    }
}
