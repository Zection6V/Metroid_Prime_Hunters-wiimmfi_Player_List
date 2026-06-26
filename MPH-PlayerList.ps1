<#
    MPH Wiimmfi Player List  (PowerShell + WinForms edition)
    --------------------------------------------------------
    元の "MPH Wimmfi Player List.ahk"（AutoHotkey v1）を、追加インストール不要で
    Windows 上で動かせるように移植したもの。

    データ元 https://wiimmfi.de/stats/game/mprimeds は現在 Cloudflare の
    JavaScript チャレンジで保護されているため、単純な HTTP GET（元の AHK の方式）は
    403 になる。そこで PC に入っている Chrome/Edge を「非ヘッドレス・画面外」で起動し、
    DevTools Protocol(CDP) 経由でページ内 fetch を実行してチャレンジ通過後の HTML を取得する。

    依存:
      - Windows + PowerShell 5.1+（標準搭載）
      - Chrome もしくは Chromium 版 Edge（どちらか一方でよい / 追加インストール不要）
    起動:  "Run MPH Player List.bat" をダブルクリック。
    （-SelfTest を付けると GUI を表示せず取得〜解析〜描画更新だけ実行しログ出力する診断モード）
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ImgDir    = Join-Path $ScriptDir 'img'
$Url       = 'https://wiimmfi.de/stats/game/mprimeds'

# ----------------------------------------------------------------------------
# ブラウザ検出
# ----------------------------------------------------------------------------
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

# ----------------------------------------------------------------------------
# CDP 経由でページ内 JavaScript を評価して結果(文字列)を返す
# ----------------------------------------------------------------------------
function Invoke-CdpEval {
    param([string]$WsUrl, [string]$Expression, [int]$TimeoutSec = 20)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource ([TimeSpan]::FromSeconds($TimeoutSec))
    $ct = $cts.Token
    try {
        $ws.ConnectAsync([Uri]$WsUrl, $ct).Wait()
        $payload = @{
            id     = 1
            method = 'Runtime.evaluate'
            params = @{ expression = $Expression; returnByValue = $true; awaitPromise = $true }
        } | ConvertTo-Json -Depth 6 -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
        $ws.SendAsync([ArraySegment[byte]]::new($bytes), 'Text', $true, $ct).Wait()
        $sb = New-Object Text.StringBuilder
        $buf = New-Object byte[] 131072
        do {
            $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct)
            $r.Wait()
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count))
        } while (-not $r.Result.EndOfMessage)
        $json = $sb.ToString() | ConvertFrom-Json
        return $json.result.result.value
    }
    finally {
        try { $ws.Dispose() } catch {}
        try { $cts.Dispose() } catch {}
    }
}

function Get-DebugWsUrl {
    param([int]$Port)
    $tabs = Invoke-RestMethod "http://127.0.0.1:$Port/json" -TimeoutSec 10
    $tab = $tabs | Where-Object { $_.type -eq 'page' -and $_.url -match 'wiimmfi' } | Select-Object -First 1
    if (-not $tab) { $tab = $tabs | Where-Object { $_.type -eq 'page' } | Select-Object -First 1 }
    return $tab.webSocketDebuggerUrl
}

# 最新の HTML を取得（チャレンジ中なら $null を返す）
function Get-StatsHtml {
    param([int]$Port)
    try {
        $ws = Get-DebugWsUrl -Port $Port
        if (-not $ws) { return $null }
        $expr = "fetch('$Url',{cache:'no-store'}).then(function(r){return r.text()})"
        $html = Invoke-CdpEval -WsUrl $ws -Expression $expr
        if ($html -and $html -match 'id="online"' -and $html -notmatch 'Just a moment') { return $html }
        return $null
    } catch { return $null }
}

