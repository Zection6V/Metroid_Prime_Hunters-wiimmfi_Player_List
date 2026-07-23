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

Write-Host '== Deterministic Direct API diagnostics =='
$queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$oldHttpsProxy = $env:HTTPS_PROXY
$oldHttpProxy = $env:HTTP_PROXY
$oldNoProxy = $env:NO_PROXY
$oldMphProxy = $env:MPH_PROXY
try {
    $env:HTTPS_PROXY = 'http://user:secret@proxy.example.test:8080/path?token=secret'
    $env:HTTP_PROXY = $null
    $env:NO_PROXY = 'localhost'
    $env:MPH_PROXY = 'auto'

    $diagnostic = Invoke-MphNetworkDiagnostics -Url ([uri]'https://api.wfc.wiilink24.com/api/stats') -LogQueue $queue -Source 'WiiLink' -TriggerError $routeFailure.error `
        -DnsResolver {
            param($HostName, $TimeoutMs)
            [pscustomobject]@{
                Success = $true
                Addresses = @([System.Net.IPAddress]::Parse('2001:db8::10'), [System.Net.IPAddress]::Parse('203.0.113.10'))
                ElapsedMs = 4
                Error = ''
            }
        } `
        -TcpProbe {
            param($Address, $Port, $TimeoutMs)
            if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                return [pscustomobject]@{ Success = $false; ElapsedMs = $TimeoutMs; Error = 'simulated-ipv6-timeout' }
            }
            return [pscustomobject]@{ Success = $true; ElapsedMs = 12; Error = '' }
        } `
        -TlsProbe {
            param($Address, $Port, $TargetHost, $TimeoutMs)
            [pscustomobject]@{
                Success = $true
                ElapsedMs = 18
                Protocol = 'Tls12'
                Cipher = 'Aes256/256'
                CertificateSubject = 'CN=api.wfc.wiilink24.com'
                CertificateIssuer = 'CN=Test CA'
                Error = ''
            }
        } `
        -SystemProxyProbe {
            param($Url)
            [pscustomobject]@{
                Success = $true
                IsBypassed = $true
                Resolved = 'DIRECT'
                ProxyType = 'TestProxy'
                ElapsedMs = 2
                Error = ''
            }
        } `
        -WinInetProbe {
            [pscustomobject]@{
                Success = $true
                ProxyEnable = $false
                ProxyServer = ''
                AutoConfigUrl = 'https://pac.example.test'
                ConnectionFlags = '0x09(direct,auto-detect)'
                Error = ''
            }
        } `
        -WinHttpProbe {
            param($TimeoutMs)
            'Direct access (no proxy server).'
        }

    Assert-True ($diagnostic.LikelyCause -eq 'ipv6-path-difference') 'IPv6 failure plus IPv4 TLS success must be classified separately.'
    $entries = @()
    while ($queue.Count -gt 0) { $entries += ,$queue.Dequeue() }
    Assert-True ($entries.Count -ge 8) 'Network diagnostics must emit a detailed sequence.'
    Assert-True (@($entries | Where-Object { $_.stage -eq 'NETDIAG' -and $_.message -match 'DNS succeeded' }).Count -eq 1) 'DNS results must be logged.'
    Assert-True (@($entries | Where-Object { $_.message -match 'TCP IPv6' -and $_.message -match 'success=False' }).Count -eq 1) 'IPv6 TCP failure must be logged.'
    Assert-True (@($entries | Where-Object { $_.message -match 'TLS IPv4' -and $_.message -match 'success=True' }).Count -eq 1) 'IPv4 TLS success must be logged.'
    Assert-True (@($entries | Where-Object { $_.message -match 'likely=ipv6-path-difference' }).Count -eq 1) 'Likely cause must be summarized.'
    $rendered = ($entries.message -join "`n")
    Assert-True ($rendered -notmatch 'user:secret') 'Proxy credentials must be redacted.'
    Assert-True ($rendered -notmatch 'token=secret') 'Proxy query secrets must be redacted.'
} finally {
    $env:HTTPS_PROXY = $oldHttpsProxy
    $env:HTTP_PROXY = $oldHttpProxy
    $env:NO_PROXY = $oldNoProxy
    $env:MPH_PROXY = $oldMphProxy
}

Write-Host '== Viewer integration surface =='
$standalone = Get-Content -LiteralPath (Join-Path $programDir 'WiiLink-PlayerList.ps1') -Raw
$unified = Get-Content -LiteralPath (Join-Path $programDir 'MPH-Unified.ps1') -Raw
foreach ($viewer in @($standalone, $unified)) {
    Assert-True ($viewer -match 'WiiLinkFallback\.ps1') 'Viewer must load the fallback policy module.'
    Assert-True ($viewer -match 'Test-WiiLinkBrowserFallbackRequired') 'Viewer worker must evaluate fallback policy.'
    Assert-True ($viewer -match "Transport\s*=\s*'browser'") 'Viewer worker must switch the synchronized transport to browser.'
    Assert-True ($viewer -match "(?:-Stage\s+)?'FALLBACK'") 'Viewer must record the automatic switch in diagnostics.'
    Assert-True ($viewer -match 'Get-WiiLinkTransportComboIndex') 'Viewer UI selector must follow the worker-selected transport.'
}
$fallbackSource = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiiLinkFallback.ps1') -Raw
Assert-True ($fallbackSource -match 'Invoke-MphNetworkDiagnostics') 'Fallback policy must run Direct API diagnostics in the WiiLink worker.'
Assert-True ($fallbackSource -match 'Running detailed Direct API diagnostics') 'Fallback policy must emit a visible NETDIAG start record.'
Assert-True ($fallbackSource -notmatch 'Start-MphNetworkDiagnostics') 'Obsolete child-runspace diagnostics must not return.'

Write-Host 'RESULT: SUCCESS'
