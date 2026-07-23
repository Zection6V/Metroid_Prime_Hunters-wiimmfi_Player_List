<#
    WiiLinkFallback.ps1 — Direct API 失敗時のブラウザ退避ポリシー

    取得やUI操作そのものは担当せず、取得結果からChrome/Edgeへ切り替えるべきかを判定する。
#>

function Test-WiiLinkBrowserFallbackRequired {
    param(
        [ValidateSet('direct', 'browser')][string]$SelectedTransport,
        [AllowNull()]$Data
    )

    if ($SelectedTransport -ne 'direct' -or $null -eq $Data) { return $false }

    $okProperty = $Data.PSObject.Properties['ok']
    if ($null -ne $okProperty -and [bool]$okProperty.Value) { return $false }

    $errorProperty = $Data.PSObject.Properties['error']
    $errorText = if ($null -ne $errorProperty) { [string]$errorProperty.Value } else { '' }
    if ([string]::IsNullOrWhiteSpace($errorText)) { return $false }

    # ProxyHttpが全経路を試し終えた場合だけ自動変更する。
    # JSON解析エラーや一時的なAPIレスポンス不整合では取得方式を勝手に変えない。
    return $errorText.StartsWith('All HTTP routes failed:', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-WiiLinkTransportComboIndex {
    param([AllowNull()][string]$Transport)
    if ([string]$Transport -eq 'browser') { return 1 }
    return 0
}
