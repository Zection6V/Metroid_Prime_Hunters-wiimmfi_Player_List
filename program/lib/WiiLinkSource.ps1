<#
    WiiLinkSource.ps1 — WiiLink WFC の情報取得ライブラリ（UI 非依存）

    Get-WiiLinkData は stats + groups を取得し、正規化データと診断状態を返す。
    Transport: direct / browser
    state: ok / empty / partial / error
#>

. (Join-Path $PSScriptRoot 'I18n.ps1')
. (Join-Path $PSScriptRoot 'PayloadLog.ps1')
. (Join-Path $PSScriptRoot 'ProxyHttp.ps1')
. (Join-Path $PSScriptRoot 'WiimmfiSource.ps1')

try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 } catch {}
try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls13 } catch {}

function Write-WiiLinkDiagnostic {
    param(
        $LogQueue,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level,
        [string]$Stage,
        [string]$Message
    )
    if ($null -eq $LogQueue) { return }
    try {
        $LogQueue.Enqueue(@{
                time = [datetime]::Now; source = 'WiiLink'; level = $Level; stage = $Stage; message = $Message
            })
    } catch {}
}

function Get-WiiLinkPropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$DefaultValue = $null
    )

    if ($null -eq $InputObject) { return $DefaultValue }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Add-WiiLinkGroupCandidate {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$List,
        [AllowNull()]$Candidate,
        [string]$FallbackId = ''
    )

    if ($null -eq $Candidate) { return }
    if ($Candidate -is [System.Array]) {
        foreach ($item in @($Candidate)) { Add-WiiLinkGroupCandidate -List $List -Candidate $item -FallbackId $FallbackId }
        return
    }

    if ($null -eq $Candidate.PSObject.Properties['game']) { return }
    if (-not [string]::IsNullOrWhiteSpace($FallbackId) -and $null -eq $Candidate.PSObject.Properties['id']) {
        try { $Candidate | Add-Member -NotePropertyName id -NotePropertyValue $FallbackId -Force } catch {}
    }
    [void]$List.Add($Candidate)
}

function ConvertFrom-WiiLinkGroupsJson {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        $LogQueue = $null
    )

    $root = $Json | ConvertFrom-Json
    $groups = New-Object System.Collections.ArrayList
    if ($null -eq $root) {
        Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'JSON' 'groups rootShape=null; normalizedCount=0'
        return @()
    }

    $container = $root
    $rootShape = if ($root -is [System.Array]) { 'array' } else { 'object' }
    if ($root -isnot [System.Array]) {
        $groupsProperty = $root.PSObject.Properties['groups']
        if ($null -ne $groupsProperty) {
            $container = $groupsProperty.Value
            $rootShape = 'wrapper.groups'
        }
    }

    if ($null -eq $container) {
        Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'JSON' ("groups rootShape={0}; normalizedCount=0" -f $rootShape)
        return @()
    }

    if ($container -is [System.Array]) {
        foreach ($candidate in @($container)) { Add-WiiLinkGroupCandidate -List $groups -Candidate $candidate }
    } elseif ($null -ne $container.PSObject.Properties['game']) {
        Add-WiiLinkGroupCandidate -List $groups -Candidate $container
    } else {
        foreach ($property in @($container.PSObject.Properties)) {
            Add-WiiLinkGroupCandidate -List $groups -Candidate $property.Value -FallbackId ([string]$property.Name)
        }
    }

    Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'JSON' ("groups rootShape={0}; normalizedCount={1}" -f $rootShape, $groups.Count)
    return @($groups.ToArray())
}

function Get-WiiLinkProxySettingLabel {
    $raw = ([string]$env:MPH_PROXY).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'auto' }
    $normalized = $raw.ToLowerInvariant()
    if ($normalized -in @('auto', 'direct', 'none', 'off', 'environment', 'env', 'system')) { return $normalized }
    $uri = $null
    if ([uri]::TryCreate($raw, [UriKind]::Absolute, [ref]$uri)) {
        return ('custom:{0}' -f (Get-MphSafeProxyLabel -ProxyUri $uri))
    }
    return 'invalid'
}

