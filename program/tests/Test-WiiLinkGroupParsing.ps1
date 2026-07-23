$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $programDir 'lib\WiiLinkSource.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

Write-Host '== Empty object =='
$empty = @(ConvertFrom-WiiLinkGroupsJson -Json '{}')
Assert-True ($empty.Count -eq 0) 'An empty object must normalize to zero groups.'

Write-Host '== Empty array =='
$emptyArray = @(ConvertFrom-WiiLinkGroupsJson -Json '[]')
Assert-True ($emptyArray.Count -eq 0) 'An empty array must normalize to zero groups.'

Write-Host '== Top-level array =='
$arrayJson = '[{"id":"room-a","game":"mprimeds","type":"anybody","players":[]}]'
$arrayGroups = @(ConvertFrom-WiiLinkGroupsJson -Json $arrayJson)
Assert-True ($arrayGroups.Count -eq 1) 'A top-level array must preserve its group.'
Assert-True ([string]$arrayGroups[0].id -eq 'room-a') 'Top-level array group ID must be preserved.'
Assert-True ([string]$arrayGroups[0].game -eq 'mprimeds') 'Top-level array game ID must be preserved.'

Write-Host '== groups wrapper array =='
$wrapperJson = '{"groups":[{"id":"room-b","game":"mprimeds","type":"private","players":[]}],"updated":"2026-07-23T00:00:00Z"}'
$wrapperGroups = @(ConvertFrom-WiiLinkGroupsJson -Json $wrapperJson)
Assert-True ($wrapperGroups.Count -eq 1) 'A groups wrapper must expose its groups array.'
Assert-True ([string]$wrapperGroups[0].id -eq 'room-b') 'Wrapped group ID must be preserved.'

Write-Host '== ID-keyed object =='
$mapJson = '{"room-c":{"game":"mprimeds","type":"anybody","players":{}}}'
$mapGroups = @(ConvertFrom-WiiLinkGroupsJson -Json $mapJson)
Assert-True ($mapGroups.Count -eq 1) 'An ID-keyed object must normalize its group value.'
Assert-True ([string]$mapGroups[0].id -eq 'room-c') 'The map key must become the fallback group ID.'

Write-Host '== groups wrapper map and unrelated metadata =='
$wrapperMapJson = '{"groups":{"room-d":{"game":"mprimeds","players":{}},"metadata":{"count":1}},"server":"wiiLink"}'
$wrapperMapGroups = @(ConvertFrom-WiiLinkGroupsJson -Json $wrapperMapJson)
Assert-True ($wrapperMapGroups.Count -eq 1) 'Non-group metadata must be ignored safely.'
Assert-True ([string]$wrapperMapGroups[0].id -eq 'room-d') 'Wrapped map key must become the fallback group ID.'

Write-Host '== Single group object =='
$singleJson = '{"id":"room-e","game":"mprimeds","players":[]}'
$singleGroups = @(ConvertFrom-WiiLinkGroupsJson -Json $singleJson)
Assert-True ($singleGroups.Count -eq 1) 'A single group object must remain supported.'

Write-Host '== Missing optional properties =='
$minimal = $singleGroups[0]
Assert-True ([string](Get-WiiLinkPropertyValue -InputObject $minimal -Name 'missing' -DefaultValue 'fallback') -eq 'fallback') 'Missing properties must return their default values under StrictMode.'

Write-Host 'RESULT: SUCCESS'
