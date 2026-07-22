$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $programDir 'lib\LogStore.ps1')
. (Join-Path $programDir 'lib\WiimmfiSource.ps1')
. (Join-Path $programDir 'lib\WiiLinkSource.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

Write-Host '== Empty Queue regression test =='
$store = New-MphLogStore -Source 'App'
Assert-True ($null -ne $store.Queue) 'A new store must expose a Queue object.'
Assert-True ($null -ne $store.Entries) 'A new store must expose an Entries object.'
Assert-True ($store.Queue.Count -eq 0) 'A new Queue must start empty.'
Assert-True ($store.Entries.Count -eq 0) 'A new history must start empty.'

Write-MphLog -Store $store -Level INFO -Stage 'TEST' -Message 'first-entry'
Assert-True ($store.Queue.Count -eq 1) 'Write-MphLog must write the first entry into an empty Queue.'
Assert-True ((Receive-MphLogEntries -Store $store) -eq 1) 'Receive-MphLogEntries must drain into an empty history.'
Assert-True ($store.Queue.Count -eq 0) 'Queue must be empty after draining.'
Assert-True ($store.Entries.Count -eq 1) 'History must contain the drained first entry.'
$storedEntry = $store.Entries[0]
Assert-True (([string]$storedEntry.message) -eq 'first-entry') 'The first log message must be preserved.'

Write-Host '== Source emitter regression test =='
$wiimmfiQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$wiiLinkQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
Assert-True ($wiimmfiQueue.Count -eq 0 -and $wiiLinkQueue.Count -eq 0) 'Source queues must start empty.'

Write-WiimmfiDiagnostic -LogQueue $wiimmfiQueue -Level INFO -Stage 'TEST' -Message 'wiimmfi-first'
Write-WiiLinkDiagnostic -LogQueue $wiiLinkQueue -Level INFO -Stage 'TEST' -Message 'wiilink-first'
Assert-True ($wiimmfiQueue.Count -eq 1) 'Wiimmfi must emit its first event into an empty Queue.'
Assert-True ($wiiLinkQueue.Count -eq 1) 'WiiLink must emit its first event into an empty Queue.'
$wiimmfiEntry = $wiimmfiQueue.Peek()
$wiiLinkEntry = $wiiLinkQueue.Peek()
Assert-True (([string]$wiimmfiEntry.source) -eq 'Wiimmfi') 'Wiimmfi event source must be normalized.'
Assert-True (([string]$wiiLinkEntry.source) -eq 'WiiLink') 'WiiLink event source must be normalized.'

Write-Host '== Null dependency behavior =='
Write-MphLog -Store $null -Message 'ignored'
Write-WiimmfiDiagnostic -LogQueue $null -Level INFO -Stage 'TEST' -Message 'ignored'
Write-WiiLinkDiagnostic -LogQueue $null -Level INFO -Stage 'TEST' -Message 'ignored'
Assert-True ((Receive-MphLogEntries -Store $null) -eq 0) 'A null store must be ignored safely.'

Write-Host 'RESULT: SUCCESS'
