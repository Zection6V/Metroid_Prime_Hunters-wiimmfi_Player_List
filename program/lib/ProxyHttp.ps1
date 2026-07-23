<#
    ProxyHttp.ps1 — プロキシ対応HTTP取得（UI・WiiLink解析非依存）

    既定の auto モードでは次の順に試行する:
      1. 直結
      2. HTTPS_PROXY / HTTP_PROXY（NO_PROXY対象外の場合）
      3. Windows システムプロキシ（PAC / WPADを含む）

    MPH_PROXY:
      未設定 / auto       … 上記の自動フォールバック
      direct / none / off … 直結のみ
      environment / env   … HTTPS_PROXY / HTTP_PROXYのみ
      system              … Windowsシステムプロキシのみ
      http(s)://host:port … 指定プロキシのみ

    任意設定:
      MPH_DIRECT_TIMEOUT_SEC … auto時の直結試行（既定6秒）
      MPH_HTTP_TIMEOUT_SEC   … その他の試行（既定20秒）
      MPH_PROXY_USERNAME / MPH_PROXY_PASSWORD / MPH_PROXY_DOMAIN
#>

try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch {}

function Get-MphBoundedIntEnvironmentValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$DefaultValue,
        [int]$Minimum,
        [int]$Maximum
    )

    $raw = [string][Environment]::GetEnvironmentVariable($Name)
    $value = 0
    if ([string]::IsNullOrWhiteSpace($raw) -or -not [int]::TryParse($raw.Trim(), [ref]$value)) { return $DefaultValue }
    if ($value -lt $Minimum -or $value -gt $Maximum) { return $DefaultValue }
    return $value
}

function Get-MphSafeProxyLabel {
    param([AllowNull()]$ProxyUri)

    if ($null -eq $ProxyUri) { return '' }
    try {
        $uri = [uri]$ProxyUri
        if ($uri.IsDefaultPort) { return $uri.Host }
        return ('{0}:{1}' -f $uri.Host, $uri.Port)
    } catch {
        return '<invalid-proxy>'
    }
}

