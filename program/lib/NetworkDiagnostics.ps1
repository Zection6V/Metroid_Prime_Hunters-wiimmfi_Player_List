<#
    NetworkDiagnostics.ps1 - background diagnostics for Direct API failures.

    The diagnostic path is intentionally separate from the HTTP transport.
    It records DNS, IPv4/IPv6 TCP, TLS, WinINet, WinHTTP, and system proxy
    information only after every Direct API HTTP route has failed.
#>

if (-not (Get-Variable -Name MphNetworkDiagnosticStarted -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MphNetworkDiagnosticStarted = @{}
}
if (-not (Get-Variable -Name MphNetworkDiagnosticJobs -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MphNetworkDiagnosticJobs = New-Object System.Collections.ArrayList
}
$script:MphNetworkDiagnosticsScriptPath = $PSCommandPath

function Write-MphNetworkDiagnostic {
    param(
        [AllowNull()]$LogQueue,
        [string]$Source = 'WiiLink',
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [string]$Message
    )

    if ($null -eq $LogQueue) { return }
    try {
        $LogQueue.Enqueue(@{
                time = [datetime]::Now
                source = $Source
                level = $Level
                stage = 'NETDIAG'
                message = $Message
            })
    } catch {}
}

function Get-MphNetworkDiagnosticTimeoutMs {
    $raw = ([string]$env:MPH_NETDIAG_TIMEOUT_MS).Trim()
    $value = 0
    if ([string]::IsNullOrWhiteSpace($raw) -or -not [int]::TryParse($raw, [ref]$value)) { return 1800 }
    if ($value -lt 500 -or $value -gt 10000) { return 1800 }
    return $value
}

function Test-MphNetworkDiagnosticsEnabled {
    $raw = ([string]$env:MPH_NETWORK_DIAGNOSTICS).Trim().ToLowerInvariant()
    return ($raw -notin @('0', 'false', 'off', 'no', 'disabled'))
}

function Get-MphSafeNetworkUriLabel {
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    try {
        $uri = [uri]$Value
        if (-not $uri.IsAbsoluteUri) { throw 'not-absolute' }
        $portText = if ($uri.IsDefaultPort) { '' } else { ':' + [string]$uri.Port }
        return ('{0}://{1}{2}' -f $uri.Scheme, $uri.DnsSafeHost, $portText)
    } catch {
        $text = ([string]$Value).Trim()
        $text = [regex]::Replace($text, '(?i)([a-z][a-z0-9+.-]*://)[^/@;\s]+@', '$1')
        $text = [regex]::Replace($text, '(?i)([a-z][a-z0-9+.-]*://[^/;\s?#]+)[/][^;\s]*', '$1')
        $text = [regex]::Replace($text, '[?#][^;\s]*', '')
        if ($text.Length -gt 240) { $text = $text.Substring(0, 240) + '...' }
        return $text
    }
}

function Get-MphSafeProxyConfigurationLabel {
    param([AllowNull()]$Value)

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $safeParts = @()
    foreach ($rawPart in ($text -split ';')) {
        $part = $rawPart.Trim()
        if (-not $part) { continue }
        $name = ''
        $target = $part
        $equals = $part.IndexOf('=')
        if ($equals -gt 0) {
            $name = $part.Substring(0, $equals).Trim() + '='
            $target = $part.Substring($equals + 1).Trim()
        }
        if ($target -notmatch '^[a-z][a-z0-9+.-]*://') { $target = 'http://' + $target }
        $safe = Get-MphSafeNetworkUriLabel -Value $target
        if ($safe.StartsWith('http://', [System.StringComparison]::OrdinalIgnoreCase) -and $part -notmatch '^[a-z][a-z0-9+.-]*://') {
            $safe = $safe.Substring(7)
        }
        $safeParts += ($name + $safe)
    }
    return ($safeParts -join ';')
}

function Get-MphWinInetProxySnapshot {
    try {
        $internetSettings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $proxyEnable = $false
        try { $proxyEnable = ([int]$internetSettings.ProxyEnable -ne 0) } catch {}
        $proxyServer = Get-MphSafeProxyConfigurationLabel -Value ([string]$internetSettings.ProxyServer)
        $autoConfig = Get-MphSafeNetworkUriLabel -Value ([string]$internetSettings.AutoConfigURL)

        $flagText = ''
        try {
            $connections = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections' -ErrorAction Stop
            $bytes = [byte[]]$connections.DefaultConnectionSettings
            if ($null -ne $bytes -and $bytes.Length -gt 8) {
                $flags = [int]$bytes[8]
                $names = @()
                if (($flags -band 1) -ne 0) { $names += 'direct' }
                if (($flags -band 2) -ne 0) { $names += 'proxy' }
                if (($flags -band 4) -ne 0) { $names += 'auto-config' }
                if (($flags -band 8) -ne 0) { $names += 'auto-detect' }
                $flagText = ('0x{0:X2}({1})' -f $flags, ($names -join ','))
            }
        } catch {}

        return [pscustomobject]@{
            Success = $true
            ProxyEnable = $proxyEnable
            ProxyServer = $proxyServer
            AutoConfigUrl = $autoConfig
            ConnectionFlags = $flagText
            Error = ''
        }
    } catch {
        return [pscustomobject]@{
            Success = $false
            ProxyEnable = $false
            ProxyServer = ''
            AutoConfigUrl = ''
            ConnectionFlags = ''
            Error = $_.Exception.Message
        }
    }
}

function Get-MphWinHttpProxySummary {
    param([int]$TimeoutMs = (Get-MphNetworkDiagnosticTimeoutMs))

    $netsh = Join-Path $env:SystemRoot 'System32\netsh.exe'
    if (-not (Test-Path -LiteralPath $netsh -PathType Leaf)) { return 'netsh-unavailable' }

    $process = $null
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $netsh
        $startInfo.Arguments = 'winhttp show proxy'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { return 'netsh-start-failed' }
        if (-not $process.WaitForExit($TimeoutMs)) {
            try { $process.Kill() } catch {}
            return ('netsh-timeout-{0}ms' -f $TimeoutMs)
        }
        $output = (($process.StandardOutput.ReadToEnd() + ' ' + $process.StandardError.ReadToEnd()) -replace '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($output)) { return 'netsh-empty-output' }
        $output = [regex]::Replace($output, '(?i)([a-z][a-z0-9+.-]*://)[^/@;\s]+@', '$1')
        if ($output.Length -gt 800) { $output = $output.Substring(0, 800) + '...' }
        return $output
    } catch {
        return ('netsh-error={0}' -f $_.Exception.Message)
    } finally {
        try { if ($null -ne $process) { $process.Dispose() } } catch {}
    }
}

function Get-MphSystemProxySnapshot {
    param([Parameter(Mandatory = $true)][uri]$Url)

    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $isBypassed = $proxy.IsBypassed($Url)
        $resolved = $proxy.GetProxy($Url)
        $watch.Stop()
        $resolvedLabel = if ($isBypassed -or $null -eq $resolved -or $resolved.AbsoluteUri -eq $Url.AbsoluteUri) {
            'DIRECT'
        } else {
            Get-MphSafeNetworkUriLabel -Value $resolved
        }
        return [pscustomobject]@{
            Success = $true
            IsBypassed = [bool]$isBypassed
            Resolved = $resolvedLabel
            ProxyType = $proxy.GetType().FullName
            ElapsedMs = $watch.ElapsedMilliseconds
            Error = ''
        }
    } catch {
        $watch.Stop()
        return [pscustomobject]@{
            Success = $false
            IsBypassed = $false
            Resolved = ''
            ProxyType = ''
            ElapsedMs = $watch.ElapsedMilliseconds
            Error = $_.Exception.Message
        }
    }
}

function Resolve-MphNetworkAddresses {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [int]$TimeoutMs = (Get-MphNetworkDiagnosticTimeoutMs)
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $async = $null
    try {
        $async = [System.Net.Dns]::BeginGetHostAddresses($HostName, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $watch.Stop()
            return [pscustomobject]@{ Success = $false; Addresses = @(); ElapsedMs = $watch.ElapsedMilliseconds; Error = ('dns-timeout-{0}ms' -f $TimeoutMs) }
        }
        $addresses = @([System.Net.Dns]::EndGetHostAddresses($async))
        $watch.Stop()
        return [pscustomobject]@{ Success = $true; Addresses = $addresses; ElapsedMs = $watch.ElapsedMilliseconds; Error = '' }
    } catch {
        $watch.Stop()
        return [pscustomobject]@{ Success = $false; Addresses = @(); ElapsedMs = $watch.ElapsedMilliseconds; Error = $_.Exception.Message }
    } finally {
        try { if ($null -ne $async -and $null -ne $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() } } catch {}
    }
}

function Test-MphTcpEndpoint {
    param(
        [Parameter(Mandatory = $true)][System.Net.IPAddress]$Address,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = (Get-MphNetworkDiagnosticTimeoutMs)
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $client = $null
    $async = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient($Address.AddressFamily)
        $async = $client.BeginConnect($Address, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $watch.Stop()
            return [pscustomobject]@{ Success = $false; ElapsedMs = $watch.ElapsedMilliseconds; Error = ('tcp-timeout-{0}ms' -f $TimeoutMs) }
        }
        $client.EndConnect($async)
        $watch.Stop()
        return [pscustomobject]@{ Success = $true; ElapsedMs = $watch.ElapsedMilliseconds; Error = '' }
    } catch {
        $watch.Stop()
        return [pscustomobject]@{ Success = $false; ElapsedMs = $watch.ElapsedMilliseconds; Error = $_.Exception.Message }
    } finally {
        try { if ($null -ne $async -and $null -ne $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() } } catch {}
        try { if ($null -ne $client) { $client.Close() } } catch {}
    }
}

function Test-MphTlsEndpoint {
    param(
        [Parameter(Mandatory = $true)][System.Net.IPAddress]$Address,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$TargetHost,
        [int]$TimeoutMs = (Get-MphNetworkDiagnosticTimeoutMs)
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $client = $null
    $networkStream = $null
    $ssl = $null
    $connectAsync = $null
    $tlsAsync = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient($Address.AddressFamily)
        $connectAsync = $client.BeginConnect($Address, $Port, $null, $null)
        if (-not $connectAsync.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw ('tcp-timeout-{0}ms' -f $TimeoutMs) }
        $client.EndConnect($connectAsync)

        $networkStream = $client.GetStream()
        $ssl = New-Object System.Net.Security.SslStream($networkStream, $false)
        $tlsAsync = $ssl.BeginAuthenticateAsClient($TargetHost, $null, $null)
        if (-not $tlsAsync.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw ('tls-timeout-{0}ms' -f $TimeoutMs) }
        $ssl.EndAuthenticateAsClient($tlsAsync)
        $watch.Stop()

        $certificateSubject = ''
        $certificateIssuer = ''
        try {
            if ($null -ne $ssl.RemoteCertificate) {
                $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
                $certificateSubject = [string]$certificate.Subject
                $certificateIssuer = [string]$certificate.Issuer
            }
        } catch {}

        return [pscustomobject]@{
            Success = $true
            ElapsedMs = $watch.ElapsedMilliseconds
            Protocol = [string]$ssl.SslProtocol
            Cipher = ('{0}/{1}' -f $ssl.CipherAlgorithm, $ssl.CipherStrength)
            CertificateSubject = $certificateSubject
            CertificateIssuer = $certificateIssuer
            Error = ''
        }
    } catch {
        $watch.Stop()
        $certificateSubject = ''
        $certificateIssuer = ''
        try {
            if ($null -ne $ssl -and $null -ne $ssl.RemoteCertificate) {
                $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
                $certificateSubject = [string]$certificate.Subject
                $certificateIssuer = [string]$certificate.Issuer
            }
        } catch {}
        return [pscustomobject]@{
            Success = $false
            ElapsedMs = $watch.ElapsedMilliseconds
            Protocol = ''
            Cipher = ''
            CertificateSubject = $certificateSubject
            CertificateIssuer = $certificateIssuer
            Error = $_.Exception.Message
        }
    } finally {
        try { if ($null -ne $tlsAsync -and $null -ne $tlsAsync.AsyncWaitHandle) { $tlsAsync.AsyncWaitHandle.Close() } } catch {}
        try { if ($null -ne $connectAsync -and $null -ne $connectAsync.AsyncWaitHandle) { $connectAsync.AsyncWaitHandle.Close() } } catch {}
        try { if ($null -ne $ssl) { $ssl.Dispose() } } catch {}
        try { if ($null -ne $networkStream) { $networkStream.Dispose() } } catch {}
        try { if ($null -ne $client) { $client.Close() } } catch {}
    }
}

function Get-MphNetworkLikelyCause {
    param(
        [Parameter(Mandatory = $true)]$DnsResult,
        [object[]]$TcpResults = @(),
        [object[]]$TlsResults = @()
    )

    if (-not [bool]$DnsResult.Success) { return 'dns-resolution-failure' }
    $tcpSuccess = @($TcpResults | Where-Object { [bool]$_.Success })
    if ($tcpSuccess.Count -eq 0) { return 'tcp-443-blocked-or-unroutable' }
    $tlsSuccess = @($TlsResults | Where-Object { [bool]$_.Success })
    if ($tlsSuccess.Count -eq 0) { return 'tls-handshake-or-interception' }

    $hasIpv4Tls = @($tlsSuccess | Where-Object { [string]$_.Family -eq 'IPv4' }).Count -gt 0
    $hasIpv6Address = @($TcpResults | Where-Object { [string]$_.Family -eq 'IPv6' }).Count -gt 0
    $hasIpv6Tcp = @($tcpSuccess | Where-Object { [string]$_.Family -eq 'IPv6' }).Count -gt 0
    if ($hasIpv4Tls -and $hasIpv6Address -and -not $hasIpv6Tcp) { return 'ipv6-path-difference' }
    return 'dotnet-http-or-proxy-stack-difference'
}

function Invoke-MphNetworkDiagnostics {
    param(
        [Parameter(Mandatory = $true)][uri]$Url,
        [AllowNull()]$LogQueue = $null,
        [string]$Source = 'WiiLink',
        [AllowNull()][string]$TriggerError = '',
        [AllowNull()][scriptblock]$DnsResolver = $null,
        [AllowNull()][scriptblock]$TcpProbe = $null,
        [AllowNull()][scriptblock]$TlsProbe = $null,
        [AllowNull()][scriptblock]$SystemProxyProbe = $null,
        [AllowNull()][scriptblock]$WinInetProbe = $null,
        [AllowNull()][scriptblock]$WinHttpProbe = $null
    )

    $timeoutMs = Get-MphNetworkDiagnosticTimeoutMs
    Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('Diagnostics started; target={0}; timeoutMs={1}; trigger={2}' -f (Get-MphSafeNetworkUriLabel -Value $Url), $timeoutMs, $TriggerError)

    $httpsProxy = Get-MphSafeNetworkUriLabel -Value $env:HTTPS_PROXY
    $httpProxy = Get-MphSafeNetworkUriLabel -Value $env:HTTP_PROXY
    Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('Runtime; PowerShell={0}; CLR={1}; OS={2}; SecurityProtocol={3}' -f $PSVersionTable.PSVersion, [Environment]::Version, [Environment]::OSVersion.VersionString, [System.Net.ServicePointManager]::SecurityProtocol)
    $mphProxy = Get-MphSafeProxyConfigurationLabel -Value $env:MPH_PROXY
    Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('Environment proxy; HTTPS_PROXY={0}; HTTP_PROXY={1}; NO_PROXY_present={2}; MPH_PROXY={3}' -f $httpsProxy, $httpProxy, (-not [string]::IsNullOrWhiteSpace([string]$env:NO_PROXY)), $mphProxy)

    $winInet = if ($null -ne $WinInetProbe) { & $WinInetProbe } else { Get-MphWinInetProxySnapshot }
    if ([bool]$winInet.Success) {
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('WinINet; proxyEnable={0}; proxyServer={1}; autoConfig={2}; connectionFlags={3}' -f $winInet.ProxyEnable, $winInet.ProxyServer, $winInet.AutoConfigUrl, $winInet.ConnectionFlags)
    } else {
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level WARN -Message ('WinINet inspection failed; error={0}' -f $winInet.Error)
    }

    $winHttp = if ($null -ne $WinHttpProbe) { & $WinHttpProbe $timeoutMs } else { Get-MphWinHttpProxySummary -TimeoutMs $timeoutMs }
    Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('WinHTTP; {0}' -f $winHttp)

    $systemProxy = if ($null -ne $SystemProxyProbe) { & $SystemProxyProbe $Url } else { Get-MphSystemProxySnapshot -Url $Url }
    if ([bool]$systemProxy.Success) {
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('System proxy resolution; bypassed={0}; resolved={1}; type={2}; elapsedMs={3}' -f $systemProxy.IsBypassed, $systemProxy.Resolved, $systemProxy.ProxyType, $systemProxy.ElapsedMs)
    } else {
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level WARN -Message ('System proxy resolution failed; elapsedMs={0}; error={1}' -f $systemProxy.ElapsedMs, $systemProxy.Error)
    }

    $dns = if ($null -ne $DnsResolver) { & $DnsResolver $Url.DnsSafeHost $timeoutMs } else { Resolve-MphNetworkAddresses -HostName $Url.DnsSafeHost -TimeoutMs $timeoutMs }
    if (-not [bool]$dns.Success) {
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level ERROR -Message ('DNS failed; host={0}; elapsedMs={1}; error={2}' -f $Url.DnsSafeHost, $dns.ElapsedMs, $dns.Error)
        $likely = Get-MphNetworkLikelyCause -DnsResult $dns
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level WARN -Message ('Diagnostics summary; likely={0}' -f $likely)
        return [pscustomobject]@{ LikelyCause = $likely; Dns = $dns; Tcp = @(); Tls = @(); SystemProxy = $systemProxy; WinInet = $winInet; WinHttp = $winHttp }
    }

    $addresses = @($dns.Addresses | ForEach-Object {
            if ($_ -is [System.Net.IPAddress]) { $_ } else { [System.Net.IPAddress]::Parse([string]$_) }
        })
    $addressText = ($addresses | ForEach-Object {
            $family = if ($_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) { 'IPv6' } else { 'IPv4' }
            '{0}:{1}' -f $family, $_
        }) -join ','
    Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('DNS succeeded; host={0}; elapsedMs={1}; addresses={2}' -f $Url.DnsSafeHost, $dns.ElapsedMs, $addressText)

    $probeAddresses = @()
    $ipv4 = $addresses | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1
    $ipv6 = $addresses | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6 } | Select-Object -First 1
    if ($null -ne $ipv6) { $probeAddresses += ,$ipv6 }
    if ($null -ne $ipv4) { $probeAddresses += ,$ipv4 }

    $tcpResults = @()
    $tlsResults = @()
    foreach ($address in $probeAddresses) {
        $family = if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) { 'IPv6' } else { 'IPv4' }
        $tcp = if ($null -ne $TcpProbe) { & $TcpProbe $address $Url.Port $timeoutMs } else { Test-MphTcpEndpoint -Address $address -Port $Url.Port -TimeoutMs $timeoutMs }
        $tcp | Add-Member -NotePropertyName Address -NotePropertyValue ([string]$address) -Force
        $tcp | Add-Member -NotePropertyName Family -NotePropertyValue $family -Force
        $tcpResults += ,$tcp
        $tcpLevel = if ([bool]$tcp.Success) { 'INFO' } else { 'WARN' }
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level $tcpLevel -Message ('TCP {0}; address={1}; port={2}; success={3}; elapsedMs={4}; error={5}' -f $family, $address, $Url.Port, $tcp.Success, $tcp.ElapsedMs, $tcp.Error)

        if ([bool]$tcp.Success) {
            $tls = if ($null -ne $TlsProbe) { & $TlsProbe $address $Url.Port $Url.DnsSafeHost $timeoutMs } else { Test-MphTlsEndpoint -Address $address -Port $Url.Port -TargetHost $Url.DnsSafeHost -TimeoutMs $timeoutMs }
            $tls | Add-Member -NotePropertyName Address -NotePropertyValue ([string]$address) -Force
            $tls | Add-Member -NotePropertyName Family -NotePropertyValue $family -Force
            $tlsResults += ,$tls
            $tlsLevel = if ([bool]$tls.Success) { 'INFO' } else { 'WARN' }
            Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level $tlsLevel -Message ('TLS {0}; address={1}; success={2}; elapsedMs={3}; protocol={4}; cipher={5}; certSubject={6}; certIssuer={7}; error={8}' -f $family, $address, $tls.Success, $tls.ElapsedMs, $tls.Protocol, $tls.Cipher, $tls.CertificateSubject, $tls.CertificateIssuer, $tls.Error)
        }
    }

    $likelyCause = Get-MphNetworkLikelyCause -DnsResult $dns -TcpResults $tcpResults -TlsResults $tlsResults
    Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level WARN -Message ('Diagnostics summary; likely={0}; dnsAddresses={1}; tcpSuccess={2}; tlsSuccess={3}; systemProxy={4}' -f $likelyCause, $addresses.Count, @($tcpResults | Where-Object { [bool]$_.Success }).Count, @($tlsResults | Where-Object { [bool]$_.Success }).Count, $systemProxy.Resolved)

    return [pscustomobject]@{
        LikelyCause = $likelyCause
        Dns = $dns
        Tcp = $tcpResults
        Tls = $tlsResults
        SystemProxy = $systemProxy
        WinInet = $winInet
        WinHttp = $winHttp
    }
}

