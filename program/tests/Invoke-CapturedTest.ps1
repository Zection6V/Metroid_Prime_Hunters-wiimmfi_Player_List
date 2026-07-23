param(
    [Parameter(Mandatory = $true)][string]$TestPath,
    [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = 'Stop'
$lines = New-Object System.Collections.Generic.List[string]
$result = 'failure'

function Add-CapturedLine {
    param([AllowNull()]$Value)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    $script:lines.Add($text)
    Write-Host $text
}

try {
    $resolvedTest = (Resolve-Path -LiteralPath $TestPath -ErrorAction Stop).Path
    & $resolvedTest *>&1 | ForEach-Object { Add-CapturedLine $_ }
    $result = 'success'
} catch {
    Add-CapturedLine ('Message: {0}' -f $_.Exception.Message)
    Add-CapturedLine ('Type: {0}' -f $_.Exception.GetType().FullName)
    Add-CapturedLine ('Position: {0}' -f $_.InvocationInfo.PositionMessage)
    Add-CapturedLine ('ScriptStackTrace: {0}' -f $_.ScriptStackTrace)
    Add-CapturedLine ('FullError: {0}' -f ($_ | Format-List * -Force | Out-String))
}

$directory = Split-Path -Parent $LogPath
if ($directory -and -not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
[System.IO.File]::WriteAllLines($LogPath, $lines, [System.Text.UTF8Encoding]::new($false))
("result={0}" -f $result) | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
