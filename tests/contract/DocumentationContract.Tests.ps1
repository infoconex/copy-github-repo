BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:documents = @{
        Readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
        Architecture = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/product/architecture.md') -Raw
        CommandDesign = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/product/command-design.md') -Raw
        ProductContract = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/product/product-contract.md') -Raw
        WizardContract = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/product/wizard-contract.md') -Raw
        Versioning = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/release/versioning.md') -Raw
        Contributing = Get-Content -LiteralPath (Join-Path $repositoryRoot 'CONTRIBUTING.md') -Raw
        Security = Get-Content -LiteralPath (Join-Path $repositoryRoot 'SECURITY.md') -Raw
    }
}

Describe 'Normative documentation consistency' {
    It 'does not describe the removed legacy settings fallback as supported' {
        foreach ($document in $script:documents.Values) {
            $document | Should -Not -Match 'legacy repository objects.*retain description-only compatibility'
            $document | Should -Not -Match 'minimal legacy repository objects.*compatibility'
        }

        $script:documents.Architecture | Should -Match 'Ordinary supported repository settings are restored only after content verification and are read back for verification'
        $script:documents.CommandDesign | Should -Match 'there is no\s+legacy description-only compatibility path'
    }

    It 'documents expanded repository settings restoration as implemented and verified' {
        $script:documents.Readme | Should -Match 'repository-level settings restoration are implemented and live-validated'
        $script:documents.ProductContract | Should -Match 'ordinary supported repository settings are restored differentially and read back'
        $script:documents.Versioning | Should -Match 'expanded repository-settings restoration contract is live-validated'
        $script:documents.ProductContract | Should -Not -Match 'Pending validation.*expanded repository settings'
    }

    It 'keeps Snapshot settings behavior aligned with the full supported settings contract' {
        $script:documents.CommandDesign | Should -Match 'Supported settings are description, homepage'
        $script:documents.CommandDesign | Should -Match 'Topics'
        $script:documents.CommandDesign | Should -Match 'read\s+back from GitHub and verified'
        $script:documents.CommandDesign | Should -Not -Match 'restores the repository\s+description unless'
    }

    It 'documents fail-closed GitHub.com host support' {
        foreach ($name in @('Architecture', 'ProductContract', 'CommandDesign', 'Security')) {
            $script:documents[$name] | Should -Match 'GitHub\.com only|supports only\s+`github\.com`|supports GitHub\.com only|supports only `github\.com`'
        }
        $script:documents.Architecture | Should -Match 'fails closed for unsupported hosts'
        $script:documents.ProductContract | Should -Match 'Other hosts fail closed before mutation'
    }

    It 'documents immutable repository identity in same-name safety' {
        $script:documents.Architecture | Should -Match 'Verify archive immutable identity|immutable archive identity check'
        $script:documents.ProductContract | Should -Match 'Immutable GitHub repository identity continuity is verified'
        $script:documents.CommandDesign | Should -Match 'replacement repository must receive a distinct immutable ID'
        $script:documents.Security | Should -Match 'distinct immutable identity'
    }

    It 'documents the stable release and bootstrap trust contracts consistently' {
        $script:documents.Versioning | Should -Match 'exact tagged commit'
        $script:documents.Versioning | Should -Match 'Stable release assets are immutable'
        $script:documents.Versioning | Should -Match 'does not use\s+`gh release upload`'
        $script:documents.Security | Should -Match 'bootstrap itself is part of the trust boundary'
        $script:documents.Readme | Should -Match 'therefore part of the trust boundary'
        $script:documents.ProductContract | Should -Match 'exact tagged commit must pass the reusable Windows, Ubuntu, and macOS quality gate'
    }

    It 'keeps the documented public discovery parameter sets explicit' {
        $script:documents.ProductContract | Should -Match '`ByRepository` and `Search` parameter sets'
        $script:documents.CommandDesign | Should -Match 'Search` is the default parameter set'
        $script:documents.CommandDesign | Should -Match '`-Repository` cannot be mixed with search filters'
    }

    It 'defines the guided wizard command and responsibility boundaries' {
        $script:documents.WizardContract | Should -Match '`Start-CopyGitHubRepositoryWizard` is the finalized public command name'
        $script:documents.WizardContract | Should -Match 'native PowerShell interactive experience'
        $script:documents.WizardContract | Should -Match 'dependency-free, keyboard-friendly, testable without a human console'
        $script:documents.WizardContract | Should -Match '`Get-GitHubRepository` owns discovery'
        $script:documents.WizardContract | Should -Match '`Copy-GitHubRepository -PlanOnly` creates the real review artifact'
        $script:documents.WizardContract | Should -Match '`Test-GitHubRepositoryMigration` remains the standalone verification command'
    }

    It 'defines wizard defaults, navigation, and state invalidation' {
        $script:documents.WizardContract | Should -Match 'Content mode is `Snapshot`'
        $script:documents.WizardContract | Should -Match 'Destination visibility: source visibility'
        $script:documents.WizardContract | Should -Match 'Supported repository settings: restore'
        $script:documents.WizardContract | Should -Match 'Back preserves still-valid values'
        $script:documents.WizardContract | Should -Match 'After mutation begins, Back is unavailable'
        $script:documents.WizardContract | Should -Match 'Changing plan-affecting state invalidates the old plan'
        $script:documents.WizardContract | Should -Match '\[F filter\] on repository selection only'
    }

    It 'defines the plan-before-mutation and same-name safety boundaries' {
        $script:documents.WizardContract | Should -Match 'invoking the real planning path of\s+`Copy-GitHubRepository` with `-PlanOnly`'
        $script:documents.WizardContract | Should -Match 'Immediately before any mutation the application re-checks the current source against the plan'
        $script:documents.WizardContract | Should -Match 'neither `-Force` nor `-Confirm:\$false` bypasses exact confirmation'
        $script:documents.WizardContract | Should -Match 'Recovery handling never implies an automatic delete, overwrite, or rename-back'
    }

    It 'defines testable cancellation and non-interactive host behavior' {
        $script:documents.WizardContract | Should -Match 'Normal cancellation is a no-change outcome before mutation'
        $script:documents.WizardContract | Should -Match 'Unexpected defects retain their PowerShell error records'
        $script:documents.WizardContract | Should -Match 'without a human console'
        $script:documents.WizardContract | Should -Match 'finalized public command name'
    }

    It 'documents canonical public copy terminology' {
        $script:documents.ProductContract | Should -Match 'stable public content-mode values are exactly `Snapshot` and `FullHistory`'
        $script:documents.ProductContract | Should -Match 'one new unrelated destination root commit'
        $script:documents.ProductContract | Should -Match 'branches, tags, reachable commits.*reachable Git LFS objects are preserved'
        $script:documents.WizardContract | Should -Match 'Repository copy plan'
        $script:documents.WizardContract | Should -Not -Match 'The review heading is \*\*Migration plan\*\*'
    }

    It 'documents the implemented wizard across release-facing surfaces' {
        $script:documents.Readme | Should -Match 'Start-CopyGitHubRepositoryWizard'
        $script:documents.Readme | Should -Not -Match '## Planned experience'
        $script:documents.ProductContract | Should -Match '`Start-CopyGitHubRepositoryWizard`'
        $script:documents.CommandDesign | Should -Match '### `Start-CopyGitHubRepositoryWizard`'
        $script:documents.Architecture | Should -Match 'Start-CopyGitHubRepositoryWizard'
    }

    It 'keeps contributor guidance aligned with the repository quality gate' {
        $script:documents.Contributing | Should -Match '\./build/Test-Project\.ps1'
        $script:documents.Contributing | Should -Match 'Windows, Ubuntu, and macOS'
    }
}
