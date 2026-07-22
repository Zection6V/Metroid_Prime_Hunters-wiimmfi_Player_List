<#
    WiiLinkSource.ps1 — WiiLink WFC の情報取得ライブラリ（UI 非依存）

    Get-WiiLinkData は stats + groups を取得し、正規化データと診断状態を返す。
    Transport: direct / browser
    state: ok / empty / partial / error
#>

. (Join-Path $PSScriptRoot 'I18n.ps1')
. (Join-Path $PSScriptRoot 'WiimmfiSource.ps1')

try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 } catch {}
try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls13 } catch {}

# プロキシ自動検出(WPAD)が原因で HTTP がハング→タイムアウトする環境があるため、既定では
# プロキシを使わず直結する。プロキシが必要な場合は環境変数 MPH_PROXY を設定:
#   MPH_PROXY=system            … Windows のシステムプロキシ設定を使う
#   MPH_PROXY=http://host:port  … 指定プロキシを使う
try {
    if (-not $env:MPH_PROXY) { [System.Net.WebRequest]::DefaultWebProxy = $null }
    elseif ($env:MPH_PROXY -ne 'system') { [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($env:MPH_PROXY, $true) }
} catch {}

function Start-WiiLinkBrowser {
    param([string]$Url = 'https://api.wfc.wiilink24.com/api/stats')
    $browser = Find-Browser
    if (-not $browser) { return @{ ok = $false; error = 'no-browser' } }
    $port = Get-FreePort
    $profile = Join-Path $env:TEMP ("mph_wiilink_profile_{0}" -f $PID)
    $args = @(
        "--remote-debugging-port=$port", "--user-data-dir=`"$profile`"",
        '--no-first-run', '--no-default-browser-check', '--disable-background-timer-throttling',
        '--disable-extensions', '--window-size=480,360', '--window-position=-32000,-32000', $Url
    )
    try {
        $proc = Start-Process -FilePath $browser -ArgumentList $args -PassThru -WindowStyle Minimized
        return @{ ok = $true; proc = $proc; port = $port; browser = $browser; profile = $profile }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Stop-WiiLinkBrowser {
    param($Context)
    try { if ($Context -and $Context.proc -and -not $Context.proc.HasExited) { & taskkill /PID $Context.proc.Id /T /F 2>$null | Out-Null } } catch {}
    try { if ($Context -and $Context.profile -and (Test-Path $Context.profile)) { Remove-Item -LiteralPath $Context.profile -Recurse -Force -EA SilentlyContinue } } catch {}
}

function Get-WiiLinkBrowserText {
    param([int]$Port, [string]$Url, [int]$TimeoutSec = 20)
    $tabs = Invoke-RestMethod "http://127.0.0.1:$Port/json" -TimeoutSec 10
    $tab = $tabs | Where-Object { $_.type -eq 'page' -and $_.url -match 'wiilink24' } | Select-Object -First 1
    if (-not $tab) { throw 'browser-not-ready' }
    $safeUrl = $Url.Replace("'", "\'")
    $expr = "fetch('$safeUrl',{cache:'no-store',credentials:'omit'}).then(function(r){return r.text().then(function(t){return JSON.stringify({ok:r.ok,status:r.status,body:t})})}).catch(function(e){return JSON.stringify({ok:false,status:0,error:String(e)})})"
    $raw = Invoke-CdpEval -WsUrl $tab.webSocketDebuggerUrl -Expression $expr -TimeoutSec $TimeoutSec
    if (-not $raw) { throw 'browser-fetch-empty-result' }
    $envelope = $raw | ConvertFrom-Json
    if (-not $envelope.ok) {
        $msg = if ($envelope.error) { [string]$envelope.error } else { "HTTP $([int]$envelope.status)" }
        throw ("browser-fetch-failed: {0}" -f $msg)
    }
    return @{ text = [string]$envelope.body; status = [int]$envelope.status; bytes = [Text.Encoding]::UTF8.GetByteCount([string]$envelope.body); contentType = 'application/json (browser fetch)' }
}

function Get-WiiLinkPayload {
    param(
        [ValidateSet('direct','browser')][string]$Transport,
        [string]$Url,
        [string]$Ua,
        [int]$BrowserPort = 0
    )
    if ($Transport -eq 'browser') {
        if ($BrowserPort -le 0) { throw 'browser-port-not-set' }
        return Get-WiiLinkBrowserText -Port $BrowserPort -Url $Url
    }
    $h = @{ 'User-Agent' = $Ua; 'Accept' = 'application/json'; 'Accept-Encoding' = 'identity'; 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 -Headers $h
    $bytes = $r.RawContentStream.ToArray()
    return @{ text = [Text.Encoding]::UTF8.GetString($bytes); status = [int]$r.StatusCode; bytes = $bytes.Length; contentType = [string]$r.Headers['Content-Type'] }
}

function Get-WiiLinkData {
    param(
        [string]$StatsUrl  = 'https://api.wfc.wiilink24.com/api/stats',
        [string]$GroupsUrl = 'https://api.wfc.wiilink24.com/api/groups',
        [string]$Game      = 'mprimeds',
        [string]$Ua        = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList',
        [string]$Lang      = (Get-MphLang),
        [ValidateSet('direct','browser')][string]$Transport = 'direct',
        [int]$BrowserPort = 0,
        $LogQueue = $null
    )
    $i = Get-MphI18n -Lang $Lang
    $result = @{
        ok = $false; state = 'error'; error = ''; transport = $Transport
        stats = @{ online = 0; active = 0; groups = 0 }
        rooms = @(); diagnostics = @{ availableGames = @(); matchedGroups = 0; players = 0 }
    }
    function Add-WlLog([string]$Level, [string]$Stage, [string]$Message) {
        if (-not $LogQueue) { return }
        try { $LogQueue.Enqueue(@{ time = [datetime]::Now; source = 'WiiLink'; level = $Level; stage = $Stage; message = $Message }) } catch {}
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Add-WlLog 'INFO' 'START' ("Update started; game={0}; transport={1}" -f $Game, $Transport)
    Add-WlLog 'DEBUG' 'ENV' ("PowerShell={0}; OS={1}; TLS={2}; browserPort={3}" -f $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, [Net.ServicePointManager]::SecurityProtocol, $BrowserPort)

    try {
        Add-WlLog 'INFO' 'HTTP' ("Requesting stats API via {0}" -f $Transport)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $statsPayload = Get-WiiLinkPayload -Transport $Transport -Url $StatsUrl -Ua $Ua -BrowserPort $BrowserPort
        $watch.Stop()
        Add-WlLog 'INFO' 'HTTP' ("stats completed; transport={0}; HTTP={1}; bytes={2}; elapsedMs={3}" -f $Transport, $statsPayload.status, $statsPayload.bytes, $watch.ElapsedMilliseconds)
        Add-WlLog 'DEBUG' 'HTTP' ("stats Content-Type={0}" -f $statsPayload.contentType)

        Add-WlLog 'INFO' 'HTTP' ("Requesting groups API via {0}" -f $Transport)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $groupsPayload = Get-WiiLinkPayload -Transport $Transport -Url $GroupsUrl -Ua $Ua -BrowserPort $BrowserPort
        $watch.Stop()
        Add-WlLog 'INFO' 'HTTP' ("groups completed; transport={0}; HTTP={1}; bytes={2}; elapsedMs={3}" -f $Transport, $groupsPayload.status, $groupsPayload.bytes, $watch.ElapsedMilliseconds)
        Add-WlLog 'DEBUG' 'HTTP' ("groups Content-Type={0}" -f $groupsPayload.contentType)

        Add-WlLog 'INFO' 'JSON' 'Parsing stats JSON'
        $s = $statsPayload.text | ConvertFrom-Json
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
        $all = @($groupsPayload.text | ConvertFrom-Json)
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
        Add-WlLog 'INFO' 'END' ("Update finished; state={0}; transport={1}; elapsedMs={2}" -f $result.state, $Transport, $sw.ElapsedMilliseconds)
    }
    return $result
}
