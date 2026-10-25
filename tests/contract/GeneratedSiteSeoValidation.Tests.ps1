#requires -Version 7.4

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:validator = Join-Path $script:repoRoot 'build/Test-GeneratedSite.ps1'
    $script:description = 'Review CopyGitHubRepo repository migration planning, source verification, approval safeguards, and safe recovery for GitHub projects.'
    $script:template = @'
<!doctype html><html><head><title>Specific documentation title</title>
<meta name="description" content="__DESCRIPTION__">
</head><body>__HEADING__</body></html>
'@
}

Describe 'Generated site SEO failure diagnostics' {
    It 'rejects missing, repeated, and empty first-level headings' {
        $fixtures = @(
            @{ Heading = '<h2>Subheading only</h2>'; Expected = 'expected exactly one h1, found 0' }
            @{ Heading = '<h1>One</h1><h1>Two</h1>'; Expected = 'expected exactly one h1, found 2' }
            @{ Heading = '<h1>   </h1>'; Expected = 'h1 heading has no text' }
        )
        foreach ($fixture in $fixtures) {
            $site = Join-Path ([System.IO.Path]::GetTempPath()) ("cgr-seo-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $site -Force | Out-Null
            try {
                $html = $script:template.Replace('__DESCRIPTION__', $script:description).Replace('__HEADING__', $fixture.Heading)
                Set-Content -LiteralPath (Join-Path $site 'index.html') -Value $html
                $caught = ''
                try { & $script:validator -SitePath $site } catch { $caught = $_.Exception.Message }
                $caught | Should -Match ([regex]::Escape($fixture.Expected))
            }
            finally { Remove-Item -LiteralPath $site -Force -Recurse }
        }
    }

    It 'rejects missing, generic, and out-of-range descriptions' {
        $cases = @(
            @{ Description = $null; Expected = 'expected exactly one meta description, found 0' }
            @{ Description = ''; Expected = 'meta description is empty' }
            @{ Description = 'Too short'; Expected = 'outside 120-160 characters' }
            @{ Description = ('x' * 161); Expected = 'outside 120-160 characters' }
            @{ Description = 'PowerShell module for safely copying and migrating GitHub repositories with clean Snapshot or history-preserving FullHistory modes.'; Expected = 'meta description uses generic site default' }
        )
        foreach ($testCase in $cases) {
            $site = Join-Path ([System.IO.Path]::GetTempPath()) ("cgr-seo-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $site -Force | Out-Null
            try {
                $html = $script:template.Replace('__DESCRIPTION__', [string]$testCase.Description).Replace('__HEADING__', '<h1>Title</h1>')
                if ($null -eq $testCase.Description) {
                    $html = $html.Replace('<meta name="description" content="">', '')
                }
                Set-Content -LiteralPath (Join-Path $site 'index.html') -Value $html
                $caught = ''
                try { & $script:validator -SitePath $site } catch { $caught = $_.Exception.Message }
                $caught | Should -Match ([regex]::Escape($testCase.Expected))
            }
            finally { Remove-Item -LiteralPath $site -Force -Recurse }
        }
    }

    It 'rejects missing, empty, and generic page titles' {
        $cases = @(
            @{ TitleMarkup = ''; Expected = 'expected exactly one title element, found 0' }
            @{ TitleMarkup = '<title></title>'; Expected = 'title element is empty' }
            @{ TitleMarkup = '<title>Copy GitHub Repository</title>'; Expected = 'page title uses generic site default' }
        )
        foreach ($testCase in $cases) {
            $site = Join-Path ([System.IO.Path]::GetTempPath()) ("cgr-seo-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $site -Force | Out-Null
            try {
                $html = $script:template.Replace('__DESCRIPTION__', $script:description).Replace('__HEADING__', '<h1>Title</h1>')
                $html = $html.Replace('<title>Specific documentation title</title>', $testCase.TitleMarkup)
                Set-Content -LiteralPath (Join-Path $site 'index.html') -Value $html
                $caught = ''
                try { & $script:validator -SitePath $site } catch { $caught = $_.Exception.Message }
                $caught | Should -Match ([regex]::Escape($testCase.Expected))
            }
            finally { Remove-Item -LiteralPath $site -Force -Recurse }
        }
    }

    It 'rejects duplicate page titles and descriptions' {
        $site = Join-Path ([System.IO.Path]::GetTempPath()) ("cgr-seo-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $site -Force | Out-Null
        try {
            $html = $script:template.Replace('__DESCRIPTION__', $script:description).Replace('__HEADING__', '<h1>Title</h1>')
            Set-Content -LiteralPath (Join-Path $site 'index.html') -Value $html
            Set-Content -LiteralPath (Join-Path $site 'second.html') -Value $html
            $caught = ''
            try { & $script:validator -SitePath $site } catch { $caught = $_.Exception.Message }
            $caught | Should -Match 'duplicate title'
            $caught | Should -Match 'duplicate meta description'
        }
        finally { Remove-Item -LiteralPath $site -Force -Recurse }
    }
}
