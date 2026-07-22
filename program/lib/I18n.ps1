<#
    I18n.ps1 — 多言語文字列（日本語 / 英語）の単一ソース

    OS の UI 言語が日本語なら日本語、それ以外は英語を返す。環境変数 MPH_LANG=ja|en で上書き可。

    公開関数:
      Get-MphLang                 … 'ja' または 'en'
      Get-MphI18n  [-Lang]        … 現在言語の文字列テーブル（ハッシュテーブル）を返す
                                     UI 文言 + データ用サブマップ（olStat/status/mode/...）を含む
#>

function Get-MphLang {
    if ($env:MPH_LANG -eq 'ja' -or $env:MPH_LANG -eq 'en') { return $env:MPH_LANG }
    try { if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ja') { return 'ja' } } catch {}
    return 'en'
}

# 大文字小文字を区別するマップ（ol_stat は G/g, C/c を区別する必要があるため）
function New-OrdinalMap {
    param([string[]]$Keys, [string[]]$Values)
    $h = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    for ($i = 0; $i -lt $Keys.Count; $i++) { $h[$Keys[$i]] = $Values[$i] }
    return $h
}

function Get-MphI18n {
    param([string]$Lang = (Get-MphLang))
    if ($Lang -eq 'ja') {
        return @{
            lang = 'ja'
            updateEvery = '更新間隔:'; refresh = '↻ 更新'; connecting = '接続中...'; refreshing = '更新中...'
            intervalLabel = '間隔'; statusLabel = '状態'; nobody = '(オンラインなし)'; connectingNode = '(接続中...)'
            chromeNotFound = 'Chrome/Edge が見つかりません'; updatedFmt = '(更新 {0})'
            wmOnline = 'オンライン'; wlOn = 'オンライン'; wlAct = 'アクティブ'; wlGrp = 'グループ'
            fcCap = 'フレンドコード:'; onlineCap = 'オンライン状態:'; statusCap = 'ステータス:'; modeCap = 'モード:'
            playersCap = '人数:'; joinCap = '参加:'; roleCap = '役割:'; pidCap = 'PID:'; connFailCap = '接続失敗:'; createdCap = '作成:'
            roomFmt = '{0} の部屋'; awaitingHost = 'ホスト待ち'; roleHost = 'ホスト'; roleMember = 'メンバー'
            diagnosticLog = '診断ログ'; logExpand = 'ログ ▼'; logCollapse = 'ログ ▲'; logCopy = 'コピー'; logClear = '消去'
            logAutoScroll = '自動スクロール'; logDetails = '詳細'; logCopied = '診断ログをクリップボードへコピーしました'
            intervals = [ordered]@{ '15秒' = 15000; '30秒' = 30000; '1分' = 60000; '2分' = 120000; '5分' = 300000 }
            status = @{ '0' = 'オフライン'; '1' = 'オンライン（待機中）'; '2' = 'ルーム/グローバルのゲスト'; '3' = 'グローバル検索中'; '4' = 'プライベートルーム接続中'; '5' = 'ルーム/グローバルのホスト'; '6' = 'ホスト' }
            mode = @{ '0' = 'サバイバル / なし'; '1' = 'バトル / バウンティ'; '2' = 'ディフェンダー / キャプチャ'; '3' = 'プライムハンター / ノード' }
            joinFriends = 'フレンドのみ'; joinRivals = 'ライバルのみ'; joinBoth = 'フレンドとライバル'
            wlPublic = '公開'; wlFriends = 'フレンド'; wlJoinable = '参加可'; wlNotJoinable = '参加不可'
            olStat = (New-OrdinalMap @('o', 'P', 'G', 'c', 'w', 'A', 'R', 'B', 'h', 'g', 'v', 'S', 'C') @('オンライン', 'プライベートルーム', 'グローバル', 'リージョン', 'ワールドワイド', 'アクティブ', 'レース', 'バトル', 'ホスト', 'ゲスト', '観戦者', 'グローバル検索中', 'ルーム接続中'))
        }
    }
    return @{
        lang = 'en'
        updateEvery = 'Update every:'; refresh = '↻ Refresh'; connecting = 'Connecting...'; refreshing = 'Refreshing...'
        intervalLabel = 'Interval'; statusLabel = 'status'; nobody = '(Nobody online)'; connectingNode = '(connecting...)'
        chromeNotFound = 'Chrome/Edge not found'; updatedFmt = '(updated {0})'
        wmOnline = 'Online'; wlOn = 'On'; wlAct = 'Act'; wlGrp = 'Grp'
        fcCap = 'Friend Code:'; onlineCap = 'Online:'; statusCap = 'Status:'; modeCap = 'Mode:'
        playersCap = 'Players:'; joinCap = 'Join:'; roleCap = 'Role:'; pidCap = 'PID:'; connFailCap = 'Conn fails:'; createdCap = 'Created:'
        roomFmt = "{0}'s room"; awaitingHost = 'Awaiting host'; roleHost = 'Host'; roleMember = 'Member'
        diagnosticLog = 'Diagnostic log'; logExpand = 'Log ▼'; logCollapse = 'Log ▲'; logCopy = 'Copy'; logClear = 'Clear'
        logAutoScroll = 'Auto-scroll'; logDetails = 'Details'; logCopied = 'Diagnostic log copied to clipboard'
        intervals = [ordered]@{ '15 sec' = 15000; '30 sec' = 30000; '1 min' = 60000; '2 min' = 120000; '5 min' = 300000 }
        status = @{ '0' = 'Offline'; '1' = 'Online (idle)'; '2' = 'Guest (Room/Global)'; '3' = 'Searching (Global)'; '4' = 'Connecting (Private Room)'; '5' = 'Host (Room/Global)'; '6' = 'Host' }
        mode = @{ '0' = 'Survival / None'; '1' = 'Battle / Bounty'; '2' = 'Defender / Capture'; '3' = 'Prime Hunter / Nodes' }
        joinFriends = 'Friends Only'; joinRivals = 'Rivals Only'; joinBoth = 'Friends and Rivals'
        wlPublic = 'Public'; wlFriends = 'Friends'; wlJoinable = 'Joinable'; wlNotJoinable = 'Not joinable'
        olStat = (New-OrdinalMap @('o', 'P', 'G', 'c', 'w', 'A', 'R', 'B', 'h', 'g', 'v', 'S', 'C') @('Online', 'Private Room', 'Global', 'Region', 'Worldwide', 'Active', 'Race', 'Battle', 'Host', 'Guest', 'Spectator', 'Searching (Global)', 'Connecting (Room)'))
    }
}