$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

Write-Host '== PowerShell syntax validation =='
$parseFailures = @()
Get-ChildItem -Path $programDir -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        foreach ($e in $errors) { $parseFailures += ("{0}:{1}: {2}" -f $_.FullName, $e.Extent.StartLineNumber, $e.Message) }
    }
}
if ($parseFailures.Count -gt 0) { throw ($parseFailures -join [Environment]::NewLine) }
Write-Host 'All PowerShell files parsed successfully.'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $programDir 'lib\WiiLinkSource.ps1')
. (Join-Path $programDir 'lib\LogStore.ps1')
. (Join-Path $programDir 'lib\ViewerCommon.ps1')
. (Join-Path $programDir 'lib\DiagnosticLogView.ps1')

Write-Host '== GUI localization validation =='
$supportedLanguages = @('ja', 'en', 'de', 'fr', 'it', 'es')
$reference = Get-MphI18n -Lang 'en'
$referenceKeys = @($reference.Keys | Sort-Object)
$referenceStatusKeys = @($reference.status.Keys | Sort-Object)
$referenceModeKeys = @($reference.mode.Keys | Sort-Object)
$referenceOlKeys = @($reference.olStat.Keys | Sort-Object)

foreach ($lang in $supportedLanguages) {
    $table = Get-MphI18n -Lang $lang
    Assert-True ($table.lang -eq $lang) ("Language table must report {0}, got {1}" -f $lang, $table.lang)
    Assert-True ((Compare-Object $referenceKeys @($table.Keys | Sort-Object)).Count -eq 0) ("Top-level translation keys differ for {0}" -f $lang)
    Assert-True ((Compare-Object $referenceStatusKeys @($table.status.Keys | Sort-Object)).Count -eq 0) ("Status translation keys differ for {0}" -f $lang)
    Assert-True ((Compare-Object $referenceModeKeys @($table.mode.Keys | Sort-Object)).Count -eq 0) ("Mode translation keys differ for {0}" -f $lang)
    Assert-True ((Compare-Object $referenceOlKeys @($table.olStat.Keys | Sort-Object)).Count -eq 0) ("Online-state translation keys differ for {0}" -f $lang)
    Assert-True ($table.intervals.Count -eq 5) ("Interval choices missing for {0}" -f $lang)
    foreach ($key in $referenceKeys) {
        if ($key -in @('status', 'mode', 'olStat', 'intervals')) { continue }
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$table[$key])) ("Translation {0}.{1} is empty" -f $lang, $key)
    }
    Write-Host ("Localization passed: {0}" -f $lang)
}

$oldOverride = $env:MPH_LANG
try {
    foreach ($lang in $supportedLanguages) {
        $env:MPH_LANG = $lang.ToUpperInvariant()
        Assert-True ((Get-MphLang) -eq $lang) ("MPH_LANG override failed for {0}" -f $lang)
    }
    $env:MPH_LANG = 'unsupported'
    Assert-True ((Get-MphI18n -Lang 'unsupported').lang -eq 'en') 'Unknown explicit language must fall back to English.'
} finally {
    $env:MPH_LANG = $oldOverride
}

Write-Host '== SRP and log architecture validation =='
$wiimmfiSourceText = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiimmfiSource.ps1') -Raw
$wiiLinkSourceText = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiiLinkSource.ps1') -Raw
$logStoreText = Get-Content -LiteralPath (Join-Path $programDir 'lib\LogStore.ps1') -Raw
$logViewText = Get-Content -LiteralPath (Join-Path $programDir 'lib\DiagnosticLogView.ps1') -Raw
$viewerCommonText = Get-Content -LiteralPath (Join-Path $programDir 'lib\ViewerCommon.ps1') -Raw
$unifiedText = Get-Content -LiteralPath (Join-Path $programDir 'MPH-Unified.ps1') -Raw
$wiimmfiViewerText = Get-Content -LiteralPath (Join-Path $programDir 'Wiimmfi-PlayerList.ps1') -Raw
$wiiLinkViewerText = Get-Content -LiteralPath (Join-Path $programDir 'WiiLink-PlayerList.ps1') -Raw

