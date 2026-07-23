from pathlib import Path

root = Path.cwd()
source_path = root / "program/lib/WiiLinkSource.ps1"
source = source_path.read_text(encoding="utf-8-sig")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one occurrence, found {count}")
    return text.replace(old, new)


helper_anchor = "function Get-WiiLinkPropertyValue {"
helper = r'''function Add-WiiLinkGameQuery {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Game
    )

    if ([string]::IsNullOrWhiteSpace($Game)) { return $Url }
    $uri = [uri]$Url
    if ([string]$uri.Query -match '(?i)(?:^|[?&])game=') { return $Url }

    $builder = New-Object System.UriBuilder($uri)
    $existing = ([string]$builder.Query).TrimStart('?')
    $pair = 'game=' + [uri]::EscapeDataString($Game)
    $builder.Query = if ([string]::IsNullOrWhiteSpace($existing)) { $pair } else { $existing + '&' + $pair }
    return $builder.Uri.AbsoluteUri
}

'''
source = replace_once(source, helper_anchor, helper + helper_anchor, "game-query helper anchor")

source = replace_once(
    source,
    """        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$List,
        [AllowNull()]$Candidate,
        [string]$FallbackId = ''
    )""",
    """        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$List,
        [AllowNull()]$Candidate,
        [string]$FallbackId = '',
        [string]$DefaultGame = ''
    )""",
    "group candidate parameters",
)
source = replace_once(
    source,
    "foreach ($item in @($Candidate)) { Add-WiiLinkGroupCandidate -List $List -Candidate $item -FallbackId $FallbackId }",
    "foreach ($item in @($Candidate)) { Add-WiiLinkGroupCandidate -List $List -Candidate $item -FallbackId $FallbackId -DefaultGame $DefaultGame }",
    "group array recursion",
)
source = replace_once(
    source,
    """    if ($null -eq $Candidate.PSObject.Properties['game']) { return }
    if (-not [string]::IsNullOrWhiteSpace($FallbackId) -and $null -eq $Candidate.PSObject.Properties['id']) {""",
    """    $gameProperty = $Candidate.PSObject.Properties['game']
    if ($null -eq $gameProperty) {
        $looksLikeGroup = $false
        foreach ($marker in @('id', 'players', 'host', 'type', 'created', 'suspend')) {
            if ($null -ne $Candidate.PSObject.Properties[$marker]) { $looksLikeGroup = $true; break }
        }
        if (-not $looksLikeGroup -or [string]::IsNullOrWhiteSpace($DefaultGame)) { return }
        try { $Candidate | Add-Member -NotePropertyName game -NotePropertyValue $DefaultGame -Force } catch { return }
    }
    if (-not [string]::IsNullOrWhiteSpace($FallbackId) -and $null -eq $Candidate.PSObject.Properties['id']) {""",
    "filtered group default game",
)
source = replace_once(
    source,
    """        [Parameter(Mandatory = $true)][string]$Json,
        $LogQueue = $null
    )""",
    """        [Parameter(Mandatory = $true)][string]$Json,
        $LogQueue = $null,
        [string]$DefaultGame = ''
    )""",
    "groups parser parameters",
)
source = replace_once(
    source,
    "foreach ($candidate in @($container)) { Add-WiiLinkGroupCandidate -List $groups -Candidate $candidate }",
    "foreach ($candidate in @($container)) { Add-WiiLinkGroupCandidate -List $groups -Candidate $candidate -DefaultGame $DefaultGame }",
    "groups array parser",
)
source = replace_once(
    source,
    "Add-WiiLinkGroupCandidate -List $groups -Candidate $container",
    "Add-WiiLinkGroupCandidate -List $groups -Candidate $container -DefaultGame $DefaultGame",
    "single group parser",
)
source = replace_once(
    source,
    "Add-WiiLinkGroupCandidate -List $groups -Candidate $property.Value -FallbackId ([string]$property.Name)",
    "Add-WiiLinkGroupCandidate -List $groups -Candidate $property.Value -FallbackId ([string]$property.Name) -DefaultGame $DefaultGame",
    "mapped group parser",
)
source = replace_once(
    source,
    "[string]$Url = 'https://api.wfc.wiilink24.com/api/stats',",
    "[string]$Url = 'https://api.wfc.wiilink24.com/api/stats?game=mprimeds',",
    "browser startup URL",
)
source = replace_once(
    source,
    """    $i = Get-MphI18n -Lang $Lang
    $result = @{""",
    """    $i = Get-MphI18n -Lang $Lang
    $statsRequestUrl = Add-WiiLinkGameQuery -Url $StatsUrl -Game $Game
    $groupsRequestUrl = Add-WiiLinkGameQuery -Url $GroupsUrl -Game $Game
    $result = @{""",
    "filtered request URL setup",
)
source = replace_once(
    source,
    "Get-WiiLinkPayload -Transport $Transport -Url $StatsUrl",
    "Get-WiiLinkPayload -Transport $Transport -Url $statsRequestUrl",
    "stats filtered URL use",
)
source = replace_once(
    source,
    "Get-WiiLinkPayload -Transport $Transport -Url $GroupsUrl",
    "Get-WiiLinkPayload -Transport $Transport -Url $groupsRequestUrl",
    "groups filtered URL use",
)
source = replace_once(
    source,
    "Write-WiiLinkDiagnostic $LogQueue 'INFO' 'START' (\"Update started; game={0}; transport={1}\" -f $Game, $Transport)",
    "Write-WiiLinkDiagnostic $LogQueue 'INFO' 'START' (\"Update started; game={0}; transport={1}; filteredApi=true\" -f $Game, $Transport)",
    "start log",
)
source = replace_once(
    source,
    """        $statsProps = @($s.PSObject.Properties)
        $statsGame = $statsProps | Where-Object { ([string]$_.Name).Trim().ToLowerInvariant() -eq $Game.Trim().ToLowerInvariant() } | Select-Object -First 1
        if ($statsGame) {
            $sv = $statsGame.Value
            $result.stats = @{
                online = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'online' -DefaultValue 0)
                active = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'active' -DefaultValue 0)
                groups = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'groups' -DefaultValue 0)
            }
            Write-WiiLinkDiagnostic $LogQueue 'INFO' 'STATS' (\"online={0}; active={1}; groups={2}\" -f $result.stats.online, $result.stats.active, $result.stats.groups)
        } else {
            Write-WiiLinkDiagnostic $LogQueue 'WARN' 'STATS' (\"Game key not found in stats; expected={0}; available={1}\" -f $Game, (($statsProps.Name | Select-Object -First 30) -join ','))
        }""",
    """        $statsProps = @($s.PSObject.Properties)
        $statsGame = $statsProps | Where-Object { ([string]$_.Name).Trim().ToLowerInvariant() -eq $Game.Trim().ToLowerInvariant() } | Select-Object -First 1
        $sv = $null
        $statsShape = 'unknown'
        if ($statsGame) {
            $sv = $statsGame.Value
            $statsShape = 'game-wrapper'
        } elseif ($null -ne $s.PSObject.Properties['online'] -or $null -ne $s.PSObject.Properties['active'] -or $null -ne $s.PSObject.Properties['groups']) {
            $sv = $s
            $statsShape = 'filtered-object'
        }
        if ($null -ne $sv) {
            $result.stats = @{
                online = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'online' -DefaultValue 0)
                active = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'active' -DefaultValue 0)
                groups = [int](Get-WiiLinkPropertyValue -InputObject $sv -Name 'groups' -DefaultValue 0)
            }
            Write-WiiLinkDiagnostic $LogQueue 'INFO' 'STATS' (\"shape={0}; online={1}; active={2}; groups={3}\" -f $statsShape, $result.stats.online, $result.stats.active, $result.stats.groups)
        } else {
            Write-WiiLinkDiagnostic $LogQueue 'WARN' 'STATS' (\"Game stats not found; expected={0}; available={1}\" -f $Game, (($statsProps.Name | Select-Object -First 30) -join ','))
        }""",
    "stats response shape parser",
)
source = replace_once(
    source,
    "ConvertFrom-WiiLinkGroupsJson -Json ([string]$groupsPayload.text) -LogQueue $LogQueue",
    "ConvertFrom-WiiLinkGroupsJson -Json ([string]$groupsPayload.text) -LogQueue $LogQueue -DefaultGame $Game",
    "groups parser call",
)
source_path.write_text(source, encoding="utf-8-sig")


