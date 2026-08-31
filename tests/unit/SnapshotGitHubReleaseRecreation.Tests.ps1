BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot GitHub Release target adaptation' {
    It 'reuses approved release restoration while validating the generated Snapshot destination tag target' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{
                Releases = @([pscustomobject] @{
                        ReleaseId = 10
                        TagName = 'v1.0.0'
                        Name = 'Release 1.0'
                        Body = 'approved body'
                        Draft = $false
                        Prerelease = $false
                        IsLatest = $false
                        TargetCommitSha = 'source-commit'
                        Assets = @()
                    })
            }
            $targets = @([pscustomobject] @{ TagName = 'v1.0.0'; DestinationCommitSha = 'snapshot-checkpoint' })
            $script:destinationReleaseReads = 0

            Mock Invoke-CgrGitHubApiReadRequest {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'repos/acme/source/releases/tags/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":10,"tag_name":"v1.0.0","name":"Release 1.0","body":"approved body","draft":false,"prerelease":false,"assets":[]}'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/source/commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('source-commit'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/commits/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('snapshot-checkpoint'); ErrorText = '' }
                }
                if ($joined -match 'repos/acme/destination/releases/tags/v1.0.0') {
                    $script:destinationReleaseReads++
                    if ($script:destinationReleaseReads -eq 1) {
                        return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 404: Not Found' }
                    }
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":20,"tag_name":"v1.0.0","name":"Release 1.0","body":"approved body","draft":false,"prerelease":false,"assets":[]}'); ErrorText = '' }
                }
                throw "Unexpected read request: $joined"
            }
            Mock Invoke-CgrNativeCommand {
                $joined = $ArgumentList -join ' '
                if ($FilePath -eq 'gh' -and $joined -match '^release create v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('created'); ErrorText = '' }
                }
                throw "Unexpected native command: $FilePath $joined"
            }

            $result = Copy-CgrApprovedGitHubRelease -SourceRepository $source -DestinationRepository $destination -ApprovedSelection $selection -DestinationTagTargets $targets

            $result.IsSuccessful | Should -BeTrue
            $result.DestinationReleaseCount | Should -Be 1
            $result.Releases[0].SourceCommitSha | Should -Be 'source-commit'
            $result.Releases[0].DestinationCommitSha | Should -Be 'snapshot-checkpoint'
            Should -Invoke Invoke-CgrNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'gh' -and ($ArgumentList -join ' ') -match '^release create v1.0.0 '
            }
        }
    }

    It 'fails closed before release mutation when destination tag-target evidence does not match the reviewed selection' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{
                Releases = @(
                    [pscustomobject] @{ ReleaseId = 10; TagName = 'v1.0.0'; TargetCommitSha = 'source-1'; Assets = @() },
                    [pscustomobject] @{ ReleaseId = 20; TagName = 'v2.0.0'; TargetCommitSha = 'source-2'; Assets = @() }
                )
            }
            $targets = @([pscustomobject] @{ TagName = 'v1.0.0'; DestinationCommitSha = 'checkpoint-1' })
            Mock Invoke-CgrGitHubApiReadRequest { throw 'No GitHub reads should occur for invalid approved target evidence.' }
            Mock Invoke-CgrNativeCommand { throw 'No release mutation should occur for invalid approved target evidence.' }

            { Copy-CgrApprovedGitHubRelease -SourceRepository $source -DestinationRepository $destination -ApprovedSelection $selection -DestinationTagTargets $targets } |
                Should -Throw -ErrorId 'ApprovedDestinationReleaseTagTargetsMismatch,Copy-CgrApprovedGitHubRelease'

            Should -Invoke Invoke-CgrGitHubApiReadRequest -Times 0
            Should -Invoke Invoke-CgrNativeCommand -Times 0
        }
    }

    It 'retains FullHistory destination-tag identity validation when no destination adapter is supplied' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }
            $selection = [pscustomobject] @{
                Releases = @([pscustomobject] @{
                        ReleaseId = 10; TagName = 'v1.0.0'; Name = 'Release'; Body = 'body'; Draft = $false; Prerelease = $false; IsLatest = $false; TargetCommitSha = 'source-commit'; Assets = @()
                    })
            }
            Mock Invoke-CgrGitHubApiReadRequest {
                $joined = $ArgumentList -join ' '
                if ($joined -match 'repos/acme/source/releases/tags/v1.0.0') { return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":10,"tag_name":"v1.0.0","name":"Release","body":"body","draft":false,"prerelease":false,"assets":[]}'); ErrorText = '' } }
                if ($joined -match 'repos/acme/source/commits/v1.0.0') { return [pscustomobject] @{ ExitCode = 0; Output = @('source-commit'); ErrorText = '' } }
                if ($joined -match 'repos/acme/destination/commits/v1.0.0') { return [pscustomobject] @{ ExitCode = 0; Output = @('snapshot-style-different-commit'); ErrorText = '' } }
                throw "Unexpected read request: $joined"
            }

            { Copy-CgrApprovedGitHubRelease -SourceRepository $source -DestinationRepository $destination -ApprovedSelection $selection } |
                Should -Throw -ErrorId 'GitHubReleaseTagTargetMismatch,Copy-CgrApprovedGitHubRelease'
        }
    }
}

