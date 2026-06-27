<#
    WiiLinkSource.ps1 — WiiLink WFC の情報取得ライブラリ（UI 非依存）

    dot-source して使う:  . "$PSScriptRoot\lib\WiiLinkSource.ps1"
    公開関数:
      Get-WiiLinkData  … stats + groups を取得し、正規化したハッシュテーブルを返す
                         @{ ok; error; stats=@{online;active;groups}; rooms=@(@{ id;host;type;joinable;created;players=@(@{name;fc;pid;role;connFail;isHost}) }) }

    WiiLink は Cloudflare 等の保護が無く、公式 JSON API を素の HTTP GET で取得できる。
      - https://api.wfc.wiilink24.com/api/stats
      - https://api.wfc.wiilink24.com/api/groups
#>

function Get-WiiLinkData {
    param(
        [string]$StatsUrl  = 'https://api.wfc.wiilink24.com/api/stats',
        [string]$GroupsUrl = 'https://api.wfc.wiilink24.com/api/groups',
        [string]$Game      = 'mprimeds',
        [string]$Ua        = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList'
    )
    $result = @{ ok = $false; error = ''; stats = @{ online = 0; active = 0; groups = 0 }; rooms = @() }
    try {
        $h = @{ 'User-Agent' = $Ua }
        # API は Content-Type に charset を持たないため、PS5.1 の .Content では UTF-8 が
        # 文字化けする。生バイトを UTF-8 で明示デコードする。
        $rs = Invoke-WebRequest -Uri $StatsUrl  -UseBasicParsing -TimeoutSec 15 -Headers $h
        $rg = Invoke-WebRequest -Uri $GroupsUrl -UseBasicParsing -TimeoutSec 15 -Headers $h
        $statsJson  = [System.Text.Encoding]::UTF8.GetString($rs.RawContentStream.ToArray())
        $groupsJson = [System.Text.Encoding]::UTF8.GetString($rg.RawContentStream.ToArray())

        $s = $statsJson | ConvertFrom-Json
        if ($s.$Game) {
            $result.stats = @{ online = [int]$s.$Game.online; active = [int]$s.$Game.active; groups = [int]$s.$Game.groups }
        }

        $all = $groupsJson | ConvertFrom-Json
        $rooms = @()
        foreach ($g in @($all | Where-Object { $_.game -eq $Game })) {
            $typeLabel = if ($g.type -eq 'private') { 'Friends' } elseif ($g.type -eq 'anybody') { 'Public' } else { [string]$g.type }
            $joinLabel = if ($g.suspend) { 'Not joinable' } else { 'Joinable' }
            $created = [string]$g.created
            try { $created = ([datetime]$g.created).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } catch {}

            $hostKey = [string]$g.host
            $players = @()
            foreach ($pp in @($g.players.PSObject.Properties | Sort-Object { [int]$_.Name })) {
                $p = $pp.Value
                $isHost = ($pp.Name -eq $hostKey)
                $players += @{
                    name = [string]$p.name; fc = [string]$p.fc; pid = [string]$p.pid
                    role = (&{ if ($isHost) { 'Host' } else { 'Member' } }); connFail = [string]$p.conn_fail; isHost = $isHost
                }
            }
            $hostName = 'Awaiting host'
            $hp = @($players | Where-Object { $_.isHost })
            if ($hp.Count -gt 0) { $hostName = $hp[0].name }

            $rooms += @{ id = [string]$g.id; host = $hostName; type = $typeLabel; joinable = $joinLabel; created = $created; players = $players }
        }
        $result.rooms = $rooms
        $result.ok = $true
    } catch {
        $result.error = $_.Exception.Message
    }
    return $result
}
