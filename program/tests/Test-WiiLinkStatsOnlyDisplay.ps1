$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $programDir 'lib\I18n.ps1')
. (Join-Path $programDir 'lib\TreeRender.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$i18n = Get-MphI18n -Lang 'ja'
$colors = @{
    cream = [System.Drawing.Color]::Beige
    dim = [System.Drawing.Color]::Gray
    cyan = [System.Drawing.Color]::Cyan
    red = [System.Drawing.Color]::Red
    orange = [System.Drawing.Color]::Orange
    green = [System.Drawing.Color]::LimeGreen
}
$tree = New-Object System.Windows.Forms.TreeView
$head = New-Object System.Windows.Forms.Label

try {
    Write-Host '== stats-only online player =='
    $statsOnly = @{
        ok = $true
        state = 'ok'
        stats = @{ online = 1; active = 0; groups = 0 }
        rooms = @()
    } | ConvertTo-Json -Depth 6 -Compress

    Update-WiiLinkTree -Tree $tree -Head $head -Json $statsOnly -Colors $colors -I18n $i18n
    Assert-True ($head.Text -match 'オンライン 1') 'Header must preserve stats.mprimeds.online=1.'
    Assert-True ($tree.Nodes.Count -eq 1) 'Stats-only response must render one summary node.'
    Assert-True ([string]$tree.Nodes[0].Text -match 'オンライン:\s*1') 'Summary node must show the stats online count.'
    Assert-True ([string]$tree.Nodes[0].Text -notmatch [regex]::Escape([string]$i18n.nobody)) 'Stats-only response must not display nobody-online text.'
    Assert-True ([string]$tree.Nodes[0].Tag.Key -eq 'wl-stats') 'Stats-only summary must use the stable wl-stats node key.'

    Write-Host '== genuinely empty response =='
    $empty = @{
        ok = $true
        state = 'empty'
        stats = @{ online = 0; active = 0; groups = 0 }
        rooms = @()
    } | ConvertTo-Json -Depth 6 -Compress

    Update-WiiLinkTree -Tree $tree -Head $head -Json $empty -Colors $colors -I18n $i18n
    Assert-True ($tree.Nodes.Count -eq 1) 'Empty response must render one placeholder node.'
    Assert-True ([string]$tree.Nodes[0].Text -eq [string]$i18n.nobody) 'All-zero stats must keep the nobody-online placeholder.'

    Write-Host 'RESULT: SUCCESS'
} finally {
    try { $tree.Dispose() } catch {}
    try { $head.Dispose() } catch {}
}
