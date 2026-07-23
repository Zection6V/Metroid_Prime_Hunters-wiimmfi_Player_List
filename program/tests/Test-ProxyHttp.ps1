$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$proxyLib = Join-Path $programDir 'lib\ProxyHttp.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$environmentNames = @(
    'MPH_PROXY', 'MPH_DIRECT_TIMEOUT_SEC', 'MPH_HTTP_TIMEOUT_SEC',
    'MPH_PROXY_USERNAME', 'MPH_PROXY_PASSWORD', 'MPH_PROXY_DOMAIN',
    'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY'
)
$oldEnvironment = @{}
foreach ($name in $environmentNames) { $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
$oldDefaultProxy = [System.Net.WebRequest]::DefaultWebProxy

try {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $null) }

    Write-Host '== Global proxy isolation =='
    $sentinel = New-Object System.Net.WebProxy('http://127.0.0.1:65530', $true)
    [System.Net.WebRequest]::DefaultWebProxy = $sentinel
    . $proxyLib
    Assert-True ([object]::ReferenceEquals([System.Net.WebRequest]::DefaultWebProxy, $sentinel)) 'Loading ProxyHttp must not modify DefaultWebProxy.'

    $target = [uri]'https://api.wfc.wiilink24.com/api/stats'

    Write-Host '== Auto route plan =='
    $autoConfig = Resolve-MphProxyConfiguration -TargetUri $target -Setting $null
    $autoPlan = @(Get-MphProxyAttemptPlan -Configuration $autoConfig)
    Assert-True ($autoConfig.Mode -eq 'auto') 'Unset MPH_PROXY must select auto mode.'
    Assert-True ($autoPlan.Count -eq 2) 'Auto mode without environment proxy must use direct and system attempts.'
    Assert-True ($autoPlan[0].Mode -eq 'direct' -and $autoPlan[1].Mode -eq 'system') 'Auto route order must be direct then system.'

    Write-Host '== Environment proxy and NO_PROXY =='
    $env:HTTPS_PROXY = 'http://proxy.example.test:8080'
    $env:NO_PROXY = ''
    $environmentConfig = Resolve-MphProxyConfiguration -TargetUri $target -Setting 'auto'
    $environmentPlan = @(Get-MphProxyAttemptPlan -Configuration $environmentConfig)
    Assert-True ($environmentPlan.Count -eq 3) 'Auto mode must include a configured HTTPS_PROXY.'
    Assert-True ($environmentPlan[1].Mode -eq 'environment') 'Environment proxy must be tried between direct and system.'
    Assert-True ((Get-MphSafeProxyLabel -ProxyUri $environmentPlan[1].ProxyUri) -eq 'proxy.example.test:8080') 'Environment proxy host and port must be preserved.'

    $env:NO_PROXY = 'api.wfc.wiilink24.com'
    $noProxyConfig = Resolve-MphProxyConfiguration -TargetUri $target -Setting 'auto'
    $noProxyPlan = @(Get-MphProxyAttemptPlan -Configuration $noProxyConfig)
    Assert-True ($noProxyPlan.Count -eq 2) 'NO_PROXY must exclude the environment proxy attempt.'
    Assert-True ($noProxyPlan[0].Mode -eq 'direct' -and $noProxyPlan[1].Mode -eq 'system') 'NO_PROXY must retain direct and Windows-system fallback.'

    Write-Host '== Explicit proxy modes =='
    Assert-True ((Resolve-MphProxyConfiguration -TargetUri $target -Setting 'direct').Mode -eq 'direct') 'direct mode must be accepted.'
    Assert-True ((Resolve-MphProxyConfiguration -TargetUri $target -Setting 'system').Mode -eq 'system') 'system mode must be accepted.'
    $custom = Resolve-MphProxyConfiguration -TargetUri $target -Setting 'http://custom.proxy.test:3128'
    Assert-True ($custom.Mode -eq 'custom') 'An HTTP URI must select custom proxy mode.'
    Assert-True ((Get-MphSafeProxyLabel -ProxyUri $custom.ProxyUri) -eq 'custom.proxy.test:3128') 'Custom proxy label must not contain credentials or paths.'
    $invalidFailed = $false
    try { [void](Resolve-MphProxyConfiguration -TargetUri $target -Setting 'not-a-proxy') } catch { $invalidFailed = $true }
    Assert-True $invalidFailed 'Invalid MPH_PROXY values must fail explicitly.'

    Write-Host '== Timeout fallback behavior =='
    $env:HTTPS_PROXY = $null
    $env:HTTP_PROXY = $null
    $env:NO_PROXY = $null
    $queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $calls = New-Object System.Collections.ArrayList
    $fallbackResult = Invoke-MphProxyHttpText -Url $target -Headers @{ Accept = 'application/json' } -LogQueue $queue -Source 'WiiLink' -ProxySetting 'auto' -AttemptInvoker {
        param($Url, $Attempt, $Headers)
        [void]$calls.Add([string]$Attempt.Mode)
        if ([string]$Attempt.Mode -eq 'direct') { throw [System.TimeoutException]::new('simulated direct timeout') }
        return @{ text = '{}'; status = 200; bytes = 2; contentType = 'application/json' }
    }
    Assert-True ($calls.Count -eq 2) 'Auto mode must make a second attempt after direct timeout.'
    Assert-True ($calls[0] -eq 'direct' -and $calls[1] -eq 'system') 'System proxy must follow the failed direct attempt.'
    Assert-True ($fallbackResult.route -eq 'system') 'Successful fallback route must be reported in the result.'
    $queued = @()
    while ($queue.Count -gt 0) { $queued += , $queue.Dequeue() }
    Assert-True ((@($queued | Where-Object { ([string]$_.level -eq 'WARN') -and ([string]$_.message -match 'trying next route') })).Count -eq 1) 'Fallback must be visible in diagnostics.'
    Assert-True ((@($queued | Where-Object { ([string]$_.level -eq 'INFO') -and ([string]$_.message -match 'route=system') })).Count -ge 1) 'Successful system route must be visible in diagnostics.'

    Write-Host '== Explicit direct does not fallback =='
    $directCalls = New-Object System.Collections.ArrayList
    $directFailed = $false
    try {
        [void](Invoke-MphProxyHttpText -Url $target -ProxySetting 'direct' -AttemptInvoker {
                param($Url, $Attempt, $Headers)
                [void]$directCalls.Add([string]$Attempt.Mode)
                throw [System.TimeoutException]::new('simulated direct-only timeout')
            })
    } catch {
        $directFailed = $true
        Assert-True ($_.Exception.Message -match 'All HTTP routes failed') 'Final failure must summarize attempted routes.'
    }
    Assert-True $directFailed 'Explicit direct mode must surface its failure.'
    Assert-True ($directCalls.Count -eq 1 -and $directCalls[0] -eq 'direct') 'Explicit direct mode must not try a proxy.'

    Write-Host '== Timeout settings =='
    $env:MPH_DIRECT_TIMEOUT_SEC = '9'
    $env:MPH_HTTP_TIMEOUT_SEC = '31'
    $timedPlan = @(Get-MphProxyAttemptPlan -Configuration (Resolve-MphProxyConfiguration -TargetUri $target -Setting 'auto'))
    Assert-True ($timedPlan[0].TimeoutSec -eq 9) 'MPH_DIRECT_TIMEOUT_SEC must configure the direct probe.'
    Assert-True ($timedPlan[1].TimeoutSec -eq 31) 'MPH_HTTP_TIMEOUT_SEC must configure the system attempt.'

    Write-Host 'RESULT: SUCCESS'
} finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name]) }
    [System.Net.WebRequest]::DefaultWebProxy = $oldDefaultProxy
}