function Start-WiiLinkBrowser {
    param(
        [string]$Url = 'https://api.wfc.wiilink24.com/api/stats',
        $LogQueue = $null
    )
    Write-WiiLinkDiagnostic $LogQueue 'INFO' 'BROWSER' 'Starting Chrome/Edge transport'
    $browser = Find-Browser
    if (-not $browser) {
        Write-WiiLinkDiagnostic $LogQueue 'ERROR' 'BROWSER' 'Chrome/Edge was not found'
        return @{ ok = $false; error = 'no-browser' }
    }
    $port = Get-FreePort
    $profile = Join-Path $env:TEMP ("mph_wiilink_profile_{0}_{1}" -f $PID, $port)
    $args = @(
        "--remote-debugging-port=$port", "--user-data-dir=`"$profile`"",
        '--no-first-run', '--no-default-browser-check', '--disable-background-timer-throttling',
        '--disable-extensions', '--window-size=480,360', '--window-position=-32000,-32000', $Url
    )
    try {
        $proc = Start-Process -FilePath $browser -ArgumentList $args -PassThru -WindowStyle Minimized
        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'BROWSER' ("Browser started; pid={0}; port={1}; executable={2}" -f $proc.Id, $port, $browser)
        return @{ ok = $true; error = ''; proc = $proc; port = $port; browser = $browser; profile = $profile }
    } catch {
        Write-WiiLinkDiagnostic $LogQueue 'ERROR' 'BROWSER' ("Browser start failed: {0}" -f $_.Exception.Message)
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Stop-WiiLinkBrowser {
    param($Context, $LogQueue = $null)
    try {
        if ($Context -and $Context.proc -and -not $Context.proc.HasExited) {
            & taskkill /PID $Context.proc.Id /T /F 2>$null | Out-Null
            Write-WiiLinkDiagnostic $LogQueue 'INFO' 'BROWSER' ("Browser stopped; pid={0}" -f $Context.proc.Id)
        }
    } catch {
        Write-WiiLinkDiagnostic $LogQueue 'WARN' 'BROWSER' ("Browser stop failed: {0}" -f $_.Exception.Message)
    }
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
    return @{
        text = [string]$envelope.body; status = [int]$envelope.status
        bytes = [Text.Encoding]::UTF8.GetByteCount([string]$envelope.body)
        contentType = 'application/json (browser fetch)'; route = 'browser'; proxy = ''; timeoutSec = $TimeoutSec
    }
}

function Get-WiiLinkPayload {
    param(
        [ValidateSet('direct', 'browser')][string]$Transport,
        [string]$Url,
        [string]$Ua,
        [int]$BrowserPort = 0,
        $LogQueue = $null
    )
    if ($Transport -eq 'browser') {
        if ($BrowserPort -le 0) { throw 'browser-port-not-set' }
        return Get-WiiLinkBrowserText -Port $BrowserPort -Url $Url
    }

    $headers = @{
        'User-Agent' = $Ua
        'Accept' = 'application/json'
        'Accept-Encoding' = 'identity'
        'Cache-Control' = 'no-cache'
        'Pragma' = 'no-cache'
    }
    return Invoke-MphProxyHttpText -Url ([uri]$Url) -Headers $headers -LogQueue $LogQueue -Source 'WiiLink'
}

function Get-WiiLinkData {
    param(
        [string]$StatsUrl  = 'https://api.wfc.wiilink24.com/api/stats',
        [string]$GroupsUrl = 'https://api.wfc.wiilink24.com/api/groups',
        [string]$Game      = 'mprimeds',
        [string]$Ua        = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList',
        [string]$Lang      = (Get-MphLang),
        [ValidateSet('direct', 'browser')][string]$Transport = 'direct',
        [int]$BrowserPort = 0,
        $LogQueue = $null
    )
    $i = Get-MphI18n -Lang $Lang
    $result = @{
        ok = $false; state = 'error'; error = ''; transport = $Transport
        stats = @{ online = 0; active = 0; groups = 0 }
        rooms = @()
        diagnostics = @{
            availableGames = @(); matchedGroups = 0; players = 0
            proxySetting = (Get-WiiLinkProxySettingLabel); statsRoute = ''; groupsRoute = ''
        }
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-WiiLinkDiagnostic $LogQueue 'INFO' 'START' ("Update started; game={0}; transport={1}" -f $Game, $Transport)
    Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'ENV' ("PowerShell={0}; OS={1}; TLS={2}; browserPort={3}; proxySetting={4}" -f $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, [Net.ServicePointManager]::SecurityProtocol, $BrowserPort, $result.diagnostics.proxySetting)

    try {
        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'HTTP' ("Requesting stats API via {0}" -f $Transport)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $statsPayload = Get-WiiLinkPayload -Transport $Transport -Url $StatsUrl -Ua $Ua -BrowserPort $BrowserPort -LogQueue $LogQueue
        $watch.Stop()
        $result.diagnostics.statsRoute = [string]$statsPayload.route
        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'HTTP' ("stats completed; transport={0}; route={1}; HTTP={2}; bytes={3}; elapsedMs={4}" -f $Transport, $statsPayload.route, $statsPayload.status, $statsPayload.bytes, $watch.ElapsedMilliseconds)
        Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'HTTP' ("stats Content-Type={0}; proxy={1}; timeoutSec={2}" -f $statsPayload.contentType, $statsPayload.proxy, $statsPayload.timeoutSec)
        Write-MphPayloadLog -LogQueue $LogQueue -Source 'WiiLink' -Name 'stats.raw.json' -Content $statsPayload.text -ContentType $statsPayload.contentType

        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'HTTP' ("Requesting groups API via {0}" -f $Transport)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $groupsPayload = Get-WiiLinkPayload -Transport $Transport -Url $GroupsUrl -Ua $Ua -BrowserPort $BrowserPort -LogQueue $LogQueue
        $watch.Stop()
        $result.diagnostics.groupsRoute = [string]$groupsPayload.route
        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'HTTP' ("groups completed; transport={0}; route={1}; HTTP={2}; bytes={3}; elapsedMs={4}" -f $Transport, $groupsPayload.route, $groupsPayload.status, $groupsPayload.bytes, $watch.ElapsedMilliseconds)
        Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'HTTP' ("groups Content-Type={0}; proxy={1}; timeoutSec={2}" -f $groupsPayload.contentType, $groupsPayload.proxy, $groupsPayload.timeoutSec)
        Write-MphPayloadLog -LogQueue $LogQueue -Source 'WiiLink' -Name 'groups.raw.json' -Content $groupsPayload.text -ContentType $groupsPayload.contentType

        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'JSON' 'Parsing stats JSON'
        $s = $statsPayload.text | ConvertFrom-Json
        $statsProps = @($s.PSObject.Properties)
        $statsGame = $statsProps | Where-Object { ([string]$_.Name).Trim().ToLowerInvariant() -eq $Game.Trim().ToLowerInvariant() } | Select-Object -First 1
        if ($statsGame) {
            $sv = $statsGame.Value
            $result.stats = @{
                online = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'online' -DefaultValue 0)
                active = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'active' -DefaultValue 0)
                groups = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'groups' -DefaultValue 0)
            }
            Write-WiiLinkDiagnostic $LogQueue 'INFO' 'STATS' ("online={0}; active={1}; groups={2}" -f $result.stats.online, $result.stats.active, $result.stats.groups)
        } else {
            Write-WiiLinkDiagnostic $LogQueue 'WARN' 'STATS' ("Game key not found in stats; expected={0}; available={1}" -f $Game, (($statsProps.Name | Select-Object -First 30) -join ','))
        }

        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'JSON' 'Parsing and normalizing groups JSON'
        $all = @(ConvertFrom-WiiLinkGroupsJson -Json ([string]$groupsPayload.text) -LogQueue $LogQueue)
        $availableGames = @($all | ForEach-Object {
                $groupGame = ([string](Get-WiiLinkPropertyValue -InputObject $_ -Name 'game' -DefaultValue '')).Trim()
                if ($groupGame) { $groupGame }
            } | Sort-Object -Unique)
        $result.diagnostics.availableGames = $availableGames
        Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'JSON' ("groups normalizedCount={0}; gameIds={1}" -f $all.Count, ($availableGames -join ','))

        $gameNorm = $Game.Trim().ToLowerInvariant()
        $matched = @($all | Where-Object {
                ([string](Get-WiiLinkPropertyValue -InputObject $_ -Name 'game' -DefaultValue '')).Trim().ToLowerInvariant() -eq $gameNorm
            })
        $result.diagnostics.matchedGroups = $matched.Count
        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'FILTER' ("matchedGroups={0}; expectedGame={1}" -f $matched.Count, $Game)

        $rooms = @()
        $totalPlayers = 0
        foreach ($g in $matched) {
            $typeValue = [string](Get-WiiLinkPropertyValue -InputObject $g -Name 'type' -DefaultValue '')
            $typeLabel = if ($typeValue -eq 'private') { $i.wlFriends } elseif ($typeValue -eq 'anybody') { $i.wlPublic } else { $typeValue }
            $suspend = [bool](Get-WiiLinkPropertyValue -InputObject $g -Name 'suspend' -DefaultValue $false)
            $joinLabel = if ($suspend) { $i.wlNotJoinable } else { $i.wlJoinable }
            $created = [string](Get-WiiLinkPropertyValue -InputObject $g -Name 'created' -DefaultValue '')
            try { if ($created) { $created = ([datetime]$created).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } } catch {}
            $hostKey = [string](Get-WiiLinkPropertyValue -InputObject $g -Name 'host' -DefaultValue '')
            $roomId = [string](Get-WiiLinkPropertyValue -InputObject $g -Name 'id' -DefaultValue '')
            $playersValue = Get-WiiLinkPropertyValue -InputObject $g -Name 'players' -DefaultValue $null
            $players = @()
            $playerItems = @()
            if ($null -ne $playersValue) {
                if ($playersValue -is [System.Array]) {
                    Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'PLAYERS' ("room={0}; playersShape=array; count={1}" -f $roomId, @($playersValue).Count)
                    $idx = 0
                    foreach ($p in @($playersValue)) { $playerItems += @{ Key = [string]$idx; Value = $p }; $idx++ }
                } else {
                    $props = @($playersValue.PSObject.Properties | Sort-Object { try { [int]$_.Name } catch { [int]::MaxValue } })
                    Write-WiiLinkDiagnostic $LogQueue 'DEBUG' 'PLAYERS' ("room={0}; playersShape=object; count={1}" -f $roomId, $props.Count)
                    foreach ($pp in $props) { $playerItems += @{ Key = [string]$pp.Name; Value = $pp.Value } }
                }
            }
            foreach ($item in $playerItems) {
                $p = $item.Value
                if ($null -eq $p) { continue }
                $isHost = ($item.Key -eq $hostKey)
                $players += @{
                    name = [string](Get-WiiLinkPropertyValue -InputObject $p -Name 'name' -DefaultValue '')
                    fc = [string](Get-WiiLinkPropertyValue -InputObject $p -Name 'fc' -DefaultValue '')
                    pid = [string](Get-WiiLinkPropertyValue -InputObject $p -Name 'pid' -DefaultValue '')
                    role = (&{ if ($isHost) { $i.roleHost } else { $i.roleMember } })
                    connFail = [string](Get-WiiLinkPropertyValue -InputObject $p -Name 'conn_fail' -DefaultValue '')
                    isHost = $isHost
                }
            }
            $totalPlayers += $players.Count
            $hostName = $i.awaitingHost
            $hp = @($players | Where-Object { $_.isHost })
            if ($hp.Count -gt 0) { $hostName = $hp[0].name }
            $rooms += @{ id = $roomId; host = $hostName; type = $typeLabel; joinable = $joinLabel; created = $created; players = $players }
        }

        $result.rooms = $rooms
        $result.diagnostics.players = $totalPlayers
        if ($result.stats.groups -gt 0 -and $rooms.Count -eq 0) {
            $result.state = 'partial'; $result.ok = $true
            Write-WiiLinkDiagnostic $LogQueue 'WARN' 'VERIFY' ("stats groups={0}, but parsed rooms=0; availableGames={1}" -f $result.stats.groups, ($availableGames -join ','))
        } elseif ($rooms.Count -eq 0 -and $result.stats.online -eq 0 -and $result.stats.active -eq 0 -and $result.stats.groups -eq 0) {
            $result.state = 'empty'; $result.ok = $true
            Write-WiiLinkDiagnostic $LogQueue 'INFO' 'VERIFY' 'No online rooms or players reported'
        } else {
            $result.state = 'ok'; $result.ok = $true
            Write-WiiLinkDiagnostic $LogQueue 'INFO' 'VERIFY' ("rooms={0}; players={1}; consistency=ok" -f $rooms.Count, $totalPlayers)
        }
    } catch {
        $result.state = 'error'; $result.error = $_.Exception.Message
        Write-WiiLinkDiagnostic $LogQueue 'ERROR' 'EXCEPTION' ("{0}: {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message)
    } finally {
        $sw.Stop()
        Write-WiiLinkDiagnostic $LogQueue 'INFO' 'END' ("Update finished; state={0}; transport={1}; elapsedMs={2}" -f $result.state, $Transport, $sw.ElapsedMilliseconds)
    }
    return $result
}
