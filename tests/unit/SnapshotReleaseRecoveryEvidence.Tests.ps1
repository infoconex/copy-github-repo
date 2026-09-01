BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'src/CopyGitHubRepo/CopyGitHubRepo.psd1'
    Import-Module $modulePath -Force
}

Describe 'Snapshot release preservation evidence' {
    It 'uses completed Snapshot and release results without live rediscovery on success' {
        InModuleScope CopyGitHubRepo {
            $checkpointPlan = [pscustomobject] @{
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'source-1'; SourceTreeSha = 'tree-1'; TagNames = @('v1.0.0') })
                ReleaseEvidence = @([pscustomobject] @{ TagName = 'v1.0.0'; TagObjectType = 'commit'; TagObjectSha = 'source-1'; PeeledCommitSha = 'source-1' })
            }
            $selection = [pscustomobject] @{ Releases = @([pscustomobject] @{ ReleaseId = 10; TagName = 'v1.0.0'; Assets = @() }) }
            $plan = [pscustomobject] @{ IncludeReleases = $true; ReleaseCheckpointPlan = $checkpointPlan; ReleaseSelection = $selection; SourceDefaultBranch = 'main' }
            $snapshot = [pscustomobject] @{
                CommitSha = 'destination-1'
                Verified = $true
                GeneratedCommits = @([pscustomobject] @{ Kind = 'ReleaseCheckpoint'; Order = 1; SourceCommitSha = 'source-1'; SourceTreeSha = 'tree-1'; TagNames = @('v1.0.0'); CommitSha = 'destination-1'; TreeSha = 'tree-1'; Published = $true })
                ReleaseTags = @([pscustomobject] @{ TagName = 'v1.0.0'; SourcePeeledCommitSha = 'source-1'; DestinationCommitSha = 'destination-1' })
            }
            $releases = [pscustomobject] @{
                Status = 'Restored'
                IsSuccessful = $true
                Releases = @([pscustomobject] @{ TagName = 'v1.0.0'; DestinationReleaseId = 20; AssetCount = 0; IsVerified = $true })
            }
            Mock Invoke-CgrGitHubApiReadRequest { throw 'Successful evidence must not rediscover mutable destination state.' }

            $result = Get-CgrSnapshotReleasePreservationEvidence -Plan $plan -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' }) -SnapshotCopyResult $snapshot -ReleaseRestoreResult $releases

            $result.Planned.ReleaseCheckpointPlan | Should -Be $checkpointPlan
            $result.Planned.ReleaseSelection | Should -Be $selection
            $result.Actual.GeneratedCommits.Count | Should -Be 1
            $result.Actual.ConstructedCheckpointCount | Should -Be 1
            $result.Actual.PublishedCheckpointCount | Should -Be 1
            $result.Actual.ReleaseTags.Count | Should -Be 1
            $result.Actual.Releases.Count | Should -Be 1
            $result.Verified.SnapshotPublication | Should -BeTrue
            $result.Verified.ReleaseRestore | Should -BeTrue
            $result.Verified.VerifiedReleaseCount | Should -Be 1
            $result.Incomplete.CheckpointConstructionCount | Should -Be 0
            $result.Incomplete.CheckpointPublicationCount | Should -Be 0
            $result.Incomplete.TagCount | Should -Be 0
            $result.Incomplete.ReleaseCount | Should -Be 0
            Should -Invoke Invoke-CgrGitHubApiReadRequest -Times 0
        }
    }

    It 'retains constructed checkpoint evidence before publication without pretending destination work succeeded' {
        InModuleScope CopyGitHubRepo {
            $checkpointPlan = [pscustomobject] @{
                Checkpoints = @([pscustomobject] @{ Order = 1; SourceCommitSha = 'source-1'; SourceTreeSha = 'tree-1'; TagNames = @('v1.0.0') })
                ReleaseEvidence = @([pscustomobject] @{ TagName = 'v1.0.0'; TagObjectType = 'commit'; TagObjectSha = 'source-1'; PeeledCommitSha = 'source-1' })
            }
            $selection = [pscustomobject] @{ Releases = @([pscustomobject] @{ ReleaseId = 10; TagName = 'v1.0.0'; Assets = @() }) }
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'
                DestinationRepository = 'acme/destination'
                SourceVisibility = 'private'
                DestinationVisibility = 'private'
                ContentMode = 'Snapshot'
                SourceDefaultBranch = 'main'
                IncludeReleases = $true
                ReleaseCheckpointPlan = $checkpointPlan
                ReleaseSelection = $selection
            }
            $generatedCommitProgress = @([pscustomobject] @{
                    Kind = 'ReleaseCheckpoint'
                    Order = 1
                    SourceCommitSha = 'source-1'
                    SourceTreeSha = 'tree-1'
                    TagNames = @('v1.0.0')
                    CommitSha = 'generated-1'
                    TreeSha = 'tree-1'
                    Message = 'Snapshot release checkpoint 1: v1.0.0'
                    Published = $false
                })
            Mock Invoke-CgrGitHubApiReadRequest { throw 'No destination rediscovery is available before publication.' }

            $evidence = Get-CgrSnapshotReleasePreservationEvidence -Plan $plan -GeneratedCommitProgress $generatedCommitProgress

            $evidence.Actual.GeneratedCommits.Count | Should -Be 1
            $evidence.Actual.GeneratedCommits[0].SourceCommitSha | Should -Be 'source-1'
            $evidence.Actual.GeneratedCommits[0].TagNames | Should -Contain 'v1.0.0'
            $evidence.Actual.GeneratedCommits[0].CommitSha | Should -Be 'generated-1'
            $evidence.Actual.GeneratedCommits[0].Published | Should -BeFalse
            $evidence.Actual.ConstructedCheckpointCount | Should -Be 1
            $evidence.Actual.PublishedCheckpointCount | Should -Be 0
            $evidence.Actual.ReleaseTags.Count | Should -Be 0
            $evidence.Verified.SnapshotPublication | Should -BeFalse
            $evidence.Incomplete.CheckpointConstructionCount | Should -Be 0
            $evidence.Incomplete.CheckpointPublicationCount | Should -Be 1
            $evidence.Incomplete.TagCount | Should -Be 1
            $evidence.Incomplete.ReleaseCount | Should -Be 1
            Should -Invoke Invoke-CgrGitHubApiReadRequest -Times 0

            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://example.test/acme/destination' }
            $steps = @([pscustomobject] @{ Order = 1; Name = 'CreateDestinationRepository'; MutatedGitHub = $true; Verified = $true })
            $exception = [System.InvalidOperationException]::new('snapshot push failed')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'DestinationRepositorySnapshotPushFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, 'acme/destination')
            $provenance = [pscustomobject] @{ ContentMode = 'Snapshot'; ReleasePreservation = $evidence }
            $reportBase = Join-Path $TestDrive 'checkpoint-construction.json'

            $path = Write-CgrMigrationRecoveryReport -Plan $plan -DestinationRepository $destination -FailureStage 'CopySnapshot' -ErrorRecord $errorRecord -CompletedSteps $steps -Provenance $provenance -PreferredReportPath $reportBase
            $report = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 30

            $report.FailureStage | Should -Be 'CopySnapshot'
            $report.LastCompletedStep.Name | Should -Be 'CreateDestinationRepository'
            $report.Provenance.ReleasePreservation.Actual.GeneratedCommits[0].CommitSha | Should -Be 'generated-1'
            $report.Provenance.ReleasePreservation.Actual.GeneratedCommits[0].Published | Should -BeFalse
            $report.Provenance.ReleasePreservation.Incomplete.CheckpointPublicationCount | Should -Be 1
            $report.Recovery.AutomaticDeletionAttempted | Should -BeFalse
        }
    }

    It 'observes published checkpoints tags releases and completed assets after a partial release failure without mutation' {
        InModuleScope CopyGitHubRepo {
            $checkpointPlan = [pscustomobject] @{
                Checkpoints = @(
                    [pscustomobject] @{ Order = 1; SourceCommitSha = 'source-1'; SourceTreeSha = 'tree-1'; TagNames = @('v1.0.0') },
                    [pscustomobject] @{ Order = 2; SourceCommitSha = 'source-2'; SourceTreeSha = 'tree-2'; TagNames = @('v2.0.0') }
                )
                ReleaseEvidence = @(
                    [pscustomobject] @{ TagName = 'v1.0.0'; TagObjectType = 'commit'; TagObjectSha = 'source-tag-1'; PeeledCommitSha = 'source-1' },
                    [pscustomobject] @{ TagName = 'v2.0.0'; TagObjectType = 'commit'; TagObjectSha = 'source-tag-2'; PeeledCommitSha = 'source-2' }
                )
            }
            $selection = [pscustomobject] @{
                Releases = @(
                    [pscustomobject] @{ ReleaseId = 10; TagName = 'v1.0.0'; Assets = @([pscustomobject] @{ Name = 'one.zip' }) },
                    [pscustomobject] @{ ReleaseId = 20; TagName = 'v2.0.0'; Assets = @([pscustomobject] @{ Name = 'two.zip' }) }
                )
            }
            $plan = [pscustomobject] @{ IncludeReleases = $true; ReleaseCheckpointPlan = $checkpointPlan; ReleaseSelection = $selection; SourceDefaultBranch = 'main' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination' }

            Mock Invoke-CgrGitHubApiReadRequest {
                $request = $ArgumentList -join ' '
                if ($request -match '/git/ref/tags/v1.0.0') { return [pscustomobject] @{ ExitCode = 0; Output = @('{"object":{"type":"commit","sha":"destination-1"}}'); ErrorText = '' } }
                if ($request -match '/git/ref/tags/v2.0.0') { return [pscustomobject] @{ ExitCode = 0; Output = @('{"object":{"type":"commit","sha":"destination-2"}}'); ErrorText = '' } }
                if ($request -match '/git/ref/heads/main') { return [pscustomobject] @{ ExitCode = 0; Output = @('{"object":{"type":"commit","sha":"destination-2"}}'); ErrorText = '' } }
                if ($request -match '/releases/tags/v1.0.0') {
                    return [pscustomobject] @{ ExitCode = 0; Output = @('{"id":110,"tag_name":"v1.0.0","name":"Release 1","body":"body","draft":false,"prerelease":false,"assets":[{"id":501,"name":"one.zip","label":"asset","size":42,"content_type":"application/zip","digest":"sha256:abc"}]}'); ErrorText = '' }
                }
                if ($request -match '/releases/tags/v2.0.0') { return [pscustomobject] @{ ExitCode = 1; Output = @(); ErrorText = 'HTTP 404: Not Found' } }
                throw "Unexpected read request: $request"
            }
            Mock Invoke-CgrGitHubApiMutation { throw 'Recovery evidence must not mutate GitHub.' }
            Mock Invoke-CgrNativeCommand { throw 'Recovery evidence must not invoke mutation commands.' }
            Mock Invoke-CgrGitCommand { throw 'Recovery evidence must not invoke Git mutation.' }

            $result = Get-CgrSnapshotReleasePreservationEvidence -Plan $plan -DestinationRepository $destination

            $result.Actual.DestinationHeadCommitSha | Should -Be 'destination-2'
            $result.Actual.GeneratedCommits.Count | Should -Be 2
            $result.Actual.ConstructedCheckpointCount | Should -Be 2
            $result.Actual.PublishedCheckpointCount | Should -Be 2
            $result.Actual.GeneratedCommits[0].SourceCommitSha | Should -Be 'source-1'
            $result.Actual.GeneratedCommits[0].CommitSha | Should -Be 'destination-1'
            $result.Actual.ReleaseTags.Count | Should -Be 2
            $result.Actual.Releases.Count | Should -Be 1
            $result.Actual.Releases[0].TagName | Should -Be 'v1.0.0'
            $result.Actual.Releases[0].Assets.Count | Should -Be 1
            $result.Actual.Releases[0].Assets[0].Name | Should -Be 'one.zip'
            $result.Actual.Releases[0].ObservedAfterFailure | Should -BeTrue
            $result.Verified.ReleaseRestore | Should -BeFalse
            $result.Incomplete.CheckpointConstructionCount | Should -Be 0
            $result.Incomplete.CheckpointPublicationCount | Should -Be 0
            $result.Incomplete.TagCount | Should -Be 0
            $result.Incomplete.ReleaseCount | Should -Be 1
            Should -Invoke Invoke-CgrGitHubApiMutation -Times 0
            Should -Invoke Invoke-CgrNativeCommand -Times 0
            Should -Invoke Invoke-CgrGitCommand -Times 0
        }
    }

    It 'does not add release-preservation behavior to plain Snapshot or FullHistory plans' {
        InModuleScope CopyGitHubRepo {
            Mock Invoke-CgrGitHubApiReadRequest { throw 'No recovery discovery should occur without a Snapshot release checkpoint plan.' }

            $plainSnapshot = Get-CgrSnapshotReleasePreservationEvidence -Plan ([pscustomobject] @{ IncludeReleases = $false; SourceDefaultBranch = 'main' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })
            $fullHistory = Get-CgrSnapshotReleasePreservationEvidence -Plan ([pscustomobject] @{ IncludeReleases = $true; ContentMode = 'FullHistory'; ReleaseSelection = [pscustomobject] @{ Releases = @() }; SourceDefaultBranch = 'main' }) -DestinationRepository ([pscustomobject] @{ FullName = 'acme/destination' })

            $plainSnapshot | Should -BeNullOrEmpty
            $fullHistory | Should -BeNullOrEmpty
            Should -Invoke Invoke-CgrGitHubApiReadRequest -Times 0
        }
    }
}

