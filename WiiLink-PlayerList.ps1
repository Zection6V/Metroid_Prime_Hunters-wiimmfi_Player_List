<#
    WiiLink WFC - Metroid Prime Hunters Player List  (PowerShell + WinForms)
    ------------------------------------------------------------------------
    私設 Wi-Fi サービス WiiLink WFC (https://wfc.wiilink24.com) 上の
    Metroid Prime Hunters のオンライン・ルーム/プレイヤーを一覧表示する。

    データ源（公式 JSON API。Cloudflare 等の保護は無く、直接 GET 可能）:
      - https://api.wfc.wiilink24.com/api/stats   … 全ゲームの {online,active,groups}
      - https://api.wfc.wiilink24.com/api/groups  … ルーム配列（game=="mprimeds" で絞る）

    ※ wiimmfi 版（MPH-PlayerList.ps1）はブラウザ(CDP)経由が必要だったが、
      WiiLink は素の HTTP GET で取れるためブラウザ不要・軽量。

    依存: Windows + PowerShell 5.1（OS 標準）のみ。
    起動: "Run WiiLink Player List.bat" をダブルクリック。
          -SelfTest を付けると GUI を出さず取得〜解析を1回実行しログ出力する。
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$StatsUrl  = 'https://api.wfc.wiilink24.com/api/stats'
$GroupsUrl = 'https://api.wfc.wiilink24.com/api/groups'
$Game      = 'mprimeds'
$Ua        = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-WiiLink-PlayerList'

# ============================================================================
# 色・GUI 構築
# ============================================================================
$bgDark = [System.Drawing.Color]::FromArgb(0x23, 0x23, 0x23)
$panel  = [System.Drawing.Color]::FromArgb(0x2D, 0x2D, 0x2D)
$orange = [System.Drawing.Color]::FromArgb(0xE7, 0x65, 0x0C)
$cream  = [System.Drawing.Color]::FromArgb(0xFF, 0xFF, 0xCA)
$cyan   = [System.Drawing.Color]::FromArgb(0xA4, 0xE1, 0xFF)
$green  = [System.Drawing.Color]::FromArgb(0x3C, 0xC7, 0x61)
$red    = [System.Drawing.Color]::FromArgb(0xC7, 0x40, 0x3C)
$white  = [System.Drawing.Color]::White

$form = New-Object System.Windows.Forms.Form
$form.Text = "WiiLink WFC - MPH Player List"
$form.Size = New-Object System.Drawing.Size(700, 560)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "WiiLink WFC  -  Metroid Prime Hunters"
$lblTitle.ForeColor = $orange
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(14, 10)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblStats = New-Object System.Windows.Forms.Label
$lblStats.Text = "Online: -    Active: -    Groups: -"
$lblStats.ForeColor = $cyan
$lblStats.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblStats.Location = New-Object System.Drawing.Point(16, 44)
$lblStats.AutoSize = $true
$form.Controls.Add($lblStats)

# 左: ルーム/プレイヤーのツリー
$tree = New-Object System.Windows.Forms.TreeView
$tree.Location = New-Object System.Drawing.Point(14, 78)
$tree.Size = New-Object System.Drawing.Size(330, 410)
$tree.BackColor = $panel
$tree.ForeColor = $cream
$tree.BorderStyle = 'FixedSingle'
# 等幅かつ日本語(カナ等)対応のフォント。Mii 名に和文が含まれても確実に描画する。
$tree.Font = New-Object System.Drawing.Font("MS Gothic", 10)
$tree.HideSelection = $false
$tree.ShowLines = $true
$tree.ShowRootLines = $true
$form.Controls.Add($tree)

# 右: 詳細フィールド
$detail = @{}
function Add-Field($form, $caption, $y) {
    $cap = New-Object System.Windows.Forms.Label
    $cap.Text = $caption
    $cap.ForeColor = $orange
    $cap.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $cap.Location = New-Object System.Drawing.Point(358, $y)
    $cap.AutoSize = $true
    $form.Controls.Add($cap)
    $val = New-Object System.Windows.Forms.Label
    $val.Text = ""
    $val.ForeColor = $white
    $val.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $val.Location = New-Object System.Drawing.Point(478, $y)
    $val.Size = New-Object System.Drawing.Size(196, 22)
    $form.Controls.Add($val)
    return $val
}
$detail.Name     = Add-Field $form "Name:"        78
$detail.Fc       = Add-Field $form "Friend Code:" 110
$detail.Pid      = Add-Field $form "PID:"         142
$detail.Role     = Add-Field $form "Role:"        174
$detail.ConnFail = Add-Field $form "Conn. fails:" 206
$detail.RoomId   = Add-Field $form "Room ID:"     254
$detail.Type     = Add-Field $form "Room Type:"   286
$detail.Joinable = Add-Field $form "Joinable:"    318
$detail.Players  = Add-Field $form "Players:"     350
$detail.Created  = Add-Field $form "Created:"     382

# ステータスバー
$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(14, 498)
$status.Size = New-Object System.Drawing.Size(660, 22)
$status.ForeColor = $cyan
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$status.Text = "Connecting..."
$form.Controls.Add($status)

# ============================================================================
# ツリー構築（描画のみ。取得はバックグラウンド runspace 側）
# ============================================================================
function Find-NodeByKey {
    param($nodes, [string]$key)
    foreach ($n in $nodes) {
        if ($n.Tag -and $n.Tag.Key -eq $key) { return $n }
        $c = Find-NodeByKey $n.Nodes $key
        if ($c) { return $c }
    }
    return $null
}

$script:LastSig = [guid]::NewGuid().ToString()
function Build-Tree {
    param([string]$GroupsJson, [string]$StatsJson)

    # --- stats ヘッダ ---
    $online = 0; $active = 0; $groupsN = 0
    if ($StatsJson) {
        try {
            $s = $StatsJson | ConvertFrom-Json
            if ($s.$Game) { $online = $s.$Game.online; $active = $s.$Game.active; $groupsN = $s.$Game.groups }
        } catch {}
    }
    $lblStats.Text = "Online: $online     Active: $active     Groups: $groupsN"

    # --- groups ---
    $groups = @()
    if ($GroupsJson) {
        try { $all = $GroupsJson | ConvertFrom-Json; $groups = @($all | Where-Object { $_.game -eq $Game }) } catch {}
    }

    $selKey = if ($tree.SelectedNode -and $tree.SelectedNode.Tag) { $tree.SelectedNode.Tag.Key } else { $null }
    $tree.BeginUpdate()
    $tree.Nodes.Clear()
    if ($groups.Count -eq 0) {
        $n = $tree.Nodes.Add("(Nobody online)")
        $n.ForeColor = [System.Drawing.Color]::Gray
    } else {
        foreach ($g in $groups) {
            $typeLabel = if ($g.type -eq 'private') { 'Friends' } elseif ($g.type -eq 'anybody') { 'Public' } else { [string]$g.type }
            $joinLabel = if ($g.suspend) { 'Not joinable' } else { 'Joinable' }
            $created = [string]$g.created
            try { $created = ([datetime]$g.created).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } catch {}

            $props = @($g.players.PSObject.Properties | Sort-Object { [int]$_.Name })
            $hostKey = [string]$g.host
            $hostPlayer = $null
            if ($g.players.PSObject.Properties.Name -contains $hostKey) { $hostPlayer = $g.players.$hostKey }
            $hostName = if ($hostPlayer) { [string]$hostPlayer.name } else { 'Awaiting host' }

            $roomMeta = @{ RoomId = [string]$g.id; Type = $typeLabel; Joinable = $joinLabel; Created = $created; Players = $props.Count }
            $roomTag = @{ Kind = 'room'; Key = "room:$($g.id)"; Name = $hostName
                Fc = (&{ if ($hostPlayer) { [string]$hostPlayer.fc } else { '' } })
                Pid = (&{ if ($hostPlayer) { [string]$hostPlayer.pid } else { '' } })
                Role = 'Room'; ConnFail = '' } + $roomMeta

            $roomNode = $tree.Nodes.Add(("{0}'s room   ({1})   - {2} - {3}  [{4}p]" -f $hostName, $g.id, $typeLabel, $joinLabel, $props.Count))
            $roomNode.ForeColor = $orange
            $roomNode.Tag = $roomTag

            foreach ($pp in $props) {
                $p = $pp.Value
                $isHost = ($pp.Name -eq $hostKey)
                $mark = if ($isHost) { '* ' } else { '  ' }
                $pTag = @{ Kind = 'player'; Key = "player:$($g.id):$($pp.Name)"
                    Name = [string]$p.name; Fc = [string]$p.fc; Pid = [string]$p.pid
                    Role = (&{ if ($isHost) { 'Host' } else { 'Member' } })
                    ConnFail = [string]$p.conn_fail } + $roomMeta
                $pnode = $roomNode.Nodes.Add(("{0}{1}    {2}" -f $mark, $p.name, $p.fc))
                $pnode.ForeColor = if ($isHost) { $cyan } else { $cream }
                $pnode.Tag = $pTag
            }
        }
        $tree.ExpandAll()
    }
    $tree.EndUpdate()

    # 選択の復元
    if ($selKey) { $node = Find-NodeByKey $tree.Nodes $selKey; if ($node) { $tree.SelectedNode = $node } }
    if (-not $tree.SelectedNode -and $tree.Nodes.Count -gt 0 -and $tree.Nodes[0].Tag) { $tree.SelectedNode = $tree.Nodes[0] }
}

function Show-NodeDetail {
    param($node)
    $t = if ($node) { $node.Tag } else { $null }
    if (-not $t) {
        foreach ($k in $detail.Keys) { $detail[$k].Text = "" }
        return
    }
    $detail.Name.Text     = $t.Name
    $detail.Fc.Text       = $t.Fc
    $detail.Pid.Text      = $t.Pid
    $detail.Role.Text     = $t.Role
    $detail.ConnFail.Text = [string]$t.ConnFail
    $detail.RoomId.Text   = $t.RoomId
    $detail.Type.Text     = $t.Type
    $detail.Joinable.Text = $t.Joinable
    $detail.Players.Text  = [string]$t.Players
    $detail.Created.Text  = $t.Created
    $detail.Joinable.ForeColor = if ($t.Joinable -eq 'Joinable') { $green } elseif ($t.Joinable -eq 'Not joinable') { $red } else { $white }
}
$tree.Add_AfterSelect({ Show-NodeDetail $tree.SelectedNode })

# ============================================================================
# バックグラウンド取得スレッド（別 runspace）— UI を固めない
# ============================================================================
$sync = [hashtable]::Synchronized(@{
        StatsUrl = $StatsUrl; GroupsUrl = $GroupsUrl; Ua = $Ua
        StatsJson = $null; GroupsJson = $null; Seq = 0
        Status = 'starting'; Err = ''; Stop = $false
    })

$workerBody = @'
$ErrorActionPreference = 'Stop'
while (-not $sync.Stop) {
    try {
        $h = @{ 'User-Agent' = $sync.Ua }
        # API は Content-Type に charset を持たないため、PS 5.1 の .Content は
        # ISO-8859-1 で誤デコードされ Mii 名が文字化けする。生バイトを UTF-8 で明示デコードする。
        $rs = Invoke-WebRequest -Uri $sync.StatsUrl  -UseBasicParsing -TimeoutSec 15 -Headers $h
        $rg = Invoke-WebRequest -Uri $sync.GroupsUrl -UseBasicParsing -TimeoutSec 15 -Headers $h
        $sync.StatsJson  = [System.Text.Encoding]::UTF8.GetString($rs.RawContentStream.ToArray())
        $sync.GroupsJson = [System.Text.Encoding]::UTF8.GetString($rg.RawContentStream.ToArray())
        $sync.Seq = [int]$sync.Seq + 1; $sync.Status = 'ok'
    } catch { $sync.Status = 'error'; $sync.Err = $_.Exception.Message }
    # 接続済みなら 15 秒間隔、未接続なら 3 秒間隔。Stop には即応。
    $waitMs = if ($sync.Status -eq 'ok') { 15000 } else { 3000 }
    $slept = 0
    while ($slept -lt $waitMs -and -not $sync.Stop) { Start-Sleep -Milliseconds 200; $slept += 200 }
}
'@

$bgRunspace = [runspacefactory]::CreateRunspace()
$bgRunspace.ApartmentState = 'MTA'
$bgRunspace.ThreadOptions = 'ReuseThread'
$bgRunspace.Open()
$bgRunspace.SessionStateProxy.SetVariable('sync', $sync)
$bgPs = [powershell]::Create()
$bgPs.Runspace = $bgRunspace
[void]$bgPs.AddScript($workerBody)
$bgHandle = $bgPs.BeginInvoke()

# ============================================================================
# UI 側: 軽量タイマー（250ms）。新着データ(Seq 変化)かつ内容変化時のみ再描画。
# ============================================================================
$script:LastSeq = -1
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 250
$uiTimer.Add_Tick({
        if ($sync.Seq -ne $script:LastSeq) {
            $script:LastSeq = $sync.Seq
            $sig = [string]$sync.GroupsJson + '|' + [string]$sync.StatsJson
            if ($sig -ne $script:LastSig) {
                $script:LastSig = $sig
                Build-Tree -GroupsJson $sync.GroupsJson -StatsJson $sync.StatsJson
            }
            $status.Text = ("Last updated {0}   /   source: api.wfc.wiilink24.com" -f (Get-Date -Format 'HH:mm:ss'))
        }
        elseif ($script:LastSeq -lt 0) {
            if ($sync.Status -eq 'error') { $status.Text = "Retrying...  " + $sync.Err + "  (" + (Get-Date -Format 'HH:mm:ss') + ")" }
            else { $status.Text = "Connecting... (api.wfc.wiilink24.com)" }
        }
    })
$form.Add_Shown({ $uiTimer.Start() })

$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}
        try { $sync.Stop = $true } catch {}
        try { Start-Sleep -Milliseconds 120 } catch {}
        try { $bgPs.Stop() } catch {}
        try { $bgPs.Dispose() } catch {}
        try { $bgRunspace.Dispose() } catch {}
    })

