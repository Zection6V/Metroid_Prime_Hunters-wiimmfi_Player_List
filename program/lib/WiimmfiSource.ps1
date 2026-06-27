<#
    WiimmfiSource.ps1 — wiimmfi の情報取得ライブラリ（UI 非依存 / 単一責務）

    dot-source して使う:  . "$PSScriptRoot\lib\WiimmfiSource.ps1"

    wiimmfi.de は現在 Cloudflare の JS チャレンジで保護されており単純 GET は 403。
    そこで PC のブラウザ(Chrome/Edge)を「非ヘッドレス・画面外」で起動し、DevTools
    Protocol(CDP) 経由でページ内 fetch を実行してチャレンジ通過後の HTML を得る。

    公開関数:
      Find-Browser                       … Chrome/Edge の実行ファイルパスを返す（無ければ $null）
      Start-WiimmfiBrowser  -Url         … ブラウザを起動 @{ ok; error; proc; port; browser }
      Stop-WiimmfiBrowser   -Proc        … 起動したブラウザを確実に終了
      Get-WiimmfiData       -Port -Url   … 取得→解析→正規化
                                           @{ ok; error; online; players=@(@{Name;Fc;OnlineStatus;PlayerStatus;JoinPlayers;GameInfo;NumPlayers;ShowFriends;ShowRivals}) }
#>

# ブラウザを実ナビゲートして Cloudflare を通過させるページ
$script:WiimmfiDefaultUrl = 'https://wiimmfi.de/stats/game/mprimeds'
# 実データ取得に使う軽量 text エンドポイント（'!' 区切りヘッダ + '|' 区切り行）
$script:WiimmfiTextUrl = 'https://wiimmfi.de/stats/game/mprimeds/text'

# 言語テーブル（ol_stat / status / mode / join の対訳）は lib\I18n.ps1 に集約
. (Join-Path $PSScriptRoot 'I18n.ps1')

function Find-Browser {
    $cands = @(
        (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -EA SilentlyContinue).'(default)',
        (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -EA SilentlyContinue).'(default)',
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe" -EA SilentlyContinue).'(default)',
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
    }
    finally { try { $ws.Dispose() } catch {}; try { $cts.Dispose() } catch {} }
}

# 軽量 text エンドポイントをページ内 fetch で取得する。
#   返り値: 通過前/エラー時は $null。通過後は本文文字列（オンライン 0 人なら空文字）。
function Get-WiimmfiText {
    param([int]$Port, [string]$TextUrl = $script:WiimmfiTextUrl)
    try {
        $tabs = Invoke-RestMethod "http://127.0.0.1:$Port/json" -TimeoutSec 10
        $tab = $tabs | Where-Object { $_.type -eq 'page' -and $_.url -match 'wiimmfi' } | Select-Object -First 1
        if (-not $tab) { return $null }
        $expr = "fetch('$TextUrl',{cache:'no-store'}).then(function(r){return r.text()})"
        $txt = Invoke-CdpEval -WsUrl $tab.webSocketDebuggerUrl -Expression $expr
        if ($null -eq $txt) { return $null }
        # まだ Cloudflare チャレンジ中なら HTML が返る。それは未通過として扱う。
        if ($txt -match 'Just a moment' -or $txt -match '(?i)<html') { return $null }
        return [string]$txt
    } catch { return $null }
}

# text 形式を行→フィールドに分解。各 player[]（0 始まり）の意味:
#   0=id4 1=pid 2=fc 3=host 4=gid 5=ls_stat 6=ol_stat 7=status 8=suspend 9=n 10=name1 11=name2
#   データ行は '|' 始まり。先頭の '!' 行はヘッダなので除外。
function Parse-WiimmfiText {
    param([string]$Text)
    $players = @()
    foreach ($line in ($Text -split "`n")) {
        $line = $line.TrimEnd("`r")
        if (-not $line.StartsWith('|')) { continue }
        $parts = $line -split '\|'   # [0]=先頭の空, [1..12]=id4..name2
        if ($parts.Count -ge 13) { $players += , ($parts[1..12]) }
    }
    return , $players
}

# 状態コードを解読し、表示用の正規化ハッシュテーブルにする（言語は -Lang / OS 既定）
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
    # ol_stat（フラグ文字列）を 1 文字ずつ訳して ＋ で連結（大文字小文字を区別する olStat マップ）
    $ol = [string]$p[6]
    if ($ol) {
        $parts = foreach ($ch in $ol.ToCharArray()) { $k = [string]$ch; if ($i.olStat.ContainsKey($k)) { $i.olStat[$k] } else { $k } }
        $res.OnlineStatus = ($parts -join '＋')
    }
    # status（数値）を訳す
    $st = [string]$p[7]
    if ($i.status.ContainsKey($st)) { $res.PlayerStatus = $i.status[$st] } elseif ($st) { $res.PlayerStatus = $st }
    return $res
}

function Start-WiimmfiBrowser {
    param([string]$Url = $script:WiimmfiDefaultUrl)
    $browser = Find-Browser
    if (-not $browser) { return @{ ok = $false; error = 'no-browser' } }
    $port = Get-FreePort
    $prof = Join-Path $env:TEMP 'mph_unified_profile'
    $args = @(
        "--remote-debugging-port=$port", "--user-data-dir=`"$prof`"",
        '--no-first-run', '--no-default-browser-check', '--disable-background-timer-throttling',
        '--window-size=480,360', '--window-position=-32000,-32000', $Url
    )
    $proc = Start-Process -FilePath $browser -ArgumentList $args -PassThru -WindowStyle Minimized
    return @{ ok = $true; proc = $proc; port = $port; browser = $browser }
}

function Stop-WiimmfiBrowser {
    param($Proc)
    try { if ($Proc -and -not $Proc.HasExited) { & taskkill /PID $Proc.Id /T /F 2>$null | Out-Null } } catch {}
}

function Get-WiimmfiData {
    param([int]$Port, [string]$TextUrl = $script:WiimmfiTextUrl, [string]$Lang = (Get-MphLang))
    $res = @{ ok = $false; error = ''; online = 0; players = @() }
    $txt = Get-WiimmfiText -Port $Port -TextUrl $TextUrl
    if ($null -eq $txt) { $res.error = 'connecting'; return $res }   # 未通過（空文字は 0 人の正常応答）
    $players = Parse-WiimmfiText -Text $txt
    $list = @()
    foreach ($p in $players) { $list += (ConvertTo-WiimmfiPlayer $p -Lang $Lang) }
    $res.players = $list
    $res.online = $list.Count
    $res.ok = $true
    return $res
}