Assert-True ($logStoreText -match 'function New-MphLogStore') 'LogStore must own log persistence.'
Assert-True ($logStoreText -match 'function Get-MphLogEntries') 'LogStore must own source filtering and aggregation.'
Assert-True ($logViewText -match 'function New-DiagnosticLogPanel') 'DiagnosticLogView must own log UI creation.'
Assert-True ($logViewText -match 'function Set-DiagnosticLogEntries') 'DiagnosticLogView must own log rendering.'
Assert-True ($viewerCommonText -notmatch 'function New-DiagnosticLogPanel') 'ViewerCommon must not own diagnostic log UI.'
Assert-True ($viewerCommonText -notmatch 'System\.Collections\.Queue') 'ViewerCommon must not own diagnostic log storage.'
Assert-True ($wiimmfiSourceText -match 'Write-WiimmfiDiagnostic') 'Wiimmfi source must emit its own diagnostics.'
Assert-True ($wiiLinkSourceText -match 'Write-WiiLinkDiagnostic') 'WiiLink source must emit its own diagnostics.'
Assert-True ($wiiLinkSourceText -match "ValidateSet\('direct',\s*'browser'\)") 'WiiLink source must expose direct/browser transport validation.'
Assert-True ($unifiedText -match "New-MphLogStore -Source 'Wiimmfi'") 'Unified viewer must create a Wiimmfi log store.'
Assert-True ($unifiedText -match "New-MphLogStore -Source 'WiiLink'") 'Unified viewer must create a WiiLink log store.'
Assert-True ($unifiedText -match "New-MphLogStore -Source 'App'") 'Unified viewer must create an application log store.'
Assert-True ($unifiedText -match 'WiimmfiLogQueue') 'Unified viewer must inject the Wiimmfi queue independently.'
Assert-True ($unifiedText -match 'WiiLinkLogQueue') 'Unified viewer must inject the WiiLink queue independently.'
Assert-True ($unifiedText -notmatch '\$sync\.LogQueue') 'Unified viewer must not retain a shared worker log queue.'
Assert-True ($unifiedText -match "Key = 'All'") 'Unified viewer must expose the combined log view.'
Assert-True ($unifiedText -match "Key = 'Wiimmfi'") 'Unified viewer must expose the Wiimmfi-only log view.'
Assert-True ($unifiedText -match "Key = 'WiiLink'") 'Unified viewer must expose the WiiLink-only log view.'
Assert-True ($wiimmfiViewerText -match 'DiagnosticLogView\.ps1') 'Wiimmfi viewer must reuse DiagnosticLogView.'
Assert-True ($wiiLinkViewerText -match 'DiagnosticLogView\.ps1') 'WiiLink viewer must reuse DiagnosticLogView.'
Assert-True ($unifiedText -match 'New-WiiLinkTransportSelector') 'Unified viewer must contain the transport selector.'
Assert-True ($wiiLinkViewerText -match 'New-WiiLinkTransportSelector') 'Standalone WiiLink viewer must contain the transport selector.'

Write-Host '== LogStore behavior validation =='
$wmStore = New-MphLogStore -Source 'Wiimmfi'
$wlStore = New-MphLogStore -Source 'WiiLink'
$appStore = New-MphLogStore -Source 'App'
$stores = @($wmStore, $wlStore, $appStore)
$baseTime = [datetime]'2026-01-01T00:00:00'
Write-MphLog -Store $wmStore -Level INFO -Stage 'FETCH' -Message 'wm-info' -Time $baseTime.AddSeconds(1)
Write-MphLog -Store $wlStore -Level DEBUG -Stage 'HTTP' -Message 'wl-debug' -Time $baseTime.AddSeconds(2)
Write-MphLog -Store $appStore -Level WARN -Stage 'UI' -Message 'app-warn' -Time $baseTime.AddSeconds(3)
Assert-True ((Receive-MphLogStores -Stores $stores) -eq 3) 'Three queued log entries must be drained.'

$withoutDebug = @(Get-MphLogEntries -Stores $stores -Source 'All')
$withDebug = @(Get-MphLogEntries -Stores $stores -Source 'All' -IncludeDebug)
$wiimmfiOnly = @(Get-MphLogEntries -Stores $stores -Source 'Wiimmfi' -IncludeDebug)
$wiiLinkOnly = @(Get-MphLogEntries -Stores $stores -Source 'WiiLink' -IncludeDebug)
Assert-True ($withoutDebug.Count -eq 2) 'Default log query must hide DEBUG entries.'
Assert-True ($withDebug.Count -eq 3) 'Detailed log query must include DEBUG entries.'
Assert-True ($wiimmfiOnly.Count -eq 1 -and $wiimmfiOnly[0].message -eq 'wm-info') 'Wiimmfi filter must only return Wiimmfi entries.'
Assert-True ($wiiLinkOnly.Count -eq 1 -and $wiiLinkOnly[0].message -eq 'wl-debug') 'WiiLink filter must only return WiiLink entries.'
Assert-True ($withDebug[0].message -eq 'wm-info' -and $withDebug[2].message -eq 'app-warn') 'Combined log view must be chronological.'

Clear-MphLogStores -Stores $stores -Source 'Wiimmfi'
$afterWiimmfiClear = @(Get-MphLogEntries -Stores $stores -Source 'Wiimmfi' -IncludeDebug)
$wiiLinkAfterWiimmfiClear = @(Get-MphLogEntries -Stores $stores -Source 'WiiLink' -IncludeDebug)
Assert-True ($afterWiimmfiClear.Count -eq 0) 'Source-specific clear must clear only Wiimmfi.'
Assert-True ($wiiLinkAfterWiimmfiClear.Count -eq 1) 'Source-specific clear must preserve WiiLink.'
Clear-MphLogStores -Stores $stores -Source 'All'
$afterAllClear = @(Get-MphLogEntries -Stores $stores -Source 'All' -IncludeDebug)
Assert-True ($afterAllClear.Count -eq 0) 'All clear must clear every store.'
Write-Host 'LogStore behavior passed.'