test_path = root / "program/tests/Test-WiiLinkGameFilter.ps1"
test_path.write_text(
    r'''$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$programDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $programDir 'lib\WiiLinkSource.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

Write-Host '== Query construction =='
Assert-True ((Add-WiiLinkGameQuery -Url 'https://api.wfc.wiilink24.com/api/stats' -Game 'mprimeds') -eq 'https://api.wfc.wiilink24.com/api/stats?game=mprimeds') 'Stats URL must receive the game query.'
Assert-True ((Add-WiiLinkGameQuery -Url 'https://example.test/api?x=1' -Game 'mprimeds') -eq 'https://example.test/api?x=1&game=mprimeds') 'Existing query parameters must be preserved.'
Assert-True ((Add-WiiLinkGameQuery -Url 'https://example.test/api?game=other' -Game 'mprimeds') -eq 'https://example.test/api?game=other') 'An existing game query must not be duplicated.'

Write-Host '== Filtered response shapes =='
$script:RequestedUrls = New-Object System.Collections.ArrayList
function Get-WiiLinkPayload {
    param([string]$Transport, [string]$Url, [string]$Ua, [int]$BrowserPort, $LogQueue)
    [void]$script:RequestedUrls.Add($Url)
    if ($Url -match '/stats\?game=mprimeds$') {
        $text = '{"online":1,"active":0,"groups":1}'
    } elseif ($Url -match '/groups\?game=mprimeds$') {
        $text = '[{"id":"room-1","host":"0","type":"anybody","suspend":false,"created":"2026-07-23T00:00:00Z","players":{"0":{"name":"Samus","fc":"0000-0000-0000","pid":1,"conn_fail":0},"1":{"name":"Trace","fc":"1111-1111-1111","pid":2,"conn_fail":0}}}]'
    } else {
        throw "Unexpected test URL: $Url"
    }
    return @{ text = $text; status = 200; bytes = [Text.Encoding]::UTF8.GetByteCount($text); contentType = 'application/json'; route = 'test'; proxy = ''; timeoutSec = 1 }
}

$result = Get-WiiLinkData -StatsUrl 'https://api.wfc.wiilink24.com/api/stats' -GroupsUrl 'https://api.wfc.wiilink24.com/api/groups' -Game 'mprimeds' -Transport direct
Assert-True ($result.ok) ("Filtered response must parse successfully: {0}" -f $result.error)
Assert-True ($result.stats.online -eq 1 -and $result.stats.groups -eq 1) 'Filtered top-level stats object must be accepted.'
Assert-True (@($result.rooms).Count -eq 1) 'Filtered groups array must produce one room.'
Assert-True (@($result.rooms[0].players).Count -eq 2) 'Filtered group without a game property must inherit the requested game.'
Assert-True ($script:RequestedUrls.Count -eq 2) 'Exactly two filtered requests must be made.'
Assert-True ([string]$script:RequestedUrls[0] -eq 'https://api.wfc.wiilink24.com/api/stats?game=mprimeds') 'Stats request must be game-filtered.'
Assert-True ([string]$script:RequestedUrls[1] -eq 'https://api.wfc.wiilink24.com/api/groups?game=mprimeds') 'Groups request must be game-filtered.'

$browserSource = Get-Content -LiteralPath (Join-Path $programDir 'lib\WiiLinkSource.ps1') -Raw
Assert-True ($browserSource -match "api/stats\?game=mprimeds") 'Browser startup page must also be game-filtered.'
Write-Host 'RESULT: SUCCESS'
''',
    encoding="utf-8-sig",
)

