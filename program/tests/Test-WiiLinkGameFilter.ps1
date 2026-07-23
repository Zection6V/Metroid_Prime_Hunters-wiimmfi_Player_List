$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $programDir 'lib\WiiLinkSource.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-TestPayload {
    param([Parameter(Mandatory = $true)][string]$Text)
    return @{
        text = $Text
        status = 200
        bytes = [Text.Encoding]::UTF8.GetByteCount($Text)
        contentType = 'application/json'
        route = 'test'
        proxy = ''
        timeoutSec = 1
    }
}

Write-Host '== Query construction =='
Assert-True ((Add-WiiLinkGameQuery -Url 'https://api.wfc.wiilink24.com/api/stats' -Game 'mprimeds') -eq 'https://api.wfc.wiilink24.com/api/stats?game=mprimeds') 'Stats URL must receive the game query.'
Assert-True ((Add-WiiLinkGameQuery -Url 'https://example.test/api?x=1' -Game 'mprimeds') -eq 'https://example.test/api?x=1&game=mprimeds') 'Existing query parameters must be preserved.'
Assert-True ((Add-WiiLinkGameQuery -Url 'https://example.test/api?game=other' -Game 'mprimeds') -eq 'https://example.test/api?game=other') 'An existing game query must not be duplicated.'

Write-Host '== Actual filtered API response shape =='
$script:RequestedUrls = New-Object System.Collections.ArrayList
function Get-WiiLinkPayload {
    param([string]$Transport, [string]$Url, [string]$Ua, [int]$BrowserPort, $LogQueue)

    [void]$script:RequestedUrls.Add($Url)
    if ($Url -match '/stats\?game=mprimeds$') {
        $text = '{"global":{"online":7,"active":7,"groups":2},"mprimeds":{"online":2,"active":2,"groups":1}}'
    } elseif ($Url -match '/groups\?game=mprimeds$') {
        $text = '[{"id":"room-1","game":"mprimeds","created":"2026-07-23T05:05:29Z","type":"private","suspend":true,"host":"0","players":{"0":{"pid":"1000000001","name":"Player One","conn_map":"0","conn_fail":"0","fc":"0000-0000-0000"},"1":{"pid":"1000000002","name":"Player Two","conn_map":"1","conn_fail":"0","fc":"1111-1111-1111"}}}]'
    } else {
        throw "Unexpected test URL: $Url"
    }
    return New-TestPayload -Text $text
}

$result = Get-WiiLinkData `
    -StatsUrl 'https://api.wfc.wiilink24.com/api/stats' `
    -GroupsUrl 'https://api.wfc.wiilink24.com/api/groups' `
    -Game 'mprimeds' `
    -Transport direct

Assert-True ($result.ok) ("Actual filtered response must parse successfully: {0}" -f $result.error)
Assert-True ($result.stats.online -eq 2 -and $result.stats.active -eq 2 -and $result.stats.groups -eq 1) 'The mprimeds stats entry must be selected instead of global.'
Assert-True (@($result.rooms).Count -eq 1) 'The filtered groups array must produce one room.'
Assert-True (@($result.rooms[0].players).Count -eq 2) 'The filtered room must preserve both players.'
Assert-True ($result.diagnostics.matchedGroups -eq 1) 'Exactly one mprimeds group must match.'
Assert-True (@($result.diagnostics.availableGames) -contains 'mprimeds') 'The game field returned by the filtered groups endpoint must be recognized.'
Assert-True ($script:RequestedUrls.Count -eq 2) 'Exactly two filtered requests must be made.'
Assert-True ([string]$script:RequestedUrls[0] -eq 'https://api.wfc.wiilink24.com/api/stats?game=mprimeds') 'Stats request must be game-filtered.'
Assert-True ([string]$script:RequestedUrls[1] -eq 'https://api.wfc.wiilink24.com/api/groups?game=mprimeds') 'Groups request must be game-filtered.'
Assert-True ([string]$result.diagnostics.statsUrl -eq [string]$script:RequestedUrls[0]) 'Diagnostics must record the filtered stats URL.'
Assert-True ([string]$result.diagnostics.groupsUrl -eq [string]$script:RequestedUrls[1]) 'Diagnostics must record the filtered groups URL.'

Write-Host '== Alternate filtered-object compatibility =='
$script:RequestedUrls.Clear()
function Get-WiiLinkPayload {
    param([string]$Transport, [string]$Url, [string]$Ua, [int]$BrowserPort, $LogQueue)
    [void]$script:RequestedUrls.Add($Url)
    if ($Url -match '/stats') {
        return New-TestPayload -Text '{"online":1,"active":0,"groups":1}'
    }
    return New-TestPayload -Text '[{"id":"room-2","host":"0","type":"anybody","suspend":false,"created":"2026-07-23T00:00:00Z","players":{"0":{"name":"Samus","fc":"0000-0000-0000","pid":1,"conn_fail":0},"1":{"name":"Trace","fc":"1111-1111-1111","pid":2,"conn_fail":0}}}]'
}

$alternate = Get-WiiLinkData -Game 'mprimeds' -Transport direct
Assert-True ($alternate.ok) 'A direct top-level stats object must remain supported.'
Assert-True ($alternate.stats.online -eq 1 -and $alternate.stats.groups -eq 1) 'Direct top-level stats values must be preserved.'
Assert-True (@($alternate.rooms).Count -eq 1) 'A filtered group without game must still be accepted.'
Assert-True (@($alternate.rooms[0].players).Count -eq 2) 'A filtered group without game must inherit the requested game.'

Write-Host '== Legacy wrapper compatibility =='
$script:RequestedUrls.Clear()
function Get-WiiLinkPayload {
    param([string]$Transport, [string]$Url, [string]$Ua, [int]$BrowserPort, $LogQueue)
    [void]$script:RequestedUrls.Add($Url)
    if ($Url -match '/stats') {
        return New-TestPayload -Text '{"mprimeds":{"online":2,"active":1,"groups":0}}'
    }
    return New-TestPayload -Text '[]'
}

$legacy = Get-WiiLinkData -Game 'mprimeds' -Transport direct
Assert-True ($legacy.ok) 'Legacy game-wrapper stats must remain supported.'
Assert-True ($legacy.stats.online -eq 2 -and $legacy.stats.active -eq 1) 'Legacy stats values must be preserved.'

$source = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiiLinkSource.ps1') -Raw
Assert-True ($source -match "api/stats\?game=mprimeds") 'Browser startup page must be game-filtered.'
Assert-True ($source -match 'Add-WiiLinkGameQuery') 'Both transport paths must share the query builder.'

Write-Host 'RESULT: SUCCESS'
