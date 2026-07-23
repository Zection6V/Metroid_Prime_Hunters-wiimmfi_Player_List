<#
    PayloadLog.ps1 — 取得payloadを診断Queueへ安全に記録する共通機能

    責務:
      - 本文の文字数・UTF-8 byte数の計測
      - 巨大payloadの上限適用
      - RichTextBoxで扱いやすいサイズへの分割

    環境変数 MPH_LOG_PAYLOAD_MAX_CHARS:
      未設定 … 262144文字まで
      0      … 上限なし
      正数   … 指定文字数まで
#>

function Get-MphPayloadLogMaxChars {
    param([int]$DefaultMaxChars = 262144)

    $configured = ([string]$env:MPH_LOG_PAYLOAD_MAX_CHARS).Trim()
    if ([string]::IsNullOrWhiteSpace($configured)) { return $DefaultMaxChars }

    $value = 0
    if (-not [int]::TryParse($configured, [ref]$value)) { return $DefaultMaxChars }
    if ($value -lt 0) { return $DefaultMaxChars }
    return $value
}

function Write-MphPayloadLog {
    param(
        [AllowNull()]$LogQueue,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$Content,
        [string]$ContentType = '',
        [string]$Stage = 'PAYLOAD',
        [int]$ChunkChars = 6000,
        [int]$MaxChars = (Get-MphPayloadLogMaxChars)
    )

    if ($null -eq $LogQueue) { return }
    if ([string]::IsNullOrWhiteSpace($Source)) { return }
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = 'unnamed' }
    if ($ChunkChars -lt 512) { $ChunkChars = 512 }
    if ($ChunkChars -gt 16000) { $ChunkChars = 16000 }
    if ($MaxChars -lt 0) { $MaxChars = Get-MphPayloadLogMaxChars }

    $text = if ($null -eq $Content) { '<null>' } else { [string]$Content }
    $originalChars = $text.Length
    $originalBytes = [Text.Encoding]::UTF8.GetByteCount($text)
    $truncated = ($MaxChars -gt 0 -and $text.Length -gt $MaxChars)
    if ($truncated) { $text = $text.Substring(0, $MaxChars) }

    $meta = 'name={0}; contentType={1}; chars={2}; utf8Bytes={3}; loggedChars={4}; truncated={5}' -f `
        $Name, $ContentType, $originalChars, $originalBytes, $text.Length, $truncated
    try {
        $LogQueue.Enqueue(@{
                time = [datetime]::Now; source = $Source; level = 'DEBUG'; stage = $Stage
                message = ('Payload metadata: {0}' -f $meta)
            })
    } catch { return }

    if ($text.Length -eq 0) {
        try {
            $LogQueue.Enqueue(@{
                    time = [datetime]::Now; source = $Source; level = 'DEBUG'; stage = $Stage
                    message = ('{0} payload [empty]' -f $Name)
                })
        } catch {}
        return
    }

    $parts = [int][Math]::Ceiling($text.Length / [double]$ChunkChars)
    for ($part = 0; $part -lt $parts; $part++) {
        $offset = $part * $ChunkChars
        $length = [Math]::Min($ChunkChars, $text.Length - $offset)
        $chunk = $text.Substring($offset, $length)
        try {
            # Double quotes are intentional: raw payload must be separated from the header by a real CRLF.
            $message = ("{0} payload [{1}/{2}]`r`n{3}" -f $Name, ($part + 1), $parts, $chunk)
            $LogQueue.Enqueue(@{
                    time = [datetime]::Now; source = $Source; level = 'DEBUG'; stage = $Stage
                    message = $message
                })
        } catch { break }
    }

    if ($truncated) {
        try {
            $LogQueue.Enqueue(@{
                    time = [datetime]::Now; source = $Source; level = 'WARN'; stage = $Stage
                    message = ('{0} payload was truncated: originalChars={1}; loggedChars={2}. Set MPH_LOG_PAYLOAD_MAX_CHARS=0 for unlimited logging.' -f $Name, $originalChars, $text.Length)
                })
        } catch {}
    }
}
