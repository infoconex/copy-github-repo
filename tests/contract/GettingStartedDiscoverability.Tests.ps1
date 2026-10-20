BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
    $script:userGuide = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/user/user-guide.md') -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
    $script:layout = Get-Content -LiteralPath (Join-Path $repositoryRoot '_layouts/default.html') -Raw
}

Describe 'Getting started discoverability contract' {
    It 'exposes install, guided launch, and scripted preview before detailed product exposition' {
        $getStarted = $script:readme.IndexOf('## Get started')
        $scripted = $script:readme.IndexOf('## Scripted quick start')
        $details = $script:readme.IndexOf('## About Copy GitHub Repository')
        $modes = $script:readme.IndexOf('## Choose the right content mode')

        $getStarted | Should -BeGreaterThan -1
        $scripted | Should -BeGreaterThan $getStarted
        $details | Should -BeGreaterThan $scripted
        $modes | Should -BeGreaterThan $details

        $quickStart = $script:readme.Substring($getStarted, $details - $getStarted)
        $quickStart | Should -Match 'Install-PSResource CopyGitHubRepo'
        $quickStart | Should -Match 'Import-Module CopyGitHubRepo'
        $quickStart | Should -Match 'gh auth login --hostname github\.com'
        $quickStart | Should -Match 'Start-CopyGitHubRepositoryWizard'
        $quickStart | Should -Match 'Copy-GitHubRepository'
        $quickStart | Should -Match '\-PlanOnly'
        @([regex]::Matches($script:readme, '(?m)^## Get started$')).Count | Should -Be 1
        @([regex]::Matches($script:readme, '(?m)^## Scripted quick start$')).Count | Should -Be 1
    }

    It 'keeps prerequisites and mutation/safety guidance close to the first commands' {
        $quickStart = $script:readme.Substring(
            $script:readme.IndexOf('## Get started'),
            $script:readme.IndexOf('## About Copy GitHub Repository') - $script:readme.IndexOf('## Get started')
        )

        foreach ($required in @(
                'PowerShell 7.4'
                'GitHub CLI'
                'Git LFS'
                'Snapshot'
                'FullHistory'
                'unrelated history'
                'not silently overwritten'
                'requires an explicit'
                'makes no changes'
                'review'
                'exact confirmation'
            )) {
            $quickStart | Should -Match ([regex]::Escape($required))
        }

        $quickStart | Should -Match '\[Installation security\]\(docs/security/installation-security\.md\)'
        $quickStart | Should -Match '\[User guide\]\(docs/user/user-guide\.md\)'
        $script:readme | Should -Match 'install-prerelease\.ps1 \| iex'
        $script:readme | Should -Match 'install-release\.ps1 \| iex'
        $script:readme | Should -Match 'uninstall\.ps1 \| iex'
    }

    It 'brings the user guide commands before its detailed journey without losing it' {
        $install = $script:userGuide.IndexOf('Install-PSResource CopyGitHubRepo')
        $wizard = $script:userGuide.IndexOf('Start-CopyGitHubRepositoryWizard')
        $plan = $script:userGuide.IndexOf('-PlanOnly')
        $journey = $script:userGuide.IndexOf('A typical user journey is:')

        $install | Should -BeGreaterThan -1
        $wizard | Should -BeGreaterThan $install
        $plan | Should -BeGreaterThan $wizard
        $journey | Should -BeGreaterThan $plan
        $script:userGuide | Should -Match 'Preview before mutation'
        $script:userGuide | Should -Match 'Preserve evidence if something fails'
    }

    It 'links the homepage heading from site header and sidebar with the Pages baseurl' {
        $script:navigation | Should -Match '(?s)title: Get Started\s+path: README\.md\s+fragment: get-started'
        $script:layout | Should -Match ([regex]::Escape("{{ '/' | relative_url }}#get-started"))
        $script:layout | Should -Match ([regex]::Escape('#{{ item.fragment }}'))
        $script:layout | Should -Match 'item\.fragment == nil'
    }
}
