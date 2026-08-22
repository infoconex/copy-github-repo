function Protect-CgrDiagnosticText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $protectedText = $Text
    $patterns = @(
        '(?i)\bgithub_pat_[A-Za-z0-9_]{20,}\b'
        '(?i)\bgh[pousr]_[A-Za-z0-9_]{20,}\b'
        '(?i)\bBearer\s+[^\s,;]+'
        '(?i)\bAuthorization:\s*[^\r\n]+'
    )

    foreach ($pattern in $patterns) {
        $protectedText = $protectedText -replace $pattern, '[REDACTED]'
    }

    return $protectedText
}