# ----------------------------------------------------------------------------
# HTML パース  ->  プレイヤー配列の配列
#   各 player[] : 0=id4 1=pid 2=fc 3=host 4=gid 5=ls_stat 6=ol_stat 7=status 8=suspend 9=n 10=name1 11=name2
# ----------------------------------------------------------------------------
function Parse-Players {
    param([string]$Html)
    $players = @()
    $s = $Html.IndexOf('<table id="online"')
    if ($s -lt 0) { return $players }
    $e = $Html.IndexOf('</table>', $s)
    if ($e -lt 0) { $e = $Html.Length }
    $tbl = $Html.Substring($s, $e - $s)
    $rows = [regex]::Matches($tbl, '(?s)<tr class="tr\d+">(.*?)</tr>')
    foreach ($r in $rows) {
        $cells = [regex]::Matches($r.Groups[1].Value, '(?s)<td[^>]*>(.*?)</td>')
        $arr = @()
        foreach ($c in $cells) {
            $v = $c.Groups[1].Value
            $v = $v -replace '&mdash;', '-'
            $v = $v -replace '&#x200B;', ''
            $v = ($v -replace '<[^>]+>', '').Trim()
            $arr += $v
        }
        if ($arr.Count -ge 11) { $players += , $arr }
    }
    return , $players   # 先頭のカンマで単一要素配列のアンロールを防ぐ
}

# ----------------------------------------------------------------------------
# 状態コードのデコード（元 AHK の selectPlayer ロジックを移植）
# ----------------------------------------------------------------------------
function Decode-Player {
    param($p)
    $res = [ordered]@{
        Name = ''; Fc = ''; OnlineStatus = ''; PlayerStatus = ''
        JoinPlayers = ''; GameInfo = ''; NumPlayers = ''
        Mode1 = $null; Mode2 = $null; ShowFriends = $false; ShowRivals = $false
    }
    $res.Name = $p[10]
    $res.Fc   = $p[2]

    # --- ls_stat (index 5) ---
    $ls = $p[5]
    $v = "$ls"
    while ($v.Length -lt 7) { $v = '0' + $v }
    if ($v.Length -lt 8) { $v = '1' + $v }
    $d = $v.ToCharArray()   # d[0]=桁1 ... d[7]=桁8
    $rivals = $false
    switch ("$($d[0])") {           # 桁1: 人数
        '1' { $res.NumPlayers = '1' }
        '2' { $res.NumPlayers = '2' }
        '4' { $res.NumPlayers = '3' }
        '6' { $res.NumPlayers = '4' }
    }
    switch ("$($d[1])") {           # 桁2: モード
        '0' { $res.GameInfo = 'Survival / None';       $res.Mode1 = 'survival.png' }
        '1' { $res.GameInfo = 'Battle / Bounty';       $res.Mode1 = 'battle.png';     $res.Mode2 = 'bounty.png' }
        '2' { $res.GameInfo = 'Defender / Capture';    $res.Mode1 = 'defender.png';   $res.Mode2 = 'capture.png' }
        '3' { $res.GameInfo = 'Prime Hunter / Nodes';  $res.Mode1 = 'primehunter.png';$res.Mode2 = 'nodes.png' }
    }
    if ("$($d[6])" -eq '1') { $rivals = $true; $res.ShowRivals = $true }   # 桁7: Rivals
    $friends = ("$($d[7])" -eq '8')                                        # 桁8: Friends
    if ($friends) { $res.ShowFriends = $true }
    if ($rivals -and $friends) { $res.JoinPlayers = 'Friends and Rivals' }
    elseif ($rivals)           { $res.JoinPlayers = 'Rivals Only' }
    elseif ($friends)          { $res.JoinPlayers = 'Friends Only' }

    # --- ol_stat (index 6) ---
    switch ($p[6]) {
        'o'    { $res.OnlineStatus = 'Online' }
        'og'   { $res.OnlineStatus = 'Guest of Room' }
        'oGv'  { $res.OnlineStatus = 'In Game' }
        'oGvS' { $res.OnlineStatus = 'Searching for Game' }
    }

    # --- status (index 7) ---
    switch ("$($p[7])") {
        '1' { $res.PlayerStatus = 'Online' }
        '2' { $res.PlayerStatus = 'Guest Room' }
        '3' { $res.PlayerStatus = 'Searching Opponents' }
        '5' { $res.PlayerStatus = 'Joining Game' }
        '6' { $res.PlayerStatus = 'Hosting Game' }
    }
    # ls_stat = 0 のときの In-Game 特例
    if ("$ls" -eq '0' -and "$($p[7])" -eq '6') {
        $res.OnlineStatus = 'In-Game (Host)';   $res.NumPlayers = 'Unknown'; $res.GameInfo = 'Unknown'
        $res.Mode1 = $null; $res.Mode2 = $null
    }
    elseif ("$ls" -eq '0' -and "$($p[7])" -eq '2') {
        $res.OnlineStatus = 'In-Game (Client)'; $res.NumPlayers = 'Unknown'; $res.GameInfo = 'Unknown'
        $res.Mode1 = $null; $res.Mode2 = $null
    }
    return $res
}