Describe 'Snapshot release recovery report contracts' {
    It 'records the last completed stage and nested release preservation evidence without destructive recovery' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'; DestinationRepository = 'acme/destination'; SourceVisibility = 'private'; DestinationVisibility = 'private'; ContentMode = 'Snapshot'; SourceDefaultBranch = 'main'
            }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; HtmlUrl = 'https://example.test/acme/destination' }
            $steps = @(
                [pscustomobject] @{ Order = 1; Name = 'CreateDestinationRepository'; MutatedGitHub = $true; Verified = $true },
                [pscustomobject] @{ Order = 2; Name = 'CopySnapshot'; MutatedGitHub = $true; Verified = $true }
            )
            $releaseEvidence = [pscustomobject] @{ Planned = [pscustomobject] @{ ReleaseCount = 2 }; Actual = [pscustomobject] @{ ReleaseTags = @('v1', 'v2') }; Verified = [pscustomobject] @{ ReleaseRestore = $false } }
            $provenance = [pscustomobject] @{ ContentMode = 'Snapshot'; ReleasePreservation = $releaseEvidence }
            $exception = [System.InvalidOperationException]::new('release restore failed')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'ReleaseRestoreFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, 'v2')
            $reportBase = Join-Path $TestDrive 'migration.json'

            $path = Write-CgrMigrationRecoveryReport -Plan $plan -DestinationRepository $destination -FailureStage 'RestoreGitHubReleases' -ErrorRecord $errorRecord -CompletedSteps $steps -Provenance $provenance -PreferredReportPath $reportBase
            $report = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 30

            $report.FailureStage | Should -Be 'RestoreGitHubReleases'
            $report.LastCompletedStep.Name | Should -Be 'CopySnapshot'
            $report.Provenance.ReleasePreservation.Planned.ReleaseCount | Should -Be 2
            $report.Recovery.AutomaticDeletionAttempted | Should -BeFalse
            $report.Recovery.SourceRepositoryMutated | Should -BeFalse
        }
    }

    It 'preserves Snapshot release evidence in same-name and delegated replacement reports' {
        InModuleScope CopyGitHubRepo {
            $plan = [pscustomobject] @{
                SourceRepository = 'acme/source'; DestinationRepository = 'acme/destination'; ArchiveRepository = 'acme/archive'; SourceVisibility = 'private'; DestinationVisibility = 'private'; ContentMode = 'Snapshot'; SourceDefaultBranch = 'main'
            }
            $archive = [pscustomobject] @{ FullName = 'acme/archive'; Id = 10; HtmlUrl = 'https://example.test/acme/archive' }
            $destination = [pscustomobject] @{ FullName = 'acme/destination'; Id = 20; HtmlUrl = 'https://example.test/acme/destination' }
            $steps = @([pscustomobject] @{ Order = 4; Name = 'VerifyReplacementRepositoryIdentity'; MutatedGitHub = $false; Verified = $true })
            $releaseEvidence = [pscustomobject] @{ Actual = [pscustomobject] @{ ReleaseTags = @([pscustomobject] @{ TagName = 'v1.0.0' }) } }
            $exception = [System.InvalidOperationException]::new('copy failed')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'CopyFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            $sameNameBase = Join-Path $TestDrive 'same-name.json'
            $delegatedBase = Join-Path $TestDrive 'delegated.json'

            $sameNamePath = Write-CgrSameNameRecoveryReport -Plan $plan -SourceRepositoryId 10 -ArchiveRepository $archive -DestinationRepository $destination -FailureStage 'RestoreGitHubReleases' -ErrorRecord $errorRecord -CompletedSteps $steps -ReleasePreservation $releaseEvidence -PreferredReportPath $sameNameBase
            $delegatedPath = Write-CgrExistingDestinationRecoveryReport -Plan $plan -OriginalDestinationRepositoryId 10 -ArchiveRepository $archive -DestinationRepository $destination -FailureStage 'CopySnapshot' -ErrorRecord $errorRecord -CompletedSteps $steps -ReleasePreservation $releaseEvidence -PreferredReportPath $delegatedBase
            $sameName = Get-Content -LiteralPath $sameNamePath -Raw | ConvertFrom-Json -Depth 30
            $delegated = Get-Content -LiteralPath $delegatedPath -Raw | ConvertFrom-Json -Depth 30

            $sameName.Provenance.ReleasePreservation.Actual.ReleaseTags[0].TagName | Should -Be 'v1.0.0'
            $sameName.LastCompletedStep.Name | Should -Be 'VerifyReplacementRepositoryIdentity'
            $sameName.Recovery.AutomaticRollbackAttempted | Should -BeFalse
            $delegated.ReleasePreservation.Actual.ReleaseTags[0].TagName | Should -Be 'v1.0.0'
            $delegated.LastCompletedStep.Name | Should -Be 'VerifyReplacementRepositoryIdentity'
            $delegated.Recovery.AutomaticDeletionAttempted | Should -BeFalse
        }
    }
}
