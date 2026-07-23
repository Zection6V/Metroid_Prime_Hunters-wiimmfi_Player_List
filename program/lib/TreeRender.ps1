<#
    TreeRender.ps1 — TreeView 描画の共有ヘルパ（3 ビューワ共通の表示ロジック）

    データ取得（WiimmfiSource / WiiLinkSource）とは責務を分離。ここは「正規化済み
    JSON を受け取り TreeView と見出しラベルを更新する」ことだけに責任を持つ。

    公開関数:
      Update-WiimmfiTree -Tree <TreeView> -Head <Label> -Json <string> -Colors <hashtable> -I18n <hashtable>
      Update-WiiLinkTree -Tree <TreeView> -Head <Label> -Json <string> -Colors <hashtable> -I18n <hashtable>

    $Colors は @{ cream; dim; cyan; red; orange; green }、$I18n は lib\I18n.ps1 の Get-MphI18n。
    （データ値（状態・種別など）は取得時に言語化済み。ここはキャプション等のみ言語化する）
#>

function Add-TreeChild($parent, $text, $color) {
    $n = $parent.Nodes.Add($text); $n.ForeColor = $color; return $n
}

function Find-TreeNodeByKey($nodes, [string]$key) {
    foreach ($n in $nodes) {
        if ($n.Tag -and $n.Tag.Key -eq $key) { return $n }
        $c = Find-TreeNodeByKey $n.Nodes $key; if ($c) { return $c }
    }
    return $null
}

function Update-WiimmfiTree {
    param($Tree, $Head, [string]$Json, $Colors, $I18n)
    $d = $null; try { $d = $Json | ConvertFrom-Json } catch {}
    if (-not $d) { return }
    if (-not $d.ok) {
        if ($d.error -eq 'no-browser') { $Head.Text = "Wiimmfi  -  " + $I18n.chromeNotFound; $Head.ForeColor = $Colors.red }
        else { $Head.Text = "Wiimmfi  -  " + $I18n.connecting; $Head.ForeColor = $Colors.dim }
        if ($Tree.Nodes.Count -eq 0) { (Add-TreeChild $Tree $I18n.connectingNode $Colors.dim) | Out-Null }
        return
    }
    $Head.ForeColor = $Colors.cyan
    $Head.Text = ("Wiimmfi  -  {0}: {1}   {2}" -f $I18n.wmOnline, $d.online, ($I18n.updatedFmt -f (Get-Date -Format 'HH:mm:ss')))

    if (-not $Tree.Tag) { $Tree.Tag = @{ Sig = '' } }
    if ($Json -eq $Tree.Tag.Sig) { return }   # 内容に変化が無ければ作り直さない
    $Tree.Tag.Sig = $Json

    $selKey = if ($Tree.SelectedNode -and $Tree.SelectedNode.Tag) { $Tree.SelectedNode.Tag.Key } else { $null }
    $Tree.BeginUpdate(); $Tree.Nodes.Clear()
    $players = @($d.players)
    if ($players.Count -eq 0) { (Add-TreeChild $Tree $I18n.nobody $Colors.dim) | Out-Null }
    else {
        foreach ($p in $players) {
            $node = $Tree.Nodes.Add([string]$p.Name); $node.ForeColor = $Colors.cream
            $node.Tag = @{ Key = "wm:$($p.Name)" }
            (Add-TreeChild $node ("{0,-15}{1}" -f $I18n.fcCap, $p.Fc) $Colors.dim) | Out-Null
            (Add-TreeChild $node ("{0,-15}{1}" -f $I18n.onlineCap, $p.OnlineStatus) $Colors.dim) | Out-Null
            if ($p.PlayerStatus) { (Add-TreeChild $node ("{0,-15}{1}" -f $I18n.statusCap, $p.PlayerStatus) $Colors.dim) | Out-Null }
            if ($p.GameInfo) { (Add-TreeChild $node ("{0,-15}{1}" -f $I18n.modeCap, $p.GameInfo) $Colors.dim) | Out-Null }
            if ($p.NumPlayers) { (Add-TreeChild $node ("{0,-15}{1}" -f $I18n.playersCap, $p.NumPlayers) $Colors.dim) | Out-Null }
            if ($p.JoinPlayers) { (Add-TreeChild $node ("{0,-15}{1}" -f $I18n.joinCap, $p.JoinPlayers) $Colors.dim) | Out-Null }
        }
    }
    $Tree.EndUpdate()
    if ($selKey) { $n = Find-TreeNodeByKey $Tree.Nodes $selKey; if ($n) { $Tree.SelectedNode = $n } }
}

