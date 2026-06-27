<#
    WiiLink WFC - MPH Player List  (WiiLink 専用ビューワ)  — PowerShell + WinForms
    ----------------------------------------------------------------------------
    責務分離（SRP）:
      lib\WiiLinkSource.ps1 … 情報取得（公式 JSON API、ブラウザ不要）
      lib\TreeRender.ps1    … TreeView 描画
      lib\ViewerCommon.ps1  … UI 部品・ワーカー基盤（共通）
      本ファイル            … 画面構成と進行

    依存: Windows + PowerShell 5.1 のみ。
    起動: "Run WiiLink Player List.bat"。 -SelfTest で診断モード。
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WiiLinkLib = Join-Path $ScriptDir 'lib\WiiLinkSource.ps1'
. $WiiLinkLib
. (Join-Path $ScriptDir 'lib\TreeRender.ps1')
. (Join-Path $ScriptDir 'lib\ViewerCommon.ps1')
. (Join-Path $ScriptDir 'lib\I18n.ps1')
$theme = Get-MphTheme
$i18n = Get-MphI18n

# ---- GUI ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "WiiLink WFC - MPH Player List"
$form.Size = New-Object System.Drawing.Size(560, 600)
$form.MinimumSize = New-Object System.Drawing.Size(420, 380)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $theme.bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$bar = New-TopBar -Theme $theme -Title "WiiLink WFC" -TitleColor $theme.green -I18n $i18n
$pane = New-TreePanel -Theme $theme -HeadColor $theme.green
$status = New-StatusBar -Theme $theme -Text $i18n.connecting
# Dock の解決順のため Fill(コンテンツ) を先に、Top/Bottom を後に追加する（z-order 操作はしない）
$form.Controls.Add($pane.Panel); $form.Controls.Add($bar.Panel); $form.Controls.Add($status)

# ---- ワーカー ----
$sync = [hashtable]::Synchronized(@{
        WiiLinkLib = $WiiLinkLib; Game = 'mprimeds'; Ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MPH-PlayerList'; Lang = $i18n.lang
        IntervalMs = 30000; Stop = $false; Refresh = $false; Json = $null; Seq = 0; Status = 'starting'
    })
$worker = @'
. $sync.WiiLinkLib
while (-not $sync.Stop) {
    $data = Get-WiiLinkData -Game $sync.Game -Ua $sync.Ua -Lang $sync.Lang
    $sync.Json = ($data | ConvertTo-Json -Depth 10 -Compress)
    $sync.Seq = [int]$sync.Seq + 1
    $sync.Status = if ($data.ok) { 'ok' } else { 'error' }
    $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
    $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop -and -not $sync.Refresh) { Start-Sleep -Milliseconds 200; $slept += 200 }
    $sync.Refresh = $false   # Refresh ボタンで待機を打ち切り即時再取得
}
'@
$job = Start-PollWorker -Sync $sync -Body $worker

# ---- UI タイマー ----
$bar.Combo.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$bar.IntervalMap[[string]$bar.Combo.SelectedItem] })
$bar.Refresh.Add_Click({ $sync.Refresh = $true; $status.Text = $i18n.refreshing })
$script:LastSeq = -1
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 300
$uiTimer.Add_Tick({
        if ($sync.Seq -ne $script:LastSeq) {
            $script:LastSeq = $sync.Seq
            Update-WiiLinkTree -Tree $pane.Tree -Head $pane.Head -Json $sync.Json -Colors $theme.Colors -I18n $i18n
        }
        $status.Text = ("{0}: {1}     {2}: {3}" -f $i18n.intervalLabel, $bar.Combo.SelectedItem, $i18n.statusLabel, $sync.Status)
    })
$form.Add_Shown({ $uiTimer.Start() })
$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}; try { $sync.Stop = $true } catch {}; try { Start-Sleep -Milliseconds 150 } catch {}
        Stop-PollWorker $job
    })

# ---- 診断モード ----
if ($SelfTest) {
    $log = Join-Path $env:TEMP 'wiilink_selftest.log'; Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline -and [int]$sync.Seq -lt 1) { Start-Sleep -Milliseconds 250 }
        L ("Seq=$($sync.Seq) Status=$($sync.Status)")
        Update-WiiLinkTree -Tree $pane.Tree -Head $pane.Head -Json $sync.Json -Colors $theme.Colors -I18n $i18n
        L ("head: " + $pane.Head.Text); L ("room nodes: " + $pane.Tree.Nodes.Count)
        foreach ($rn in $pane.Tree.Nodes) { L ("   " + $rn.Text); foreach ($pn in $rn.Nodes) { if ($pn.Tag.Key -like 'wl:*') { L ("      " + $pn.Text) } } }
        L "RESULT: SUCCESS"
    } catch { L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace) }
    finally { try { $sync.Stop = $true; Start-Sleep -Milliseconds 150 } catch {}; Stop-PollWorker $job }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
