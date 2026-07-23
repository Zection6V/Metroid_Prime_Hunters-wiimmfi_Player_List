<#
    I18n.ps1 — GUI と表示データ用の多言語文字列の単一ソース

    対応言語: ja / en / de / fr / it / es
    OS の UI 言語を自動検出し、環境変数 MPH_LANG で上書き可能。
#>

function Get-MphLang {
    $supported = @('ja', 'en', 'de', 'fr', 'it', 'es')
    $override = ([string]$env:MPH_LANG).Trim().ToLowerInvariant()
    if ($supported -contains $override) { return $override }
    try {
        $osLang = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName.ToLowerInvariant()
        if ($supported -contains $osLang) { return $osLang }
    } catch {}
    return 'en'
}

function New-OrdinalMap {
    param([string[]]$Keys, [string[]]$Values)
    $h = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
    for ($i = 0; $i -lt $Keys.Count; $i++) { $h[$Keys[$i]] = $Values[$i] }
    return $h
}

function Get-MphI18n {
    param([string]$Lang = (Get-MphLang))
    $Lang = ([string]$Lang).Trim().ToLowerInvariant()

    switch ($Lang) {
        'ja' {
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
                logSource = '表示:'; logAll = 'すべて'; logWiimmfi = 'Wiimmfi'; logWiiLink = 'WiiLink'; logApp = 'アプリ'
                wlTransport = 'WiiLink取得:'; wlDirect = '直接API'; wlBrowser = 'Chrome/Edge'; wlTransportChanged = 'WiiLink取得方式を {0} に変更しました'
                wlRoomVisibilityNote = '※ WiiLinkの仕様上、部屋一覧は2人以上いる場合のみ表示されます。'
                intervals = [ordered]@{ '15秒' = 15000; '30秒' = 30000; '1分' = 60000; '2分' = 120000; '5分' = 300000 }
                status = @{ '0' = 'オフライン'; '1' = 'オンライン（待機中）'; '2' = 'ルーム/グローバルのゲスト'; '3' = 'グローバル検索中'; '4' = 'プライベートルーム接続中'; '5' = 'ルーム/グローバルのホスト'; '6' = 'ホスト' }
                mode = @{ '0' = 'サバイバル / なし'; '1' = 'バトル / バウンティ'; '2' = 'ディフェンダー / キャプチャ'; '3' = 'プライムハンター / ノード' }
                joinFriends = 'フレンドのみ'; joinRivals = 'ライバルのみ'; joinBoth = 'フレンドとライバル'
                wlPublic = '公開'; wlFriends = 'フレンド'; wlJoinable = '参加可'; wlNotJoinable = '参加不可'
                olStat = (New-OrdinalMap @('o', 'P', 'G', 'c', 'w', 'A', 'R', 'B', 'h', 'g', 'v', 'S', 'C') @('オンライン', 'プライベートルーム', 'グローバル', 'リージョン', 'ワールドワイド', 'アクティブ', 'レース', 'バトル', 'ホスト', 'ゲスト', '観戦者', 'グローバル検索中', 'ルーム接続中'))
            }
        }
        'de' {
            return @{
                lang = 'de'
                updateEvery = 'Aktualisierung:'; refresh = '↻ Aktualisieren'; connecting = 'Verbindung wird hergestellt...'; refreshing = 'Wird aktualisiert...'
                intervalLabel = 'Intervall'; statusLabel = 'Status'; nobody = '(Niemand online)'; connectingNode = '(Verbindung wird hergestellt...)'
                chromeNotFound = 'Chrome/Edge wurde nicht gefunden'; updatedFmt = '(aktualisiert {0})'
                wmOnline = 'Online'; wlOn = 'Online'; wlAct = 'Aktiv'; wlGrp = 'Gruppen'
                fcCap = 'Freundescode:'; onlineCap = 'Online-Status:'; statusCap = 'Status:'; modeCap = 'Modus:'
                playersCap = 'Spieler:'; joinCap = 'Beitritt:'; roleCap = 'Rolle:'; pidCap = 'PID:'; connFailCap = 'Verbindungsfehler:'; createdCap = 'Erstellt:'
                roomFmt = 'Raum von {0}'; awaitingHost = 'Warten auf Host'; roleHost = 'Host'; roleMember = 'Mitglied'
                diagnosticLog = 'Diagnoseprotokoll'; logExpand = 'Protokoll ▼'; logCollapse = 'Protokoll ▲'; logCopy = 'Kopieren'; logClear = 'Löschen'
                logAutoScroll = 'Automatisch scrollen'; logDetails = 'Details'; logCopied = 'Diagnoseprotokoll wurde in die Zwischenablage kopiert'
                logSource = 'Quelle:'; logAll = 'Alle'; logWiimmfi = 'Wiimmfi'; logWiiLink = 'WiiLink'; logApp = 'Anwendung'
                wlTransport = 'WiiLink über:'; wlDirect = 'Direkte API'; wlBrowser = 'Chrome/Edge'; wlTransportChanged = 'WiiLink-Abrufmethode wurde auf {0} geändert'
                wlRoomVisibilityNote = 'Hinweis: WiiLink zeigt einen Raum erst an, wenn mindestens zwei Spieler darin sind.'
                intervals = [ordered]@{ '15 Sek.' = 15000; '30 Sek.' = 30000; '1 Min.' = 60000; '2 Min.' = 120000; '5 Min.' = 300000 }
                status = @{ '0' = 'Offline'; '1' = 'Online (wartend)'; '2' = 'Gast (Raum/Global)'; '3' = 'Globale Suche'; '4' = 'Verbindung mit privatem Raum'; '5' = 'Host (Raum/Global)'; '6' = 'Host' }
                mode = @{ '0' = 'Überleben / Keiner'; '1' = 'Kampf / Kopfgeld'; '2' = 'Verteidiger / Eroberung'; '3' = 'Prime Hunter / Knoten' }
                joinFriends = 'Nur Freunde'; joinRivals = 'Nur Rivalen'; joinBoth = 'Freunde und Rivalen'
                wlPublic = 'Öffentlich'; wlFriends = 'Freunde'; wlJoinable = 'Beitritt möglich'; wlNotJoinable = 'Kein Beitritt möglich'
                olStat = (New-OrdinalMap @('o', 'P', 'G', 'c', 'w', 'A', 'R', 'B', 'h', 'g', 'v', 'S', 'C') @('Online', 'Privater Raum', 'Global', 'Region', 'Weltweit', 'Aktiv', 'Rennen', 'Kampf', 'Host', 'Gast', 'Zuschauer', 'Globale Suche', 'Raumverbindung'))
            }
        }
        'fr' {
            return @{
                lang = 'fr'
                updateEvery = 'Actualisation toutes les :'; refresh = '↻ Actualiser'; connecting = 'Connexion...'; refreshing = 'Actualisation...'
                intervalLabel = 'Intervalle'; statusLabel = 'État'; nobody = '(Personne en ligne)'; connectingNode = '(connexion...)'
                chromeNotFound = 'Chrome/Edge introuvable'; updatedFmt = '(actualisé {0})'
                wmOnline = 'En ligne'; wlOn = 'En ligne'; wlAct = 'Actifs'; wlGrp = 'Groupes'
                fcCap = 'Code ami :'; onlineCap = 'État en ligne :'; statusCap = 'État :'; modeCap = 'Mode :'
                playersCap = 'Joueurs :'; joinCap = 'Accès :'; roleCap = 'Rôle :'; pidCap = 'PID :'; connFailCap = 'Échecs de connexion :'; createdCap = 'Créé :'
                roomFmt = 'Salle de {0}'; awaitingHost = "En attente de l'hôte"; roleHost = 'Hôte'; roleMember = 'Membre'
                diagnosticLog = 'Journal de diagnostic'; logExpand = 'Journal ▼'; logCollapse = 'Journal ▲'; logCopy = 'Copier'; logClear = 'Effacer'
                logAutoScroll = 'Défilement automatique'; logDetails = 'Détails'; logCopied = 'Journal de diagnostic copié dans le presse-papiers'
                logSource = 'Source :'; logAll = 'Tous'; logWiimmfi = 'Wiimmfi'; logWiiLink = 'WiiLink'; logApp = 'Application'
                wlTransport = 'WiiLink via :'; wlDirect = 'API directe'; wlBrowser = 'Chrome/Edge'; wlTransportChanged = 'Méthode de récupération WiiLink changée en {0}'
                wlRoomVisibilityNote = "Remarque : WiiLink n'affiche une salle que lorsqu'au moins deux joueurs y sont présents."
                intervals = [ordered]@{ '15 s' = 15000; '30 s' = 30000; '1 min' = 60000; '2 min' = 120000; '5 min' = 300000 }
                status = @{ '0' = 'Hors ligne'; '1' = 'En ligne (en attente)'; '2' = 'Invité (Salle/Global)'; '3' = 'Recherche globale'; '4' = 'Connexion à une salle privée'; '5' = 'Hôte (Salle/Global)'; '6' = 'Hôte' }
                mode = @{ '0' = 'Survie / Aucun'; '1' = 'Combat / Prime'; '2' = 'Défenseur / Capture'; '3' = 'Prime Hunter / Nœuds' }
                joinFriends = 'Amis uniquement'; joinRivals = 'Rivaux uniquement'; joinBoth = 'Amis et rivaux'
                wlPublic = 'Publique'; wlFriends = 'Amis'; wlJoinable = 'Accessible'; wlNotJoinable = 'Non accessible'
                olStat = (New-OrdinalMap @('o', 'P', 'G', 'c', 'w', 'A', 'R', 'B', 'h', 'g', 'v', 'S', 'C') @('En ligne', 'Salle privée', 'Global', 'Région', 'Monde entier', 'Actif', 'Course', 'Combat', 'Hôte', 'Invité', 'Spectateur', 'Recherche globale', 'Connexion à la salle'))
            }
        }
        'it' {
            return @{
                lang = 'it'
                updateEvery = 'Aggiorna ogni:'; refresh = '↻ Aggiorna'; connecting = 'Connessione...'; refreshing = 'Aggiornamento...'
                intervalLabel = 'Intervallo'; statusLabel = 'Stato'; nobody = '(Nessuno online)'; connectingNode = '(connessione...)'
                chromeNotFound = 'Chrome/Edge non trovato'; updatedFmt = '(aggiornato {0})'
                wmOnline = 'Online'; wlOn = 'Online'; wlAct = 'Attivi'; wlGrp = 'Gruppi'
                fcCap = 'Codice amico:'; onlineCap = 'Stato online:'; statusCap = 'Stato:'; modeCap = 'Modalità:'
                playersCap = 'Giocatori:'; joinCap = 'Accesso:'; roleCap = 'Ruolo:'; pidCap = 'PID:'; connFailCap = 'Errori di connessione:'; createdCap = 'Creata:'
                roomFmt = 'Stanza di {0}'; awaitingHost = "In attesa dell'host"; roleHost = 'Host'; roleMember = 'Membro'
                diagnosticLog = 'Registro diagnostico'; logExpand = 'Registro ▼'; logCollapse = 'Registro ▲'; logCopy = 'Copia'; logClear = 'Cancella'
                logAutoScroll = 'Scorrimento automatico'; logDetails = 'Dettagli'; logCopied = 'Registro diagnostico copiato negli appunti'
                logSource = 'Origine:'; logAll = 'Tutti'; logWiimmfi = 'Wiimmfi'; logWiiLink = 'WiiLink'; logApp = 'Applicazione'
                wlTransport = 'WiiLink tramite:'; wlDirect = 'API diretta'; wlBrowser = 'Chrome/Edge'; wlTransportChanged = 'Metodo di acquisizione WiiLink cambiato in {0}'
                wlRoomVisibilityNote = 'Nota: WiiLink mostra una stanza solo quando sono presenti almeno due giocatori.'
                intervals = [ordered]@{ '15 sec' = 15000; '30 sec' = 30000; '1 min' = 60000; '2 min' = 120000; '5 min' = 300000 }
                status = @{ '0' = 'Offline'; '1' = 'Online (in attesa)'; '2' = 'Ospite (Stanza/Globale)'; '3' = 'Ricerca globale'; '4' = 'Connessione a stanza privata'; '5' = 'Host (Stanza/Globale)'; '6' = 'Host' }
                mode = @{ '0' = 'Sopravvivenza / Nessuno'; '1' = 'Battaglia / Taglia'; '2' = 'Difensore / Cattura'; '3' = 'Prime Hunter / Nodi' }
                joinFriends = 'Solo amici'; joinRivals = 'Solo rivali'; joinBoth = 'Amici e rivali'
                wlPublic = 'Pubblica'; wlFriends = 'Amici'; wlJoinable = 'Accessibile'; wlNotJoinable = 'Non accessibile'
                olStat = (New-OrdinalMap @('o', 'P', 'G', 'c', 'w', 'A', 'R', 'B', 'h', 'g', 'v', 'S', 'C') @('Online', 'Stanza privata', 'Globale', 'Regione', 'Tutto il mondo', 'Attivo', 'Gara', 'Battaglia', 'Host', 'Ospite', 'Spettatore', 'Ricerca globale', 'Connessione alla stanza'))
            }
        }
        'es' {
            return @{
                lang = 'es'
                updateEvery = 'Actualizar cada:'; refresh = '↻ Actualizar'; connecting = 'Conectando...'; refreshing = 'Actualizando...'
                intervalLabel = 'Intervalo'; statusLabel = 'Estado'; nobody = '(Nadie en línea)'; connectingNode = '(conectando...)'
                chromeNotFound = 'No se encontró Chrome/Edge'; updatedFmt = '(actualizado {0})'
                wmOnline = 'En línea'; wlOn = 'En línea'; wlAct = 'Activos'; wlGrp = 'Grupos'
                fcCap = 'Código de amigo:'; onlineCap = 'Estado en línea:'; statusCap = 'Estado:'; modeCap = 'Modo:'
                playersCap = 'Jugadores:'; joinCap = 'Acceso:'; roleCap = 'Rol:'; pidCap = 'PID:'; connFailCap = 'Fallos de conexión:'; createdCap = 'Creada:'
                roomFmt = 'Sala de {0}'; awaitingHost = 'Esperando al anfitrión'; roleHost = 'Anfitrión'; roleMember = 'Miembro'
                diagnosticLog = 'Registro de diagnóstico'; logExpand = 'Registro ▼'; logCollapse = 'Registro ▲'; logCopy = 'Copiar'; logClear = 'Borrar'
                logAutoScroll = 'Desplazamiento automático'; logDetails = 'Detalles'; logCopied = 'Registro de diagnóstico copiado al portapapeles'
                logSource = 'Origen:'; logAll = 'Todos'; logWiimmfi = 'Wiimmfi'; logWiiLink = 'WiiLink'; logApp = 'Aplicación'
                wlTransport = 'WiiLink mediante:'; wlDirect = 'API directa'; wlBrowser = 'Chrome/Edge'; wlTransportChanged = 'Método de obtención de WiiLink cambiado a {0}'
                wlRoomVisibilityNote = 'Nota: WiiLink solo muestra una sala cuando hay al menos dos jugadores.'
                intervals = [ordered]@{ '15 s' = 15000; '30 s' = 30000; '1 min' = 60000; '2 min' = 120000; '5 min' = 300000 }
                status = @{ '0' = 'Sin conexión'; '1' = 'En línea (en espera)'; '2' = 'Invitado (Sala/Global)'; '3' = 'Búsqueda global'; '4' = 'Conectando a sala privada'; '5' = 'Anfitrión (Sala/Global)'; '6' = 'Anfitrión' }
                mode = @{ '0' = 'Supervivencia / Ninguno'; '1' = 'Batalla / Recompensa'; '2' = 'Defensor / Captura'; '3' = 'Prime Hunter / Nodos' }
                joinFriends = 'Solo amigos'; joinRivals = 'Solo rivales'; joinBoth = 'Amigos y rivales'
                wlPublic = 'Pública'; wlFriends = 'Amigos'; wlJoinable = 'Se puede entrar'; wlNotJoinable = 'No se puede entrar'
                olStat = (New-OrdinalMap @('o', 'P', 'G', 'c', 'w', 'A', 'R', 'B', 'h', 'g', 'v', 'S', 'C') @('En línea', 'Sala privada', 'Global', 'Región', 'Todo el mundo', 'Activo', 'Carrera', 'Batalla', 'Anfitrión', 'Invitado', 'Espectador', 'Búsqueda global', 'Conectando a sala'))
            }
        }
        default {
            return @{
                lang = 'en'
                updateEvery = 'Update every:'; refresh = '↻ Refresh'; connecting = 'Connecting...'; refreshing = 'Refreshing...'
                intervalLabel = 'Interval'; statusLabel = 'Status'; nobody = '(Nobody online)'; connectingNode = '(connecting...)'
                chromeNotFound = 'Chrome/Edge not found'; updatedFmt = '(updated {0})'
                wmOnline = 'Online'; wlOn = 'On'; wlAct = 'Act'; wlGrp = 'Grp'
                fcCap = 'Friend Code:'; onlineCap = 'Online:'; statusCap = 'Status:'; modeCap = 'Mode:'
                playersCap = 'Players:'; joinCap = 'Join:'; roleCap = 'Role:'; pidCap = 'PID:'; connFailCap = 'Conn fails:'; createdCap = 'Created:'
                roomFmt = "{0}'s room"; awaitingHost = 'Awaiting host'; roleHost = 'Host'; roleMember = 'Member'
                diagnosticLog = 'Diagnostic log'; logExpand = 'Log ▼'; logCollapse = 'Log ▲'; logCopy = 'Copy'; logClear = 'Clear'
                logAutoScroll = 'Auto-scroll'; logDetails = 'Details'; logCopied = 'Diagnostic log copied to clipboard'
                logSource = 'Source:'; logAll = 'All'; logWiimmfi = 'Wiimmfi'; logWiiLink = 'WiiLink'; logApp = 'Application'
                wlTransport = 'WiiLink via:'; wlDirect = 'Direct API'; wlBrowser = 'Chrome/Edge'; wlTransportChanged = 'WiiLink transport changed to {0}'
                wlRoomVisibilityNote = 'Note: WiiLink lists a room only when at least two players are present.'
                intervals = [ordered]@{ '15 sec' = 15000; '30 sec' = 30000; '1 min' = 60000; '2 min' = 120000; '5 min' = 300000 }
                status = @{ '0' = 'Offline'; '1' = 'Online (idle)'; '2' = 'Guest (Room/Global)'; '3' = 'Searching (Global)'; '4' = 'Connecting (Private Room)'; '5' = 'Host (Room/Global)'; '6' = 'Host' }
                mode = @{ '0' = 'Survival / None'; '1' = 'Battle / Bounty'; '2' = 'Defender / Capture'; '3' = 'Prime Hunter / Nodes' }
                joinFriends = 'Friends Only'; joinRivals = 'Rivals Only'; joinBoth = 'Friends and Rivals'
                wlPublic = 'Public'; wlFriends = 'Friends'; wlJoinable = 'Joinable'; wlNotJoinable = 'Not joinable'
                olStat = (New-OrdinalMap @('o', 'P', 'G', 'c', 'w', 'A', 'R', 'B', 'h', 'g', 'v', 'S', 'C') @('Online', 'Private Room', 'Global', 'Region', 'Worldwide', 'Active', 'Race', 'Battle', 'Host', 'Guest', 'Spectator', 'Searching (Global)', 'Connecting (Room)'))
            }
        }
    }
}
