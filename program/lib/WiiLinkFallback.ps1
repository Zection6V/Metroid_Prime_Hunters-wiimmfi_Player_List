<#
    WiiLinkFallback.ps1 - policy and reliable diagnostics for Direct API failures.

    The worker dot-sources this file after its synchronized state has been created.
    Capture that Queue at load time and run diagnostics in the same worker so that
    NETDIAG output cannot disappear because of dynamic-scope or child-runspace issues.
#>

$networkDiagnosticsPath = Join-Path $PSScriptRoot 'NetworkDiagnostics.ps1'
if (Test-Path -LiteralPath $networkDiagnosticsPath -PathType Leaf) {
    . $networkDiagnosticsPath
}

$script:WiiLinkFallbackLogQueue = $null
try {
    $syncVariable = Get-Variable -Name sync -Scope 0 -ErrorAction SilentlyContinue
    if ($null -ne $syncVariable -and $null -ne $syncVariable.Value) {
        $syncObject = $syncVariable.Value
        if ($syncObject -is [hashtable] -and $syncObject.ContainsKey('WiiLinkLogQueue')) {
            $script:WiiLinkFallbackLogQueue = $syncObject.WiiLinkLogQueue
        } elseif ($syncObject -is [hashtable] -and $syncObject.ContainsKey('LogQueue')) {
            $script:WiiLinkFallbackLogQueue = $syncObject.LogQueue
        }
    }
} catch {}

function Write-WiiLinkFallbackNetDiag {
    param(
        [AllowNull()]$LogQueue,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($null -eq $LogQueue) { return }
    try {
        $LogQueue.Enqueue(@{
                time = [datetime]::Now
                source = 'WiiLink'
                level = $Level
                stage = 'NETDIAG'
                message = $Message
            })
    } catch {}
}

function Test-WiiLinkBrowserFallbackRequired {
    param(
        [ValidateSet('direct', 'browser')][string]$SelectedTransport,
        [AllowNull()]$Data,
        [AllowNull()]$LogQueue = $null
    )

    if ($SelectedTransport -ne 'direct' -or $null -eq $Data) { return $false }

    $okProperty = $Data.PSObject.Properties['ok']
    if ($null -ne $okProperty -and [bool]$okProperty.Value) { return $false }

    $errorProperty = $Data.PSObject.Properties['error']
    $errorText = if ($null -ne $errorProperty) { [string]$errorProperty.Value } else { '' }
    if ([string]::IsNullOrWhiteSpace($errorText)) { return $false }

    $fallbackRequired = $errorText.StartsWith('All HTTP routes failed:', [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $fallbackRequired) { return $false }

    if ($null -eq $LogQueue) { $LogQueue = $script:WiiLinkFallbackLogQueue }
    if ($null -eq $LogQueue) { return $true }

    try {
        $diagnosticCommand = Get-Command Invoke-MphNetworkDiagnostics -ErrorAction SilentlyContinue
        if ($null -eq $diagnosticCommand) {
            Write-WiiLinkFallbackNetDiag -LogQueue $LogQueue -Level ERROR -Message 'Detailed diagnostics unavailable; Invoke-MphNetworkDiagnostics was not loaded.'
        } else {
            Write-WiiLinkFallbackNetDiag -LogQueue $LogQueue -Level INFO -Message 'Running detailed Direct API diagnostics before Chrome/Edge fallback.'
            Invoke-MphNetworkDiagnostics -Url ([uri]'https://api.wfc.wiilink24.com/api/stats') -LogQueue $LogQueue -Source 'WiiLink' -TriggerError $errorText | Out-Null
            Write-WiiLinkFallbackNetDiag -LogQueue $LogQueue -Level INFO -Message 'Detailed Direct API diagnostics completed; continuing with Chrome/Edge fallback.'
        }
    } catch {
        Write-WiiLinkFallbackNetDiag -LogQueue $LogQueue -Level ERROR -Message ('Detailed diagnostics failed; type={0}; error={1}' -f $_.Exception.GetType().FullName, $_.Exception.Message)
    }

    return $true
}

function Get-WiiLinkTransportComboIndex {
    param([AllowNull()][string]$Transport)
    if ([string]$Transport -eq 'browser') { return 1 }
    return 0
}
