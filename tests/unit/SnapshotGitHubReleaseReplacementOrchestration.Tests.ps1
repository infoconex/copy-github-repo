BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Same-name Snapshot GitHub Release orchestration' {
    It 'restores the reviewed releases from the preserved source archive against generated Snapshot tags' {
        InModuleScope CopyGitHubRepo {
            $script:source = [pscustomobject] @{ FullName = 'acme/widget'; Id = 1; NodeId = 'SRC'; Visibility = 'private' }
            $script:archive = [pscustomobject] @{ FullName = 'acme/widget-archive'; Id = 1; NodeId = 'SRC'; Visibility = 'private' }
            $script:destination = [pscustomobject] @{ FullName = 'acme/widget'; Id = 2; NodeId = 'DST'; HtmlUrl = 'https://example.test/acme/widget' }
            $script:selection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
            $script:tagTargets = @([pscustomobject] @{ TagName = 'v1.0.0'; DestinationCommitSha = 'checkpoint-1' })
            $script:plan = [pscustomobject] @{
                ContentMode = 'Snapshot'
                SourceRepository = 'acme/widget'
                SourceDefaultBranch = 'main'
                SourceVisibility = 'private'
                DestinationRepository = 'acme/widget'
                DestinationVisibility = 'private'
                ArchiveRepository = 'acme/widget-archive'
                CommitMessage = 'Initial repository commit'
                IncludeReleases = $true
                ReleaseSelection = $script:selection
                ReleaseCheckpointPlan = [pscustomobject] @{ Checkpoints = @() }
                SkipSettings = $true
                SourceState = [pscustomobject] @{ RepositoryId = 1; RepositoryNodeId = 'SRC'; DefaultBranch = 'main'; CommitSha = 'source-head'; TreeSha = 'tree-head' }
            }
            $script:sequence = [System.Collections.Generic.List[string]]::new()

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $script:archive }
            Mock New-CgrGitHubRepository { $script:destination }
            Mock Assert-CgrReplacementRepositoryIdentity { [pscustomobject] @{ SourceRepositoryId = 1; ArchiveRepositoryId = 1; ReplacementRepositoryId = 2 } }
            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ Verified = $true; RootCommitSha = 'root'; CommitSha = 'head'; SourceCommitSha = 'source-head'; TreeSha = 'tree-head'; BranchName = 'main'; ReleaseTags = $script:tagTargets }
            }
            Mock Get-CgrRepository { $script:destination }
            Mock Invoke-CgrRepositorySnapshotVerification { [pscustomobject] @{ IsSuccessful = $true; DestinationTree = 'tree-head' } }
            Mock Invoke-CgrActivityStage {
                if ($Name -eq 'RestoreGitHubReleases') { $script:sequence.Add('release') }
                & $Action
            }
            Mock Copy-CgrApprovedGitHubRelease {
                [pscustomobject] @{ IsSuccessful = $true; ApprovedReleaseCount = 1; DestinationReleaseCount = 1; Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
            }
            Mock Invoke-CgrPostVerificationConfigurationRestore {
                $script:sequence.Add('configuration')
                [pscustomobject] @{
                    Settings = [pscustomobject] @{ IsSuccessful = $true }
                    Protection = [pscustomobject] @{ IsSuccessful = $true }
                    SettingsRestored = $false
                    ProtectionRestored = $false
                }
            }

            $result = Invoke-CgrSameNameSnapshotReplacement -Plan $script:plan -SourceRepository $script:source

            $result.IsVerified | Should -BeTrue
            $result.ReleasesRestored | Should -BeTrue
            @($script:sequence) | Should -Be @('release', 'configuration')
            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 1 -Exactly -ParameterFilter {
                $SourceRepository -eq $script:archive -and
                $DestinationRepository -eq $script:destination -and
                $ApprovedSelection -eq $script:selection -and
                @($DestinationTagTargets).Count -eq 1 -and
                $DestinationTagTargets[0].DestinationCommitSha -eq 'checkpoint-1'
            }
        }
    }
}

Describe 'Existing-destination Snapshot delegation' {
    It 'keeps Snapshot release restoration on the shared new-destination orchestration path' {
        InModuleScope CopyGitHubRepo {
            $script:source = [pscustomobject] @{ FullName = 'acme/source'; Id = 1; NodeId = 'SRC' }
            $script:existing = [pscustomobject] @{ FullName = 'acme/destination'; Id = 2; NodeId = 'OLD' }
            $script:archive = [pscustomobject] @{ FullName = 'acme/destination-archive'; Id = 2; NodeId = 'OLD' }
            $script:replacement = [pscustomobject] @{ FullName = 'acme/destination'; Id = 3; NodeId = 'NEW' }
            $script:plan = [pscustomobject] @{
                ContentMode = 'Snapshot'
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'
                DestinationVisibility = 'private'
                ArchiveRepository = 'acme/destination-archive'
                IncludeReleases = $true
                SourceState = [pscustomobject] @{ CommitSha = 'source-head'; TreeSha = 'tree-head' }
            }
            $script:childResult = [pscustomobject] @{
                CompletedSteps = @(
                    [pscustomobject] @{ Name = 'CreateDestinationRepository'; MutatedGitHub = $true; Verified = $true },
                    [pscustomobject] @{ Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $true },
                    [pscustomobject] @{ Name = 'RestoreGitHubReleases'; MutatedGitHub = $true; Verified = $true }
                )
                ReleasesRestored = $true
            }

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $script:archive }
            Mock New-CgrGitHubRepository { $script:replacement }
            Mock Assert-CgrReplacementRepositoryIdentity { [pscustomobject] @{ SourceRepositoryId = 2; ArchiveRepositoryId = 2; ReplacementRepositoryId = 3 } }
            Mock Invoke-CgrNewDestinationSnapshot { $script:childResult }

            $result = Invoke-CgrExistingDestinationReplacement -Plan $script:plan -SourceRepository $script:source -ExistingDestinationRepository $script:existing

            $result.ReleasesRestored | Should -BeTrue
            @($result.CompletedSteps.Name) | Should -Contain 'RestoreGitHubReleases'
            Should -Invoke Invoke-CgrNewDestinationSnapshot -Times 1 -Exactly -ParameterFilter {
                $Plan -eq $script:plan -and $SourceRepository -eq $script:source -and $DestinationRepository -eq $script:replacement
            }
        }
    }
}
