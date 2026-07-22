<#
    WiiLinkSource.ps1 — WiiLink WFC の情報取得ライブラリ（UI 非依存）

    Get-WiiLinkData は stats + groups を取得し、正規化データと診断状態を返す。
    state: ok / empty / partial / error
#>

. (Join-Path $PSScriptRoot 'I18n.ps1')

try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 } catch {}
try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls13 } catch {}

function Get-WiiLinkData {
    param(
        [string]$StatsUrl  = 'https://api.wfc.wiilink24.com/api/stats',
        [string]$GroupsUrl = 'https://api.wfc.wiilink24.com/api/groups',
        [string]$Game      = 'mprimeds',
        [string]$Ua        = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList',
        [string]$Lang      = (Get-MphLang),
        $LogQueue = $null
    )
    $i = Get-MphI18n -Lang $Lang
    $result = @{
        ok = $false; state = 'error'; error = ''
        stats = @{ online = 0; active = 0; groups = 0 }
        rooms = @(); diagnostics = @{ availableGames = @(); matchedGroups = 0; players = 0 }
    }
    function Add-WlLog([string]$Level, [string]$Stage, [string]$Message) {
        if (-not $LogQueue) { return }
        try { $LogQueue.Enqueue(@{ time = [datetime]::Now; source = 'WiiLink'; level = $Level; stage = $Stage; message = $Message }) } catch {}
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Add-WlLog 'INFO' 'START' ("Update started; game={0}" -f $Game)
    Add-WlLog 'DEBUG' 'ENV' ("PowerShell={0}; OS={1}; TLS={2}" -f $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, [System.Net.ServicePointManager]::SecurityProtocol)

    try {
        $h = @{ 'User-Agent' = $Ua; 'Accept' = 'application/json'; 'Accept-Encoding' = 'identity'; 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }

        Add-WlLog 'INFO' 'HTTP' 'Requesting stats API'
        $statsWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $rs = Invoke-WebRequest -Uri $StatsUrl -UseBasicParsing -TimeoutSec 15 -Headers $h
        $statsWatch.Stop()
        $statsBytes = $rs.RawContentStream.ToArray()
        Add-WlLog 'INFO' 'HTTP' ("stats completed; HTTP={0}; bytes={1}; elapsedMs={2}" -f [int]$rs.StatusCode, $statsBytes.Length, $statsWatch.ElapsedMilliseconds)
        Add-WlLog 'DEBUG' 'HTTP' ("stats Content-Type={0}" -f [string]$rs.Headers['Content-Type'])

        Add-WlLog 'INFO' 'HTTP' 'Requesting groups API'
        $groupsWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $rg = Invoke-WebRequest -Uri $GroupsUrl -UseBasicParsing -TimeoutSec 15 -Headers $h
        $groupsWatch.Stop()
        $groupsBytes = $rg.RawContentStream.ToArray()
        Add-WlLog 'INFO' 'HTTP' ("groups completed; HTTP={0}; bytes={1}; elapsedMs={2}" -f [int]$rg.StatusCode, $groupsBytes.Length, $groupsWatch.ElapsedMilliseconds)
        Add-WlLog 'DEBUG' 'HTTP' ("groups Content-Type={0}" -f [string]$rg.Headers['Content-Type'])

        $statsJson = [System.Text.Encoding]::UTF8.GetString($statsBytes)
        $groupsJson = [System.Text.Encoding]::UTF8.GetString($groupsBytes)

        Add-WlLog 'INFO' 'JSON' 'Parsing stats JSON'
        $s = $statsJson | ConvertFrom-Json
        $statsProps = @($s.PSObject.Properties)
        $statsGame = $statsProps | Where-Object { ([string]$_.Name).Trim().ToLowerInvariant() -eq $Game.Trim().ToLowerInvariant() } | Select-Object -First 1
        if ($statsGame) {
            $sv = $statsGame.Value
            $result.stats = @{ online = [int]$sv.online; active = [int]$sv.active; groups = [int]$sv.groups }
            Add-WlLog 'INFO' 'STATS' ("online={0}; active={1}; groups={2}" -f $result.stats.online, $result.stats.active, $result.stats.groups)
        } else {
            Add-WlLog 'WARN' 'STATS' ("Game key not found in stats; expected={0}; available={1}" -f $Game, (($statsProps.Name | Select-Object -First 30) -join ','))
        }

        Add-WlLog 'INFO' 'JSON' 'Parsing groups JSON'
        $all = @($groupsJson | ConvertFrom-Json)
        $availableGames = @($all | ForEach-Object { ([string]$_.game).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        $result.diagnostics.availableGames = $availableGames
        Add-WlLog 'DEBUG' 'JSON' ("groups rootCount={0}; gameIds={1}" -f $all.Count, ($availableGames -join ','))

        $gameNorm = $Game.Trim().ToLowerInvariant()
        $matched = @($all | Where-Object { ([string]$_.game).Trim().ToLowerInvariant() -eq $gameNorm })
        $result.diagnostics.matchedGroups = $matched.Count
        Add-WlLog 'INFO' 'FILTER' ("matchedGroups={0}; expectedGame={1}" -f $matched.Count, $Game)

        $rooms = @()
        $totalPlayers = 0
        foreach ($g in $matched) {
            $typeLabel = if ($g.type -eq 'private') { $i.wlFriends } elseif ($g.type -eq 'anybody') { $i.wlPublic } else { [string]$g.type }
            $joinLabel = if ($g.suspend) { $i.wlNotJoinable } else { $i.wlJoinable }
            $created = [string]$g.created
            try { $created = ([datetime]$g.created).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } catch {}

            $hostKey = [string]$g.host
            $players = @()
            $playerItems = @()
            if ($null -ne $g.players) {
                if ($g.players -is [System.Array]) {
                    Add-WlLog 'DEBUG' 'PLAYERS' ("room={0}; playersShape=array; count={1}" -f [string]$g.id, @($g.players).Count)
                    $idx = 0
                    foreach ($p in @($g.players)) { $playerItems += @{ Key = [string]$idx; Value = $p }; $idx++ }
                } else {
                    $props = @($g.players.PSObject.Properties | Sort-Object { try { [int]$_.Name } catch { [int]::MaxValue } })
                    Add-WlLog 'DEBUG' 'PLAYERS' ("room={0}; playersShape=object; count={1}" -f [string]$g.id, $props.Count)
                    foreach ($pp in $props) { $playerItems += @{ Key = [string]$pp.Name; Value = $pp.Value } }
                }
            }
            foreach ($item in $playerItems) {
                $p = $item.Value
                $isHost = ($item.Key -eq $hostKey)
                $players += @{
                    name = [string]$p.name; fc = [string]$p.fc; pid = [string]$p.pid
                    role = (&{ if ($isHost) { $i.roleHost } else { $i.roleMember } }); connFail = [string]$p.conn_fail; isHost = $isHost
                }
            }
            $totalPlayers += $players.Count
            $hostName = $i.awaitingHost
            $hp = @($players | Where-Object { $_.isHost })
            if ($hp.Count -gt 0) { $hostName = $hp[0].name }
            $rooms += @{ id = [string]$g.id; host = $hostName; type = $typeLabel; joinable = $joinLabel; created = $created; players = $players }
        }

        $result.rooms = $rooms
        $result.diagnostics.players = $totalPlayers
        if ($result.stats.groups -gt 0 -and $rooms.Count -eq 0) {
            $result.state = 'partial'; $result.ok = $true
            Add-WlLog 'WARN' 'VERIFY' ("stats groups={0}, but parsed rooms=0; availableGames={1}" -f $result.stats.groups, ($availableGames -join ','))
        } elseif ($rooms.Count -eq 0 -and $result.stats.online -eq 0 -and $result.stats.active -eq 0 -and $result.stats.groups -eq 0) {
            $result.state = 'empty'; $result.ok = $true
            Add-WlLog 'INFO' 'VERIFY' 'No online rooms or players reported'
        } else {
            $result.state = 'ok'; $result.ok = $true
            Add-WlLog 'INFO' 'VERIFY' ("rooms={0}; players={1}; consistency=ok" -f $rooms.Count, $totalPlayers)
        }
    } catch {
        $result.state = 'error'; $result.error = $_.Exception.Message
        Add-WlLog 'ERROR' 'EXCEPTION' ("{0}: {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message)
    } finally {
        $sw.Stop()
        Add-WlLog 'INFO' 'END' ("Update finished; state={0}; elapsedMs={1}" -f $result.state, $sw.ElapsedMilliseconds)
    }
    return $result
}