$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $programDir 'lib\ViewerCommon.ps1')
. (Join-Path $programDir 'lib\DiagnosticLogView.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-TestEntry {
    param([int]$Second, [string]$Message)
    [pscustomobject]@{
        time = [datetime]::new(2026, 7, 23, 12, 0, $Second, [datetimekind]::Local)
        source = 'WiiLink'
        level = 'INFO'
        stage = 'TEST'
        message = $Message
    }
}

$theme = Get-MphTheme
$i18n = Get-MphI18n -Lang 'en'
$panel = New-DiagnosticLogPanel -Theme $theme -I18n $i18n -SourceOptions @(@{ Key = 'WiiLink'; Text = 'WiiLink' })
try {
    Write-Host '== initial render =='
    $first = @((New-TestEntry 1 'first'), (New-TestEntry 2 'second'))
    Set-DiagnosticLogEntries -LogPanel $panel -Entries $first -Theme $theme
    Assert-True ($panel.LastRenderMode -eq 'rebuild') 'Initial rendering must build the log once.'
    Assert-True ($panel.RenderedKeys.Count -eq 2) 'Initial rendering must track two entries.'

    Write-Host '== append from the current position =='
    $panel.AutoScroll.Checked = $false
    $panel.LogBox.SelectionStart = 5
    $savedSelection = $panel.LogBox.SelectionStart
    $second = @($first) + @((New-TestEntry 3 'third'))
    Set-DiagnosticLogEntries -LogPanel $panel -Entries $second -Theme $theme
    Assert-True ($panel.LastRenderMode -eq 'append') 'Normal polling must append only new entries.'
    Assert-True ($panel.LogBox.SelectionStart -eq $savedSelection) 'Appending with auto-scroll disabled must preserve the current position.'
    Assert-True ($panel.RenderedKeys.Count -eq 3) 'Append rendering must track all three entries.'

    Write-Host '== unchanged snapshot =='
    Set-DiagnosticLogEntries -LogPanel $panel -Entries $second -Theme $theme
    Assert-True ($panel.LastRenderMode -eq 'unchanged') 'An unchanged snapshot must not redraw the log.'

    Write-Host '== auto-scroll to the latest entry once =='
    $panel.AutoScroll.Checked = $true
    $third = @($second) + @((New-TestEntry 4 'fourth'))
    Set-DiagnosticLogEntries -LogPanel $panel -Entries $third -Theme $theme
    Assert-True ($panel.LastRenderMode -eq 'append') 'Auto-scroll updates must still append incrementally.'
    Assert-True ($panel.LogBox.SelectionStart -eq $panel.LogBox.TextLength) 'Auto-scroll must move directly to the latest entry after appending.'

    Write-Host '== filter or history reset =='
    $filtered = @($third | Select-Object -Last 2)
    Set-DiagnosticLogEntries -LogPanel $panel -Entries $filtered -Theme $theme
    Assert-True ($panel.LastRenderMode -eq 'rebuild') 'Filter or history changes must rebuild the displayed snapshot.'

    Write-Host 'RESULT: SUCCESS'
} finally {
    try { $panel.Panel.Dispose() } catch {}
}
