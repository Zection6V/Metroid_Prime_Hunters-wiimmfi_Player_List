$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $programDir 'lib\WiiLinkSource.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

Write-Host '== Query construction =='
Assert-True ((Add-WiiLinkGameQuery -Url 'https://api.wfc.wiilink24.com/api/stats' -Game 'mprimeds') -eq 'https://api.wfc.wiilink24.com/api/stats?game=mprimeds') 'Stats URL must receive the game query.'
Assert-True ((Add-WiiLinkGameQuery -Url 'https://example.test/api?x=1' -Game 'mprimeds') -eq 'https://example.test/api?x=1&game=mprimeds') 'Existing query parameters must be preserved.'
Assert-True ((Add-WiiLinkGameQuery -Url 'https://example.test/api?game=other' -Game 'mprimeds') -eq 'https://example.test/api?game=other') 'An existing game query must not be duplicated.'

Write-Host '== Filtered response shapes =='
$script:RequestedUrls = New-Object System.Collections.ArrayList
function Get-WiiLinkPayload {
    param(
        [string]$Transport,
        [string]$Url,
        [string]$Ua,
        [int]$BrowserPort,
        $LogQueue
    )

    [void]$script:RequestedUrls.Add($Url)
    if ($Url -match '/stats\?game=mprimeds$') {
        $text = '{"online":1,"active":0,"groups":1}'
    } elseif ($Url -match '/groups\?game=mprimeds$') {
        $text = '[{"id":"room-1","host":"0","type":"anybody","suspend":false,"created":"2026-07-23T00:00:00Z","players":{"0":{"name":"Samus","fc":"0000-0000-0000","pid":1,"conn_fail":0},"1":{"name":"Trace","fc":"1111-1111-1111","pid":2,"conn_fail":0}}}]'
    } else {
        throw "Unexpected test URL: $Url"
    }

    return @{
        text = $text
        status = 200
        bytes = [Text.Encoding]::UTF8.GetByteCount($text)
        contentType = 'application/json'
        route = 'test'
        proxy = ''
        timeoutSec = 1
    }
}

$result = Get-WiiLinkData `
    -StatsUrl 'https://api.wfc.wiilink24.com/api/stats' `
    -GroupsUrl 'https://api.wfc.wiilink24.com/api/groups' `
    -Game 'mprimeds' `
    -Transport direct

Assert-True ($result.ok) ("Filtered response must parse successfully: {0}" -f $result.error)
Assert-True ($result.stats.online -eq 1 -and $result.stats.groups -eq 1) 'Filtered top-level stats object must be accepted.'
Assert-True (@($result.rooms).Count -eq 1) 'Filtered groups array must produce one room.'
Assert-True (@($result.rooms[0].players).Count -eq 2) 'Filtered group without a game property must inherit the requested game.'
Assert-True ($script:RequestedUrls.Count -eq 2) 'Exactly two filtered requests must be made.'
Assert-True ([string]$script:RequestedUrls[0] -eq 'https://api.wfc.wiilink24.com/api/stats?game=mprimeds') 'Stats request must be game-filtered.'
Assert-True ([string]$script:RequestedUrls[1] -eq 'https://api.wfc.wiilink24.com/api/groups?game=mprimeds') 'Groups request must be game-filtered.'
Assert-True ([string]$result.diagnostics.statsUrl -eq [string]$script:RequestedUrls[0]) 'Diagnostics must record the filtered stats URL.'
Assert-True ([string]$result.diagnostics.groupsUrl -eq [string]$script:RequestedUrls[1]) 'Diagnostics must record the filtered groups URL.'

Write-Host '== Legacy wrapper compatibility =='
$legacyStats = '{"mprimeds":{"online":2,"active":1,"groups":0}}'
$legacyGroups = '[]'
$script:RequestedUrls.Clear()
function Get-WiiLinkPayload {
    param([string]$Transport, [string]$Url, [string]$Ua, [int]$BrowserPort, $LogQueue)
    [void]$script:RequestedUrls.Add($Url)
    $text = if ($Url -match '/stats') { $legacyStats } else { $legacyGroups }
    return @{ text = $text; status = 200; bytes = $text.Length; contentType = 'application/json'; route = 'test'; proxy = ''; timeoutSec = 1 }
}
$legacy = Get-WiiLinkData -Game 'mprimeds' -Transport direct
Assert-True ($legacy.ok) 'Legacy game-wrapper stats must remain supported.'
Assert-True ($legacy.stats.online -eq 2 -and $legacy.stats.active -eq 1) 'Legacy stats values must be preserved.'

$source = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiiLinkSource.ps1') -Raw
Assert-True ($source -match "api/stats\?game=mprimeds") 'Browser startup page must be game-filtered.'
Assert-True ($source -match 'Add-WiiLinkGameQuery') 'Both transport paths must share the query builder.'

Write-Host 'RESULT: SUCCESS'
