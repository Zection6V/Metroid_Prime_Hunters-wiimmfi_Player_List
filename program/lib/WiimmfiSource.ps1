<#
    WiimmfiSource.ps1 — Wiimmfi の情報取得ライブラリ（UI 非依存）

    Chrome/Edge を CDP 経由で操作し、Cloudflare 通過後の軽量 text
    エンドポイントを取得・解析する。診断イベントは注入された Queue にのみ出力する。
#>

$script:WiimmfiDefaultUrl = 'https://wiimmfi.de/stats/game/mprimeds'
$script:WiimmfiTextUrl = 'https://wiimmfi.de/stats/game/mprimeds/text'

. (Join-Path $PSScriptRoot 'I18n.ps1')

function Write-WiimmfiDiagnostic {
    param(
        $LogQueue,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level,
        [string]$Stage,
        [string]$Message
    )
    if (-not $LogQueue) { return }
    try {
        $LogQueue.Enqueue(@{
                time = [datetime]::Now
                source = 'Wiimmfi'
                level = $Level
                stage = $Stage
                message = $Message
            })
    } catch {}
}

function Find-Browser {
    $cands = @(
        (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -EA SilentlyContinue).'(default)',
        (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -EA SilentlyContinue).'(default)',
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -EA SilentlyContinue).'(default)',
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Get-FreePort {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $p = $l.LocalEndpoint.Port; $l.Stop(); return $p
}

function Invoke-CdpEval {
    param([string]$WsUrl, [string]$Expression, [int]$TimeoutSec = 20)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource ([TimeSpan]::FromSeconds($TimeoutSec))
    $ct = $cts.Token
    try {
        $ws.ConnectAsync([Uri]$WsUrl, $ct).Wait()
        $payload = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expression; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Depth 6 -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
        $ws.SendAsync([ArraySegment[byte]]::new($bytes), 'Text', $true, $ct).Wait()
        $sb = New-Object Text.StringBuilder
        $buf = New-Object byte[] 131072
        do {
            $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct); $r.Wait()
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count))
        } while (-not $r.Result.EndOfMessage)
        return (($sb.ToString() | ConvertFrom-Json).result.result.value)
    } finally {
        try { $ws.Dispose() } catch {}
        try { $cts.Dispose() } catch {}
    }
}