function Remove-MphCompletedNetworkDiagnosticJobs {
    if (-not (Get-Variable -Name MphNetworkDiagnosticJobs -Scope Script -ErrorAction SilentlyContinue)) { return }
    foreach ($job in @($script:MphNetworkDiagnosticJobs)) {
        if ($null -eq $job -or $null -eq $job.Handle -or -not $job.Handle.IsCompleted) { continue }
        try { [void]$job.PowerShell.EndInvoke($job.Handle) } catch {}
        try { $job.PowerShell.Dispose() } catch {}
        [void]$script:MphNetworkDiagnosticJobs.Remove($job)
    }
}

function Start-MphNetworkDiagnostics {
    param(
        [Parameter(Mandatory = $true)][uri]$Url,
        [AllowNull()]$LogQueue = $null,
        [string]$Source = 'WiiLink',
        [AllowNull()][string]$TriggerError = ''
    )

    if ($null -eq $LogQueue -or -not (Test-MphNetworkDiagnosticsEnabled)) { return $false }
    Remove-MphCompletedNetworkDiagnosticJobs

    $key = ('{0}://{1}:{2}' -f $Url.Scheme, $Url.DnsSafeHost.ToLowerInvariant(), $Url.Port)
    if ($script:MphNetworkDiagnosticStarted.ContainsKey($key)) {
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level DEBUG -Message ('Diagnostics already scheduled for {0}' -f $key)
        return $false
    }
    $script:MphNetworkDiagnosticStarted[$key] = [datetime]::UtcNow

    Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('Background diagnostics scheduled for {0}' -f $key)
    $powerShell = $null
    try {
        $powerShell = [powershell]::Create()
        $scriptText = @'
param($diagnosticScript, $urlText, $queue, $sourceName, $trigger)
. $diagnosticScript
Invoke-MphNetworkDiagnostics -Url ([uri]$urlText) -LogQueue $queue -Source $sourceName -TriggerError $trigger | Out-Null
'@
        [void]$powerShell.AddScript($scriptText)
        [void]$powerShell.AddArgument($script:MphNetworkDiagnosticsScriptPath)
        [void]$powerShell.AddArgument($Url.AbsoluteUri)
        [void]$powerShell.AddArgument($LogQueue)
        [void]$powerShell.AddArgument($Source)
        [void]$powerShell.AddArgument($TriggerError)
        $handle = $powerShell.BeginInvoke()
        [void]$script:MphNetworkDiagnosticJobs.Add([pscustomobject]@{ PowerShell = $powerShell; Handle = $handle; Key = $key })
        return $true
    } catch {
        try { if ($null -ne $powerShell) { $powerShell.Dispose() } } catch {}
        Write-MphNetworkDiagnostic -LogQueue $LogQueue -Source $Source -Level ERROR -Message ('Unable to start background diagnostics; error={0}' -f $_.Exception.Message)
        return $false
    }
}
