#requires -Version 7.4

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:pages = @(
        Get-Item -LiteralPath (Join-Path $script:repoRoot 'README.md')
        Get-Item -LiteralPath (Join-Path $script:repoRoot 'CONTRIBUTING.md')
        Get-Item -LiteralPath (Join-Path $script:repoRoot 'SECURITY.md')
        Get-Item -LiteralPath (Join-Path $script:repoRoot 'CODE_OF_CONDUCT.md')
        Get-Item -LiteralPath (Join-Path $script:repoRoot 'CHANGELOG.md')
        Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'docs') -Filter '*.md' -Recurse -File
    )
}

Describe 'Published documentation SEO contracts' {
    It 'has an explicit, unique title and 120-160-character page-specific description for every page' {
        $titles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $descriptions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($page in $script:pages) {
            $markdown = Get-Content -LiteralPath $page.FullName -Raw
            $frontMatter = [regex]::Match($markdown, '(?s)\A---\s*\r?\n(?<yaml>.*?)\r?\n---\s*\r?\n')
            $frontMatter.Success | Should -BeTrue -Because "$($page.FullName) must declare front matter"
            if (-not $frontMatter.Success) { continue }
            $yaml = $frontMatter.Groups['yaml'].Value
            foreach ($field in @('title', 'description')) {
                $lines = @($yaml -split '\r?\n' | Where-Object { $_ -match "^$field\s*:" })
                $lines.Count | Should -Be 1 -Because "$($page.FullName) must explicitly declare $field"
            }
            $title = ([regex]::Match($yaml, '(?m)^title:\s*(?<value>.+)$').Groups['value'].Value).Trim('"', "'", ' ')
            $description = ([regex]::Match($yaml, '(?m)^description:\s*(?<value>.+)$').Groups['value'].Value).Trim('"', "'", ' ')
            $title | Should -Not -BeNullOrEmpty
            $description.Length | Should -BeGreaterOrEqual 120 -Because $page.FullName
            $description.Length | Should -BeLessOrEqual 160 -Because $page.FullName
            $titles.Add($title) | Should -BeTrue -Because "$($page.FullName) needs a unique title"
            $descriptions.Add($description) | Should -BeTrue -Because "$($page.FullName) needs a unique description"
        }
    }

    It 'has exactly one nonempty first-level heading on every published Markdown page' {
        foreach ($page in $script:pages) {
            $markdown = Get-Content -LiteralPath $page.FullName -Raw
            $markdownOutsideFences = [regex]::Replace($markdown, '(?ms)^```[^\r\n]*\r?\n.*?^```\s*$', '')
            $markdownOutsideFences = [regex]::Replace($markdownOutsideFences, '(?ms)^~~~[^\r\n]*\r?\n.*?^~~~\s*$', '')
            $headingMatches = @([regex]::Matches($markdownOutsideFences, '(?m)^#(?!#)\s+(?<heading>.*)$'))
            $headingMatches.Count | Should -Be 1 -Because $page.FullName
            if ($headingMatches.Count -eq 1) {
                $headingMatches[0].Groups['heading'].Value.Trim() | Should -Not -BeNullOrEmpty
            }
        }
    }
}
