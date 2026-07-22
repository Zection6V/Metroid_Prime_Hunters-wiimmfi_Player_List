$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$repoRoot = Split-Path -Parent $programDir

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

Write-Host '== PowerShell syntax validation =='
$parseFailures = @()
Get-ChildItem -Path $programDir -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        foreach ($e in $errors) { $parseFailures += "${($_.FullName)}:$($e.Extent.StartLineNumber): $($e.Message)" }
    }
}
if ($parseFailures.Count -gt 0) { throw ($parseFailures -join [Environment]::NewLine) }
Write-Host 'All PowerShell files parsed successfully.'

. (Join-Path $programDir 'lib\WiiLinkSource.ps1')

Write-Host '== Static transport surface validation =='
$sourceText = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiiLinkSource.ps1') -Raw
$unifiedText = Get-Content -LiteralPath (Join-Path $programDir 'MPH-Unified.ps1') -Raw
$standaloneText = Get-Content -LiteralPath (Join-Path $programDir 'WiiLink-PlayerList.ps1') -Raw
Assert-True ($sourceText -match "ValidateSet\('direct','browser'\)") 'WiiLink source must expose direct/browser transport validation.'
Assert-True ($sourceText -match 'Start-WiiLinkBrowser') 'WiiLink source must expose browser startup.'
Assert-True ($sourceText -match 'Get-WiiLinkBrowserText') 'WiiLink source must expose CDP browser fetch.'
Assert-True ($unifiedText -match 'New-WiiLinkTransportSelector') 'Unified viewer must contain the transport selector.'
Assert-True ($standaloneText -match 'New-WiiLinkTransportSelector') 'Standalone viewer must contain the transport selector.'

Write-Host '== Direct API integration test =='
$directLogs = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$direct = Get-WiiLinkData -Transport direct -Game 'mprimeds' -LogQueue $directLogs
Assert-True ($direct.transport -eq 'direct') 'Direct result must report direct transport.'
Assert-True (@('ok','empty','partial') -contains [string]$direct.state) ("Direct API returned unexpected state: {0}; error={1}" -f $direct.state, $direct.error)
Assert-True ($null -ne $direct.stats) 'Direct result must contain stats.'
Assert-True ($null -ne $direct.rooms) 'Direct result must contain rooms.'
Assert-True ($directLogs.Count -gt 0) 'Direct test must produce diagnostics.'
Write-Host ("Direct API passed: state={0}; rooms={1}; online={2}" -f $direct.state, @($direct.rooms).Count, $direct.stats.online)

Write-Host '== Chrome/Edge browser integration test =='
$browser = Start-WiiLinkBrowser
Assert-True ([bool]$browser.ok) ("Chrome/Edge failed to start: {0}" -f $browser.error)
try {
    $browserLogs = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $browserResult = $null
    $lastError = ''
    $deadline = (Get-Date).AddSeconds(45)
    do {
        try {
            $candidate = Get-WiiLinkData -Transport browser -BrowserPort ([int]$browser.port) -Game 'mprimeds' -LogQueue $browserLogs
            if ($candidate.ok) { $browserResult = $candidate; break }
            $lastError = [string]$candidate.error
        } catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 1000
    } while ((Get-Date) -lt $deadline)

    Assert-True ($null -ne $browserResult) ("Browser transport did not become ready: $lastError")
    Assert-True ($browserResult.transport -eq 'browser') 'Browser result must report browser transport.'
    Assert-True (@('ok','empty','partial') -contains [string]$browserResult.state) ("Browser transport returned unexpected state: {0}; error={1}" -f $browserResult.state, $browserResult.error)
    Assert-True ($browserLogs.Count -gt 0) 'Browser test must produce diagnostics.'
    Write-Host ("Browser transport passed: state={0}; rooms={1}; online={2}; browser={3}" -f $browserResult.state, @($browserResult.rooms).Count, $browserResult.stats.online, $browser.browser)
} finally {
    Stop-WiiLinkBrowser -Context $browser
}

Write-Host 'RESULT: SUCCESS'
