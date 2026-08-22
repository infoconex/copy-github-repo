BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot

    $topLevelDocumentation = @(
        'README.md'
        'SECURITY.md'
        'CHANGELOG.md'
        'CODE_OF_CONDUCT.md'
        'CONTRIBUTING.md'
    ) | ForEach-Object { Join-Path $script:repositoryRoot $_ }

    $docsRoot = Join-Path $script:repositoryRoot 'docs'
    $script:documentationFiles = @(
        $topLevelDocumentation
        Get-ChildItem -LiteralPath $docsRoot -Filter '*.md' -File -Recurse | Select-Object -ExpandProperty FullName
    ) | Sort-Object -Unique
}

Describe 'Durable documentation issue-reference policy' {
    It 'does not depend on GitHub issue numbers or issue URLs' {
        $violations = [System.Collections.Generic.List[string]]::new()
        $issueNumberPattern = '(?i)(?:\bissues?\s+|(?<![\w#])#)\d+\b'
        $issueUrlPattern = '(?i)https?://github\.com/[^\s)]+/issues/\d+\b'
        $runReferencePattern = '(?i)\b(?:workflow\s+run|quality\s+gate(?:\s+run)?|documentation\s+validation(?:\s+run)?|codeql(?:\s+workflow)?\s+run)\s+#\d+\b'

        foreach ($filePath in $script:documentationFiles) {
            $relativePath = [IO.Path]::GetRelativePath($script:repositoryRoot, $filePath).Replace('\\', '/')
            $lineNumber = 0
            foreach ($line in Get-Content -LiteralPath $filePath) {
                $lineNumber++
                $issueCheckText = $line -replace $runReferencePattern, ''
                if ($issueCheckText -match $issueNumberPattern -or $issueCheckText -match $issueUrlPattern) {
                    $violations.Add("${relativePath}:${lineNumber}: $($line.Trim())")
                }
            }
        }

        $violations | Should -BeNullOrEmpty -Because (
            "durable documentation must describe requirements, state, evidence, and limitations directly rather than depend on issue history.`n" +
            ($violations -join "`n")
        )
    }
}