function Test-MphNoProxyMatch {
    param(
        [Parameter(Mandatory = $true)][uri]$TargetUri,
        [AllowNull()][string]$NoProxy = $env:NO_PROXY
    )

    if ([string]::IsNullOrWhiteSpace($NoProxy)) { return $false }
    $host = $TargetUri.DnsSafeHost.ToLowerInvariant()
    $hostPort = ('{0}:{1}' -f $host, $TargetUri.Port)

    foreach ($rawRule in ($NoProxy -split ',')) {
        $rule = $rawRule.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($rule)) { continue }
        if ($rule -eq '*') { return $true }
        if ($rule -eq $host -or $rule -eq $hostPort) { return $true }

        $ruleHost = $rule
        $colon = $rule.LastIndexOf(':')
        if ($colon -gt 0 -and $rule.IndexOf(']') -lt 0) { $ruleHost = $rule.Substring(0, $colon) }
        if ($ruleHost.StartsWith('.')) {
            $suffix = $ruleHost.Substring(1)
            if ($host -eq $suffix -or $host.EndsWith('.' + $suffix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        } elseif ($host.EndsWith('.' + $ruleHost, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-MphEnvironmentProxyUri {
    param([Parameter(Mandatory = $true)][uri]$TargetUri)

    if (Test-MphNoProxyMatch -TargetUri $TargetUri) { return $null }
    $raw = if ($TargetUri.Scheme -eq 'https' -and -not [string]::IsNullOrWhiteSpace([string]$env:HTTPS_PROXY)) {
        [string]$env:HTTPS_PROXY
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$env:HTTP_PROXY)) {
        [string]$env:HTTP_PROXY
    } else {
        ''
    }

    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $uri = $null
    if (-not [uri]::TryCreate($raw.Trim(), [UriKind]::Absolute, [ref]$uri)) { return $null }
    if ($uri.Scheme -notin @('http', 'https')) { return $null }
    return $uri
}

function Resolve-MphProxyConfiguration {
    param(
        [Parameter(Mandatory = $true)][uri]$TargetUri,
        [AllowNull()][string]$Setting = $env:MPH_PROXY
    )

    $raw = ([string]$Setting).Trim()
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Equals('auto', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ Mode = 'auto'; ProxyUri = $null; EnvironmentProxyUri = (Get-MphEnvironmentProxyUri -TargetUri $TargetUri) }
    }

    $normalized = $raw.ToLowerInvariant()
    if ($normalized -in @('direct', 'none', 'off')) {
        return [pscustomobject]@{ Mode = 'direct'; ProxyUri = $null; EnvironmentProxyUri = $null }
    }
    if ($normalized -in @('environment', 'env')) {
        $environmentProxy = Get-MphEnvironmentProxyUri -TargetUri $TargetUri
        if ($null -eq $environmentProxy) { throw 'MPH_PROXY requests an environment proxy, but HTTPS_PROXY/HTTP_PROXY is not configured or NO_PROXY excludes this host.' }
        return [pscustomobject]@{ Mode = 'environment'; ProxyUri = $environmentProxy; EnvironmentProxyUri = $environmentProxy }
    }
    if ($normalized -eq 'system') {
        return [pscustomobject]@{ Mode = 'system'; ProxyUri = $null; EnvironmentProxyUri = $null }
    }

    $proxyUri = $null
    if (-not [uri]::TryCreate($raw, [UriKind]::Absolute, [ref]$proxyUri) -or $proxyUri.Scheme -notin @('http', 'https')) {
        throw 'Invalid MPH_PROXY value. Use auto, direct, environment, system, or an http(s) proxy URI.'
    }
    return [pscustomobject]@{ Mode = 'custom'; ProxyUri = $proxyUri; EnvironmentProxyUri = $null }
}

function Get-MphProxyAttemptPlan {
    param([Parameter(Mandatory = $true)]$Configuration)

    $directTimeout = Get-MphBoundedIntEnvironmentValue -Name 'MPH_DIRECT_TIMEOUT_SEC' -DefaultValue 6 -Minimum 2 -Maximum 120
    $httpTimeout = Get-MphBoundedIntEnvironmentValue -Name 'MPH_HTTP_TIMEOUT_SEC' -DefaultValue 20 -Minimum 3 -Maximum 300
    $attempts = @()

    switch ([string]$Configuration.Mode) {
        'auto' {
            $attempts += [pscustomobject]@{ Mode = 'direct'; ProxyUri = $null; TimeoutSec = $directTimeout }
            if ($null -ne $Configuration.EnvironmentProxyUri) {
                $attempts += [pscustomobject]@{ Mode = 'environment'; ProxyUri = $Configuration.EnvironmentProxyUri; TimeoutSec = $httpTimeout }
            }
            $attempts += [pscustomobject]@{ Mode = 'system'; ProxyUri = $null; TimeoutSec = $httpTimeout }
        }
        'direct'      { $attempts += [pscustomobject]@{ Mode = 'direct'; ProxyUri = $null; TimeoutSec = $httpTimeout } }
        'environment' { $attempts += [pscustomobject]@{ Mode = 'environment'; ProxyUri = $Configuration.ProxyUri; TimeoutSec = $httpTimeout } }
        'system'      { $attempts += [pscustomobject]@{ Mode = 'system'; ProxyUri = $null; TimeoutSec = $httpTimeout } }
        'custom'      { $attempts += [pscustomobject]@{ Mode = 'custom'; ProxyUri = $Configuration.ProxyUri; TimeoutSec = $httpTimeout } }
        default       { throw ('Unsupported proxy mode: {0}' -f $Configuration.Mode) }
    }
    return $attempts
}

function Get-MphProxyCredentials {
    $username = [string]$env:MPH_PROXY_USERNAME
    if ([string]::IsNullOrWhiteSpace($username)) { return [System.Net.CredentialCache]::DefaultNetworkCredentials }
    $password = [string]$env:MPH_PROXY_PASSWORD
    $domain = [string]$env:MPH_PROXY_DOMAIN
    if ([string]::IsNullOrWhiteSpace($domain)) { return New-Object System.Net.NetworkCredential($username, $password) }
    return New-Object System.Net.NetworkCredential($username, $password, $domain)
}

function Write-MphHttpDiagnostic {
    param(
        [AllowNull()]$LogQueue,
        [string]$Source,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level,
        [string]$Message
    )

    if ($null -eq $LogQueue) { return }
    try {
        $LogQueue.Enqueue(@{
                time = [datetime]::Now; source = $Source; level = $Level; stage = 'PROXY'; message = $Message
            })
    } catch {}
}

function Invoke-MphProxyHttpAttempt {
    param(
        [Parameter(Mandatory = $true)][uri]$Url,
        [Parameter(Mandatory = $true)]$Attempt,
        [hashtable]$Headers = @{}
    )

    $handler = $null
    $client = $null
    $request = $null
    $response = $null
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $true
        $handler.UseCookies = $false
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

        if ([string]$Attempt.Mode -eq 'direct') {
            $handler.UseProxy = $false
        } else {
            $handler.UseProxy = $true
            $proxy = if ([string]$Attempt.Mode -eq 'system') {
                [System.Net.WebRequest]::GetSystemWebProxy()
            } else {
                New-Object System.Net.WebProxy([uri]$Attempt.ProxyUri, $true)
            }
            $credentials = Get-MphProxyCredentials
            try { $proxy.Credentials = $credentials } catch {}
            $handler.Proxy = $proxy
            try {
                if ($null -ne $handler.PSObject.Properties['DefaultProxyCredentials']) {
                    $handler.DefaultProxyCredentials = $credentials
                }
            } catch {}
        }

        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds([int]$Attempt.TimeoutSec)
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $Url)
        foreach ($header in $Headers.GetEnumerator()) {
            [void]$request.Headers.TryAddWithoutValidation([string]$header.Key, [string]$header.Value)
        }

        try {
            $response = $client.SendAsync($request).GetAwaiter().GetResult()
        } catch [System.Threading.Tasks.TaskCanceledException] {
            throw [System.TimeoutException]::new(('HTTP request timed out after {0}s' -f $Attempt.TimeoutSec), $_.Exception)
        } catch [System.OperationCanceledException] {
            throw [System.TimeoutException]::new(('HTTP request timed out after {0}s' -f $Attempt.TimeoutSec), $_.Exception)
        }

        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        $status = [int]$response.StatusCode
        $contentType = if ($null -ne $response.Content.Headers.ContentType) { [string]$response.Content.Headers.ContentType } else { '' }
        if (-not $response.IsSuccessStatusCode) {
            $preview = $text.Replace("`r", ' ').Replace("`n", ' ')
            if ($preview.Length -gt 300) { $preview = $preview.Substring(0, 300) + '...' }
            throw [System.Net.WebException]::new(('HTTP {0} {1}; body={2}' -f $status, $response.ReasonPhrase, $preview))
        }

        return @{
            text = $text; status = $status; bytes = $bytes.Length; contentType = $contentType
            route = [string]$Attempt.Mode; proxy = (Get-MphSafeProxyLabel -ProxyUri $Attempt.ProxyUri); timeoutSec = [int]$Attempt.TimeoutSec
        }
    } finally {
        try { if ($null -ne $response) { $response.Dispose() } } catch {}
        try { if ($null -ne $request) { $request.Dispose() } } catch {}
        try { if ($null -ne $client) { $client.Dispose() } } catch {}
        try { if ($null -ne $handler) { $handler.Dispose() } } catch {}
    }
}

function Invoke-MphProxyHttpText {
    param(
        [Parameter(Mandatory = $true)][uri]$Url,
        [hashtable]$Headers = @{},
        [AllowNull()]$LogQueue = $null,
        [string]$Source = 'App',
        [AllowNull()][string]$ProxySetting = $env:MPH_PROXY,
        [AllowNull()][scriptblock]$AttemptInvoker = $null
    )

    $configuration = Resolve-MphProxyConfiguration -TargetUri $Url -Setting $ProxySetting
    $attempts = @(Get-MphProxyAttemptPlan -Configuration $configuration)
    $planText = ($attempts | ForEach-Object {
            $proxyLabel = Get-MphSafeProxyLabel -ProxyUri $_.ProxyUri
            if ($proxyLabel) { '{0}({1},{2}s)' -f $_.Mode, $proxyLabel, $_.TimeoutSec } else { '{0}({1}s)' -f $_.Mode, $_.TimeoutSec }
        }) -join ' -> '
    Write-MphHttpDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('HTTP route plan: {0}' -f $planText)

    $failures = @()
    for ($index = 0; $index -lt $attempts.Count; $index++) {
        $attempt = $attempts[$index]
        $proxyLabel = Get-MphSafeProxyLabel -ProxyUri $attempt.ProxyUri
        $routeLabel = if ($proxyLabel) { '{0}:{1}' -f $attempt.Mode, $proxyLabel } else { [string]$attempt.Mode }
        Write-MphHttpDiagnostic -LogQueue $LogQueue -Source $Source -Level DEBUG -Message ('Attempt {0}/{1} started; route={2}; timeoutSec={3}; host={4}' -f ($index + 1), $attempts.Count, $routeLabel, $attempt.TimeoutSec, $Url.Host)
        try {
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $result = if ($null -ne $AttemptInvoker) {
                & $AttemptInvoker $Url $attempt $Headers
            } else {
                Invoke-MphProxyHttpAttempt -Url $Url -Attempt $attempt -Headers $Headers
            }
            $watch.Stop()
            if ($result -is [hashtable]) {
                if (-not $result.ContainsKey('route')) { $result.route = [string]$attempt.Mode }
                if (-not $result.ContainsKey('proxy')) { $result.proxy = $proxyLabel }
            }
            Write-MphHttpDiagnostic -LogQueue $LogQueue -Source $Source -Level INFO -Message ('HTTP attempt succeeded; route={0}; elapsedMs={1}' -f $routeLabel, $watch.ElapsedMilliseconds)
            return $result
        } catch {
            $message = $_.Exception.Message
            $failures += ('{0}: {1}' -f $routeLabel, $message)
            $hasNext = ($index + 1 -lt $attempts.Count)
            $level = if ($hasNext) { 'WARN' } else { 'ERROR' }
            $suffix = if ($hasNext) { '; trying next route' } else { '' }
            Write-MphHttpDiagnostic -LogQueue $LogQueue -Source $Source -Level $level -Message ('HTTP attempt failed; route={0}; error={1}{2}' -f $routeLabel, $message, $suffix)
        }
    }

    throw ('All HTTP routes failed: {0}' -f ($failures -join ' | '))
}