# ============================================================================
# 診断モード
# ============================================================================
if ($SelfTest) {
    $log = Join-Path $env:TEMP 'wiilink_selftest.log'
    Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        L "FORM BUILT OK; controls=$($form.Controls.Count)"
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline -and [int]$sync.Seq -lt 1) { Start-Sleep -Milliseconds 250 }
        L "Worker Seq=$($sync.Seq)  Status=$($sync.Status)"
        L ("StatsJson=" + $sync.StatsJson)
        Build-Tree -GroupsJson $sync.GroupsJson -StatsJson $sync.StatsJson
        L ("Stats header=" + $lblStats.Text)
        L ("Room nodes=" + $tree.Nodes.Count)
        foreach ($rn in $tree.Nodes) {
            L ("  ROOM: " + $rn.Text)
            foreach ($pn in $rn.Nodes) { L ("     PLAYER: " + $pn.Text + "  [pid=" + $pn.Tag.Pid + " role=" + $pn.Tag.Role + "]") }
        }
        if ($tree.Nodes.Count -gt 0 -and $tree.Nodes[0].Nodes.Count -gt 0) {
            Show-NodeDetail $tree.Nodes[0].Nodes[0]
            L ("Selected detail: Name=" + $detail.Name.Text + " Fc=" + $detail.Fc.Text + " Role=" + $detail.Role.Text + " Room=" + $detail.RoomId.Text + " Type=" + $detail.Type.Text + " Joinable=" + $detail.Joinable.Text)
        }
        L "RESULT: SUCCESS"
    } catch {
        L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace)
    } finally {
        try { $sync.Stop = $true; Start-Sleep -Milliseconds 150; $bgPs.Stop(); $bgPs.Dispose(); $bgRunspace.Dispose() } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