function Update-WiiLinkTree {
    param($Tree, $Head, [string]$Json, $Colors, $I18n)
    $d = $null; try { $d = $Json | ConvertFrom-Json } catch {}
    if (-not $d) { return }
    if (-not $d.ok) {
        # WiiLink は Cloudflare 等が無いので、ok でない＝実エラー。原因をそのまま表示する。
        $msg = if ($d.error) { [string]$d.error } else { $I18n.connecting }
        $col = if ($d.error) { $Colors.red } else { $Colors.dim }
        $Head.Text = "WiiLink  -  " + $msg; $Head.ForeColor = $col
        if ($Tree.Nodes.Count -eq 0) { (Add-TreeChild $Tree $msg $col) | Out-Null }
        return
    }
    $Head.ForeColor = $Colors.green
    $Head.Text = ("WiiLink  -  {0} {1}  {2} {3}  {4} {5}   {6}" -f $I18n.wlOn, $d.stats.online, $I18n.wlAct, $d.stats.active, $I18n.wlGrp, $d.stats.groups, ($I18n.updatedFmt -f (Get-Date -Format 'HH:mm:ss')))

    if (-not $Tree.Tag) { $Tree.Tag = @{ Sig = '' } }
    if ($Json -eq $Tree.Tag.Sig) { return }
    $Tree.Tag.Sig = $Json

    $selKey = if ($Tree.SelectedNode -and $Tree.SelectedNode.Tag) { $Tree.SelectedNode.Tag.Key } else { $null }
    $Tree.BeginUpdate(); $Tree.Nodes.Clear()
    $rooms = @($d.rooms)
    if ($rooms.Count -eq 0) {
        $statsOnline = [int]$d.stats.online
        $statsActive = [int]$d.stats.active
        $statsGroups = [int]$d.stats.groups
        if ($statsOnline -gt 0 -or $statsActive -gt 0 -or $statsGroups -gt 0) {
            # groups=0 でも stats に対象ゲームが存在する場合、オンライン情報を消さない。
            $statsNode = $Tree.Nodes.Add(("{0}: {1}   {2}: {3}   {4}: {5}" -f $I18n.wlOn, $statsOnline, $I18n.wlAct, $statsActive, $I18n.wlGrp, $statsGroups))
            $statsNode.ForeColor = $Colors.green
            $statsNode.Tag = @{ Key = 'wl-stats' }
        } else {
            (Add-TreeChild $Tree $I18n.nobody $Colors.dim) | Out-Null
        }
    }
    else {
        foreach ($g in $rooms) {
            $rp = @($g.players)
            $roomNode = $Tree.Nodes.Add(("{0}   ({1})   - {2} - {3}  [{4}p]" -f ($I18n.roomFmt -f $g.host), $g.id, $g.type, $g.joinable, $rp.Count))
            $roomNode.ForeColor = $Colors.orange; $roomNode.Tag = @{ Key = "wl-room:$($g.id)" }
            (Add-TreeChild $roomNode ("{0,-13}{1}" -f $I18n.createdCap, $g.created) $Colors.dim) | Out-Null
            foreach ($p in $rp) {
                $pnode = $roomNode.Nodes.Add(("{0}{1}    {2}" -f (&{ if ($p.isHost) { '* ' } else { '  ' } }), $p.name, $p.fc))
                $pnode.ForeColor = if ($p.isHost) { $Colors.cyan } else { $Colors.cream }
                $pnode.Tag = @{ Key = "wl:$($g.id):$($p.name)" }
                (Add-TreeChild $pnode ("{0,-13}{1}" -f $I18n.roleCap, $p.role) $Colors.dim) | Out-Null
                (Add-TreeChild $pnode ("{0,-13}{1}" -f $I18n.pidCap, $p.pid) $Colors.dim) | Out-Null
                (Add-TreeChild $pnode ("{0,-13}{1}" -f $I18n.connFailCap, $p.connFail) $Colors.dim) | Out-Null
            }
            $roomNode.Expand()
        }
    }
    $Tree.EndUpdate()
    if ($selKey) { $n = Find-TreeNodeByKey $Tree.Nodes $selKey; if ($n) { $Tree.SelectedNode = $n } }
}
