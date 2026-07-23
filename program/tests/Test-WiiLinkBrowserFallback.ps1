$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $programDir 'lib\WiiLinkFallback.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

Write-Host '== Route exhaustion triggers browser fallback =='
$routeFailure = [pscustomobject]@{
    ok = $false
    state = 'error'
    error = 'All HTTP routes failed: direct: timeout | system: timeout'
}
Assert-True (Test-WiiLinkBrowserFallbackRequired -SelectedTransport direct -Data $routeFailure) 'Direct route exhaustion must request Chrome/Edge fallback.'

Write-Host '== Successful direct request stays direct =='
$success = [pscustomobject]@{ ok = $true; state = 'ok'; error = '' }
Assert-True (-not (Test-WiiLinkBrowserFallbackRequired -SelectedTransport direct -Data $success)) 'Successful Direct API data must not switch transport.'

Write-Host '== Non-network errors stay on selected transport =='
$jsonFailure = [pscustomobject]@{ ok = $false; state = 'error'; error = 'Unexpected JSON token' }
Assert-True (-not (Test-WiiLinkBrowserFallbackRequired -SelectedTransport direct -Data $jsonFailure)) 'JSON errors must not be mistaken for route exhaustion.'
Assert-True (-not (Test-WiiLinkBrowserFallbackRequired -SelectedTransport browser -Data $routeFailure)) 'Browser mode must never recursively request browser fallback.'
Assert-True (-not (Test-WiiLinkBrowserFallbackRequired -SelectedTransport direct -Data $null)) 'Null data must not trigger fallback.'

Write-Host '== UI transport mapping =='
Assert-True ((Get-WiiLinkTransportComboIndex -Transport direct) -eq 0) 'Direct API must map to selector index 0.'
Assert-True ((Get-WiiLinkTransportComboIndex -Transport browser) -eq 1) 'Chrome/Edge must map to selector index 1.'

Write-Host '== Viewer integration surface =='
$standalone = Get-Content -LiteralPath (Join-Path $programDir 'WiiLink-PlayerList.ps1') -Raw
$unified = Get-Content -LiteralPath (Join-Path $programDir 'MPH-Unified.ps1') -Raw
foreach ($viewer in @($standalone, $unified)) {
    Assert-True ($viewer -match 'WiiLinkFallback\.ps1') 'Viewer must load the fallback policy module.'
    Assert-True ($viewer -match 'Test-WiiLinkBrowserFallbackRequired') 'Viewer worker must evaluate fallback policy.'
    Assert-True ($viewer -match "Transport\s*=\s*'browser'") 'Viewer worker must switch the synchronized transport to browser.'
    Assert-True ($viewer -match "Stage 'FALLBACK'") 'Viewer must record the automatic switch in diagnostics.'
    Assert-True ($viewer -match 'Get-WiiLinkTransportComboIndex') 'Viewer UI selector must follow the worker-selected transport.'
}

Write-Host 'RESULT: SUCCESS'
