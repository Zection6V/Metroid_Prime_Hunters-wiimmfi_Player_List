<#
    TreeRender.ps1 — TreeView 描画の共有ヘルパ（3 ビューワ共通の表示ロジック）

    データ取得（WiimmfiSource / WiiLinkSource）とは責務を分離。ここは「正規化済み
    JSON を受け取り TreeView と見出しラベルを更新する」ことだけに責任を持つ。

    公開関数:
      Update-WiimmfiTree -Tree <TreeView> -Head <Label> -Json <string> -Colors <hashtable>
      Update-WiiLinkTree -Tree <TreeView> -Head <Label> -Json <string> -Colors <hashtable>

    $Colors は @{ cream; dim; cyan; red; orange; green } を期待。
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
    param($Tree, $Head, [string]$Json, $Colors)
    $d = $null; try { $d = $Json | ConvertFrom-Json } catch {}
    if (-not $d) { return }
    if (-not $d.ok) {
        if ($d.error -eq 'no-browser') { $Head.Text = "Wiimmfi  -  Chrome/Edge not found"; $Head.ForeColor = $Colors.red }
        else { $Head.Text = "Wiimmfi  -  connecting..."; $Head.ForeColor = $Colors.dim }
        if ($Tree.Nodes.Count -eq 0) { (Add-TreeChild $Tree '(connecting...)' $Colors.dim) | Out-Null }
        return
    }
    $Head.ForeColor = $Colors.cyan
    $Head.Text = ("Wiimmfi  -  Online: {0}   (updated {1})" -f $d.online, (Get-Date -Format 'HH:mm:ss'))

    if (-not $Tree.Tag) { $Tree.Tag = @{ Sig = '' } }
    if ($Json -eq $Tree.Tag.Sig) { return }   # 内容に変化が無ければ作り直さない
    $Tree.Tag.Sig = $Json

    $selKey = if ($Tree.SelectedNode -and $Tree.SelectedNode.Tag) { $Tree.SelectedNode.Tag.Key } else { $null }
    $Tree.BeginUpdate(); $Tree.Nodes.Clear()
    $players = @($d.players)
    if ($players.Count -eq 0) { (Add-TreeChild $Tree '(Nobody online)' $Colors.dim) | Out-Null }
    else {
        foreach ($p in $players) {
            $node = $Tree.Nodes.Add([string]$p.Name); $node.ForeColor = $Colors.cream
            $node.Tag = @{ Key = "wm:$($p.Name)" }
            (Add-TreeChild $node ("Friend Code:  {0}" -f $p.Fc) $Colors.dim) | Out-Null
            (Add-TreeChild $node ("Online:       {0}" -f $p.OnlineStatus) $Colors.dim) | Out-Null
            if ($p.PlayerStatus) { (Add-TreeChild $node ("Status:       {0}" -f $p.PlayerStatus) $Colors.dim) | Out-Null }
            if ($p.GameInfo) { (Add-TreeChild $node ("Mode:         {0}" -f $p.GameInfo) $Colors.dim) | Out-Null }
            if ($p.NumPlayers) { (Add-TreeChild $node ("Players:      {0}" -f $p.NumPlayers) $Colors.dim) | Out-Null }
            if ($p.JoinPlayers) { (Add-TreeChild $node ("Join:         {0}" -f $p.JoinPlayers) $Colors.dim) | Out-Null }
        }
    }
    $Tree.EndUpdate()
    if ($selKey) { $n = Find-TreeNodeByKey $Tree.Nodes $selKey; if ($n) { $Tree.SelectedNode = $n } }
}

function Update-WiiLinkTree {
    param($Tree, $Head, [string]$Json, $Colors)
    $d = $null; try { $d = $Json | ConvertFrom-Json } catch {}
    if (-not $d) { return }
    if (-not $d.ok) {
        $Head.Text = "WiiLink  -  connecting..."; $Head.ForeColor = $Colors.dim
        if ($Tree.Nodes.Count -eq 0) { (Add-TreeChild $Tree '(connecting...)' $Colors.dim) | Out-Null }
        return
    }
    $Head.ForeColor = $Colors.green
    $Head.Text = ("WiiLink  -  On {0}  Act {1}  Grp {2}   (updated {3})" -f $d.stats.online, $d.stats.active, $d.stats.groups, (Get-Date -Format 'HH:mm:ss'))

    if (-not $Tree.Tag) { $Tree.Tag = @{ Sig = '' } }
    if ($Json -eq $Tree.Tag.Sig) { return }
    $Tree.Tag.Sig = $Json

    $selKey = if ($Tree.SelectedNode -and $Tree.SelectedNode.Tag) { $Tree.SelectedNode.Tag.Key } else { $null }
    $Tree.BeginUpdate(); $Tree.Nodes.Clear()
    $rooms = @($d.rooms)
    if ($rooms.Count -eq 0) { (Add-TreeChild $Tree '(Nobody online)' $Colors.dim) | Out-Null }
    else {
        foreach ($g in $rooms) {
            $rp = @($g.players)
            $roomNode = $Tree.Nodes.Add(("{0}'s room   ({1})   - {2} - {3}  [{4}p]" -f $g.host, $g.id, $g.type, $g.joinable, $rp.Count))
            $roomNode.ForeColor = $Colors.orange; $roomNode.Tag = @{ Key = "wl-room:$($g.id)" }
            (Add-TreeChild $roomNode ("Created:  {0}" -f $g.created) $Colors.dim) | Out-Null
            foreach ($p in $rp) {
                $pnode = $roomNode.Nodes.Add(("{0}{1}    {2}" -f (&{ if ($p.isHost) { '* ' } else { '  ' } }), $p.name, $p.fc))
                $pnode.ForeColor = if ($p.isHost) { $Colors.cyan } else { $Colors.cream }
                $pnode.Tag = @{ Key = "wl:$($g.id):$($p.name)" }
                (Add-TreeChild $pnode ("Role:        {0}" -f $p.role) $Colors.dim) | Out-Null
                (Add-TreeChild $pnode ("PID:         {0}" -f $p.pid) $Colors.dim) | Out-Null
                (Add-TreeChild $pnode ("Conn fails:  {0}" -f $p.connFail) $Colors.dim) | Out-Null
            }
            $roomNode.Expand()
        }
    }
    $Tree.EndUpdate()
    if ($selKey) { $n = Find-TreeNodeByKey $Tree.Nodes $selKey; if ($n) { $Tree.SelectedNode = $n } }
}
