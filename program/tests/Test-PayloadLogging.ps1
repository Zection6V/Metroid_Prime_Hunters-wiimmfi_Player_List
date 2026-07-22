$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $programDir 'lib\PayloadLog.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Read-AllQueueItems {
    param($Queue)
    $items = @()
    while ($Queue.Count -gt 0) { $items += , $Queue.Dequeue() }
    return , $items
}

function Get-PayloadBody {
    param([string]$Message)
    $separator = "`r`n"
    $index = $Message.IndexOf($separator, [System.StringComparison]::Ordinal)
    if ($index -lt 0) { return '' }
    return $Message.Substring($index + $separator.Length)
}

Write-Host '== Payload chunking and reconstruction =='
$queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$content = '{"value":"' + ('abc123' * 300) + '"}'
Write-MphPayloadLog -LogQueue $queue -Source 'WiiLink' -Name 'test.raw.json' -Content $content -ContentType 'application/json' -ChunkChars 512 -MaxChars 0
$items = @(Read-AllQueueItems -Queue $queue)
Assert-True ($items.Count -gt 2) 'Large payload must produce metadata and multiple payload chunks.'
Assert-True ([string]$items[0].message -match 'name=test\.raw\.json') 'Metadata must identify the payload.'
Assert-True ([string]$items[0].message -match 'contentType=application/json') 'Metadata must preserve Content-Type.'
$chunks = @($items | Where-Object { [string]$_.message -match '^test\.raw\.json payload \[' })
$reconstructed = (($chunks | ForEach-Object { Get-PayloadBody -Message ([string]$_.message) }) -join '')
Assert-True ($reconstructed -ceq $content) 'Chunked payload must reconstruct to the exact original content.'
Assert-True ((@($items | Where-Object { [string]$_.level -eq 'WARN' })).Count -eq 0) 'Unlimited payload logging must not report truncation.'

Write-Host '== Payload truncation =='
$queue.Clear()
Write-MphPayloadLog -LogQueue $queue -Source 'Wiimmfi' -Name 'wiimmfi.text.raw' -Content '0123456789ABCDEFGHIJ' -ContentType 'text/plain' -ChunkChars 512 -MaxChars 10
$truncatedItems = @(Read-AllQueueItems -Queue $queue)
$truncatedChunks = @($truncatedItems | Where-Object { [string]$_.message -match '^wiimmfi\.text\.raw payload \[' })
$truncatedBody = (($truncatedChunks | ForEach-Object { Get-PayloadBody -Message ([string]$_.message) }) -join '')
Assert-True ($truncatedBody -ceq '0123456789') 'Payload body must respect the configured maximum.'
Assert-True ((@($truncatedItems | Where-Object { [string]$_.level -eq 'WARN' -and [string]$_.message -match 'truncated' })).Count -eq 1) 'Truncation must be explicit in the log.'

Write-Host '== Empty and null payloads =='
$queue.Clear()
Write-MphPayloadLog -LogQueue $queue -Source 'WiiLink' -Name 'empty.raw.json' -Content '' -MaxChars 0
$emptyItems = @(Read-AllQueueItems -Queue $queue)
Assert-True ((@($emptyItems | Where-Object { [string]$_.message -eq 'empty.raw.json payload [empty]' })).Count -eq 1) 'An empty response must be logged explicitly.'
$queue.Clear()
Write-MphPayloadLog -LogQueue $queue -Source 'WiiLink' -Name 'null.raw.json' -Content $null -MaxChars 0
$nullItems = @(Read-AllQueueItems -Queue $queue)
$nullChunk = @($nullItems | Where-Object { [string]$_.message -match '^null\.raw\.json payload \[' } | Select-Object -First 1)
Assert-True ($nullChunk.Count -eq 1) 'A null response must produce one payload chunk.'
Assert-True ((Get-PayloadBody -Message ([string]$nullChunk[0].message)) -ceq '<null>') 'A null response must be represented explicitly.'

Write-Host '== Environment limit parsing =='
$oldLimit = $env:MPH_LOG_PAYLOAD_MAX_CHARS
try {
    $env:MPH_LOG_PAYLOAD_MAX_CHARS = '12345'
    Assert-True ((Get-MphPayloadLogMaxChars) -eq 12345) 'Positive environment limit must be applied.'
    $env:MPH_LOG_PAYLOAD_MAX_CHARS = '0'
    Assert-True ((Get-MphPayloadLogMaxChars) -eq 0) 'Zero must enable unlimited payload logging.'
    $env:MPH_LOG_PAYLOAD_MAX_CHARS = 'invalid'
    Assert-True ((Get-MphPayloadLogMaxChars -DefaultMaxChars 777) -eq 777) 'Invalid environment limit must fall back safely.'
} finally {
    $env:MPH_LOG_PAYLOAD_MAX_CHARS = $oldLimit
}

Write-Host '== Source integration surface =='
$wiimmfiSource = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiimmfiSource.ps1') -Raw
$wiiLinkSource = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiiLinkSource.ps1') -Raw
Assert-True ($wiimmfiSource -match "Name 'wiimmfi\.text\.raw'") 'Wiimmfi must log the fetched text body.'
Assert-True ($wiiLinkSource -match "Name 'stats\.raw\.json'") 'WiiLink must log the fetched stats JSON.'
Assert-True ($wiiLinkSource -match "Name 'groups\.raw\.json'") 'WiiLink must log the fetched groups JSON.'
Assert-True ($wiiLinkSource.IndexOf("Name 'stats.raw.json'", [System.StringComparison]::Ordinal) -lt $wiiLinkSource.IndexOf('Parsing stats JSON', [System.StringComparison]::Ordinal)) 'Stats payload must be logged before JSON parsing.'
Assert-True ($wiiLinkSource.IndexOf("Name 'groups.raw.json'", [System.StringComparison]::Ordinal) -lt $wiiLinkSource.IndexOf('Parsing groups JSON', [System.StringComparison]::Ordinal)) 'Groups payload must be logged before JSON parsing.'

Write-Host 'RESULT: SUCCESS'
