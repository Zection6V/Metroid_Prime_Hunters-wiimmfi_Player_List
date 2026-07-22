<#
    LogStore.ps1 — 診断ログの保存・集約・フィルタリング

    UI やデータ取得処理には依存しない。各ソースは専用 Queue に書き込み、
    UI スレッドが Receive-MphLogEntries で履歴へ取り込む。

    PowerShell では空の ICollection が条件式で $false と評価される。
    Queue / ArrayList の存在確認には必ず $null 比較を使い、Count=0 を
    「未初期化」と誤認しないこと。
#>

function New-MphLogStore {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [int]$MaxEntries = 2000
    )
    if ([string]::IsNullOrWhiteSpace($Source)) { throw 'Log source is required.' }
    if ($MaxEntries -lt 100) { $MaxEntries = 100 }

    $queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $entries = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    return [hashtable]::Synchronized(@{
            Source = $Source
            Queue = $queue
            Entries = $entries
            MaxEntries = $MaxEntries
            Version = 0
        })
}

function Write-MphLog {
    param(
        $Store,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [string]$Stage = '',
        [Parameter(Mandatory = $true)][string]$Message,
        [datetime]$Time = (Get-Date)
    )
    if ($null -eq $Store) { return }
    $queue = $Store.Queue
    if ($null -eq $queue) { return }

    $queue.Enqueue(@{
            time = $Time
            source = [string]$Store.Source
            level = $Level
            stage = $Stage
            message = $Message
        })
}

function Receive-MphLogEntries {
    param(
        [Parameter(Mandatory = $true)]$Store,
        [int]$MaxDrain = 500
    )
    if ($null -eq $Store) { return 0 }
    $queue = $Store.Queue
    $entries = $Store.Entries
    if ($null -eq $queue -or $null -eq $entries) { return 0 }
    if ($MaxDrain -lt 1) { return 0 }

    $drained = 0
    while ($drained -lt $MaxDrain -and $queue.Count -gt 0) {
        try { $raw = $queue.Dequeue() } catch { break }
        if ($null -eq $raw) { continue }

        $entryTime = Get-Date
        try { if ($null -ne $raw.time) { $entryTime = [datetime]$raw.time } } catch {}
        $source = [string]$raw.source
        if ([string]::IsNullOrWhiteSpace($source)) { $source = [string]$Store.Source }
        $level = ([string]$raw.level).ToUpperInvariant()
        if ($level -notin @('DEBUG', 'INFO', 'WARN', 'ERROR')) { $level = 'INFO' }

        [void]$entries.Add([pscustomobject][ordered]@{
                time = $entryTime
                source = $source
                level = $level
                stage = [string]$raw.stage
                message = [string]$raw.message
            })
        $drained++
    }

    $limit = [int]$Store.MaxEntries
    while ($entries.Count -gt $limit) { $entries.RemoveAt(0) }
    if ($drained -gt 0) { $Store.Version = [long]$Store.Version + $drained }
    return $drained
}

function Receive-MphLogStores {
    param(
        [Parameter(Mandatory = $true)][array]$Stores,
        [int]$MaxDrainPerStore = 500
    )
    $total = 0
    foreach ($store in @($Stores)) {
        if ($null -ne $store) { $total += Receive-MphLogEntries -Store $store -MaxDrain $MaxDrainPerStore }
    }
    return $total
}

function Get-MphLogEntries {
    param(
        [Parameter(Mandatory = $true)][array]$Stores,
        [string]$Source = 'All',
        [switch]$IncludeDebug
    )
    $result = New-Object System.Collections.ArrayList
    foreach ($store in @($Stores)) {
        if ($null -eq $store) { continue }
        if ($Source -ne 'All' -and -not ([string]$store.Source).Equals($Source, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $entries = $store.Entries
        if ($null -eq $entries) { continue }
        $snapshot = @($entries.ToArray())
        foreach ($entry in $snapshot) {
            if ($null -eq $entry) { continue }
            if (-not $IncludeDebug -and ([string]$entry.level).Equals('DEBUG', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            [void]$result.Add($entry)
        }
    }

    @($result | Sort-Object `
            @{ Expression = { try { [datetime]$_.time } catch { [datetime]::MinValue } } }, `
            @{ Expression = { [string]$_.source } }, `
            @{ Expression = { [string]$_.stage } })
}

function Clear-MphLogStore {
    param([Parameter(Mandatory = $true)]$Store)
    if ($null -eq $Store) { return }
    $queue = $Store.Queue
    $entries = $Store.Entries
    if ($null -ne $queue) { $queue.Clear() }
    if ($null -ne $entries) { $entries.Clear() }
    $Store.Version = [long]$Store.Version + 1
}

function Clear-MphLogStores {
    param(
        [Parameter(Mandatory = $true)][array]$Stores,
        [string]$Source = 'All'
    )
    foreach ($store in @($Stores)) {
        if ($null -eq $store) { continue }
        if ($Source -eq 'All' -or ([string]$store.Source).Equals($Source, [System.StringComparison]::OrdinalIgnoreCase)) {
            Clear-MphLogStore -Store $store
        }
    }
}
