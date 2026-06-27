<#
    Wiimmfi - MPH Player List  (Wiimmfi 専用ビューワ)  — PowerShell + WinForms
    -------------------------------------------------------------------------
    責務分離（SRP）:
      lib\WiimmfiSource.ps1 … 情報取得（Chrome/Edge を CDP 経由で操作し Cloudflare 通過、
                              軽量 /text エンドポイントを取得・解析）
      lib\TreeRender.ps1    … TreeView 描画
      lib\ViewerCommon.ps1  … UI 部品・ワーカー基盤（共通）
      本ファイル            … 画面構成と進行

    依存: Windows + PowerShell 5.1。Chrome もしくは Chromium 版 Edge が必要。
    起動: "Run Wiimmfi Player List.bat"。 -SelfTest で診断モード。
#>
param([switch]$SelfTest)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WiimmfiLib = Join-Path $ScriptDir 'lib\WiimmfiSource.ps1'
. $WiimmfiLib
. (Join-Path $ScriptDir 'lib\TreeRender.ps1')
. (Join-Path $ScriptDir 'lib\ViewerCommon.ps1')
$theme = Get-MphTheme

# ---- GUI ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Wiimmfi - MPH Player List"
$form.Size = New-Object System.Drawing.Size(560, 600)
$form.MinimumSize = New-Object System.Drawing.Size(420, 380)
$form.StartPosition = 'CenterScreen'; $form.BackColor = $theme.bgDark
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$bar = New-TopBar -Theme $theme -Title "Wiimmfi" -TitleColor $theme.orange
$pane = New-TreePanel -Theme $theme -HeadColor $theme.cyan
$status = New-StatusBar -Theme $theme
$form.Controls.Add($pane.Panel); $form.Controls.Add($bar.Panel); $form.Controls.Add($status)
$pane.Panel.SendToBack(); $bar.Panel.BringToFront(); $status.BringToFront()

# ---- ワーカー（Chrome を起動し /text を取得） ----
$sync = [hashtable]::Synchronized(@{
        WiimmfiLib = $WiimmfiLib; WiimmfiUrl = 'https://wiimmfi.de/stats/game/mprimeds'
        IntervalMs = 30000; Stop = $false; Json = $null; Seq = 0; Status = 'starting'; Pid = 0
    })
$worker = @'
. $sync.WiimmfiLib
$ctx = Start-WiimmfiBrowser -Url $sync.WiimmfiUrl
if (-not $ctx.ok) {
    $sync.Json = (@{ ok = $false; error = $ctx.error; online = 0; players = @() } | ConvertTo-Json -Depth 6 -Compress)
    $sync.Seq = [int]$sync.Seq + 1; $sync.Status = $ctx.error
    return
}
$sync.Pid = $ctx.proc.Id
try {
    while (-not $sync.Stop) {
        $data = Get-WiimmfiData -Port $ctx.port
        $sync.Json = ($data | ConvertTo-Json -Depth 8 -Compress)
        $sync.Seq = [int]$sync.Seq + 1
        $sync.Status = if ($data.ok) { 'ok' } else { 'connecting' }
        $waitMs = if ($data.ok) { [int]$sync.IntervalMs } else { 3000 }
        $slept = 0; while ($slept -lt $waitMs -and -not $sync.Stop) { Start-Sleep -Milliseconds 200; $slept += 200 }
    }
} finally { Stop-WiimmfiBrowser -Proc $ctx.proc }
'@
$job = Start-PollWorker -Sync $sync -Body $worker

# ---- UI タイマー ----
$bar.Combo.Add_SelectedIndexChanged({ $sync.IntervalMs = [int]$bar.IntervalMap[[string]$bar.Combo.SelectedItem] })
$script:LastSeq = -1
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 300
$uiTimer.Add_Tick({
        if ($sync.Seq -ne $script:LastSeq) {
            $script:LastSeq = $sync.Seq
            Update-WiimmfiTree -Tree $pane.Tree -Head $pane.Head -Json $sync.Json -Colors $theme.Colors
        }
        $status.Text = ("Interval: {0}     status: {1}" -f [string]$bar.Combo.SelectedItem, $sync.Status)
    })
$form.Add_Shown({ $uiTimer.Start() })
$form.Add_FormClosing({
        try { $uiTimer.Stop() } catch {}; try { $sync.Stop = $true } catch {}; try { Start-Sleep -Milliseconds 200 } catch {}
        Stop-PollWorker $job
        try { if ($sync.Pid -gt 0) { & taskkill /PID $sync.Pid /T /F 2>$null | Out-Null } } catch {}
    })

# ---- 診断モード ----
if ($SelfTest) {
    $log = Join-Path $env:TEMP 'mph_selftest.log'; Remove-Item $log -EA SilentlyContinue
    function L($m) { Add-Content -Path $log -Value $m -Encoding UTF8 }
    try {
        $deadline = (Get-Date).AddSeconds(50)
        while ((Get-Date) -lt $deadline -and $sync.Status -ne 'ok' -and $sync.Status -ne 'no-browser') { Start-Sleep -Milliseconds 300 }
        L ("Seq=$($sync.Seq) Status=$($sync.Status)")
        Update-WiimmfiTree -Tree $pane.Tree -Head $pane.Head -Json $sync.Json -Colors $theme.Colors
        L ("head: " + $pane.Head.Text); L ("player nodes: " + $pane.Tree.Nodes.Count)
        foreach ($pn in $pane.Tree.Nodes) { L ("   " + $pn.Text); foreach ($cn in $pn.Nodes) { L ("      " + $cn.Text) } }
        L "RESULT: SUCCESS"
    } catch { L ("EXCEPTION: " + $_.Exception.Message); L ($_.ScriptStackTrace) }
    finally {
        try { $sync.Stop = $true; Start-Sleep -Milliseconds 200 } catch {}; Stop-PollWorker $job
        try { if ($sync.Pid -gt 0) { Stop-Process -Id $sync.Pid -Force -EA SilentlyContinue } } catch {}
    }
    return
}

[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
