BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Same-name Snapshot GitHub Release orchestration' {
    It 'restores the reviewed releases from the preserved source archive against generated Snapshot tags' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/widget'; Id = 1; NodeId = 'SRC'; Visibility = 'private' }
            $archive = [pscustomobject] @{ FullName = 'acme/widget-archive'; Id = 1; NodeId = 'SRC'; Visibility = 'private' }
            $destination = [pscustomobject] @{ FullName = 'acme/widget'; Id = 2; NodeId = 'DST'; HtmlUrl = 'https://example.test/acme/widget' }
            $selection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
            $tagTargets = @([pscustomobject] @{ TagName = 'v1.0.0'; DestinationCommitSha = 'checkpoint-1' })
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/widget'
                SourceDefaultBranch = 'main'
                SourceVisibility = 'private'
                DestinationRepository = 'acme/widget'
                DestinationVisibility = 'private'
                ArchiveRepository = 'acme/widget-archive'
                CommitMessage = 'Initial repository commit'
                IncludeReleases = $true
                ReleaseSelection = $selection
                ReleaseCheckpointPlan = [pscustomobject] @{ Checkpoints = @() }
                SkipSettings = $true
                SourceState = [pscustomobject] @{ RepositoryId = 1; RepositoryNodeId = 'SRC'; DefaultBranch = 'main'; CommitSha = 'source-head'; TreeSha = 'tree-head' }
            }
            $script:sequence = [System.Collections.Generic.List[string]]::new()

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $archive }
            Mock New-CgrGitHubRepository { $destination }
            Mock Assert-CgrReplacementRepositoryIdentity { [pscustomobject] @{ SourceRepositoryId = 1; ArchiveRepositoryId = 1; ReplacementRepositoryId = 2 } }
            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ Verified = $true; RootCommitSha = 'root'; CommitSha = 'head'; SourceCommitSha = 'source-head'; TreeSha = 'tree-head'; BranchName = 'main'; ReleaseTags = $tagTargets }
            }
            Mock Get-CgrRepository { $destination }
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

            $result = Invoke-CgrSameNameSnapshotReplacement -Plan $plan -SourceRepository $source

            $result.IsVerified | Should -BeTrue
            $result.ReleasesRestored | Should -BeTrue
            @($script:sequence) | Should -Be @('release', 'configuration')
            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 1 -Exactly -ParameterFilter {
                $SourceRepository -eq $archive -and
                $DestinationRepository -eq $destination -and
                $ApprovedSelection -eq $selection -and
                @($DestinationTagTargets).Count -eq 1 -and
                $DestinationTagTargets[0].DestinationCommitSha -eq 'checkpoint-1'
            }
        }
    }
}

Describe 'Existing-destination Snapshot delegation' {
    It 'keeps Snapshot release restoration on the shared new-destination orchestration path' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Id = 1; NodeId = 'SRC' }
            $existing = [pscustomobject] @{ FullName = 'acme/destination'; Id = 2; NodeId = 'OLD' }
            $archive = [pscustomobject] @{ FullName = 'acme/destination-archive'; Id = 2; NodeId = 'OLD' }
            $replacement = [pscustomobject] @{ FullName = 'acme/destination'; Id = 3; NodeId = 'NEW' }
            $plan = [pscustomobject] @{
                ContentMode = 'Snapshot'
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'
                DestinationVisibility = 'private'
                ArchiveRepository = 'acme/destination-archive'
                IncludeReleases = $true
                SourceState = [pscustomobject] @{ CommitSha = 'source-head'; TreeSha = 'tree-head' }
            }
            $childResult = [pscustomobject] @{
                CompletedSteps = @(
                    [pscustomobject] @{ Name = 'CreateDestinationRepository'; MutatedGitHub = $true; Verified = $true },
                    [pscustomobject] @{ Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $true },
                    [pscustomobject] @{ Name = 'RestoreGitHubReleases'; MutatedGitHub = $true; Verified = $true }
                )
                ReleasesRestored = $true
            }

            Mock Assert-CgrApprovedSourceState {}
            Mock Rename-CgrGitHubRepository { $archive }
            Mock New-CgrGitHubRepository { $replacement }
            Mock Assert-CgrReplacementRepositoryIdentity { [pscustomobject] @{ SourceRepositoryId = 2; ArchiveRepositoryId = 2; ReplacementRepositoryId = 3 } }
            Mock Invoke-CgrNewDestinationSnapshot { $childResult }

            $result = Invoke-CgrExistingDestinationReplacement -Plan $plan -SourceRepository $source -ExistingDestinationRepository $existing

            $result.ReleasesRestored | Should -BeTrue
            @($result.CompletedSteps.Name) | Should -Contain 'RestoreGitHubReleases'
            Should -Invoke Invoke-CgrNewDestinationSnapshot -Times 1 -Exactly -ParameterFilter {
                $Plan -eq $plan -and $SourceRepository -eq $source -and $DestinationRepository -eq $replacement
            }
        }
    }
}