Write-Host '== Diagnostic log UI validation =='
$theme = Get-MphTheme
$i18n = Get-MphI18n -Lang 'en'
$multiPanel = New-DiagnosticLogPanel -Theme $theme -I18n $i18n -SourceOptions @(
    @{ Key = 'All'; Text = $i18n.logAll },
    @{ Key = 'Wiimmfi'; Text = $i18n.logWiimmfi },
    @{ Key = 'WiiLink'; Text = $i18n.logWiiLink },
    @{ Key = 'App'; Text = $i18n.logApp }
)
$singlePanel = New-DiagnosticLogPanel -Theme $theme -I18n $i18n -SourceOptions @(
    @{ Key = 'Wiimmfi'; Text = $i18n.logWiimmfi }
)
try {
    Assert-True ($multiPanel.SourceCombo.Items.Count -eq 4) 'Unified log source selector must contain four choices.'
    Assert-True ($multiPanel.SourceCombo.Visible) 'Unified log source selector must be visible.'
    $multiPanel.SourceCombo.SelectedIndex = 1
    Assert-True ((Get-DiagnosticLogSource -LogPanel $multiPanel) -eq 'Wiimmfi') 'Source selector must map display text to the Wiimmfi source key.'
    $multiPanel.SourceCombo.SelectedIndex = 2
    Assert-True ((Get-DiagnosticLogSource -LogPanel $multiPanel) -eq 'WiiLink') 'Source selector must map display text to the WiiLink source key.'
    Assert-True (-not $singlePanel.SourceCombo.Visible) 'Single-source viewers must hide the redundant source selector.'
    Set-DiagnosticLogEntries -LogPanel $multiPanel -Entries $withDebug -Theme $theme
    Assert-True ($multiPanel.LogBox.Text -match '\[Wiimmfi\]') 'Rendered log must identify Wiimmfi entries.'
    Assert-True ($multiPanel.LogBox.Text -match '\[WiiLink\]') 'Rendered log must identify WiiLink entries.'
} finally {
    try { $multiPanel.Panel.Dispose() } catch {}
    try { $singlePanel.Panel.Dispose() } catch {}
}
Write-Host 'Diagnostic log UI passed.'

Write-Host '== Direct API integration test =='
$directStore = New-MphLogStore -Source 'WiiLink'
$direct = Get-WiiLinkData -Transport direct -Game 'mprimeds' -LogQueue $directStore.Queue
[void](Receive-MphLogEntries -Store $directStore -MaxDrain 1000)
Assert-True ($direct.transport -eq 'direct') 'Direct result must report direct transport.'
Assert-True (@('ok', 'empty', 'partial') -contains [string]$direct.state) ("Direct API returned unexpected state: {0}; error={1}" -f $direct.state, $direct.error)
Assert-True ($null -ne $direct.stats) 'Direct result must contain stats.'
Assert-True ($null -ne $direct.rooms) 'Direct result must contain rooms.'
Assert-True ($directStore.Entries.Count -gt 0) 'Direct test must produce WiiLink diagnostics.'
Write-Host ("Direct API passed: state={0}; rooms={1}; online={2}" -f $direct.state, @($direct.rooms).Count, $direct.stats.online)

Write-Host '== Chrome/Edge browser integration test =='
$browserStore = New-MphLogStore -Source 'WiiLink'
$browser = Start-WiiLinkBrowser -LogQueue $browserStore.Queue
Assert-True ([bool]$browser.ok) ("Chrome/Edge failed to start: {0}" -f $browser.error)
try {
    $browserResult = $null
    $lastError = ''
    $deadline = (Get-Date).AddSeconds(45)
    do {
        try {
            $candidate = Get-WiiLinkData -Transport browser -BrowserPort ([int]$browser.port) -Game 'mprimeds' -LogQueue $browserStore.Queue
            if ($candidate.ok) { $browserResult = $candidate; break }
            $lastError = [string]$candidate.error
        } catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 1000
    } while ((Get-Date) -lt $deadline)

    [void](Receive-MphLogEntries -Store $browserStore -MaxDrain 5000)
    Assert-True ($null -ne $browserResult) ("Browser transport did not become ready: $lastError")
    Assert-True ($browserResult.transport -eq 'browser') 'Browser result must report browser transport.'
    Assert-True (@('ok', 'empty', 'partial') -contains [string]$browserResult.state) ("Browser transport returned unexpected state: {0}; error={1}" -f $browserResult.state, $browserResult.error)
    Assert-True ($browserStore.Entries.Count -gt 0) 'Browser test must produce WiiLink diagnostics.'
    Write-Host ("Browser transport passed: state={0}; rooms={1}; online={2}; browser={3}" -f $browserResult.state, @($browserResult.rooms).Count, $browserResult.stats.online, $browser.browser)
} finally {
    Stop-WiiLinkBrowser -Context $browser -LogQueue $browserStore.Queue
}

Write-Host 'RESULT: SUCCESS'
