BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:domain = 'copy-github-repo.infoconex.com'
    $script:siteOrigin = "https://$($script:domain)"
    $script:cname = Get-Content -LiteralPath (Join-Path $repositoryRoot 'CNAME') -Raw
    $script:config = Get-Content -LiteralPath (Join-Path $repositoryRoot '_config.yml') -Raw
    $script:manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1')
    $script:validator = Get-Content -LiteralPath (Join-Path $repositoryRoot 'build/Test-GeneratedSite.ps1') -Raw
    $script:deployment = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/deploy-documentation-site.yml') -Raw
    $script:documentationWorkflow = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/validate-documentation.yml') -Raw
    $script:pagesGuide = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/release/pages-deployment.md') -Raw
}

Describe 'Documentation custom-domain contract' {
    It 'declares the expected hostname and Jekyll root path' {
        $script:cname.Trim() | Should -BeExactly $script:domain
        $script:config | Should -Match '(?m)^url: https://copy-github-repo\.infoconex\.com$'
        $script:config | Should -Match '(?m)^baseurl: ""$'
        $script:config | Should -Not -Match 'infoconex\.github\.io'
    }

    It 'uses the new host in the source PowerShell Gallery metadata' {
        $script:manifest.PrivateData.PSData.ProjectUri | Should -Be "$($script:siteOrigin)/"
        $script:manifest.PrivateData.PSData.IconUri | Should -Be "$($script:siteOrigin)/assets/images/gallery-icon.png"
        $script:manifest.Description | Should -Match ([regex]::Escape("$($script:siteOrigin)/"))
    }

    It 'validates the root-level CSS JS search asset and canonical contract' {
        $script:validator | Should -Match ([regex]::Escape("[string]`$BaseUrlPath = ''"))
        $script:validator | Should -Match ([regex]::Escape($script:siteOrigin))
        foreach ($asset in @('assets/css/site.css', 'assets/css/site-layout.css', 'assets/js/site.js', 'assets/images/hero_icon.png', 'assets/search-index.json')) {
            $script:validator | Should -Match ([regex]::Escape($asset))
        }
    }

    It 'publishes and validates CNAME as a documentation input and smoke-tests root assets' {
        $script:deployment | Should -Match "'CNAME'"
        $script:documentationWorkflow | Should -Match "'CNAME'"
        $script:documentationWorkflow | Should -Match 'CNAME\$'
        $script:deployment | Should -Match ([regex]::Escape($script:siteOrigin))
        foreach ($asset in @('assets/css/site.css', 'assets/css/site-layout.css', 'assets/js/site.js', 'assets/search-index.json')) {
            $script:deployment | Should -Match ([regex]::Escape($asset))
        }
    }

    It 'identifies external Pages configuration and DNS responsibilities' {
        $script:pagesGuide | Should -Match ([regex]::Escape("$($script:siteOrigin)/"))
        $script:pagesGuide | Should -Match 'GitHub Actions'
        $script:pagesGuide | Should -Match 'Settings.*Pages.*Custom domain'
        $script:pagesGuide | Should -Match 'DNS'
        $script:pagesGuide | Should -Match 'Enforce HTTPS'
        $script:pagesGuide | Should -Match 'Search Console'
    }
}
