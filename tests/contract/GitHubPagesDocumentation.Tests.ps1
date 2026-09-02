BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
    $script:userGuide = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/user/user-guide.md') -Raw
    $script:pagesGuide = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/user/github-pages-migration.md') -Raw
    $script:copyReference = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/reference/commands/Copy-GitHubRepository.md') -Raw
    $script:wizardReference = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/reference/commands/Start-CopyGitHubRepositoryWizard.md') -Raw
    $script:productContract = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/product/product-contract.md') -Raw
    $script:pagesContract = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/product/github-pages-migration-contract.md') -Raw
    $script:architecture = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/product/architecture.md') -Raw
    $script:recovery = Get-Content -LiteralPath (Join-Path $repositoryRoot 'docs/user/troubleshooting-recovery.md') -Raw
    $script:navigation = Get-Content -LiteralPath (Join-Path $repositoryRoot '_data/navigation.yml') -Raw
    $script:copySource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'src/CopyGitHubRepo/Public/Copy-GitHubRepository.ps1') -Raw
    $script:wizardSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'src/CopyGitHubRepo/Public/Start-CopyGitHubRepositoryWizard.ps1') -Raw
}

Describe 'GitHub Pages migration documentation' {
    It 'documents RestorePages as implemented opt-in behavior' {
        foreach ($document in @($script:readme, $script:userGuide, $script:pagesGuide, $script:copyReference, $script:productContract)) {
            $document | Should -Match ([regex]::Escape('-RestorePages'))
            $document | Should -Match 'opt-in|explicit opt-in|off by default|disabled unless explicitly requested'
        }

        $script:copyReference | Should -Not -Match 'RestorePages.*restoration is not implemented'
        $script:copyReference | Should -Not -Match 'RestorePages.*mutating execution rejects'
        $script:pagesContract | Should -Match 'implements deterministic GitHub-side Pages planning, restoration, independent verification'
    }

    It 'distinguishes repository Git content from GitHub-side Pages state' {
        foreach ($document in @($script:readme, $script:userGuide, $script:pagesGuide, $script:copyReference, $script:pagesContract)) {
            $document | Should -Match 'Git content|ordinary Git content|repository content'
            $document | Should -Match 'GitHub-side Pages'
        }

        $script:pagesGuide | Should -Match 'CNAME'
        $script:pagesGuide | Should -Match '\.github/workflows'
        $script:pagesGuide | Should -Match 'does not prove|not proof'
    }

    It 'documents Actions and branch-path publishing without inventing representability' {
        foreach ($document in @($script:pagesGuide, $script:copyReference, $script:pagesContract)) {
            $document | Should -Match 'Actions-based(?: Pages)?'
            $document | Should -Match 'workflow'
            $document | Should -Match 'branch/path'
            $document | Should -Match 'representable|representability'
            $document | Should -Match 'fail[s]? closed'
        }

        $script:pagesGuide | Should -Match '/docs'
        $script:pagesGuide | Should -Match 'does not invent|not invent'
        $script:pagesGuide | Should -Match 'silently redirect|substitut'
    }

    It 'documents immutable Pages evidence drift detection activation control and independent verification' {
        foreach ($document in @($script:pagesGuide, $script:copyReference, $script:productContract, $script:architecture)) {
            $document | Should -Match 'immutable.*Pages evidence|reviewed Pages evidence'
            $document | Should -Match 'revalidat'
            $document | Should -Match 'drift|stale'
            $document | Should -Match 'independent.*verif|independently.*read back|independent.*read-back'
        }

        foreach ($document in @($script:pagesGuide, $script:architecture)) {
            $document | Should -Match 'activation guard|activation.*control|workflow activation'
        }
    }

    It 'documents the omitted RestorePages behavior without claiming Pages preservation' {
        foreach ($document in @($script:pagesGuide, $script:copyReference, $script:pagesContract)) {
            $document | Should -Match '`-RestorePages` is (?:off by default|opt-in)\. Without it|Without `-RestorePages`|Without -RestorePages|when `-RestorePages` is omitted'
            $document | Should -Match 'does not claim|no guarantee|does not.*preserved or restored'
        }
    }

    It 'documents replacement custom-domain identity handoff and recoverability' {
        foreach ($document in @($script:pagesGuide, $script:copyReference, $script:recovery, $script:pagesContract)) {
            $document | Should -Match 'custom.domain'
            $document | Should -Match 'archive'
            $document | Should -Match 'replacement'
            $document | Should -Match 'identity|identities'
            $document | Should -Match 'handoff'
        }

        $script:pagesGuide | Should -Match 'release.*archive|releases.*domain|release.*domain'
        $script:pagesGuide | Should -Match 'read.back|read back'
        $script:recovery | Should -Match 'ArchiveReleaseAttempted/Succeeded'
        $script:recovery | Should -Match 'ReplacementClaimAttempted/Succeeded'
        $script:recovery | Should -Match 'do not automatically rebind|does not automatically.*reclaim'
    }

    It 'keeps external DNS domain verification certificates and secrets outside migrated state' {
        foreach ($document in @($script:readme, $script:userGuide, $script:pagesGuide, $script:copyReference, $script:productContract)) {
            $document | Should -Match 'external DNS|External DNS'
            $document | Should -Match 'domain verification|domain-verification'
            $document | Should -Match 'certificate'
            $document | Should -Match 'secret'
        }

        $script:pagesGuide | Should -Match 'not copied or modified|never changed|never modified'
        $script:pagesGuide | Should -Match 'not transferred'
        $script:pagesGuide | Should -Match 'not migrated'
        $script:pagesGuide | Should -Match 'PendingCertificate|pending certificate|certificate provisioning as pending'
        $script:pagesGuide | Should -Match 'external readiness'
    }

    It 'documents Pages ordering with protection last' {
        foreach ($document in @($script:pagesGuide, $script:copyReference, $script:architecture)) {
            $document | Should -Match 'content.*verif'
            $document | Should -Match 'Pages'
            $document | Should -Match 'protection.*last|protection remains.*final|protection.*final'
        }
    }

    It 'keeps wizard documentation aligned with the reviewed Pages plan flow' {
        foreach ($document in @($script:wizardReference, $script:wizardSource)) {
            $document | Should -Match 'Pages restoration'
            $document | Should -Match 'opt-in|off by default|no Pages restoration'
            $document | Should -Match 'plan.*evidence|plan-derived evidence|reviewed Pages'
            $document | Should -Match 'custom domain'
            $document | Should -Match 'external DNS'
            $document | Should -Match 'certificate'
            $document | Should -Match 'secret'
        }
    }

    It 'is discoverable from user and product navigation' {
        $script:navigation | Should -Match 'title: GitHub Pages Migration'
        $script:navigation | Should -Match 'path: docs/user/github-pages-migration\.md'
        $script:navigation | Should -Match 'title: GitHub Pages Contract'
        $script:navigation | Should -Match 'path: docs/product/github-pages-migration-contract\.md'
        $script:readme | Should -Match 'docs/user/github-pages-migration\.md'
    }

    It 'keeps public help consistent with implemented Pages behavior' {
        $script:copySource | Should -Match '\.PARAMETER RestorePages'
        $script:copySource | Should -Match 'immutable reviewed\s+plan evidence'
        $script:copySource | Should -Match 'after destination content verification'
        $script:copySource | Should -Match 'revalidated immediately before mutation'

        $restorePagesHelp = [regex]::Match(
            $script:copySource,
            '(?s)\.PARAMETER RestorePages(?<Body>.*?)\.PARAMETER EnableActionsAfterMigration'
        ).Groups['Body'].Value
        $restorePagesHelp | Should -Not -BeNullOrEmpty
        $restorePagesHelp | Should -Not -Match 'not implemented'

        $script:wizardSource | Should -Match 'GitHub Pages restoration is explicit and opt-in'
        $script:wizardSource | Should -Match 'GitHub-side Pages configuration'
    }
}
