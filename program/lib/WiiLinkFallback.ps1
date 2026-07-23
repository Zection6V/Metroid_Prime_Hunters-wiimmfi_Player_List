<#
    WiiLinkFallback.ps1 - policy and diagnostics for Direct API failures.

    The viewer keeps Direct API as the first choice. When every HTTP route is
    exhausted, a one-time background diagnostic is started and the viewer
    changes to Chrome/Edge.
#>

$networkDiagnosticsPath = Join-Path $PSScriptRoot 'NetworkDiagnostics.ps1'
if (Test-Path -LiteralPath $networkDiagnosticsPath -PathType Leaf) {
    . $networkDiagnosticsPath
}

function Get-WiiLinkFallbackLogQueue {
    for ($scope = 1; $scope -le 8; $scope++) {
        $syncVariable = Get-Variable -Name sync -Scope $scope -ErrorAction SilentlyContinue
        if ($null -eq $syncVariable -or $null -eq $syncVariable.Value) { continue }
        $syncObject = $syncVariable.Value
        try {
            if ($syncObject -is [hashtable] -and $syncObject.ContainsKey('WiiLinkLogQueue')) {
                return $syncObject.WiiLinkLogQueue
            }
            if ($syncObject -is [hashtable] -and $syncObject.ContainsKey('LogQueue')) {
                return $syncObject.LogQueue
            }
        } catch {}
    }
    return $null
}

function Test-WiiLinkBrowserFallbackRequired {
    param(
        [ValidateSet('direct', 'browser')][string]$SelectedTransport,
        [AllowNull()]$Data
    )

    if ($SelectedTransport -ne 'direct' -or $null -eq $Data) { return $false }

    $okProperty = $Data.PSObject.Properties['ok']
    if ($null -ne $okProperty -and [bool]$okProperty.Value) { return $false }

    $errorProperty = $Data.PSObject.Properties['error']
    $errorText = if ($null -ne $errorProperty) { [string]$errorProperty.Value } else { '' }
    if ([string]::IsNullOrWhiteSpace($errorText)) { return $false }

    # Only route exhaustion starts diagnostics and changes the transport.
    # JSON parsing or response-shape errors remain on the selected transport.
    $fallbackRequired = $errorText.StartsWith('All HTTP routes failed:', [System.StringComparison]::OrdinalIgnoreCase)
    if ($fallbackRequired) {
        try {
            $queue = Get-WiiLinkFallbackLogQueue
            if ($null -ne $queue -and $null -ne (Get-Command Start-MphNetworkDiagnostics -ErrorAction SilentlyContinue)) {
                [void](Start-MphNetworkDiagnostics -Url ([uri]'https://api.wfc.wiilink24.com/api/stats') -LogQueue $queue -Source 'WiiLink' -TriggerError $errorText)
            }
        } catch {}
    }
    return $fallbackRequired
}

function Get-WiiLinkTransportComboIndex {
    param([AllowNull()][string]$Transport)
    if ([string]$Transport -eq 'browser') { return 1 }
    return 0
}
