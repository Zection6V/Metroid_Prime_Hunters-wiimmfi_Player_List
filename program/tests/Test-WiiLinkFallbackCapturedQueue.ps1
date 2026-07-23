$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

Write-Host '== Standalone worker Queue capture =='
$standaloneQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$sync = [hashtable]::Synchronized(@{ LogQueue = $standaloneQueue })
. (Join-Path $programDir 'lib\WiiLinkFallback.ps1')

$script:ObservedQueue = $null
$script:ObservedTrigger = ''
function Invoke-MphNetworkDiagnostics {
    param(
        [uri]$Url,
        [AllowNull()]$LogQueue,
        [string]$Source,
        [string]$TriggerError
    )
    $script:ObservedQueue = $LogQueue
    $script:ObservedTrigger = $TriggerError
    $LogQueue.Enqueue(@{
            time = [datetime]::Now
            source = $Source
            level = 'INFO'
            stage = 'NETDIAG'
            message = 'stub diagnostics'
        })
    return [pscustomobject]@{ LikelyCause = 'stub' }
}

$failure = [pscustomobject]@{
    ok = $false
    state = 'error'
    error = 'All HTTP routes failed: direct: timeout | system: timeout'
}

Assert-True (Test-WiiLinkBrowserFallbackRequired -SelectedTransport direct -Data $failure) 'Route exhaustion must trigger fallback.'
Assert-True ([object]::ReferenceEquals($standaloneQueue, $script:ObservedQueue)) 'Standalone Queue must be captured when the fallback module is loaded.'
Assert-True ($script:ObservedTrigger -eq $failure.error) 'Original route failure must reach diagnostics.'
$standaloneEntries = @()
while ($standaloneQueue.Count -gt 0) { $standaloneEntries += ,$standaloneQueue.Dequeue() }
Assert-True (@($standaloneEntries | Where-Object { $_.stage -eq 'NETDIAG' }).Count -ge 3) 'NETDIAG start, diagnostic, and completion records must be emitted.'

Write-Host '== Unified worker Queue capture =='
$unifiedQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$sync = [hashtable]::Synchronized(@{ WiiLinkLogQueue = $unifiedQueue })
. (Join-Path $programDir 'lib\WiiLinkFallback.ps1')

# Reloading WiiLinkFallback also reloads the real diagnostics implementation.
# Restore the deterministic stub before checking which Queue the fallback captured.
$script:ObservedQueue = $null
$script:ObservedTrigger = ''
function Invoke-MphNetworkDiagnostics {
    param(
        [uri]$Url,
        [AllowNull()]$LogQueue,
        [string]$Source,
        [string]$TriggerError
    )
    $script:ObservedQueue = $LogQueue
    $script:ObservedTrigger = $TriggerError
    $LogQueue.Enqueue(@{
            time = [datetime]::Now
            source = $Source
            level = 'INFO'
            stage = 'NETDIAG'
            message = 'stub diagnostics'
        })
    return [pscustomobject]@{ LikelyCause = 'stub' }
}

Assert-True (Test-WiiLinkBrowserFallbackRequired -SelectedTransport direct -Data $failure) 'Unified route exhaustion must trigger fallback.'
Assert-True ([object]::ReferenceEquals($unifiedQueue, $script:ObservedQueue)) 'Unified WiiLink Queue must be captured when the fallback module is loaded.'
Assert-True ($script:ObservedTrigger -eq $failure.error) 'Unified diagnostics must receive the original route failure.'

Write-Host '== Explicit Queue takes precedence =='
$explicitQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$script:ObservedQueue = $null
Assert-True (Test-WiiLinkBrowserFallbackRequired -SelectedTransport direct -Data $failure -LogQueue $explicitQueue) 'Explicit Queue call must still trigger fallback.'
Assert-True ([object]::ReferenceEquals($explicitQueue, $script:ObservedQueue)) 'Explicit Queue must override the captured Queue.'

Write-Host '== Source inspection =='
$fallbackSource = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiiLinkFallback.ps1') -Raw
Assert-True ($fallbackSource -notmatch 'Get-WiiLinkFallbackLogQueue') 'Obsolete dynamic-scope Queue search must not exist.'
Assert-True ($fallbackSource -match 'Invoke-MphNetworkDiagnostics') 'Fallback must invoke detailed diagnostics directly.'
Assert-True ($fallbackSource -match 'Running detailed Direct API diagnostics') 'A visible NETDIAG start record must be emitted.'

Write-Host 'RESULT: SUCCESS'
