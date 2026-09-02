BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:userGuide = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/user/user-guide.md') -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
    $script:readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
    $script:strategy = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/engineering/documentation-strategy.md') -Raw
}

Describe 'User capabilities and scenario documentation' {
    It 'provides a complete user progression' {
        foreach ($text in @(
                'Choose the outcome'
                'Install and authenticate'
                'Preview before mutation'
                'Execute deliberately'
                'Verify the result'
                'Preserve evidence if something fails'
            )) {
            $script:userGuide | Should -Match ([regex]::Escape($text))
        }
    }

    It 'provides the normal stable Gallery installation path' {
        $script:userGuide | Should -Match 'For normal stable installation, use PowerShell Gallery'
        $script:userGuide | Should -Match 'Install-PSResource CopyGitHubRepo'
        $script:userGuide | Should -Match 'Import-Module CopyGitHubRepo'
        $script:userGuide | Should -Match 'gh auth login --hostname github\.com'
        $script:userGuide | Should -Match 'Install-PSResource CopyGitHubRepo -Version 0\.1\.0'
        $script:userGuide | Should -Match 'installation-security\.md'
    }

    It 'defines one Snapshot versus FullHistory decision matrix' {
        $script:userGuide | Should -Match '## Choose Snapshot or FullHistory'
        $script:userGuide | Should -Match 'Publish the current default-branch contents as a clean repository'
        $script:userGuide | Should -Match 'Preserve commit ancestry'
        $script:userGuide | Should -Match 'Preserve ordinary branches'
        $script:userGuide | Should -Match 'Preserve ordinary tags'
    }

    It 'defines the user-facing what gets copied matrix for supported and unsupported state' {
        $script:userGuide | Should -Match '## What gets copied\?'
        foreach ($item in @(
                'Git LFS'
                'Description and homepage'
                'Transferable repository-level rulesets'
                'Pull requests'
                'Issues and issue history'
                'GitHub Releases / release history'
                'GitHub Actions workflow-run history'
                'GitHub Pages'
                'External DNS records'
                'Secret values'
                'Collaborator/team access'
                'Packages / deployments'
            )) {
            $script:userGuide | Should -Match ([regex]::Escape($item))
        }
        $script:userGuide | Should -Match 'RestorePages'
        $script:userGuide | Should -Match 'certificate.*external|external.*certificate'
    }

    It 'documents the required user scenarios by intent' {
        foreach ($heading in @(
                '### Publish a clean Snapshot to a new destination'
                '### Copy FullHistory to a new destination'
                '### Restore Pages to a new destination'
                '### Replace an existing different destination'
                '### Replace a repository under the same name'
                '### Preview without mutation'
                '### Run non-interactively'
                '### Verify independently'
            )) {
            $script:userGuide | Should -Match ([regex]::Escape($heading))
        }
    }

    It 'preserves authority boundaries instead of duplicating command contracts' {
        $script:userGuide | Should -Match 'product-contract\.md.*authoritative|normative behavior.*product-contract\.md'
        $script:userGuide | Should -Match 'Detailed command syntax.*reference/commands|Detailed command syntax.*commands'
        $script:userGuide | Should -Match 'product-model\.md'
    }

    It 'explains stale plans and partial-failure preservation' {
        $script:userGuide | Should -Match 'fails closed before destination creation or rename'
        $script:userGuide | Should -Match 'repositories are not automatically deleted'
        $script:userGuide | Should -Match 'archives are not automatically renamed back'
    }

    It 'is discoverable as the authoritative user guide' {
        $script:navigation | Should -Match 'title: User Guide'
        $script:navigation | Should -Match 'path: docs/user/user-guide\.md'
        $script:readme | Should -Match '\[User guide\]\(docs/user/user-guide\.md\)'
        $script:strategy | Should -Match 'User getting-started/scenario guidance.*`docs/user/user-guide\.md`'
    }
}