Describe 'Snapshot GitHub Release orchestration' {
    It 'passes the immutable reviewed selection and generated release-tag mapping to the shared release restorer before configuration restore' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Id = 1; NodeId = 'SRC' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://example.test/acme/destination'; Id = 2; NodeId = 'DST' }
            $selection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1.0.0' }) }
            $tagTargets = @([pscustomobject] @{ TagName = 'v1.0.0'; DestinationCommitSha = 'checkpoint-1' })
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'; SourceDefaultBranch = 'main'; SourceVisibility = 'private'; DestinationVisibility = 'private'; CommitMessage = 'Initial repository commit'; IncludeReleases = $true; ReleaseSelection = $selection; ReleaseCheckpointPlan = [pscustomobject] @{ Checkpoints = @() }; SkipSettings = $true
                SourceState = [pscustomobject] @{ RepositoryId = 1; RepositoryNodeId = 'SRC'; DefaultBranch = 'main'; CommitSha = 'source-head'; TreeSha = 'tree-head' }
            }
            $script:sequence = [System.Collections.Generic.List[string]]::new()

            Mock Copy-CgrRepositorySnapshot {
                [pscustomobject] @{ Verified = $true; RootCommitSha = 'root'; CommitSha = 'head'; SourceCommitSha = 'source-head'; TreeSha = 'tree-head'; BranchName = 'main'; ReleaseTags = $tagTargets }
            }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrRepositorySnapshotVerification { [pscustomobject] @{ IsSuccessful = $true; SourceTree = 'tree-head'; DestinationTree = 'tree-head' } }
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

            $result = Invoke-CgrNewDestinationSnapshot -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.IsVerified | Should -BeTrue
            $result.ReleasesRestored | Should -BeTrue
            @($result.CompletedSteps.Name) | Should -Contain 'RestoreGitHubReleases'
            @($script:sequence) | Should -Be @('release', 'configuration')
            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 1 -Exactly -ParameterFilter {
                $ApprovedSelection -eq $selection -and
                $SourceRepository -eq $source -and
                $DestinationRepository -eq $destination -and
                @($DestinationTagTargets).Count -eq 1 -and
                $DestinationTagTargets[0].TagName -eq 'v1.0.0' -and
                $DestinationTagTargets[0].DestinationCommitSha -eq 'checkpoint-1'
            }
        }
    }

    It 'does not restore releases when Snapshot verification fails' {
        InModuleScope CopyGitHubRepo {
            $source = [pscustomobject] @{ FullName = 'acme/source'; Id = 1; NodeId = 'SRC' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://example.test/acme/destination'; Id = 2; NodeId = 'DST' }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'; SourceDefaultBranch = 'main'; SourceVisibility = 'private'; DestinationVisibility = 'private'; CommitMessage = 'Initial repository commit'; IncludeReleases = $true; ReleaseSelection = [pscustomobject] @{ Releases = @([pscustomobject] @{ TagName = 'v1' }) }; ReleaseCheckpointPlan = [pscustomobject] @{ Checkpoints = @() }; SkipSettings = $true
                SourceState = [pscustomobject] @{ RepositoryId = 1; RepositoryNodeId = 'SRC'; DefaultBranch = 'main'; CommitSha = 'source-head'; TreeSha = 'tree-head' }
            }
            Mock Copy-CgrRepositorySnapshot { [pscustomobject] @{ Verified = $true; RootCommitSha = 'root'; CommitSha = 'head'; SourceCommitSha = 'source-head'; TreeSha = 'tree-head'; BranchName = 'main'; ReleaseTags = @([pscustomobject] @{ TagName = 'v1'; DestinationCommitSha = 'checkpoint' }) } }
            Mock Get-CgrRepository { $destination }
            Mock Invoke-CgrActivityStage { & $Action }
            Mock Invoke-CgrRepositorySnapshotVerification { [pscustomobject] @{ IsSuccessful = $false; SourceTree = 'tree-head'; DestinationTree = 'different-tree' } }
            Mock Copy-CgrApprovedGitHubRelease { throw 'Release restoration must not run after failed Snapshot verification.' }
            Mock Invoke-CgrPostVerificationConfigurationRestore { [pscustomobject] @{ Settings = [pscustomobject] @{ IsSuccessful = $true }; Protection = [pscustomobject] @{ IsSuccessful = $true }; SettingsRestored = $false; ProtectionRestored = $false } }

            $result = Invoke-CgrNewDestinationSnapshot -Plan $plan -SourceRepository $source -DestinationRepository $destination

            $result.IsVerified | Should -BeFalse
            $result.Releases.Status | Should -Be 'SnapshotVerificationFailed'
            Should -Invoke Copy-CgrApprovedGitHubRelease -Times 0
        }
    }
}