function Get-WiimmfiText {
    param(
        [int]$Port,
        [string]$TextUrl = $script:WiimmfiTextUrl,
        $LogQueue = $null
    )
    try {
        $tabs = Invoke-RestMethod "http://127.0.0.1:$Port/json" -TimeoutSec 10
        $tab = $tabs | Where-Object { $_.type -eq 'page' -and $_.url -match 'wiimmfi' } | Select-Object -First 1
        if (-not $tab) {
            Write-WiimmfiDiagnostic $LogQueue 'DEBUG' 'CDP' 'Wiimmfi page target is not ready'
            return $null
        }

        $expr = "fetch('$TextUrl',{cache:'no-store'}).then(function(r){return r.text()})"
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $txt = Invoke-CdpEval -WsUrl $tab.webSocketDebuggerUrl -Expression $expr
        $watch.Stop()
        if ($null -eq $txt) {
            Write-WiimmfiDiagnostic $LogQueue 'DEBUG' 'FETCH' 'CDP fetch returned no value'
            return $null
        }
        if ($txt -match 'Just a moment' -or $txt -match '(?i)<html') {
            Write-WiimmfiDiagnostic $LogQueue 'DEBUG' 'CLOUDFLARE' 'Cloudflare challenge is still active'
            return $null
        }

        $bytes = [Text.Encoding]::UTF8.GetByteCount([string]$txt)
        Write-WiimmfiDiagnostic $LogQueue 'INFO' 'FETCH' ("text endpoint completed; bytes={0}; elapsedMs={1}" -f $bytes, $watch.ElapsedMilliseconds)
        return [string]$txt
    } catch {
        Write-WiimmfiDiagnostic $LogQueue 'WARN' 'FETCH' ("{0}: {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message)
        return $null
    }
}

function Parse-WiimmfiText {
    param([string]$Text)
    $players = @()
    foreach ($line in ($Text -split "`n")) {
        $line = $line.TrimEnd("`r")
        if (-not $line.StartsWith('|')) { continue }
        $parts = $line -split '\|'
        if ($parts.Count -ge 13) { $players += , ($parts[1..12]) }
    }
    return , $players
}

function ConvertTo-WiimmfiPlayer {
    param($p, [string]$Lang = (Get-MphLang))
    $i = Get-MphI18n -Lang $Lang
    $res = [ordered]@{
        Name = [string]$p[10]; Fc = [string]$p[2]; OnlineStatus = ''; PlayerStatus = ''
        JoinPlayers = ''; GameInfo = ''; NumPlayers = ''; ShowFriends = $false; ShowRivals = $false
    }
    $ls = [string]$p[5]
    $v = $ls; while ($v.Length -lt 7) { $v = '0' + $v }; if ($v.Length -lt 8) { $v = '1' + $v }
    $d = $v.ToCharArray()
    switch ("$($d[0])") { '1' { $res.NumPlayers = '1' } '2' { $res.NumPlayers = '2' } '4' { $res.NumPlayers = '3' } '6' { $res.NumPlayers = '4' } }
    if ($i.mode.ContainsKey("$($d[1])")) { $res.GameInfo = $i.mode["$($d[1])"] }
    $rivals = ("$($d[6])" -eq '1'); $friends = ("$($d[7])" -eq '8')
    $res.ShowRivals = $rivals; $res.ShowFriends = $friends
    if ($rivals -and $friends) { $res.JoinPlayers = $i.joinBoth }
    elseif ($rivals) { $res.JoinPlayers = $i.joinRivals }
    elseif ($friends) { $res.JoinPlayers = $i.joinFriends }

    $ol = [string]$p[6]
    if ($ol) {
        $parts = foreach ($ch in $ol.ToCharArray()) { $k = [string]$ch; if ($i.olStat.ContainsKey($k)) { $i.olStat[$k] } else { $k } }
        $res.OnlineStatus = ($parts -join '＋')
    }
    $st = [string]$p[7]
    if ($i.status.ContainsKey($st)) { $res.PlayerStatus = $i.status[$st] } elseif ($st) { $res.PlayerStatus = $st }
    return $res
}

function Start-WiimmfiBrowser {
    param(
        [string]$Url = $script:WiimmfiDefaultUrl,
        $LogQueue = $null
    )
    Write-WiimmfiDiagnostic $LogQueue 'INFO' 'BROWSER' 'Starting Chrome/Edge transport'
    $browser = Find-Browser
    if (-not $browser) {
        Write-WiimmfiDiagnostic $LogQueue 'ERROR' 'BROWSER' 'Chrome/Edge was not found'
        return @{ ok = $false; error = 'no-browser' }
    }

    $port = Get-FreePort
    $profile = Join-Path $env:TEMP ("mph_wiimmfi_profile_{0}" -f $PID)
    $args = @(
        "--remote-debugging-port=$port", "--user-data-dir=`"$profile`"",
        '--no-first-run', '--no-default-browser-check', '--disable-background-timer-throttling',
        '--window-size=480,360', '--window-position=-32000,-32000', $Url
    )
    try {
        $proc = Start-Process -FilePath $browser -ArgumentList $args -PassThru -WindowStyle Minimized
        Write-WiimmfiDiagnostic $LogQueue 'INFO' 'BROWSER' ("Browser started; pid={0}; port={1}; executable={2}" -f $proc.Id, $port, $browser)
        return @{ ok = $true; proc = $proc; port = $port; browser = $browser; profile = $profile }
    } catch {
        Write-WiimmfiDiagnostic $LogQueue 'ERROR' 'BROWSER' ("Browser start failed: {0}" -f $_.Exception.Message)
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Stop-WiimmfiBrowser {
    param($Proc, [string]$Profile = '', $LogQueue = $null)
    try {
        if ($Proc -and -not $Proc.HasExited) {
            & taskkill /PID $Proc.Id /T /F 2>$null | Out-Null
            Write-WiimmfiDiagnostic $LogQueue 'INFO' 'BROWSER' ("Browser stopped; pid={0}" -f $Proc.Id)
        }
    } catch {
        Write-WiimmfiDiagnostic $LogQueue 'WARN' 'BROWSER' ("Browser stop failed: {0}" -f $_.Exception.Message)
    }
    try { if ($Profile -and (Test-Path $Profile)) { Remove-Item -LiteralPath $Profile -Recurse -Force -EA SilentlyContinue } } catch {}
}

function Get-WiimmfiData {
    param(
        [int]$Port,
        [string]$TextUrl = $script:WiimmfiTextUrl,
        [string]$Lang = (Get-MphLang),
        $LogQueue = $null
    )
    $res = @{ ok = $false; error = ''; online = 0; players = @() }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-WiimmfiDiagnostic $LogQueue 'DEBUG' 'START' ("Update started; port={0}" -f $Port)
    try {
        $txt = Get-WiimmfiText -Port $Port -TextUrl $TextUrl -LogQueue $LogQueue
        if ($null -eq $txt) {
            $res.error = 'connecting'
            Write-WiimmfiDiagnostic $LogQueue 'DEBUG' 'VERIFY' 'Browser or Cloudflare challenge is not ready'
            return $res
        }

        $players = Parse-WiimmfiText -Text $txt
        $list = @()
        foreach ($p in $players) { $list += (ConvertTo-WiimmfiPlayer $p -Lang $Lang) }
        $res.players = $list
        $res.online = $list.Count
        $res.ok = $true
        Write-WiimmfiDiagnostic $LogQueue 'INFO' 'PARSE' ("players={0}; consistency=ok" -f $list.Count)
        return $res
    } catch {
        $res.error = $_.Exception.Message
        Write-WiimmfiDiagnostic $LogQueue 'ERROR' 'EXCEPTION' ("{0}: {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message)
        return $res
    } finally {
        $watch.Stop()
        Write-WiimmfiDiagnostic $LogQueue 'DEBUG' 'END' ("Update finished; ok={0}; elapsedMs={1}" -f $res.ok, $watch.ElapsedMilliseconds)
    }
}