# ============================================================================
# 起動: ブラウザ
# ============================================================================
$browser = Find-Browser
if (-not $browser) {
    [System.Windows.Forms.MessageBox]::Show(
        "Chrome もしくは Chromium 版 Edge が見つかりませんでした。`n" +
        "wiimmfi.de は Cloudflare 保護のため、ページを描画できるブラウザが必要です。`n" +
        "Chrome か Edge をインストールしてから再度お試しください。",
        "MPH Player List", 'OK', 'Error') | Out-Null
    return
}

$Port = Get-FreePort
$Profile = Join-Path $env:TEMP 'mph_playerlist_profile'
$chromeArgs = @(
    "--remote-debugging-port=$Port",
    "--user-data-dir=`"$Profile`"",
    '--no-first-run', '--no-default-browser-check',
    '--disable-background-timer-throttling',
    '--window-size=480,360', '--window-position=-32000,-32000',
    $Url
)
$proc = Start-Process -FilePath $browser -ArgumentList $chromeArgs -PassThru -WindowStyle Minimized

# ============================================================================
# GUI 構築
# ============================================================================
$bgDark   = [System.Drawing.Color]::FromArgb(0x37,0x37,0x37)
$orange   = [System.Drawing.Color]::FromArgb(0xE7,0x65,0x0C)
$cream    = [System.Drawing.Color]::FromArgb(0xFF,0xFF,0xCA)
$white    = [System.Drawing.Color]::White

$form = New-Object System.Windows.Forms.Form
$form.Text = "MPH Wiimmfi Player List"
$form.Size = New-Object System.Drawing.Size(660, 500)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$icoPath = Join-Path $ImgDir 'wifi.png'

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Player List"
$lblTitle.ForeColor = $orange
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(14, 10)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$list = New-Object System.Windows.Forms.ListBox
$list.Location = New-Object System.Drawing.Point(14, 48)
$list.Size = New-Object System.Drawing.Size(220, 360)
$list.BackColor = $bgDark
$list.ForeColor = $cream
$list.BorderStyle = 'FixedSingle'
$list.Font = New-Object System.Drawing.Font("Consolas", 11)
$form.Controls.Add($list)

# 詳細ラベルを生成するヘルパ
$detail = @{}
function Add-Field($form, $key, $caption, $y) {
    $cap = New-Object System.Windows.Forms.Label
    $cap.Text = $caption
    $cap.ForeColor = $orange
    $cap.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $cap.Location = New-Object System.Drawing.Point(250, $y)
    $cap.AutoSize = $true
    $form.Controls.Add($cap)
    $val = New-Object System.Windows.Forms.Label
    $val.Text = ""
    $val.ForeColor = $white
    $val.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $val.Location = New-Object System.Drawing.Point(420, $y)
    $val.Size = New-Object System.Drawing.Size(210, 22)
    $form.Controls.Add($val)
    return $val
}
$detail.Name        = Add-Field $form 'Name'        "Player Name:"      48
$detail.Fc          = Add-Field $form 'Fc'          "Friend Code:"      80
$detail.Online      = Add-Field $form 'Online'      "Online Status:"   112
$detail.Status      = Add-Field $form 'Status'      "Player Status:"   144
$detail.Join        = Add-Field $form 'Join'        "Join Players:"    176
$detail.Game        = Add-Field $form 'Game'        "Game Info:"       208
$detail.Num         = Add-Field $form 'Num'         "Number of Players:" 240

# モードアイコン
$picMode1 = New-Object System.Windows.Forms.PictureBox
$picMode1.Location = New-Object System.Drawing.Point(420, 280)
$picMode1.Size = New-Object System.Drawing.Size(80, 80)
$picMode1.SizeMode = 'Zoom'
$picMode1.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($picMode1)
$picMode2 = New-Object System.Windows.Forms.PictureBox
$picMode2.Location = New-Object System.Drawing.Point(520, 280)
$picMode2.Size = New-Object System.Drawing.Size(80, 80)
$picMode2.SizeMode = 'Zoom'
$picMode2.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($picMode2)

# Friends / Rivals
$lblFriends = New-Object System.Windows.Forms.Label
$lblFriends.Text = "Friends"; $lblFriends.ForeColor = [System.Drawing.Color]::FromArgb(0x5E,0x5E,0xFF)
$lblFriends.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblFriends.Location = New-Object System.Drawing.Point(250, 288); $lblFriends.AutoSize = $true
$lblFriends.Visible = $false; $form.Controls.Add($lblFriends)
$lblRivals = New-Object System.Windows.Forms.Label
$lblRivals.Text = "Rivals"; $lblRivals.ForeColor = [System.Drawing.Color]::FromArgb(0xFF,0x62,0x62)
$lblRivals.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblRivals.Location = New-Object System.Drawing.Point(250, 320); $lblRivals.AutoSize = $true
$lblRivals.Visible = $false; $form.Controls.Add($lblRivals)

# ステータスバー
$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(14, 420)
$status.Size = New-Object System.Drawing.Size(620, 40)
$status.ForeColor = [System.Drawing.Color]::FromArgb(0xA4,0xE1,0xFF)
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$status.Text = "Connecting... (Cloudflare を通過中。初回は数秒〜十数秒かかります)"
$form.Controls.Add($status)

# ----------------------------------------------------------------------------
# 状態保持 + 画像ロード（キャッシュ）
# ----------------------------------------------------------------------------
$script:PlayersDecoded = @()
$script:ImgCache = @{}
function Load-Img($name) {
    if (-not $name) { return $null }
    if ($script:ImgCache.ContainsKey($name)) { return $script:ImgCache[$name] }
    $path = Join-Path $ImgDir $name
    if (Test-Path $path) {
        try { $img = [System.Drawing.Image]::FromFile($path); $script:ImgCache[$name] = $img; return $img } catch { return $null }
    }
    return $null
}

function Update-Detail {
    $i = $list.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:PlayersDecoded.Count) { return }
    $d = $script:PlayersDecoded[$i]
    $detail.Name.Text   = $d.Name
    $detail.Fc.Text     = $d.Fc
    $detail.Online.Text = $d.OnlineStatus
    $detail.Status.Text = $d.PlayerStatus
    $detail.Join.Text   = $d.JoinPlayers
    $detail.Game.Text   = $d.GameInfo
    $detail.Num.Text    = $d.NumPlayers
    $picMode1.Image = Load-Img $d.Mode1
    $picMode2.Image = Load-Img $d.Mode2
    $lblFriends.Visible = $d.ShowFriends
    $lblRivals.Visible  = $d.ShowRivals
}
$list.Add_SelectedIndexChanged({ Update-Detail })

# ----------------------------------------------------------------------------
# データ更新（16 秒ごと + 起動直後）
# ----------------------------------------------------------------------------
function Refresh-Data {
    $html = Get-StatsHtml -Port $Port
    if (-not $html) {
        $status.Text = "接続待ち... Cloudflare チャレンジ通過中、またはネットワーク確認中 (" + (Get-Date -Format 'HH:mm:ss') + ")"
        return
    }
    $players = Parse-Players -Html $html   # カンマ返しのため @() は付けない
    $script:PlayersDecoded = @()
    foreach ($p in $players) { $script:PlayersDecoded += (Decode-Player $p) }

    $prev = $list.SelectedItem
    $list.BeginUpdate()
    $list.Items.Clear()
    foreach ($d in $script:PlayersDecoded) { [void]$list.Items.Add($d.Name) }
    $list.EndUpdate()
    if ($list.Items.Count -gt 0) {
        $idx = if ($prev) { $list.Items.IndexOf($prev) } else { -1 }
        $list.SelectedIndex = [Math]::Max(0, $idx)
    } else {
        foreach ($k in $detail.Keys) { $detail[$k].Text = "" }
        $picMode1.Image = $null; $picMode2.Image = $null
        $lblFriends.Visible = $false; $lblRivals.Visible = $false
    }
    $status.Text = ("Online: {0} players   /   Last updated {1}   /   source: wiimmfi.de (via {2})" -f $script:PlayersDecoded.Count, (Get-Date -Format 'HH:mm:ss'), (Split-Path $browser -Leaf))
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 16000
$timer.Add_Tick({ Refresh-Data })

# 起動直後: Cloudflare 通過をポーリング（最大 ~45 秒）してから初回描画
$form.Add_Shown({
    $form.Refresh()
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        [System.Windows.Forms.Application]::DoEvents()
        $html = Get-StatsHtml -Port $Port
        if ($html) { break }
        Start-Sleep -Milliseconds 1500
    }
    Refresh-Data
    $timer.Start()
})

# 終了時: 起動した Chrome/Edge を確実に閉じる
$form.Add_FormClosing({
    try { $timer.Stop() } catch {}
    try { if ($proc -and -not $proc.HasExited) { & taskkill /PID $proc.Id /T /F 2>$null | Out-Null } } catch {}
})

if ($SelfTest) {
    # --- 診断モード: GUI を表示せず、取得→解析→描画更新を1回実行してログ出力 ---
    $log = Join-Path $env:TEMP 'mph_selftest.log'
    Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        L "FORM BUILT OK; controls=$($form.Controls.Count)"
        $deadline = (Get-Date).AddSeconds(45); $ok = $false
        while ((Get-Date) -lt $deadline) { $h = Get-StatsHtml -Port $Port; if ($h) { $ok = $true; break }; Start-Sleep -Milliseconds 1500 }
        L "Cloudflare passed=$ok"
        Refresh-Data
        L "ListBox items=$($list.Items.Count)"
        for ($i = 0; $i -lt $list.Items.Count; $i++) { L ("  item[$i]=" + $list.Items[$i]) }
        if ($list.Items.Count -gt 0) {
            $list.SelectedIndex = 0
            L ("Name=" + $detail.Name.Text + " | Fc=" + $detail.Fc.Text + " | Online=" + $detail.Online.Text + " | Status=" + $detail.Status.Text)
            L ("Join=" + $detail.Join.Text + " | Game=" + $detail.Game.Text + " | Num=" + $detail.Num.Text)
            L ("Mode1.Image set=" + ($picMode1.Image -ne $null) + " | Friends.Vis=" + $lblFriends.Visible + " | Rivals.Vis=" + $lblRivals.Visible)
        }
        L ("Status bar=" + $status.Text)
        L "RESULT: SUCCESS"
    } catch {
        L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace)
    } finally {
        try { if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -EA SilentlyContinue } } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