Describe 'Snapshot IncludeReleases execution planning' {
    It 'builds the same reviewed selection and checkpoint plan for mutating Snapshot execution' {
        InModuleScope CopyGitHubRepo {
            $sourceRepository = [pscustomobject] @{ FullName = 'acme/source'; Owner = 'acme'; DefaultBranch = 'main'; Visibility = 'private'; Id = $null }
            $sourceState = [pscustomobject] @{ ContentMode = 'Snapshot'; Repository = 'acme/source'; DefaultBranch = 'main'; CommitSha = 'head'; TreeSha = 'tree-head' }
            $selection = [pscustomobject] @{ SelectedReleaseCount = 1; SelectedAssetCount = 0; Releases = @([pscustomobject] @{ ReleaseId = 1; TagName = 'v1'; TargetCommitSha = 'c1' }) }
            $checkpointPlan = [pscustomobject] @{ CheckpointCount = 1; FinalHeadCheckpointRequired = $false }
            Mock Test-CgrGitHubRepositoryExistence { $false }
            Mock Get-CgrApprovedSourceState { $sourceState }
            Mock Get-CgrGitHubReleaseSelection { $selection }
            Mock New-CgrSnapshotReleaseCheckpointPlan { $checkpointPlan }

            $plan = New-CgrMigrationPlan -SourceRepository $sourceRepository -DestinationRepository acme/destination -ContentMode Snapshot -IncludeReleases -DestinationVisibility private -CommitMessage 'Initial repository commit' -SkipSettings

            $plan.PlanOnly | Should -BeFalse
            $plan.WillMutateGitHub | Should -BeTrue
            $plan.ReleaseSelection | Should -Be $selection
            $plan.ReleaseCheckpointPlan | Should -Be $checkpointPlan
            Should -Invoke Get-CgrGitHubReleaseSelection -Times 1 -Exactly
            Should -Invoke New-CgrSnapshotReleaseCheckpointPlan -Times 1 -Exactly
        }
    }
}