workflow_path = root / ".github/workflows/wiilink-transport-tests.yml"
workflow = workflow_path.read_text(encoding="utf-8")
group_line = "          .\\program\\tests\\Test-WiiLinkGroupParsing.ps1"
if "Test-WiiLinkGameFilter.ps1" not in workflow:
    workflow = replace_once(workflow, group_line, group_line + "\n          .\\program\\tests\\Test-WiiLinkGameFilter.ps1", "group test CI anchor")
logging_line = "          .\\program\\tests\\Test-LoggingCore.ps1"
if "Test-DiagnosticLogIncremental.ps1" not in workflow:
    workflow = replace_once(workflow, logging_line, logging_line + "\n          .\\program\\tests\\Test-DiagnosticLogIncremental.ps1", "logging CI anchor")
workflow_path.write_text(workflow, encoding="utf-8")

readme_path = root / "README.md"
readme = readme_path.read_text(encoding="utf-8")
anchor = "The browser transport is useful when local security software, TLS interception, or a network proxy blocks direct PowerShell requests."
paragraph = "**Chrome / Edge is the default WiiLink transport.** Direct API remains available as a manual option. Both WiiLink requests are filtered with `?game=mprimeds`. WiiLink only exposes a room in the room list when at least two players are present, so the online count may be nonzero even when no room row is shown."
if paragraph not in readme:
    if "**Chrome / Edge is the default WiiLink transport.**" in readme:
        start = readme.index("**Chrome / Edge is the default WiiLink transport.**")
        end = readme.find("\n\n", start)
        if end < 0:
            end = len(readme)
        readme = readme[:start] + paragraph + readme[end:]
    else:
        readme = replace_once(readme, anchor, anchor + "\n\n" + paragraph, "README WiiLink transport anchor")
readme_path.write_text(readme, encoding="utf-8")
